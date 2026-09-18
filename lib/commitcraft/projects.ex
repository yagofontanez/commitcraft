defmodule CommitCraft.Projects do
  @moduledoc """
  Os projetos de cada pessoa.

  Toda função recebe o dono como primeiro argumento e filtra por ele. Nenhuma
  busca por id solto: assim não existe o caminho em que um id adivinhado devolve
  o projeto de outra pessoa.
  """
  import Ecto.Query, warn: false

  alias CommitCraft.Accounts.User
  alias CommitCraft.Projects.Project
  alias CommitCraft.Repo

  @doc "Os projetos de alguém, do mais recente para o mais antigo."
  def list_projects(%User{} = user) do
    Project
    |> where(user_id: ^user.id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  @doc "Um projeto pelo apelido na URL. Devolve nil se não for da pessoa."
  def get_project(%User{} = user, slug) when is_binary(slug) do
    Repo.get_by(Project, user_id: user.id, slug: slug)
  end

  @doc """
  Apaga um projeto da pessoa, pelo apelido.

  Recebe o dono junto para que não exista caminho em que um apelido adivinhado
  apague o projeto de outra conta. Devolve `:error` quando não há o que apagar —
  inexistente e alheio respondem igual, de propósito.
  """
  def delete_project(%User{} = user, slug) when is_binary(slug) do
    case get_project(user, slug) do
      nil -> :error
      project -> {:ok, Repo.delete!(project)}
    end
  end

  @doc "Um changeset vazio, para o formulário."
  def change_project(%Project{} = project \\ %Project{}, attrs \\ %{}) do
    Project.changeset(project, attrs)
  end

  @doc """
  Cria um projeto, derivando o apelido da URL a partir do nome.

  Se o apelido já estiver em uso naquela conta, ganha um número no fim —
  "site", "site-2", "site-3".
  """
  def create_project(%User{} = user, attrs) do
    com_apelido_livre(attrs, fn atributos ->
      %Project{user_id: user.id}
      |> Project.changeset(atributos)
      |> Repo.insert()
    end)
  end

  @doc """
  Troca o nome de um projeto — e o apelido na URL junto.

  Deixar o apelido preso ao nome antigo faria a URL mentir para sempre sobre o
  que o projeto é. O preço é que um link salvo do endereço antigo para de
  funcionar; hoje ninguém depende desses endereços, e quando o webhook existir
  ele vai usar um identificador próprio, não o apelido.

  Devolve `{:error, :not_found}` quando o projeto não é da pessoa — inexistente
  e alheio respondem igual, de propósito.
  """
  def rename_project(%User{} = user, slug, attrs) do
    case get_project(user, slug) do
      nil ->
        {:error, :not_found}

      project ->
        com_apelido_livre(attrs, fn atributos ->
          project
          |> Project.changeset(atributos)
          |> Repo.update()
        end)
    end
  end

  # Quantas variações de apelido tentar antes de desistir.
  @tentativas 25

  # Criar e renomear fazem a mesma dança: derivar o apelido do nome, tentar
  # gravar, e somar um número no fim se aquele já estiver ocupado. A tentativa
  # é repetida contra o banco em vez de decidida por uma consulta antes, porque
  # entre consultar e gravar cabe outra requisição da mesma pessoa em outra aba.
  defp com_apelido_livre(attrs, salvar) do
    atributos = stringify(attrs)
    base = atributos |> Map.get("name", "") |> to_string() |> String.trim() |> slugify()

    tentar(atributos, base, 1, salvar)
  end

  defp tentar(atributos, base, tentativa, salvar) do
    apelido = if tentativa == 1, do: base, else: "#{base}-#{tentativa}"

    case salvar.(Map.put(atributos, "slug", apelido)) do
      {:ok, project} ->
        {:ok, project}

      {:error, changeset} ->
        if tentativa < @tentativas and apelido_ocupado?(changeset) do
          tentar(atributos, base, tentativa + 1, salvar)
        else
          # O erro de apelido é nosso, não de quem digitou; não faz sentido
          # mostrar "slug já está em uso" para quem só viu um campo "nome".
          {:error, %{changeset | errors: Keyword.delete(changeset.errors, :slug)}}
        end
    end
  end

  defp apelido_ocupado?(changeset) do
    Enum.any?(changeset.errors, fn
      {:slug, {_mensagem, opts}} -> opts[:constraint] == :unique
      _outro -> false
    end)
  end

  @doc """
  Transforma um nome no apelido que vai para a URL.

      iex> CommitCraft.Projects.slugify("Minha Loja")
      "minha-loja"

      iex> CommitCraft.Projects.slugify("Ração & Cia — 2024")
      "racao-cia-2024"

  Um nome sem nenhuma letra latina (só emoji, por exemplo) não tem apelido
  possível, então ganha um aleatório em vez de impedir a criação.

      iex> CommitCraft.Projects.slugify("🎮") =~ ~r/^projeto-[a-z0-9]+$/
      true
  """
  def slugify(nome) when is_binary(nome) do
    slug =
      nome
      # NFD separa o acento da letra ("ç" vira "c" + cedilha solta), e o filtro
      # seguinte descarta o acento — então "Ração" chega em "racao".
      |> :unicode.characters_to_nfd_binary()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/u, "")
      |> String.trim()
      |> String.replace(~r/[\s-]+/, "-")

    if slug == "",
      do: "projeto-" <> Base.encode32(:crypto.strong_rand_bytes(4), case: :lower, padding: false),
      else: slug
  end

  defp stringify(attrs) do
    Map.new(attrs, fn {chave, valor} -> {to_string(chave), valor} end)
  end
end

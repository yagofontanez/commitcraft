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
  "site", "site-2", "site-3". A tentativa é repetida contra o banco em vez de
  ser decidida por uma consulta antes: entre consultar e inserir cabe outra
  requisição da mesma pessoa em outra aba.
  """
  def create_project(%User{} = user, attrs) do
    nome = attrs |> Map.get("name", Map.get(attrs, :name, "")) |> to_string() |> String.trim()

    inserir(user, attrs, slugify(nome), 1)
  end

  @tentativas 25

  defp inserir(user, attrs, base, tentativa) do
    slug = if tentativa == 1, do: base, else: "#{base}-#{tentativa}"

    resultado =
      %Project{user_id: user.id}
      |> Project.changeset(Map.put(stringify(attrs), "slug", slug))
      |> Repo.insert()

    case resultado do
      {:ok, project} ->
        {:ok, project}

      {:error, changeset} ->
        if tentativa < @tentativas and slug_ocupado?(changeset) do
          inserir(user, attrs, base, tentativa + 1)
        else
          # O erro de slug é nosso, não de quem digitou; não faz sentido
          # mostrar "slug já está em uso" para quem nunca viu esse campo.
          {:error, %{changeset | errors: Keyword.delete(changeset.errors, :slug)}}
        end
    end
  end

  defp slug_ocupado?(changeset) do
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

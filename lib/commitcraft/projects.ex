defmodule CommitCraft.Projects do
  @moduledoc """
  Os projetos de cada pessoa.

  Toda função recebe o dono como primeiro argumento e filtra por ele. Nenhuma
  busca por id solto: assim não existe o caminho em que um id adivinhado devolve
  o projeto de outra pessoa.
  """
  import Ecto.Query, warn: false

  alias CommitCraft.Accounts.User
  alias CommitCraft.Projects.Event
  alias CommitCraft.Projects.Project
  alias CommitCraft.Projects.Webhook
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
  Liga um repositório do GitHub a um projeto.

  Recebe o repositório já normalizado por `CommitCraft.GitHub.Api`. Devolve
  `{:error, :already_connected}` quando outro projeto da mesma conta já aponta
  para esse repositório — dois projetos no mesmo repo contariam cada commit
  duas vezes.
  """
  def connect_repo(%User{} = user, slug, repo) do
    case get_project(user, slug) do
      nil ->
        {:error, :not_found}

      project ->
        project
        |> Project.repo_changeset(repo)
        |> Repo.update()
        |> case do
          {:ok, project} -> {:ok, project}
          {:error, changeset} -> {:error, motivo_da_conexao(changeset)}
        end
    end
  end

  defp motivo_da_conexao(changeset) do
    if Enum.any?(changeset.errors, fn {_campo, {_msg, opts}} ->
         opts[:constraint] == :unique
       end),
       do: :already_connected,
       else: changeset
  end

  @doc """
  O webhook e o projeto dono dele, achados pelo identificador que vai na URL.

  Devolve `{webhook, project}` — o receptor precisa dos dois, e uma consulta só
  evita ida e volta extra num caminho que roda a cada entrega.
  """
  def get_webhook_by_token(token) when is_binary(token) do
    Webhook
    |> where(token: ^token)
    |> preload(:project)
    |> Repo.one()
    |> case do
      nil -> nil
      %Webhook{project: project} = webhook -> {webhook, project}
    end
  end

  @doc "O webhook de uma fonte para um projeto, se existir."
  def get_webhook(%Project{} = project, source) when is_binary(source) do
    Repo.get_by(Webhook, project_id: project.id, source: source)
  end

  @doc "Todos os webhooks de um projeto, indexados pela fonte."
  def webhooks_by_source(%Project{} = project) do
    Webhook
    |> where(project_id: ^project.id)
    |> Repo.all()
    |> Map.new(&{&1.source, &1})
  end

  @doc """
  Guarda (ou substitui) o webhook de uma fonte.

  O segredo é por projeto e por fonte: se um vazar, o estrago não se espalha
  para os outros. Para GitHub nós o sorteamos; para Vercel e Stripe ele vem do
  painel do próprio serviço, onde quem manda é quem configurou.
  """
  def put_webhook(%Project{} = project, source, attrs) do
    existente = get_webhook(project, source) || %Webhook{project_id: project.id}

    atributos =
      attrs
      |> Map.new(fn {chave, valor} -> {to_string(chave), valor} end)
      |> Map.put("source", source)
      |> Map.put_new("token", new_webhook_token())
      |> Map.put_new("installed_at", DateTime.utc_now(:second))

    existente
    |> Webhook.changeset(atributos)
    |> Repo.insert_or_update()
  end

  @doc "Esquece o webhook de uma fonte, sem tocar no XP já conquistado."
  def delete_webhook(%Project{} = project, source) do
    case get_webhook(project, source) do
      nil -> :ok
      webhook -> Repo.delete!(webhook) && :ok
    end
  end

  @doc """
  Garante que existe um endereço para uma fonte, mesmo antes de haver segredo.

  A ordem importa: para criar o webhook no painel da Vercel ou da Stripe é
  preciso colar a URL lá primeiro, e só então copiar de volta o segredo que
  elas geram. Se o endereço só existisse depois do segredo, não haveria por
  onde começar.
  """
  def ensure_webhook_token(%Project{} = project, source) do
    case get_webhook(project, source) do
      nil ->
        {:ok, webhook} = put_webhook(project, source, %{})
        webhook

      webhook ->
        webhook
    end
  end

  @doc """
  Se a fonte está de fato escutando.

  Ter endereço não basta: sem segredo não dá para conferir assinatura, e sem
  conferir assinatura nada é aceito.
  """
  def connected?(nil), do: false
  def connected?(%Webhook{secret: secret}), do: not is_nil(secret)

  @doc "Um identificador novo para pôr na URL de um webhook."
  def new_webhook_token, do: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

  @doc "Um segredo novo, para as fontes em que somos nós que o escolhemos."
  def new_webhook_secret, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  @doc "Se o projeto está de fato escutando os eventos do repositório."
  def listening?(%Project{} = project) do
    not is_nil(project.repo_id) and connected?(get_webhook(project, "github"))
  end

  @doc "Se o projeto já registrou algum acontecimento de um tipo."
  def has_event_kind?(%Project{} = project, kind) when is_binary(kind) do
    Event
    |> where(project_id: ^project.id, kind: ^kind)
    |> Repo.exists?()
  end

  @doc "Desliga o repositório, mantendo o projeto e o XP já conquistado."
  def disconnect_repo(%User{} = user, slug) do
    case get_project(user, slug) do
      nil -> {:error, :not_found}
      project -> project |> Project.disconnect_changeset() |> Repo.update()
    end
  end

  @doc "O projeto da conta que já usa este repositório, se houver."
  def project_with_repo(%User{} = user, repo_id) when is_integer(repo_id) do
    Repo.get_by(Project, user_id: user.id, repo_id: repo_id)
  end

  @doc "Os últimos acontecimentos de um projeto."
  def list_events(%Project{} = project, opts \\ []) do
    limite = Keyword.get(opts, :limit, 30)

    Event
    |> where(project_id: ^project.id)
    |> order_by(desc: :occurred_at, desc: :id)
    |> limit(^limite)
    |> Repo.all()
  end

  @doc """
  Registra o que aconteceu e acerta o XP do projeto.

  Um acontecimento já registrado é ignorado em silêncio: o GitHub reenvia
  entregas, e o mesmo commit não pode pagar duas vezes. Quem garante isso é o
  índice único em `(project_id, external_id)` — não uma consulta antes de
  gravar, que perderia a corrida com uma segunda entrega chegando junto.

  Devolve `{:ok, %{project: project, events: recem_registrados}}`.
  """
  def record_events(%Project{} = project, acontecimentos) when is_list(acontecimentos) do
    Repo.transaction(fn ->
      registrados = Enum.flat_map(acontecimentos, &registrar(project, &1))

      %{project: recalcular_xp(project), events: registrados}
    end)
  end

  defp registrar(project, attrs) do
    %Event{project_id: project.id}
    |> Event.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
    |> case do
      # Sem id significa que o índice único barrou: já estava registrado.
      {:ok, %Event{id: nil}} -> []
      {:ok, event} -> [event]
      {:error, _changeset} -> []
    end
  end

  # O XP é sempre a soma do que está registrado, nunca um contador incrementado.
  # Assim uma entrega repetida, ou um evento apagado, não deixam o total mentindo.
  defp recalcular_xp(project) do
    total =
      Event
      |> where(project_id: ^project.id)
      |> select([e], coalesce(sum(e.xp), 0))
      |> Repo.one()

    project
    |> Ecto.Changeset.change(xp: total)
    |> Repo.update!()
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

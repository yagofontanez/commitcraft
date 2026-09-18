defmodule CommitCraftWeb.Game do
  @moduledoc """
  As peças de interface do jogo: barra de XP, nível, estado de um projeto.
  """
  use Phoenix.Component

  import CommitCraftWeb.Pixel

  alias Phoenix.LiveView.JS

  @doc """
  O céu noturno, com estrelas.

  As posições vêm de uma conta e não de sorteio: sorteio no servidor faria as
  estrelas pularem de lugar a cada render do LiveView.
  """
  attr :class, :string, default: nil

  def stars(assigns) do
    ~H"""
    <div class={["stars pointer-events-none absolute inset-0", @class]} aria-hidden="true">
      <span
        :for={i <- 0..47}
        class="twinkle"
        style={"left:#{rem(i * 37, 100)}%; top:#{rem(i * 53, 62)}%; animation-delay:#{rem(i * 7, 32) / 10}s"}
      ></span>
    </div>
    """
  end

  @doc "As montanhas em degraus: o horizonte também é feito de pixels."
  attr :class, :string, default: nil

  def hills(assigns) do
    ~H"""
    <svg
      class={["relative block w-full", @class]}
      viewBox="0 0 1200 90"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <polygon
        fill="#33285c"
        points="0,90 0,70 60,70 60,55 140,55 140,40 220,40 220,52 300,52 300,35 400,35 400,60 480,60 480,48 560,48 560,30 660,30 660,58 740,58 740,45 840,45 840,62 920,62 920,38 1020,38 1020,55 1100,55 1100,70 1200,70 1200,90"
      />
      <polygon
        fill="#1c1533"
        points="0,90 0,80 90,80 90,68 180,68 180,76 280,76 280,60 380,60 380,72 470,72 470,64 570,64 570,78 680,78 680,66 780,66 780,74 880,74 880,62 980,62 980,75 1080,75 1080,68 1200,68 1200,90"
      />
    </svg>
    """
  end

  @doc """
  O caminho já percorrido: cada acontecimento vira um bloco de chão.

  É a promessa da página inicial cumprida com dado real. A ordem é a do tempo,
  do mais antigo à esquerda para o mais recente à direita — e é sobre o bloco
  mais recente que o artesão fica de pé.
  """
  attr :events, :list, required: true
  attr :listening, :boolean, default: false
  attr :recem_chegados, :any, default: nil
  attr :reveal_titles, :boolean, default: true

  def journey(assigns) do
    # O mais antigo primeiro: o caminho se lê da esquerda para a direita, como
    # qualquer linha do tempo.
    assigns = assign(assigns, :blocos, Enum.reverse(assigns.events))

    ~H"""
    <div class="sky relative overflow-hidden">
      <.stars />

      <div class="relative pt-10">
        <.hills class="h-16 md:h-20" />

        <div class="relative bg-[#1c1533]">
          <%!-- O artesão fica no fim do caminho, em cima do que acabou de
                acontecer. --%>
          <div class="pointer-events-none absolute right-6 bottom-full z-20 md:right-10">
            <.crafter class="h-16 w-16 md:h-20 md:w-20" />
          </div>

          <div
            id="jornada"
            phx-hook="Jornada"
            tabindex="0"
            role="group"
            aria-label="Caminho do projeto, do mais antigo ao mais recente"
            class="flex overflow-x-auto focus:outline-none focus-visible:outline-3 focus-visible:outline-gold"
          >
            <div
              :for={event <- @blocos}
              id={"bloco-#{event.id}"}
              phx-mounted={
                novidade?(@recem_chegados, :event, event.id) &&
                  JS.transition({"bloco-entrada", "opacity-0", "opacity-100"}, time: 700)
              }
              title={
                if @reveal_titles,
                  do: "#{event.title} · #{Calendar.strftime(event.occurred_at, "%d/%m/%Y %H:%M")}",
                  else: Calendar.strftime(event.occurred_at, "%d/%m/%Y %H:%M")
              }
              class={[
                "shrink-0 border-r-[3px] border-b-[3px] border-ink px-4 py-3",
                "w-[150px] md:w-[172px]",
                bloco_altura(event.kind),
                bloco_cor(event.kind)
              ]}
            >
              <div class="flex items-center justify-between gap-2">
                <span class="font-pixel text-[10px] opacity-80">{event_label(event.kind)}</span>
                <span class="font-pixel text-[10px]">
                  {if event.xp > 0, do: "+#{event.xp}", else: event.xp}
                </span>
              </div>
              <%!-- Sem os títulos, o bloco ainda conta o que aconteceu e
                    quanto valeu — só não conta o que foi escrito. --%>
              <p
                :if={@reveal_titles}
                class="mt-2 line-clamp-2 text-xs leading-snug text-bone/75"
              >
                {event.title}
              </p>
            </div>

            <%!-- Sem nada gravado, o chão ainda existe: o caminho começa vazio,
                  não quebrado. --%>
            <div
              :if={@blocos == []}
              class="flex h-24 w-full shrink-0 items-center justify-center bg-panel px-6 md:h-28"
            >
              <p class="font-pixel text-[11px] text-muted">
                {if @listening,
                  do: "o caminho começa no seu próximo commit",
                  else: "conecte um repositório para o caminho começar"}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Se um item acabou de chegar ao vivo.

  `phx-mounted` dispara sempre que um elemento entra no DOM — inclusive no
  primeiro carregamento, quando nada é novidade. Marcar explicitamente o que
  chegou agora é o que impede a tela inteira de piscar ao abrir.
  """
  def novidade?(nil, _tipo, _id), do: false
  def novidade?(conjunto, tipo, id), do: MapSet.member?(conjunto, {tipo, id})

  # Build quebrado afunda o chão: é um buraco no caminho, e lê como buraco sem
  # precisar de legenda.
  defp bloco_altura("broken_build"), do: "h-16 self-end md:h-20"
  defp bloco_altura(_outro), do: "h-24 md:h-28"

  defp bloco_cor("deploy"), do: "bg-[#1b3326] text-moss"
  defp bloco_cor("broken_build"), do: "bg-[#3a1b1b] text-ember"
  defp bloco_cor("first_sale"), do: "bg-[#3a2c14] text-gold"
  defp bloco_cor("sale"), do: "bg-[#33290f] text-gold"
  defp bloco_cor("streak_week"), do: "bg-[#2b2350] text-violet"
  defp bloco_cor("pull_request_merged"), do: "bg-[#241b3d] text-bone"
  defp bloco_cor(_outro), do: "bg-panel text-muted"

  @doc """
  O painel de nível e XP.

  Recebe o mapa de `CommitCraft.Game.Level.progress/1` inteiro em vez de nível e
  XP soltos — assim a tela não tem como mostrar um nível que não corresponde à
  barra desenhada ao lado dele.
  """
  attr :progress, :map, required: true
  attr :class, :string, default: nil
  slot :caption

  def hud(assigns) do
    ~H"""
    <div class={["frame px-5 py-4", @class]}>
      <div class="mb-3 flex items-baseline justify-between gap-4">
        <span class="font-pixel text-sm text-gold">LV {padded(@progress.level)}</span>
        <span class="font-pixel text-[10px] text-muted">
          {numero(@progress.into_level)} / {numero(@progress.to_advance)} XP
        </span>
      </div>

      <div
        class="xp-track"
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax={@progress.to_advance}
        aria-valuenow={@progress.into_level}
        aria-label={"Progresso para o nível #{@progress.level + 1}"}
      >
        <div class="xp-fill" style={"width: #{round(@progress.ratio * 100)}%"}></div>
        <div class="xp-notches"></div>
      </div>

      <p :if={@caption != []} class="mt-3 text-left text-xs text-muted">
        {render_slot(@caption)}
      </p>
    </div>
    """
  end

  @doc """
  A cor de uma raridade, usada para repintar o sprite da medalha.

  Devolve um mapa de troca de paleta aceito por `CommitCraftWeb.Pixel.sprite/1`.
  """
  def rarity_paint("Lendário"), do: %{"g" => "#ffc24b", "o" => "#c8871f"}
  def rarity_paint("Raro"), do: %{"g" => "#7c6be8", "o" => "#5b4cb8"}
  def rarity_paint("Incomum"), do: %{"g" => "#6fbf73", "o" => "#3f7a45"}
  def rarity_paint(_), do: %{"g" => "#c9d4e8", "o" => "#7d879b"}

  @doc "Medalha apagada: a conquista existe, mas ainda não foi conseguida."
  def locked_paint, do: %{"g" => "#2f2450", "o" => "#241b3d", "k" => "#1c1533"}

  def rarity_text("Lendário"), do: "text-gold"
  def rarity_text("Raro"), do: "text-violet"
  def rarity_text("Incomum"), do: "text-moss"
  def rarity_text(_), do: "text-muted"

  @doc "A cor de um acontecimento, pelo sinal do XP que ele vale."
  def event_tone(xp) when xp < 0, do: "text-ember"
  def event_tone(xp) when xp >= 100, do: "text-gold"
  def event_tone(_xp), do: "text-moss"

  @doc """
  O nome de um tipo de acontecimento em português.

  Fica aqui, e não no banco, porque é rótulo de tela: mudar o texto não deveria
  exigir migração.
  """
  def event_label("commit"), do: "commit"
  def event_label("pull_request_merged"), do: "pull request mesclado"
  def event_label("issue_closed"), do: "issue fechada"
  def event_label("deploy"), do: "deploy"
  def event_label(outro), do: outro

  @doc """
  O cartão de uma integração que se conecta colando um segredo.

  Mostra o endereço que o serviço precisa chamar e recebe o segredo de
  assinatura. Conectada, o segredo nunca mais aparece na tela — não há motivo
  para exibi-lo de novo, e exibir é o jeito mais fácil de vazá-lo.
  """
  attr :source, :string, required: true
  attr :nome, :string, required: true
  attr :sprite, :atom, required: true
  attr :descricao, :string, required: true
  attr :onde, :string, required: true
  attr :webhook, :any, default: nil

  def integration(assigns) do
    assigns = assign(assigns, :conectado, CommitCraft.Projects.connected?(assigns.webhook))

    ~H"""
    <div class="frame px-6 py-6">
      <div class="flex items-start gap-4">
        <div class="frame-thin flex h-12 w-12 shrink-0 items-center justify-center">
          <.sprite name={@sprite} class="h-6 w-6" />
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-baseline gap-x-3">
            <h3 class="font-semibold text-bone">{@nome}</h3>
            <span :if={@conectado} class="font-pixel text-[10px] text-moss">escutando</span>
            <span :if={!@conectado} class="font-pixel text-[10px] text-muted">não conectado</span>
          </div>
          <p class="mt-2 text-sm leading-relaxed text-muted">{@descricao}</p>
        </div>
      </div>

      <div :if={@conectado} class="mt-6 flex items-center justify-between gap-4">
        <p class="text-xs text-muted">
          conectado {Calendar.strftime(@webhook.installed_at, "%d/%m/%Y")}
        </p>
        <button
          type="button"
          phx-click="remove_integration"
          phx-value-source={@source}
          class="text-sm text-muted hover:text-ember"
        >
          desconectar
        </button>
      </div>

      <form :if={!@conectado} id={"integracao-#{@source}"} phx-submit="save_integration" class="mt-6">
        <p class="text-xs leading-relaxed text-muted">{@onde}</p>

        <input type="hidden" name="source" value={@source} />

        <label class="mt-4 block text-xs text-muted" for={"segredo-#{@source}"}>
          Endereço para colar lá
        </label>
        <code class="mt-2 block truncate bg-ink px-4 py-3 text-xs text-bone">
          {webhook_url(@webhook, @source)}
        </code>

        <input
          id={"segredo-#{@source}"}
          type="text"
          name="secret"
          required
          placeholder="Segredo de assinatura"
          aria-label={"Segredo de assinatura do #{@nome}"}
          class="mt-3 w-full border-0 bg-ink px-4 py-3 text-bone placeholder:text-muted/60 focus:outline-none"
        />

        <button type="submit" class="btn-ghost-craft mt-4 w-full justify-center">
          Conectar {@nome}
        </button>
      </form>
    </div>
    """
  end

  @doc "O endereço que o serviço externo deve chamar."
  def webhook_url(webhook, source) do
    base =
      Application.get_env(:commitcraft, :webhook_base_url) ||
        CommitCraftWeb.Endpoint.url()

    String.trim_trailing(base, "/") <> "/webhooks/" <> source <> "/" <> webhook.token
  end

  @doc """
  Número com ponto de milhar, do jeito que se lê em português.

      iex> CommitCraftWeb.Game.numero(1240)
      "1.240"

      iex> CommitCraftWeb.Game.numero(0)
      "0"
  """
  def numero(valor) when is_integer(valor) do
    valor
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end

  @doc """
  Nível com dois dígitos, como num placar de fliperama.

      iex> CommitCraftWeb.Game.padded(7)
      "07"

      iex> CommitCraftWeb.Game.padded(42)
      "42"
  """
  def padded(level) when is_integer(level),
    do: level |> Integer.to_string() |> String.pad_leading(2, "0")
end

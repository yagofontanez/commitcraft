defmodule CommitCraftWeb.Game do
  @moduledoc """
  As peças de interface do jogo: barra de XP, nível, estado de um projeto.
  """
  use Phoenix.Component

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
          <CommitCraftWeb.Pixel.sprite name={@sprite} class="h-6 w-6" />
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

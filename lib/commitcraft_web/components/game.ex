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

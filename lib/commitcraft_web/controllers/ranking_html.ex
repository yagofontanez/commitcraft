defmodule CommitCraftWeb.RankingHTML do
  @moduledoc """
  A tabela de classificação.
  """
  use CommitCraftWeb, :html

  embed_templates "ranking_html/*"

  @doc """
  O metal de cada pódio.

  Do quarto em diante não há metal nenhum — a medalha perde o sentido se todo
  mundo ganha uma.
  """
  def podium(1), do: %{sprite: :trophy, paint: %{}, label: "text-gold"}

  def podium(2),
    do: %{
      sprite: :medal,
      paint: %{"g" => "#cdd3dd", "o" => "#8d95a3", "m" => "#5c6475"},
      label: "text-bone"
    }

  def podium(3),
    do: %{
      sprite: :medal,
      paint: %{"g" => "#c98a52", "o" => "#8a5a34", "m" => "#5c4430"},
      label: "text-[#c98a52]"
    }

  def podium(_outra), do: nil
end

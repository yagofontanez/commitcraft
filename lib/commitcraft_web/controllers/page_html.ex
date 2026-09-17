defmodule CommitCraftWeb.PageHTML do
  @moduledoc """
  Páginas públicas.

  As funções aqui traduzem o *significado* de um dado (um bloco é um deploy, uma
  conquista é lendária) para as cores do tema, para que o template continue
  falando de conteúdo e não de hexadecimal.
  """
  use CommitCraftWeb, :html

  embed_templates "page_html/*"

  @doc "Cor do bloco de chão conforme o tipo de evento que ele representa."
  def block_tone(:deploy), do: "bg-[#1b3326] text-moss"
  def block_tone(:gold), do: "bg-[#3a2c14] text-gold"
  def block_tone(_), do: "bg-panel text-muted"

  @doc "Cor do valor de XP na tabela de pontos."
  def xp_tone(:great), do: "text-gold"
  def xp_tone(:good), do: "text-moss"
  def xp_tone(:bad), do: "text-ember"
  def xp_tone(_), do: "text-bone"

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
end

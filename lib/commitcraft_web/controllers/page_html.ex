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
end

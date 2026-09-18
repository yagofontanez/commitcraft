defmodule CommitCraftWeb.ProjectHTML do
  @moduledoc """
  A área de quem está logado.
  """
  use CommitCraftWeb, :html

  embed_templates "project_html/*"

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
end

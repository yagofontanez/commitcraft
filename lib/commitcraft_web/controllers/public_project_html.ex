defmodule CommitCraftWeb.PublicProjectHTML do
  @moduledoc """
  A vitrine pública de um projeto.
  """
  use CommitCraftWeb, :html

  embed_templates "public_project_html/*"

  @doc """
  A frase que aparece no card quando o link é colado em algum lugar.

  É a única coisa que muita gente vai ler sobre o projeto, então diz o estado
  em vez de se apresentar.
  """
  def compartilhamento(progress, class) do
    partes =
      [
        "Nível #{progress.level}",
        class && class.name,
        "#{CommitCraftWeb.Game.numero(progress.xp)} XP"
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(partes, " · ") <> " no CommitCraft."
  end
end

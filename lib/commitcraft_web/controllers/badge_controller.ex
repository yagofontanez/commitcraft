defmodule CommitCraftWeb.BadgeController do
  @moduledoc """
  O selo de um projeto público, para colar no README.
  """
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Level
  alias CommitCraft.Projects
  alias CommitCraftWeb.Badge

  def show(conn, %{"login" => login, "slug" => slug}) do
    case Projects.get_public_project(login, slug) do
      nil ->
        # Um selo quebrado no README de alguém é pior do que um selo que diz
        # que não achou: pelo menos assim a pessoa entende o que houve.
        entregar(conn, Badge.render("commitcraft", "não encontrado"), 404)

      project ->
        progress = Level.progress(project.xp)
        # Dois dígitos como no resto do jogo: "LV 03", não "LV 3".
        entregar(
          conn,
          Badge.render(project.name, "LV #{CommitCraftWeb.Game.padded(progress.level)}"),
          200
        )
    end
  end

  defp entregar(conn, svg, status) do
    conn
    |> put_resp_content_type("image/svg+xml")
    # O GitHub serve imagem de README por um proxy que respeita cache. Cinco
    # minutos deixa o selo acompanhar o projeto sem bater aqui a cada visita.
    |> put_resp_header("cache-control", "public, max-age=300")
    |> send_resp(status, svg)
  end
end

defmodule CommitCraftWeb.BadgeController do
  @moduledoc """
  O selo de um projeto público, para colar no README.
  """
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Level
  alias CommitCraft.Projects
  alias CommitCraft.Game.Class
  alias CommitCraftWeb.Badge
  alias CommitCraftWeb.Card

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

  @doc """
  A imagem que as redes mostram quando alguém cola o link.

  Gerada a cada pedido: são milissegundos, e guardar arquivo em disco criaria a
  pergunta de quando invalidá-lo. Quem guarda é o cache do robô que buscou.
  """
  def card(conn, %{"login" => login, "slug" => slug}) do
    case Projects.get_public_project(login, slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_resp_content_type("image/png")
        |> send_resp(
          404,
          Card.render(name: "não encontrado", login: "commitcraft", progress: Level.progress(0))
        )

      project ->
        png =
          Card.render(
            name: project.name,
            login: project.user.github_login,
            progress: Level.progress(project.xp),
            class: project |> Projects.list_events(limit: 2000) |> Class.for_events()
          )

        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", "public, max-age=300")
        |> send_resp(200, png)
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

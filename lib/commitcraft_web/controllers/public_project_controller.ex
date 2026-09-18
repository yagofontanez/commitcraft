defmodule CommitCraftWeb.PublicProjectController do
  @moduledoc """
  A vitrine de um projeto: a única tela do CommitCraft que qualquer um abre.

  É uma página comum, não LiveView: ela vai ser aberta por gente que clicou num
  link, muitas vezes de dentro de um app de mensagem, e abrir um websocket para
  quem só quer olhar é gasto sem retorno.
  """
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Class
  alias CommitCraft.Game.Heatmap
  alias CommitCraft.Game.Level
  alias CommitCraft.Projects

  def show(conn, %{"login" => login, "slug" => slug}) do
    case Projects.get_public_project(login, slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(html: CommitCraftWeb.ErrorHTML)
        |> render(:"404")

      project ->
        eventos = Projects.list_events(project, limit: 60)
        todos = Projects.list_events(project, limit: 2000)

        conn
        |> assign(:page_title, "#{project.name} · #{project.user.github_login}")
        |> assign(:project, project)
        |> assign(:progress, Level.progress(project.xp))
        |> assign(:class, Class.for_events(todos))
        |> assign(:heatmap, Heatmap.build(todos))
        |> assign(:events, eventos)
        |> assign(:achievements, Projects.list_achievements(project))
        |> assign(:streak, Projects.current_streak(project))
        |> assign(:reveal_titles, Projects.reveal_titles?(project))
        |> assign(
          :share_description,
          CommitCraftWeb.PublicProjectHTML.compartilhamento(
            Level.progress(project.xp),
            Class.for_events(todos)
          )
        )
        |> render(:show)
    end
  end
end

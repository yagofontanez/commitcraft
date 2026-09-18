defmodule CommitCraftWeb.ProjectController do
  @moduledoc """
  A área de quem entrou: a lista de projetos e cada projeto.
  """
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Level
  alias CommitCraft.Projects

  def index(conn, _params) do
    render_index(conn, Projects.change_project())
  end

  def create(conn, %{"project" => params}) do
    case Projects.create_project(conn.assigns.current_user, params) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Projeto criado. Boa sorte.")
        |> redirect(to: ~p"/jogar/#{project.slug}")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_index(changeset)
    end
  end

  def show(conn, %{"slug" => slug}) do
    case Projects.get_project(conn.assigns.current_user, slug) do
      nil ->
        # Projeto de outra pessoa e projeto inexistente respondem igual: dizer
        # "existe, mas não é seu" já é contar algo sobre a conta alheia.
        conn
        |> put_flash(:error, "Não encontrei esse projeto.")
        |> redirect(to: ~p"/jogar")

      project ->
        conn
        |> assign(:page_title, project.name)
        |> assign(:project, project)
        |> assign(:progress, Level.progress(project.xp))
        |> render(:show)
    end
  end

  def delete(conn, %{"slug" => slug}) do
    case Projects.delete_project(conn.assigns.current_user, slug) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "\"#{project.name}\" foi apagado.")
        |> redirect(to: ~p"/jogar")

      :error ->
        conn
        |> put_flash(:error, "Não encontrei esse projeto.")
        |> redirect(to: ~p"/jogar")
    end
  end

  defp render_index(conn, changeset) do
    # O nível vem junto de cada projeto porque a tela desenha os dois lados da
    # mesma informação; calcular na hora de renderizar faria a mesma conta
    # quatro vezes por cartão.
    projetos =
      conn.assigns.current_user
      |> Projects.list_projects()
      |> Enum.map(&%{project: &1, progress: Level.progress(&1.xp)})

    conn
    |> assign(:page_title, "Seus projetos")
    |> assign(:projects, projetos)
    |> assign(:changeset, changeset)
    |> render(:index)
  end
end

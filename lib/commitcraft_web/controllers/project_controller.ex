defmodule CommitCraftWeb.ProjectController do
  @moduledoc """
  A área de quem entrou: a lista de projetos e cada projeto.
  """
  use CommitCraftWeb, :controller

  require Logger

  alias CommitCraft.Accounts
  alias CommitCraft.Game.Level
  alias CommitCraft.GitHub.Api
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
        render_show(conn, project, Projects.change_project(project))
    end
  end

  def update(conn, %{"slug" => slug, "project" => params}) do
    case Projects.rename_project(conn.assigns.current_user, slug, params) do
      {:ok, project} ->
        conn
        |> put_flash(:info, "Agora se chama \"#{project.name}\".")
        |> redirect(to: ~p"/jogar/#{project.slug}")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Não encontrei esse projeto.")
        |> redirect(to: ~p"/jogar")

      {:error, changeset} ->
        # Renderiza de novo em vez de redirecionar, para não jogar fora o que a
        # pessoa digitou junto com o erro.
        conn
        |> put_status(:unprocessable_entity)
        |> render_show(Projects.get_project(conn.assigns.current_user, slug), changeset)
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

  @doc """
  A tela de escolher qual repositório este projeto acompanha.

  Se a autorização atual não cobre `repo`, a pessoa é mandada para ampliá-la
  antes — e volta para cá depois.
  """
  def choose_repo(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user

    with {:ok, project} <- buscar(user, slug),
         :ok <- exigir_escopo(user, slug),
         {:ok, repos} <- Api.list_repos(user.github_token) do
      conn
      |> assign(:page_title, "Conectar repositório")
      |> assign(:project, project)
      |> assign(:repos, repos)
      |> assign(:conectados, conectados(user))
      |> render(:choose_repo)
    else
      {:redirect, :ampliar, slug} -> ampliar(conn, slug)
      {:error, motivo} -> desviar(conn, motivo, slug)
    end
  end

  def connect_repo(conn, %{"slug" => slug, "repo_id" => repo_id}) do
    user = conn.assigns.current_user

    with {:ok, _project} <- buscar(user, slug),
         :ok <- exigir_escopo(user, slug),
         {:ok, id} <- inteiro(repo_id),
         {:ok, repo} <- Api.get_repo(user.github_token, id),
         {:ok, project} <- Projects.connect_repo(user, slug, repo) do
      conn
      |> instalar_webhook(user, project)
      |> redirect(to: ~p"/jogar/#{project.slug}")
    else
      {:redirect, :ampliar, slug} -> ampliar(conn, slug)
      {:error, motivo} -> desviar(conn, motivo, slug)
    end
  end

  @doc "Tenta instalar o webhook de novo, para quando a primeira vez falhou."
  def install_webhook(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user

    case buscar(user, slug) do
      {:ok, %{repo_id: nil}} ->
        desviar(conn, :not_found, slug)

      {:ok, project} ->
        conn
        |> instalar_webhook(user, project)
        |> redirect(to: ~p"/jogar/#{slug}")

      {:error, motivo} ->
        desviar(conn, motivo, slug)
    end
  end

  def disconnect_repo(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user

    with {:ok, project} <- buscar(user, slug) do
      remover_webhook(user, project)

      case Projects.disconnect_repo(user, slug) do
        {:ok, project} ->
          conn
          |> put_flash(:info, "Repositório desconectado. O XP já conquistado fica.")
          |> redirect(to: ~p"/jogar/#{project.slug}")

        {:error, motivo} ->
          desviar(conn, motivo, slug)
      end
    else
      {:error, motivo} -> desviar(conn, motivo, slug)
    end
  end

  # Conectar o repositório e instalar o webhook são coisas separadas de
  # propósito: se o GitHub não conseguir alcançar este servidor — o caso normal
  # em desenvolvimento, sem túnel —, o repositório continua ligado e a tela diz
  # o que falta, em vez de desfazer tudo e não explicar nada.
  defp instalar_webhook(conn, user, project) do
    %{token: token, secret: secret} = Projects.new_webhook_credentials()

    case webhook_url(token) do
      {:error, :sem_url_publica} ->
        put_flash(
          conn,
          :error,
          "#{project.repo_full_name} conectado, mas o webhook não foi instalado: " <>
            "este servidor não tem endereço público. Suba um túnel e defina WEBHOOK_BASE_URL."
        )

      {:ok, url} ->
        case Api.create_hook(user.github_token, project.repo_full_name, url, secret) do
          {:ok, hook_id} ->
            {:ok, _project} = Projects.record_webhook(project, hook_id, token, secret)

            put_flash(
              conn,
              :info,
              "#{project.repo_full_name} conectado. A partir do próximo commit a barra começa a andar."
            )

          {:error, motivo} ->
            Logger.warning("não deu para criar o webhook: #{inspect(motivo)}")

            put_flash(
              conn,
              :error,
              "#{project.repo_full_name} conectado, mas não deu para instalar o webhook. " <>
                explicar(motivo)
            )
        end
    end
  end

  defp remover_webhook(user, %{webhook_id: id, repo_full_name: repo} = project)
       when is_integer(id) and is_binary(repo) do
    # Deixar hook órfão no repositório de alguém é sujeira nossa, não dela.
    case Api.delete_hook(user.github_token, repo, id) do
      :ok -> :ok
      {:error, motivo} -> Logger.warning("não deu para remover o webhook: #{inspect(motivo)}")
    end

    Projects.clear_webhook(project)
  end

  defp remover_webhook(_user, _project), do: :ok

  defp explicar(:already_exists),
    do:
      "Já existe um webhook com este endereço no repositório — apague-o no GitHub e tente de novo."

  defp explicar(:unauthorized),
    do: "O GitHub recusou a autorização. Autorize de novo e tente."

  defp explicar(:not_found),
    do: "O GitHub não encontrou esse repositório."

  defp explicar(_outro), do: "Tente de novo em instantes."

  defp webhook_url(token) do
    case Application.get_env(:commitcraft, :webhook_base_url) do
      base when is_binary(base) and base != "" ->
        {:ok, String.trim_trailing(base, "/") <> "/webhooks/github/" <> token}

      _sem_base ->
        {:error, :sem_url_publica}
    end
  end

  defp ampliar(conn, slug) do
    redirect(conn, to: ~p"/auth/github/ampliar?voltar=#{~p"/jogar/#{slug}/repositorio"}")
  end

  defp buscar(user, slug) do
    case Projects.get_project(user, slug) do
      nil -> {:error, :not_found}
      project -> {:ok, project}
    end
  end

  # O escopo `repo` é pedido aqui, não no login — e o caminho de volta vai
  # junto, para a pessoa cair de novo na tela que ela queria.
  defp exigir_escopo(user, slug) do
    if Accounts.has_github_scope?(user, "repo") do
      :ok
    else
      {:redirect, :ampliar, slug}
    end
  end

  defp inteiro(valor) do
    case Integer.parse(to_string(valor)) do
      {id, ""} -> {:ok, id}
      _outro -> {:error, :not_found}
    end
  end

  defp conectados(user) do
    user
    |> Projects.list_projects()
    |> Enum.reject(&is_nil(&1.repo_id))
    |> Map.new(&{&1.repo_id, &1})
  end

  defp desviar(conn, :not_found, _slug) do
    conn
    |> put_flash(:error, "Não encontrei esse projeto.")
    |> redirect(to: ~p"/jogar")
  end

  defp desviar(conn, :already_connected, slug) do
    conn
    |> put_flash(:error, "Esse repositório já está em outro projeto seu.")
    |> redirect(to: ~p"/jogar/#{slug}/repositorio")
  end

  defp desviar(conn, :unauthorized, slug) do
    # O token perdeu a validade — a pessoa revogou o app no GitHub, por
    # exemplo. Pedir de novo resolve, e é melhor do que mostrar "deu erro".
    conn
    |> put_flash(:error, "O GitHub não aceitou mais essa autorização. Autorize de novo.")
    |> redirect(to: ~p"/auth/github/ampliar?voltar=#{~p"/jogar/#{slug}/repositorio"}")
  end

  defp desviar(conn, _outro, slug) do
    conn
    |> put_flash(:error, "Não deu para falar com o GitHub agora. Tente de novo.")
    |> redirect(to: ~p"/jogar/#{slug}")
  end

  defp render_show(conn, project, changeset) do
    conn
    |> assign(:page_title, project.name)
    |> assign(:project, project)
    |> assign(:progress, Level.progress(project.xp))
    |> assign(:changeset, changeset)
    |> assign(:events, Projects.list_events(project))
    |> assign(:listening?, Projects.listening?(project))
    |> render(:show)
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

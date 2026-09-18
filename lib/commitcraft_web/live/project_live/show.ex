defmodule CommitCraftWeb.ProjectLive.Show do
  @moduledoc """
  A tela de um projeto, ao vivo.

  Quando um commit chega pelo webhook, o processo que atendeu a entrega avisa
  pelo PubSub e esta tela se atualiza sozinha — sem recarregar, sem consultar de
  tempos em tempos. É o motivo de o CommitCraft ser Phoenix.
  """
  use CommitCraftWeb, :live_view

  alias CommitCraft.Game.Class
  alias CommitCraft.Game.Heatmap
  alias CommitCraft.Game.Level
  alias CommitCraft.GitHub.Api
  alias CommitCraft.Projects

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Projects.get_project(socket.assigns.current_user, slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Não encontrei esse projeto.")
         |> push_navigate(to: ~p"/jogar")}

      project ->
        # Só a conexão de verdade escuta: o primeiro render é HTTP e morre em
        # seguida, então inscrever ali deixaria assinatura órfã.
        if connected?(socket), do: Projects.subscribe(project)

        {:ok,
         socket
         |> carregar(project)
         |> assign(:level_up, nil)
         # Vazio no primeiro render de propósito: sem isso, `phx-mounted`
         # dispararia para tudo que já estava lá e a tela inteira piscaria como
         # se o projeto todo tivesse acontecido agora.
         |> assign(:recem_chegados, MapSet.new())}
    end
  end

  @impl true
  def handle_info({:project_advanced, %{project: atualizado} = novidade}, socket) do
    antes = socket.assigns.progress.level

    socket =
      socket
      |> carregar(atualizado)
      |> assign(:recem_chegados, ids_novos(novidade))

    depois = socket.assigns.progress.level

    socket =
      cond do
        depois > antes ->
          # O nível subir é o momento que o jogo inteiro existe para produzir.
          # Fica na tela por alguns segundos e sai sozinho.
          Process.send_after(self(), :esconder_level_up, 6_000)

          socket
          |> assign(:level_up, depois)
          |> push_event("som", %{tipo: "level_up"})

        novidade.achievements != [] ->
          push_event(socket, "som", %{tipo: "conquista"})

        # Um som por entrega, não um por commit: um push com trinta commits
        # viraria metralhadora.
        novidade.events != [] ->
          push_event(socket, "som", %{tipo: "xp"})

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_info(:esconder_level_up, socket), do: {:noreply, assign(socket, :level_up, nil)}

  @impl true
  def handle_event("rename", %{"project" => params}, socket) do
    user = socket.assigns.current_user

    case Projects.rename_project(user, socket.assigns.project.slug, params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Agora se chama \"#{project.name}\".")
         |> push_patch(to: ~p"/jogar/#{project.slug}")}

      {:error, :not_found} ->
        {:noreply, sumiu(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :project))}
    end
  end

  def handle_event("delete", _params, socket) do
    case Projects.delete_project(socket.assigns.current_user, socket.assigns.project.slug) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "\"#{project.name}\" foi apagado.")
         |> push_navigate(to: ~p"/jogar")}

      :error ->
        {:noreply, sumiu(socket)}
    end
  end

  def handle_event("toggle_public", _params, socket) do
    %{current_user: user, project: project} = socket.assigns

    case Projects.set_visibility(user, project.slug, not project.public) do
      {:ok, project} ->
        aviso =
          if project.public,
            do: "Página pública aberta. Qualquer um com o link vê este projeto.",
            else: "Página pública fechada."

        {:noreply, socket |> put_flash(:info, aviso) |> carregar(project)}

      {:error, :not_found} ->
        {:noreply, sumiu(socket)}
    end
  end

  def handle_event("disconnect_repo", _params, socket) do
    %{current_user: user, project: project} = socket.assigns

    remover_hook_do_github(user, project)
    {:ok, project} = Projects.disconnect_repo(user, project.slug)

    {:noreply,
     socket
     |> put_flash(:info, "Repositório desconectado. O XP já conquistado fica.")
     |> carregar(project)}
  end

  def handle_event("save_integration", %{"source" => source, "secret" => secret}, socket) do
    secret = String.trim(secret)

    cond do
      source not in ["vercel", "stripe"] ->
        {:noreply, sumiu(socket)}

      secret == "" ->
        {:noreply,
         put_flash(socket, :error, "Cole o segredo de assinatura que o painel mostrou.")}

      true ->
        {:ok, _webhook} = Projects.put_webhook(socket.assigns.project, source, %{secret: secret})

        {:noreply,
         socket
         |> put_flash(:info, "#{nome_da_fonte(source)} conectado.")
         |> carregar(socket.assigns.project)}
    end
  end

  def handle_event("remove_integration", %{"source" => source}, socket) do
    if source in ["vercel", "stripe"] do
      :ok = Projects.delete_webhook(socket.assigns.project, source)

      {:noreply,
       socket
       |> put_flash(:info, "#{nome_da_fonte(source)} desconectado. O XP já conquistado fica.")
       |> carregar(socket.assigns.project)}
    else
      {:noreply, sumiu(socket)}
    end
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    # Renomear troca o apelido na URL; recarregar aqui mantém a tela coerente
    # com o endereço sem perder a conexão.
    case Projects.get_project(socket.assigns.current_user, slug) do
      nil -> {:noreply, socket}
      project -> {:noreply, carregar(socket, project)}
    end
  end

  # O que acabou de chegar ganha animação; o resto entra em silêncio.
  defp ids_novos(%{events: eventos, achievements: conquistas}) do
    MapSet.new(
      Enum.map(eventos, &{:event, &1.id}) ++ Enum.map(conquistas, &{:achievement, &1.id})
    )
  end

  defp carregar(socket, project) do
    # O mapa de calor olha o ano inteiro, não só o que a lista mostra.
    todos = Projects.list_events(project, limit: 2000)

    if project.repo_full_name do
      for fonte <- ["vercel", "stripe"], do: Projects.ensure_webhook_token(project, fonte)
    end

    socket
    |> assign_new(:recem_chegados, fn -> MapSet.new() end)
    |> assign(:page_title, project.name)
    |> assign(:project, project)
    |> assign(:progress, Level.progress(project.xp))
    |> assign(:form, to_form(Projects.change_project(project), as: :project))
    |> assign(:events, Projects.list_events(project))
    |> assign(:achievements, Projects.list_achievements(project))
    |> assign(:webhooks, Projects.webhooks_by_source(project))
    |> assign(:listening?, Projects.listening?(project))
    |> assign(:streak_status, Projects.streak_status(project))
    # A classe olha o histórico inteiro, não só os últimos que a tela mostra:
    # um projeto não deixa de ser Maratonista porque a lista foi cortada em 30.
    |> assign(:class, Class.for_events(todos))
    |> assign(:heatmap, Heatmap.build(todos))
    |> assign(:reveal_titles, Projects.reveal_titles?(project))
  end

  defp remover_hook_do_github(user, project) do
    hook = Projects.get_webhook(project, "github")

    if hook && hook.external_id && project.repo_full_name do
      Api.delete_hook(user.github_token, project.repo_full_name, hook.external_id)
    end

    Projects.delete_webhook(project, "github")
  end

  @doc """
  O trecho de markdown do selo, pronto para colar.

  Montado aqui e não no template porque HEEx preserva a indentação dentro de
  `whitespace-pre`, e o que a pessoa copia não pode vir com espaços na frente.
  """
  def markdown_do_selo(login, slug) do
    pagina = url(~p"/p/#{login}/#{slug}")
    selo = url(~p"/p/#{login}/#{slug}/badge.svg")

    "[![CommitCraft](#{selo})](#{pagina})"
  end

  defp sumiu(socket) do
    socket
    |> put_flash(:error, "Não encontrei esse projeto.")
    |> push_navigate(to: ~p"/jogar")
  end

  defp nome_da_fonte("vercel"), do: "Vercel"
  defp nome_da_fonte("stripe"), do: "Stripe"
  defp nome_da_fonte(outra), do: outra
end

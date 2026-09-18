defmodule CommitCraftWeb.ProjectLiveTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures
  import Phoenix.LiveViewTest

  alias CommitCraft.Projects

  setup %{conn: conn} do
    user = user_fixture(login: "yagofontanez", name: "Yago")
    %{conn: log_in_user(conn, user), user: user}
  end

  defp commit(sha, titulo, xp \\ 5) do
    %{
      kind: "commit",
      title: titulo,
      xp: xp,
      occurred_at: DateTime.utc_now(:second),
      external_id: sha,
      meta: %{}
    }
  end

  describe "abrir" do
    test "mostra o projeto e o estado dele", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Minha Loja", xp: 6940})

      {:ok, _live, html} = live(conn, ~p"/jogar/minha-loja")

      assert html =~ "Minha Loja"
      assert html =~ "LV 07"
      assert html =~ "1.240 / 2.000 XP"
    end

    test "projeto de outra pessoa responde igual a inexistente", %{conn: conn} do
      project_fixture(user_fixture(), %{name: "Segredo Alheio"})

      assert {:error, {:live_redirect, %{to: "/jogar"}}} = live(conn, ~p"/jogar/segredo-alheio")
      assert {:error, {:live_redirect, %{to: "/jogar"}}} = live(conn, ~p"/jogar/nunca-existiu")
    end

    test "exige estar logado", %{} do
      user = user_fixture()
      project_fixture(user, %{name: "Meu"})

      assert {:error, {:redirect, %{to: "/"}}} = live(build_conn(), ~p"/jogar/meu")
    end
  end

  describe "ao vivo" do
    test "a barra sobe quando um commit chega, sem recarregar", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu"})

      {:ok, live, html} = live(conn, ~p"/jogar/meu")
      assert html =~ "0 / 200 XP"

      # O webhook roda noutro processo; aqui simulamos exatamente isso.
      {:ok, _} = Projects.record_events(project, [commit("abc", "feat: algo")])

      assert render(live) =~ "5 / 200 XP"
      assert render(live) =~ "feat: algo"
    end

    test "o aviso de nível novo aparece só quando o nível muda", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu"})

      # O XP é a soma dos eventos, então o estado inicial também precisa ser
      # feito de eventos — escrever no campo seria apagado no primeiro webhook.
      {:ok, _} = Projects.record_events(project, [commit("base", "trabalho anterior", 190)])

      {:ok, live, _html} = live(conn, ~p"/jogar/meu")
      refute render(live) =~ "LEVEL UP"

      # 190 + 5 ainda é nível 1.
      {:ok, _} = Projects.record_events(project, [commit("a", "quase")])
      refute render(live) =~ "LEVEL UP"

      # 195 + 5 chega a 200, que é o nível 2.
      {:ok, _} = Projects.record_events(project, [commit("b", "chegou")])
      html = render(live)

      assert html =~ "LEVEL UP"
      assert html =~ "LV 02"
    end

    test "conquista destravada aparece sozinha na tela", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu"})

      {:ok, live, html} = live(conn, ~p"/jogar/meu")
      refute html =~ "Não Fui Eu"

      {:ok, _} = Projects.record_events(project, [commit("r", "Revert \"feat: algo\"")])

      assert render(live) =~ "Não Fui Eu"
    end

    test "ao abrir, nada é marcado como novidade", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu"})
      {:ok, _} = Projects.record_events(project, [commit("a", "coisa antiga")])

      {:ok, _live, html} = live(conn, ~p"/jogar/meu")

      # `phx-mounted` dispara para todo elemento que entra no DOM, inclusive no
      # primeiro carregamento. Sem essa distinção, a tela inteira piscaria como
      # se o projeto todo tivesse acontecido agora.
      refute html =~ "bloco-entrada"
      assert html =~ "coisa antiga"
    end

    test "o que chega ao vivo é marcado como novidade", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu"})
      {:ok, _} = Projects.record_events(project, [commit("a", "coisa antiga")])

      {:ok, live, _html} = live(conn, ~p"/jogar/meu")

      {:ok, _} = Projects.record_events(project, [commit("b", "acabou de chegar")])
      html = render(live)

      assert html =~ "bloco-entrada"
      assert html =~ "acabou de chegar"
    end

    test "só recebe as novidades do próprio projeto", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Meu"})
      outro = project_fixture(user, %{name: "Outro"})

      {:ok, live, _html} = live(conn, ~p"/jogar/meu")

      {:ok, _} = Projects.record_events(outro, [commit("x", "coisa do outro projeto")])

      refute render(live) =~ "coisa do outro projeto"
      assert render(live) =~ "0 / 200 XP"
    end
  end

  describe "renomear" do
    test "troca o nome e o endereço sem sair da tela", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Teste"})

      {:ok, live, _html} = live(conn, ~p"/jogar/teste")

      live
      |> form("form[phx-submit=rename]", project: %{name: "Minha Loja"})
      |> render_submit()

      assert_patched(live, ~p"/jogar/minha-loja")
      assert render(live) =~ "Minha Loja"
      assert Projects.get_project(user, "minha-loja")
    end

    test "nome inválido mostra o erro sem perder o que foi digitado", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Intacto"})

      {:ok, live, _html} = live(conn, ~p"/jogar/intacto")

      html =
        live
        |> form("form[phx-submit=rename]", project: %{name: "x"})
        |> render_submit()

      assert html =~ "O nome"
      assert html =~ ~s(value="x")
      assert Projects.get_project(user, "intacto").name == "Intacto"
    end
  end

  describe "apagar" do
    test "apaga e volta para a lista", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Descartável"})

      {:ok, live, _html} = live(conn, ~p"/jogar/descartavel")

      live |> element("button[phx-click=delete]") |> render_click()

      assert_redirect(live, ~p"/jogar")
      assert Projects.list_projects(user) == []
    end
  end

  describe "integrações" do
    setup %{user: user} do
      project = project_fixture(user, %{name: "Meu"})

      {:ok, project} =
        Projects.connect_repo(user, project.slug, %{
          id: 7,
          full_name: "yagofontanez/commitcraft",
          private: false
        })

      %{project: project}
    end

    test "colar o segredo conecta a fonte", %{conn: conn, project: project} do
      {:ok, live, html} = live(conn, ~p"/jogar/meu")
      assert html =~ "não conectado"

      html =
        live
        |> form("#integracao-vercel", source: "vercel", secret: "segredo-da-vercel")
        |> render_submit()

      assert html =~ "escutando"
      assert Projects.connected?(Projects.get_webhook(project, "vercel"))
    end

    test "segredo em branco não conecta nada", %{conn: conn, project: project} do
      {:ok, live, _html} = live(conn, ~p"/jogar/meu")

      live
      |> render_submit("save_integration", %{"source" => "vercel", "secret" => "   "})

      refute Projects.connected?(Projects.get_webhook(project, "vercel"))
    end

    test "fonte inventada não vira webhook", %{conn: conn, project: project} do
      {:ok, live, _html} = live(conn, ~p"/jogar/meu")

      live |> render_submit("save_integration", %{"source" => "bitcoin", "secret" => "x"})

      assert is_nil(Projects.get_webhook(project, "bitcoin"))
    end

    test "desconectar não apaga o XP", %{conn: conn, user: user, project: project} do
      {:ok, _} = Projects.record_events(project, [commit("a", "feat: algo")])
      {:ok, _} = Projects.put_webhook(project, "vercel", %{secret: "s"})

      {:ok, live, _html} = live(conn, ~p"/jogar/meu")

      live
      |> element("button[phx-click=remove_integration][phx-value-source=vercel]")
      |> render_click()

      refute Projects.connected?(Projects.get_webhook(project, "vercel"))
      assert Projects.get_project(user, "meu").xp == 5
    end
  end
end

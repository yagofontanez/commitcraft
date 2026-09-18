defmodule CommitCraftWeb.ProjectControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.GitHubStub, only: [stub: 1, repo: 1]
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Accounts
  alias CommitCraft.Projects

  setup %{conn: conn} do
    user = user_fixture(login: "yagofontanez", name: "Yago")
    %{conn: log_in_user(conn, user), user: user}
  end

  # Quem já ampliou a autorização e pode enxergar os repositórios.
  defp com_escopo_repo(user) do
    {:ok, user} =
      Accounts.update_github_credentials(user, %{token: "gho_repo", scopes: ["read:user", "repo"]})

    user
  end

  describe "GET /jogar" do
    test "mostra a vaga vazia de quem ainda não começou", %{conn: conn} do
      html = conn |> get(~p"/jogar") |> html_response(200)

      assert html =~ "Vaga vazia"
      assert html =~ "Seus projetos"
    end

    test "lista os projetos com nível e XP", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Minha Loja", xp: 6940})

      html = conn |> get(~p"/jogar") |> html_response(200)

      refute html =~ "Vaga vazia"
      assert html =~ "Minha Loja"
      assert html =~ "LV 07"
      assert html =~ "1.240 / 2.000 XP"
    end

    test "não mostra projeto de outra pessoa", %{conn: conn} do
      project_fixture(user_fixture(), %{name: "Segredo Alheio"})

      html = conn |> get(~p"/jogar") |> html_response(200)

      refute html =~ "Segredo Alheio"
      assert html =~ "Vaga vazia"
    end

    test "exige estar logado", %{} do
      assert build_conn() |> get(~p"/jogar") |> redirected_to() == ~p"/"
    end
  end

  describe "POST /jogar" do
    test "cria e leva para o projeto", %{conn: conn, user: user} do
      conn = post(conn, ~p"/jogar", %{"project" => %{"name" => "Minha Loja"}})

      assert redirected_to(conn) == ~p"/jogar/minha-loja"
      assert [%{name: "Minha Loja", xp: 0}] = Projects.list_projects(user)
    end

    test "nome inválido volta para a lista com o erro, sem criar nada", %{conn: conn, user: user} do
      conn = post(conn, ~p"/jogar", %{"project" => %{"name" => "x"}})

      assert html_response(conn, 422) =~ "Seus projetos"
      assert Projects.list_projects(user) == []
    end

    test "o projeto nasce no nível 1 com a barra zerada", %{conn: conn} do
      conn = post(conn, ~p"/jogar", %{"project" => %{"name" => "Recém-nascido"}})

      html = conn |> get(redirected_to(conn)) |> html_response(200)

      assert html =~ "LV 01"
      assert html =~ "0 / 200 XP"
    end
  end

  describe "GET /jogar/:slug/repositorio" do
    test "manda ampliar a autorização quem ainda só tem read:user", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Meu"})

      conn = get(conn, ~p"/jogar/meu/repositorio")

      # O escopo pesado é pedido aqui, não no login — e o caminho de volta vai
      # junto, para a pessoa cair de novo na tela que ela queria.
      destino = redirected_to(conn)
      assert destino =~ "/auth/github/ampliar"
      assert destino =~ URI.encode_www_form("/jogar/meu/repositorio")
    end

    test "lista os repositórios de quem já ampliou", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Meu"})
      conn = log_in_user(conn, com_escopo_repo(user))

      stub(repos: [repo(%{"id" => 1, "name" => "commitcraft"})])

      html = conn |> get(~p"/jogar/meu/repositorio") |> html_response(200)

      assert html =~ "commitcraft"
      assert html =~ "Escolha o repositório"
    end

    test "marca o repositório que já está em outro projeto", %{conn: conn, user: user} do
      ocupado = project_fixture(user, %{name: "Já Conectado"})
      project_fixture(user, %{name: "Novo"})
      conn = log_in_user(conn, com_escopo_repo(user))

      {:ok, _} =
        Projects.connect_repo(user, ocupado.slug, %{
          id: 1,
          full_name: "yagofontanez/commitcraft",
          private: false
        })

      stub(repos: [repo(%{"id" => 1})])

      html = conn |> get(~p"/jogar/novo/repositorio") |> html_response(200)

      assert html =~ "já está em"
      assert html =~ "Já Conectado"
    end

    test "token recusado pelo GitHub manda reautorizar, não mostra erro", %{
      conn: conn,
      user: user
    } do
      project_fixture(user, %{name: "Meu"})
      conn = log_in_user(conn, com_escopo_repo(user))

      stub(status: 401)

      conn = get(conn, ~p"/jogar/meu/repositorio")

      assert redirected_to(conn) =~ "/auth/github/ampliar"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não aceitou mais"
    end
  end

  describe "POST /jogar/:slug/repositorio" do
    test "conecta e guarda o que o GitHub disse, não o que o formulário mandou", %{
      conn: conn,
      user: user
    } do
      project_fixture(user, %{name: "Meu"})
      conn = log_in_user(conn, com_escopo_repo(user))

      stub(
        repos: [repo(%{"id" => 7, "full_name" => "yagofontanez/commitcraft", "private" => true})]
      )

      conn = post(conn, ~p"/jogar/meu/repositorio", %{"repo_id" => "7"})

      assert redirected_to(conn) == ~p"/jogar/meu"

      project = Projects.get_project(user, "meu")
      assert project.repo_id == 7
      assert project.repo_full_name == "yagofontanez/commitcraft"
      assert project.repo_private == true
      assert project.repo_connected_at
    end

    test "recusa id de repositório a que a pessoa não tem acesso", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Meu"})
      conn = log_in_user(conn, com_escopo_repo(user))

      # O GitHub responde 404 para id que o token não enxerga — é ele quem
      # decide o acesso, não o nosso formulário.
      stub(repos: [repo(%{"id" => 7})])

      conn = post(conn, ~p"/jogar/meu/repositorio", %{"repo_id" => "999999"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error)
      assert is_nil(Projects.get_project(user, "meu").repo_id)
    end

    test "não deixa dois projetos apontarem para o mesmo repositório", %{conn: conn, user: user} do
      primeiro = project_fixture(user, %{name: "Primeiro"})
      project_fixture(user, %{name: "Segundo"})
      conn = log_in_user(conn, com_escopo_repo(user))

      {:ok, _} =
        Projects.connect_repo(user, primeiro.slug, %{
          id: 7,
          full_name: "yagofontanez/commitcraft",
          private: false
        })

      stub(repos: [repo(%{"id" => 7})])

      conn = post(conn, ~p"/jogar/segundo/repositorio", %{"repo_id" => "7"})

      # Dois projetos no mesmo repo contariam cada commit duas vezes.
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "já está em outro projeto"
      assert is_nil(Projects.get_project(user, "segundo").repo_id)
    end

    test "não conecta em projeto de outra pessoa", %{conn: conn, user: user} do
      dona = user_fixture()
      project_fixture(dona, %{name: "Alheio"})
      conn = log_in_user(conn, com_escopo_repo(user))

      stub(repos: [repo(%{"id" => 7})])

      conn = post(conn, ~p"/jogar/alheio/repositorio", %{"repo_id" => "7"})

      assert redirected_to(conn) == ~p"/jogar"
      assert is_nil(Projects.get_project(dona, "alheio").repo_id)
    end
  end
end

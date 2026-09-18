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

  describe "GET /jogar/:slug" do
    test "mostra o projeto e o estado dele", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Minha Loja", xp: 6940})

      html = conn |> get(~p"/jogar/minha-loja") |> html_response(200)

      assert html =~ "Minha Loja"
      assert html =~ "LV 07"
      assert html =~ "1.240 / 2.000 XP"
      assert html =~ "Nada aconteceu ainda"
    end

    test "oferece apagar, com o que se perde escrito em números", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Minha Loja", xp: 6940})

      html = conn |> get(~p"/jogar/minha-loja") |> html_response(200)

      assert html =~ "Apagar este projeto"
      # O aviso precisa dizer o tamanho do estrago, não só "tem certeza?".
      assert html =~ "o nível 7"
      assert html =~ "6.940 de XP"
      assert html =~ "Não dá para desfazer"
    end

    test "projeto de outra pessoa responde igual a projeto inexistente", %{conn: conn} do
      project_fixture(user_fixture(), %{name: "Segredo Alheio"})

      alheio = conn |> get(~p"/jogar/segredo-alheio")
      inexistente = conn |> get(~p"/jogar/nunca-existiu")

      # As duas respostas têm que ser indistinguíveis: dizer "existe, mas não é
      # seu" já conta algo sobre a conta de outra pessoa.
      assert redirected_to(alheio) == ~p"/jogar"
      assert redirected_to(inexistente) == ~p"/jogar"

      assert Phoenix.Flash.get(alheio.assigns.flash, :error) ==
               Phoenix.Flash.get(inexistente.assigns.flash, :error)
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

  describe "DELETE /jogar/:slug/repositorio" do
    test "desconecta mas preserva o XP conquistado", %{conn: conn, user: user} do
      project = project_fixture(user, %{name: "Meu", xp: 6940})

      {:ok, _} =
        Projects.connect_repo(user, project.slug, %{
          id: 7,
          full_name: "yagofontanez/commitcraft",
          private: false
        })

      conn = delete(conn, ~p"/jogar/meu/repositorio")

      assert redirected_to(conn) == ~p"/jogar/meu"

      desconectado = Projects.get_project(user, "meu")
      assert is_nil(desconectado.repo_id)
      assert is_nil(desconectado.repo_full_name)
      assert desconectado.xp == 6940, "desconectar não pode zerar o que já foi conquistado"
    end
  end

  describe "PUT /jogar/:slug" do
    test "renomeia e leva para o endereço novo", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Teste"})

      conn = put(conn, ~p"/jogar/teste", %{"project" => %{"name" => "Minha Loja"}})

      assert redirected_to(conn) == ~p"/jogar/minha-loja"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Minha Loja"
      assert Projects.get_project(user, "minha-loja").name == "Minha Loja"
    end

    test "nome inválido mostra o erro sem perder o que foi digitado", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Intacto"})

      conn = put(conn, ~p"/jogar/intacto", %{"project" => %{"name" => "x"}})
      html = html_response(conn, 422)

      # O formulário volta aberto, com o texto recusado ainda no campo.
      assert html =~ ~s(value="x")
      assert html =~ "O nome"
      assert Projects.get_project(user, "intacto").name == "Intacto"
    end

    test "não renomeia o projeto de outra pessoa", %{conn: conn} do
      dona = user_fixture()
      project_fixture(dona, %{name: "Segredo Alheio"})

      conn = put(conn, ~p"/jogar/segredo-alheio", %{"project" => %{"name" => "Roubado"}})

      assert redirected_to(conn) == ~p"/jogar"
      assert Projects.get_project(dona, "segredo-alheio").name == "Segredo Alheio"
    end

    test "exige estar logado", %{user: user} do
      project_fixture(user, %{name: "Intacto"})

      conn = build_conn() |> put(~p"/jogar/intacto", %{"project" => %{"name" => "Roubado"}})

      assert redirected_to(conn) == ~p"/"
      assert Projects.get_project(user, "intacto").name == "Intacto"
    end
  end

  describe "DELETE /jogar/:slug" do
    test "apaga e volta para a lista", %{conn: conn, user: user} do
      project_fixture(user, %{name: "Descartável"})

      conn = delete(conn, ~p"/jogar/descartavel")

      assert redirected_to(conn) == ~p"/jogar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Descartável"
      assert Projects.list_projects(user) == []
    end

    test "não apaga o projeto de outra pessoa", %{conn: conn} do
      dona = user_fixture()
      project_fixture(dona, %{name: "Segredo Alheio"})

      conn = delete(conn, ~p"/jogar/segredo-alheio")

      assert redirected_to(conn) == ~p"/jogar"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Não encontrei"
      assert [ainda_la] = Projects.list_projects(dona)
      assert ainda_la.name == "Segredo Alheio"
    end

    test "exige estar logado", %{user: user} do
      project_fixture(user, %{name: "Descartável"})

      assert build_conn() |> delete(~p"/jogar/descartavel") |> redirected_to() == ~p"/"
      assert length(Projects.list_projects(user)) == 1
    end
  end
end

defmodule CommitCraftWeb.ProjectControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Projects

  setup %{conn: conn} do
    user = user_fixture(login: "yagofontanez", name: "Yago")
    %{conn: log_in_user(conn, user), user: user}
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

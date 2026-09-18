defmodule CommitCraftWeb.AuthControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.GitHubStub, only: [stub: 1]

  alias CommitCraft.Accounts
  alias CommitCraft.Accounts.User
  alias CommitCraft.Repo

  # Faz o caminho de ida para gravar o `state` na sessão, como um navegador faria.
  defp com_state(conn, caminho \\ "/auth/github") do
    conn = get(conn, caminho)
    {conn, Plug.Conn.get_session(conn, :github_oauth).state}
  end

  describe "GET /auth/github" do
    test "manda para o GitHub com os dados certos", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")

      destino = redirected_to(conn, 302)
      assert destino =~ "https://github.com/login/oauth/authorize"

      %{query: query} = URI.parse(destino)
      params = URI.decode_query(query)

      assert params["client_id"] == "client-id-de-teste"
      assert params["redirect_uri"] =~ "/auth/github/callback"
      assert params["state"] == Plug.Conn.get_session(conn, :github_oauth).state
      assert params["state"] != nil
    end

    test "pede só leitura do perfil, nunca acesso ao código", %{conn: conn} do
      conn = get(conn, ~p"/auth/github")
      params = conn |> redirected_to(302) |> URI.parse() |> Map.get(:query) |> URI.decode_query()

      assert params["scope"] == "read:user"
      refute params["scope"] =~ "repo"
    end

    test "avisa quando o servidor não tem OAuth configurado", %{conn: conn} do
      # Um client_id em branco e o placeholder do arquivo de desenvolvimento
      # contam igual: mandar a pessoa para o GitHub com credencial falsa a joga
      # numa página de erro que não explica nada.
      for id <- [nil, "", "COLE_AQUI_O_CLIENT_ID"] do
        com_client_id(id, fn ->
          conn = get(conn, ~p"/auth/github")

          assert redirected_to(conn) == ~p"/"

          assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não está configurado",
                 "client_id #{inspect(id)} deveria contar como não configurado"
        end)
      end
    end

    defp com_client_id(id, fun) do
      chave = CommitCraft.GitHub.OAuth
      anterior = Application.get_env(:commitcraft, chave)
      Application.put_env(:commitcraft, chave, Keyword.put(anterior, :client_id, id))

      try do
        fun.()
      after
        Application.put_env(:commitcraft, chave, anterior)
      end
    end
  end

  describe "GET /auth/github/callback" do
    test "cria a conta e abre a sessão", %{conn: conn} do
      stub([])
      {conn, state} = com_state(conn)

      conn = get(conn, ~p"/auth/github/callback?code=codigo-valido&state=#{state}")

      assert redirected_to(conn) == ~p"/jogar"

      user = Repo.get_by!(User, github_id: 4242)
      assert user.github_login == "yagofontanez"
      assert user.github_token == "gho_abc"
      assert user.github_scopes == ["read:user"]
      assert Plug.Conn.get_session(conn, :user_id) == user.id
    end

    test "entrar duas vezes não cria conta duplicada", %{conn: _conn} do
      stub([])

      for _ <- 1..2 do
        {c, state} = com_state(build_conn())
        get(c, ~p"/auth/github/callback?code=codigo&state=#{state}")
      end

      assert Repo.aggregate(User, :count) == 1
    end

    test "recusa quando o state não confere", %{conn: conn} do
      stub([])
      {conn, _state} = com_state(conn)

      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=state-de-outra-pessoa")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "partiu daqui"
      assert Repo.aggregate(User, :count) == 0
      refute Plug.Conn.get_session(conn, :user_id)
    end

    test "recusa quando não houve ida, só volta", %{conn: conn} do
      stub([])

      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=qualquer")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expirou"
      assert Repo.aggregate(User, :count) == 0
    end

    test "quem desiste no GitHub volta em silêncio", %{conn: conn} do
      conn = get(conn, ~p"/auth/github/callback?error=access_denied")

      assert redirected_to(conn) == ~p"/"
      # Desistir não é erro: a página não deve gritar com quem mudou de ideia.
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      assert Repo.aggregate(User, :count) == 0
    end

    test "sobrevive ao GitHub recusando o código", %{conn: conn} do
      # O GitHub responde 200 mesmo ao recusar; o erro vem no corpo.
      stub(token: %{"error" => "bad_verification_code"})

      {conn, state} = com_state(conn)
      conn = get(conn, ~p"/auth/github/callback?code=expirado&state=#{state}")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Não deu para falar com o GitHub"
      assert Repo.aggregate(User, :count) == 0
    end
  end

  describe "GET /auth/github/ampliar" do
    test "pede o escopo repo, que o login não pede", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/auth/github/ampliar")

      params = conn |> redirected_to(302) |> URI.parse() |> Map.get(:query) |> URI.decode_query()

      assert params["scope"] == "read:user repo"
    end

    test "exige estar logado", %{conn: conn} do
      assert conn |> get(~p"/auth/github/ampliar") |> redirected_to() == ~p"/"
    end

    test "amplia a autorização e volta para onde a pessoa estava", %{conn: conn} do
      user = user_fixture(id: 4242)
      assert user.github_scopes == ["read:user"]

      stub(token: CommitCraft.GitHubStub.token_com_repo())

      conn = log_in_user(conn, user)

      {conn, state} =
        com_state(conn, "/auth/github/ampliar?voltar=/jogar/meu-projeto/repositorio")

      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=#{state}")

      assert redirected_to(conn) == "/jogar/meu-projeto/repositorio"

      atualizado = CommitCraft.Accounts.get_user(user.id)
      assert atualizado.github_scopes == ["read:user", "repo"]
      assert atualizado.github_token == "gho_repo"
    end

    test "recusa quando a autorização volta de outra conta do GitHub", %{conn: conn} do
      user = user_fixture(id: 4242, login: "yagofontanez")

      # A tela do GitHub deixa trocar de conta no meio do caminho; sem esta
      # conferência, o token de uma conta grudaria na sessão de outra.
      stub(
        profile: %{"id" => 9999, "login" => "outra-pessoa", "name" => "Outra"},
        token: CommitCraft.GitHubStub.token_com_repo()
      )

      conn = log_in_user(conn, user)
      {conn, state} = com_state(conn, "/auth/github/ampliar")
      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=#{state}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "outra conta do GitHub"

      intacto = CommitCraft.Accounts.get_user(user.id)
      assert intacto.github_scopes == ["read:user"]
      refute intacto.github_token == "gho_repo"
    end

    test "o state de uma reautorização não serve para entrar como outra pessoa", %{conn: conn} do
      stub([])

      # Pega um state emitido para ampliação e tenta usá-lo sem sessão aberta.
      {conn_ampliar, state} =
        conn |> log_in_user(user_fixture(id: 4242)) |> com_state("/auth/github/ampliar")

      sessao = Plug.Conn.get_session(conn_ampliar, :github_oauth)

      conn =
        build_conn()
        |> Phoenix.ConnTest.init_test_session(%{github_oauth: sessao})
        |> get(~p"/auth/github/callback?code=codigo&state=#{state}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "sessão expirou"
      refute Plug.Conn.get_session(conn, :user_id)
    end
  end

  describe "DELETE /auth/sair" do
    test "fecha a sessão e esquece o token do GitHub", %{conn: conn} do
      user = user_fixture()
      assert user.github_token

      conn = conn |> log_in_user(user) |> delete(~p"/auth/sair")

      assert redirected_to(conn) == ~p"/"
      refute Plug.Conn.get_session(conn, :user_id)
      assert is_nil(Accounts.get_user(user.id).github_token)
    end
  end

  describe "GET /jogar" do
    test "manda para a porta quem não entrou", %{conn: conn} do
      conn = get(conn, ~p"/jogar")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Entre com o GitHub"
    end

    test "volta para onde a pessoa queria ir depois de entrar", %{conn: conn} do
      stub([])

      # Bate numa página protegida, é barrada, entra — e cai na página pedida.
      conn = get(conn, ~p"/jogar")
      {conn, state} = com_state(conn)
      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=#{state}")

      assert redirected_to(conn) == ~p"/jogar"
    end

    test "mostra quem entrou", %{conn: conn} do
      user = user_fixture(login: "yagofontanez", name: "Yago")

      html = conn |> log_in_user(user) |> get(~p"/jogar") |> html_response(200)

      assert html =~ "Yago"
      assert html =~ "yagofontanez"
      assert html =~ "Vaga vazia"
    end

    test "nunca põe o token do GitHub no HTML", %{conn: conn} do
      user = user_fixture()

      html = conn |> log_in_user(user) |> get(~p"/jogar") |> html_response(200)

      refute html =~ user.github_token
    end
  end
end

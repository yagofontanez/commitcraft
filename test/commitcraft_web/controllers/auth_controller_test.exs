defmodule CommitCraftWeb.AuthControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures

  alias CommitCraft.Accounts
  alias CommitCraft.Accounts.User
  alias CommitCraft.Repo

  # Nenhum teste aqui fala com o GitHub: o Req é desviado para este plug, que
  # responde conforme a rota pedida.
  defp stub_github(opts) do
    perfil =
      Keyword.get(opts, :profile, %{"id" => 4242, "login" => "yagofontanez", "name" => "Yago"})

    token = Keyword.get(opts, :token, %{"access_token" => "gho_abc", "scope" => "read:user"})

    Req.Test.stub(CommitCraft.GitHub.OAuth, fn conn ->
      case conn.request_path do
        "/login/oauth/access_token" -> Req.Test.json(conn, token)
        "/user" -> Req.Test.json(conn, perfil)
      end
    end)
  end

  # Faz o caminho de ida para gravar o `state` na sessão, como um navegador faria.
  defp com_state(conn) do
    conn = get(conn, ~p"/auth/github")
    {conn, Plug.Conn.get_session(conn, :github_oauth_state)}
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
      assert params["state"] == Plug.Conn.get_session(conn, :github_oauth_state)
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
      stub_github([])
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
      stub_github([])

      for _ <- 1..2 do
        {c, state} = com_state(build_conn())
        get(c, ~p"/auth/github/callback?code=codigo&state=#{state}")
      end

      assert Repo.aggregate(User, :count) == 1
    end

    test "recusa quando o state não confere", %{conn: conn} do
      stub_github([])
      {conn, _state} = com_state(conn)

      conn = get(conn, ~p"/auth/github/callback?code=codigo&state=state-de-outra-pessoa")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "partiu daqui"
      assert Repo.aggregate(User, :count) == 0
      refute Plug.Conn.get_session(conn, :user_id)
    end

    test "recusa quando não houve ida, só volta", %{conn: conn} do
      stub_github([])

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
      Req.Test.stub(CommitCraft.GitHub.OAuth, fn c ->
        # O GitHub responde 200 mesmo ao recusar; o erro vem no corpo.
        Req.Test.json(c, %{"error" => "bad_verification_code"})
      end)

      {conn, state} = com_state(conn)
      conn = get(conn, ~p"/auth/github/callback?code=expirado&state=#{state}")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Não deu para entrar"
      assert Repo.aggregate(User, :count) == 0
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
      stub_github([])

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

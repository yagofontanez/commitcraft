defmodule CommitCraftWeb.AuthController do
  @moduledoc """
  Entrada e saída pelo OAuth do GitHub.
  """
  use CommitCraftWeb, :controller

  require Logger

  alias CommitCraft.Accounts
  alias CommitCraft.GitHub.OAuth
  alias CommitCraftWeb.UserAuth

  @doc "Manda a pessoa autorizar no GitHub."
  def request(conn, _params) do
    if OAuth.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      conn
      |> put_session(:github_oauth_state, state)
      |> redirect(external: OAuth.authorize_url(state, callback_url()))
    else
      Logger.warning("""
      Login com GitHub não configurado.

      Crie um OAuth App em https://github.com/settings/developers com a callback
      URL #{callback_url()} e guarde as credenciais:

          mix commitcraft.dev_secrets

      Depois preencha config/dev.secret.exs e reinicie o servidor.
      """)

      conn
      |> put_flash(:error, "O login com GitHub ainda não está configurado neste servidor.")
      |> redirect(to: ~p"/")
    end
  end

  @doc """
  Recebe a pessoa de volta do GitHub.

  O `state` é conferido antes de qualquer outra coisa: sem isso, um atacante
  poderia fazer a vítima entrar na conta *dele* por um link preparado, e tudo
  que ela conectasse depois cairia no colo dele.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    esperado = get_session(conn, :github_oauth_state)
    conn = delete_session(conn, :github_oauth_state)

    cond do
      is_nil(esperado) ->
        recusar(conn, "A autorização expirou. Tente entrar de novo.")

      not Plug.Crypto.secure_compare(state, esperado) ->
        Logger.warning("state do OAuth não confere; possível tentativa de fixação de sessão")
        recusar(conn, "Não consegui confirmar que essa autorização partiu daqui.")

      true ->
        entrar(conn, code)
    end
  end

  # O GitHub manda `error=access_denied` quando a pessoa clica em "cancelar".
  # Isso não é falha: ela mudou de ideia, e a página não deve gritar com ela.
  def callback(conn, %{"error" => _error}) do
    conn
    |> delete_session(:github_oauth_state)
    |> redirect(to: ~p"/")
  end

  def callback(conn, _params), do: recusar(conn, "Faltou informação na volta do GitHub.")

  @doc "Sai."
  def delete(conn, _params), do: UserAuth.log_out_user(conn)

  defp entrar(conn, code) do
    with {:ok, credentials} <- OAuth.exchange_code(code, callback_url()),
         {:ok, profile} <- OAuth.fetch_user(credentials.token),
         {:ok, user} <- Accounts.upsert_from_github(profile, credentials) do
      conn
      |> put_flash(:info, "Bem-vindo, #{Accounts.User.display_name(user)}.")
      |> UserAuth.log_in_user(user)
    else
      {:error, reason} ->
        Logger.warning("login com GitHub falhou: #{inspect(reason)}")
        recusar(conn, "Não deu para entrar com o GitHub agora. Tente de novo.")
    end
  end

  defp recusar(conn, mensagem) do
    conn
    |> delete_session(:github_oauth_state)
    |> put_flash(:error, mensagem)
    |> redirect(to: ~p"/")
  end

  # Precisa bater exatamente com a URL cadastrada no OAuth App do GitHub.
  defp callback_url, do: url(~p"/auth/github/callback")
end

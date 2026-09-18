defmodule CommitCraftWeb.AuthController do
  @moduledoc """
  Entrada, saída e ampliação de permissão pelo OAuth do GitHub.

  Os dois fluxos — entrar e pedir acesso aos repositórios — voltam pela mesma
  URL de callback, porque o GitHub compara a `redirect_uri` com a cadastrada no
  OAuth App. O que os distingue é a intenção guardada na sessão junto do
  `state`, e não algo vindo na URL, que a pessoa poderia trocar.
  """
  use CommitCraftWeb, :controller

  require Logger

  alias CommitCraft.Accounts
  alias CommitCraft.GitHub.OAuth
  alias CommitCraftWeb.UserAuth

  @sessao :github_oauth

  @doc "Manda a pessoa autorizar o login."
  def request(conn, _params) do
    comecar(conn, :login, OAuth.login_scopes(), ~p"/")
  end

  @doc """
  Manda a pessoa ampliar a autorização para enxergar os repositórios.

  Só faz sentido para quem já entrou: a conta é a mesma, muda só a credencial.
  """
  def upgrade(conn, params) do
    volta = if params["voltar"] in [nil, ""], do: ~p"/jogar", else: params["voltar"]

    comecar(conn, :repo, OAuth.repo_scopes(), volta)
  end

  @doc """
  Recebe a pessoa de volta do GitHub.

  O `state` é conferido antes de qualquer outra coisa: sem isso, um atacante
  poderia fazer a vítima entrar na conta *dele* por um link preparado, e tudo
  que ela conectasse depois cairia no colo dele.
  """
  def callback(conn, %{"code" => code, "state" => state}) do
    pendente = get_session(conn, @sessao)
    conn = delete_session(conn, @sessao)

    cond do
      is_nil(pendente) ->
        recusar(conn, "A autorização expirou. Tente entrar de novo.")

      not Plug.Crypto.secure_compare(state, pendente.state) ->
        Logger.warning("state do OAuth não confere; possível tentativa de fixação de sessão")
        recusar(conn, "Não consegui confirmar que essa autorização partiu daqui.")

      true ->
        concluir(conn, code, pendente)
    end
  end

  # O GitHub manda `error=access_denied` quando a pessoa clica em "cancelar".
  # Isso não é falha: ela mudou de ideia, e a página não deve gritar com ela.
  def callback(conn, %{"error" => _error}) do
    volta = (get_session(conn, @sessao) || %{return_to: ~p"/"}).return_to

    conn
    |> delete_session(@sessao)
    |> redirect(to: volta)
  end

  def callback(conn, _params), do: recusar(conn, "Faltou informação na volta do GitHub.")

  @doc "Sai."
  def delete(conn, _params), do: UserAuth.log_out_user(conn)

  defp comecar(conn, intencao, scopes, volta) do
    if OAuth.configured?() do
      state = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

      conn
      |> put_session(@sessao, %{state: state, intent: intencao, return_to: volta})
      |> redirect(external: OAuth.authorize_url(state, callback_url(), scopes))
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

  defp concluir(conn, code, pendente) do
    with {:ok, credentials} <- OAuth.exchange_code(code, callback_url()),
         {:ok, profile} <- OAuth.fetch_user(credentials.token) do
      aplicar(conn, pendente, profile, credentials)
    else
      {:error, motivo} ->
        Logger.warning("autorização do GitHub falhou: #{inspect(motivo)}")
        recusar(conn, "Não deu para falar com o GitHub agora. Tente de novo.")
    end
  end

  defp aplicar(conn, %{intent: :login}, profile, credentials) do
    case Accounts.upsert_from_github(profile, credentials) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Bem-vindo, #{Accounts.User.display_name(user)}.")
        |> UserAuth.log_in_user(user)

      {:error, _changeset} ->
        recusar(conn, "Não deu para entrar com o GitHub agora. Tente de novo.")
    end
  end

  defp aplicar(conn, %{intent: :repo, return_to: volta}, profile, credentials) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        recusar(conn, "Sua sessão expirou no meio do caminho. Entre de novo.")

      user.github_id != profile.id ->
        # A tela do GitHub deixa trocar de conta no meio do caminho. Sem esta
        # conferência, o token de uma conta ficaria grudado na sessão de outra.
        Logger.warning("autorização voltou de uma conta diferente da que está na sessão")

        recusar(
          conn,
          "Essa autorização veio de outra conta do GitHub. Entre com @#{user.github_login} para continuar."
        )

      true ->
        {:ok, _user} = Accounts.update_github_credentials(user, credentials)

        conn
        |> put_flash(:info, "Pronto. Agora dá para escolher um repositório.")
        |> redirect(to: volta)
    end
  end

  defp recusar(conn, mensagem) do
    conn
    |> delete_session(@sessao)
    |> put_flash(:error, mensagem)
    |> redirect(to: ~p"/")
  end

  # Precisa bater exatamente com a URL cadastrada no OAuth App do GitHub.
  defp callback_url, do: url(~p"/auth/github/callback")
end

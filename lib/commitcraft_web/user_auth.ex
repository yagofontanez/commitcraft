defmodule CommitCraftWeb.UserAuth do
  @moduledoc """
  Sessão de quem está logado.

  A sessão guarda só o id do usuário, dentro do cookie assinado do Phoenix. Não
  há tabela de tokens: enquanto o CommitCraft não tiver nada a revogar à
  distância, uma tabela a mais só seria cerimônia. Quando existir "encerrar
  sessão nos outros aparelhos", isso muda.
  """
  use CommitCraftWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias CommitCraft.Accounts

  @doc """
  Abre a sessão e leva a pessoa para onde ela queria ir.

  O id da sessão é renovado no login: sem isso, quem tivesse plantado um cookie
  de sessão na vítima antes dela entrar continuaria dentro da sessão dela depois.
  """
  def log_in_user(conn, user) do
    destino = get_session(conn, :user_return_to) || signed_in_path()

    conn
    |> renew_session()
    |> put_session(:user_id, user.id)
    |> redirect(to: destino)
  end

  @doc "Encerra a sessão e esquece o token guardado do GitHub."
  def log_out_user(conn) do
    # Não há motivo para guardar uma credencial de acesso aos repositórios de
    # alguém que fechou a sessão. O próximo login traz um token novo.
    if user = conn.assigns[:current_user] do
      Accounts.forget_github_token(user)
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/")
  end

  @doc "Coloca o usuário da sessão em `conn.assigns.current_user` (ou nil)."
  def fetch_current_user(conn, _opts) do
    user =
      case get_session(conn, :user_id) do
        nil -> nil
        id -> Accounts.get_user(id)
      end

    assign(conn, :current_user, user)
  end

  @doc "Barra quem não está logado, lembrando para onde a pessoa queria ir."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "Entre com o GitHub para continuar.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  @doc "Para onde vai quem acabou de entrar."
  def signed_in_path, do: ~p"/jogar"

  defp renew_session(conn) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end

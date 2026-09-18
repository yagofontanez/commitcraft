defmodule CommitCraft.GitHub.OAuth do
  @moduledoc """
  O fluxo de autorização do GitHub.

  ## Escopo

  O login pede só `read:user` — o suficiente para saber quem é a pessoa. O escopo
  `repo`, que dá acesso ao código, só será pedido quando ela for de fato conectar
  um repositório. Pedir tudo na porta de entrada assusta, e com razão.

  Por isso `github_scopes` é guardado junto do token: é assim que dá para saber,
  mais tarde, se já temos permissão para uma ação ou se é preciso mandar a pessoa
  autorizar de novo.
  """
  require Logger

  @authorize_url "https://github.com/login/oauth/authorize"
  @token_url "https://github.com/login/oauth/access_token"
  @user_url "https://api.github.com/user"

  @login_scopes ["read:user"]

  @doc "Os escopos pedidos no login."
  def login_scopes, do: @login_scopes

  @doc """
  Para onde mandar a pessoa para autorizar.

  O `state` volta intacto no callback e é o que impede que alguém force uma
  sessão nossa com um código de autorização de outra pessoa.
  """
  def authorize_url(state, redirect_uri) do
    query =
      URI.encode_query(%{
        "client_id" => client_id(),
        "redirect_uri" => redirect_uri,
        "scope" => Enum.join(@login_scopes, " "),
        "state" => state,
        "allow_signup" => "true"
      })

    @authorize_url <> "?" <> query
  end

  @doc """
  Troca o código de autorização por um token de acesso.

  Devolve `{:ok, %{token: token, scopes: [...]}}`.
  """
  def exchange_code(code, redirect_uri) do
    request =
      request(
        url: @token_url,
        method: :post,
        headers: [{"accept", "application/json"}],
        json: %{
          client_id: client_id(),
          client_secret: client_secret(),
          code: code,
          redirect_uri: redirect_uri
        }
      )

    case Req.request(request) do
      # O GitHub responde 200 mesmo quando recusa o código; o erro vem no corpo.
      {:ok, %{status: 200, body: %{"access_token" => token} = body}} ->
        {:ok, %{token: token, scopes: parse_scopes(body["scope"])}}

      {:ok, %{status: 200, body: %{"error" => error} = body}} ->
        Logger.warning("GitHub recusou o código de autorização: #{inspect(body)}")
        {:error, {:github, error}}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        Logger.warning("falha ao falar com o GitHub: #{inspect(reason)}")
        {:error, {:transport, reason}}
    end
  end

  @doc """
  Lê o perfil de quem acabou de autorizar.

  Devolve `{:ok, %{id: id, login: login, name: name, avatar_url: url}}`.
  """
  def fetch_user(token) do
    request =
      request(
        url: @user_url,
        method: :get,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"authorization", "Bearer " <> token},
          {"x-github-api-version", "2022-11-28"}
        ]
      )

    case Req.request(request) do
      {:ok, %{status: 200, body: %{"id" => id, "login" => login} = body}}
      when is_integer(id) and is_binary(login) ->
        {:ok,
         %{
           id: id,
           login: login,
           name: body["name"],
           avatar_url: body["avatar_url"]
         }}

      {:ok, %{status: 200, body: body}} ->
        {:error, {:unexpected_body, body}}

      {:ok, %{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, reason} ->
        {:error, {:transport, reason}}
    end
  end

  @doc """
  Se o OAuth está configurado. Sem isso, o botão de entrar não deve aparecer.
  """
  def configured?, do: is_binary(client_id()) and client_id() != ""

  # O GitHub devolve os escopos concedidos separados por vírgula — e uma string
  # vazia quando não concedeu nenhum.
  defp parse_scopes(nil), do: []

  defp parse_scopes(scope) when is_binary(scope) do
    scope
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # As opções extras existem para os testes trocarem a camada HTTP por um plug,
  # sem nenhuma chamada de rede.
  defp request(opts) do
    Req.new(opts)
    |> Req.merge(Application.get_env(:commitcraft, :github_req_options, []))
  end

  defp client_id, do: config()[:client_id]
  defp client_secret, do: config()[:client_secret]
  defp config, do: Application.get_env(:commitcraft, __MODULE__, [])
end

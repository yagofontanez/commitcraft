defmodule CommitCraft.GitHubStub do
  @moduledoc """
  Respostas falsas do GitHub para os testes.

  Nenhum teste toca a rede: o Req é desviado para um plug, e este módulo decide
  o que responder conforme o caminho pedido.
  """
  import Plug.Conn, only: [put_status: 2]

  @perfil %{"id" => 4242, "login" => "yagofontanez", "name" => "Yago"}
  @token %{"access_token" => "gho_abc", "scope" => "read:user"}

  @doc """
  Monta o stub. Cada opção troca uma parte da resposta:

    * `:profile`, `:token` — o que o OAuth devolve
    * `:repos` — a lista de repositórios
    * `:status` — força um status em toda chamada de API, para testar o erro
  """
  def stub(opts \\ []) do
    perfil = Keyword.get(opts, :profile, @perfil)
    token = Keyword.get(opts, :token, @token)
    repos = Keyword.get(opts, :repos, [repo()])
    status = Keyword.get(opts, :status)
    hook_status = Keyword.get(opts, :hook_status)
    hook_id = Keyword.get(opts, :hook_id, 555)

    Req.Test.stub(CommitCraft.GitHub, fn conn ->
      cond do
        conn.request_path == "/login/oauth/access_token" ->
          Req.Test.json(conn, token)

        conn.request_path == "/user" ->
          Req.Test.json(conn, perfil)

        # Criar e remover webhook: `/repos/dono/nome/hooks[/id]`
        String.contains?(conn.request_path, "/hooks") ->
          cond do
            hook_status -> conn |> put_status(hook_status) |> Req.Test.json(%{"message" => "no"})
            conn.method == "DELETE" -> conn |> put_status(204) |> Req.Test.json(%{})
            true -> conn |> put_status(201) |> Req.Test.json(%{"id" => hook_id})
          end

        status ->
          conn |> put_status(status) |> Req.Test.json(%{"message" => "erro de teste"})

        conn.request_path == "/user/repos" ->
          Req.Test.json(conn, repos)

        String.starts_with?(conn.request_path, "/repositories/") ->
          id = conn.request_path |> String.split("/") |> List.last() |> String.to_integer()

          case Enum.find(repos, &(&1["id"] == id)) do
            nil -> conn |> put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
            achado -> Req.Test.json(conn, achado)
          end

        true ->
          conn |> put_status(404) |> Req.Test.json(%{"message" => "rota não ensinada ao stub"})
      end
    end)
  end

  @doc "Um repositório como o GitHub devolve."
  def repo(attrs \\ %{}) do
    id = Map.get(attrs, "id", System.unique_integer([:positive]))

    Enum.into(attrs, %{
      "id" => id,
      "name" => "commitcraft",
      "full_name" => "yagofontanez/commitcraft",
      "private" => false,
      "description" => "Um jogo sobre construir coisas",
      "pushed_at" => "2026-09-18T00:00:00Z"
    })
  end

  @doc "O token com escopos ampliados, como volta de uma reautorização."
  def token_com_repo, do: %{"access_token" => "gho_repo", "scope" => "read:user,repo"}
end

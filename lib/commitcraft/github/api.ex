defmodule CommitCraft.GitHub.Api do
  @moduledoc """
  As chamadas à API do GitHub feitas em nome de quem está logado.

  Separado de `CommitCraft.GitHub.OAuth` de propósito: aquele cuida de conseguir
  a credencial, este cuida de usá-la.
  """
  require Logger

  @base "https://api.github.com"

  @doc """
  Os repositórios em que a pessoa pode mexer, do mais recentemente empurrado
  para o mais antigo.

  Pede `affiliation=owner` porque conectar um repositório vai exigir criar um
  webhook nele, e isso só quem administra consegue — listar o que a pessoa não
  vai poder conectar seria oferecer um botão que falha.

  Devolve `{:ok, [%{id:, full_name:, private:, pushed_at:, description:}]}`.
  """
  def list_repos(token, opts \\ []) do
    por_pagina = Keyword.get(opts, :per_page, 100)

    resultado =
      get(token, "/user/repos",
        affiliation: "owner",
        sort: "pushed",
        direction: "desc",
        per_page: por_pagina
      )

    case resultado do
      {:ok, repos} when is_list(repos) -> {:ok, Enum.map(repos, &normalizar/1)}
      {:ok, outro} -> {:error, {:unexpected_body, outro}}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc """
  Um repositório pelo identificador numérico.

  Buscar de novo em vez de confiar no que o formulário mandou não é paranoia: o
  nome do repositório vem do navegador, e é o GitHub quem sabe se aquela pessoa
  realmente tem acesso àquele id.
  """
  def get_repo(token, repo_id) when is_integer(repo_id) do
    case get(token, "/repositories/#{repo_id}", []) do
      {:ok, %{"id" => _} = repo} -> {:ok, normalizar(repo)}
      {:ok, outro} -> {:error, {:unexpected_body, outro}}
      {:error, motivo} -> {:error, motivo}
    end
  end

  defp normalizar(repo) do
    %{
      id: repo["id"],
      full_name: repo["full_name"],
      name: repo["name"],
      private: repo["private"] == true,
      description: repo["description"],
      pushed_at: repo["pushed_at"]
    }
  end

  defp get(token, caminho, params) do
    request =
      request(
        url: @base <> caminho,
        method: :get,
        params: params,
        headers: [
          {"accept", "application/vnd.github+json"},
          {"authorization", "Bearer " <> token},
          {"x-github-api-version", "2022-11-28"}
        ]
      )

    case Req.request(request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      # O token perdeu a validade (a pessoa revogou o app, por exemplo). Quem
      # chama precisa saber disso para mandar autorizar de novo, em vez de
      # mostrar "deu erro".
      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, :unauthorized}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        Logger.warning("GitHub respondeu #{status} em #{caminho}")
        {:error, {:unexpected_status, status}}

      {:error, motivo} ->
        Logger.warning("falha ao falar com o GitHub: #{inspect(motivo)}")
        {:error, {:transport, motivo}}
    end
  end

  # As opções extras existem para os testes trocarem a camada HTTP por um plug,
  # sem nenhuma chamada de rede.
  defp request(opts) do
    Req.new(opts)
    |> Req.merge(Application.get_env(:commitcraft, :github_req_options, []))
  end
end

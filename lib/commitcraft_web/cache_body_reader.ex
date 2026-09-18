defmodule CommitCraftWeb.CacheBodyReader do
  @moduledoc """
  Guarda o corpo cru das requisições de webhook.

  O GitHub assina os bytes exatos que mandou. Depois que o `Plug.Parsers`
  transforma isso em mapa, reserializar não devolve os mesmos bytes — a ordem
  das chaves e o escape mudam — e a assinatura nunca confere. Por isso o corpo
  precisa ser guardado antes de ser interpretado.

  Só as rotas de webhook são guardadas; guardar o corpo de toda requisição seria
  memória jogada fora.
  """
  @caminho_webhook "/webhooks"

  def read_body(conn, opts) do
    {:ok, corpo, conn} = Plug.Conn.read_body(conn, opts)

    if webhook?(conn) do
      {:ok, corpo, Plug.Conn.assign(conn, :raw_body, corpo)}
    else
      {:ok, corpo, conn}
    end
  end

  defp webhook?(%{request_path: caminho}), do: String.starts_with?(caminho, @caminho_webhook)
end

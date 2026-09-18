defmodule CommitCraftWeb.WebhookController do
  @moduledoc """
  A porta por onde GitHub, Vercel e Stripe contam o que aconteceu.

  É a única rota pública que aceita escrita sem sessão, então tudo aqui parte do
  princípio de que quem bate pode não ser quem diz ser.
  """
  use CommitCraftWeb, :controller

  require Logger

  alias CommitCraft.Game.Rules
  alias CommitCraft.Projects
  alias CommitCraftWeb.WebhookSignature

  @doc """
  Recebe uma entrega.

  A resposta é sempre curta e rápida: os três serviços desistem de entregas
  lentas e passam a considerar o webhook quebrado.
  """
  def receive(conn, %{"source" => source, "token" => token}) do
    with :ok <- fonte_conhecida(source),
         {:ok, webhook, project} <- achar(token, source),
         :ok <- conferir(conn, source, webhook) do
      processar(conn, source, project)
    else
      {:error, :nao_encontrado} ->
        # Não dizemos se o token existe: quem estiver adivinhando não ganha
        # pista de qual tentativa chegou mais perto.
        responder(conn, 404, "no")

      {:error, motivo} ->
        Logger.warning("webhook #{source} recusado: #{inspect(motivo)}")
        responder(conn, 401, "no")
    end
  end

  defp processar(conn, source, project) do
    evento = nome_do_evento(conn, source)
    contexto = %{first_sale?: not Projects.has_event_kind?(project, "first_sale")}

    case Rules.events_for(source, evento, conn.body_params, contexto) do
      [] ->
        # Ping da criação do webhook, deploy de preview, evento que o jogo
        # ignora. Não houve erro — só não havia nada a pontuar.
        responder(conn, 200, "ok")

      acontecimentos ->
        {:ok, %{project: atualizado, events: novos}} =
          Projects.record_events(project, acontecimentos)

        Logger.info(
          "webhook #{source}/#{evento} em #{project.name}: " <>
            "#{length(novos)} de #{length(acontecimentos)} novos, XP agora #{atualizado.xp}"
        )

        responder(conn, 200, "ok")
    end
  end

  # Cada serviço põe o nome do evento num lugar diferente: GitHub e Vercel num
  # cabeçalho, Stripe dentro do próprio corpo.
  defp nome_do_evento(conn, "github"),
    do: conn |> get_req_header("x-github-event") |> List.first() |> to_string()

  defp nome_do_evento(conn, "vercel"), do: to_string(conn.body_params["type"])
  defp nome_do_evento(conn, "stripe"), do: to_string(conn.body_params["type"])

  defp fonte_conhecida(source) do
    if source in CommitCraft.Projects.Webhook.sources(),
      do: :ok,
      else: {:error, :nao_encontrado}
  end

  defp achar(token, source) do
    case Projects.get_webhook_by_token(token) do
      # O token tem que bater com a fonte da URL: sem isso, um token de GitHub
      # entregue em /webhooks/stripe seria conferido com o algoritmo errado.
      {%{source: ^source} = webhook, project} -> {:ok, webhook, project}
      _outro -> {:error, :nao_encontrado}
    end
  end

  defp conferir(conn, source, webhook) do
    corpo = conn.assigns[:raw_body]

    cond do
      is_nil(webhook.secret) -> {:error, :sem_segredo}
      is_nil(corpo) -> {:error, :sem_corpo}
      true -> WebhookSignature.verify(source, corpo, webhook.secret, conn.req_headers)
    end
  end

  defp responder(conn, status, corpo) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, corpo)
  end
end

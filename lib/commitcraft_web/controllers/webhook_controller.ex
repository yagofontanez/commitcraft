defmodule CommitCraftWeb.WebhookController do
  @moduledoc """
  A porta por onde o GitHub conta o que aconteceu.

  Esta é a única rota pública que aceita escrita sem sessão, então tudo aqui
  parte do princípio de que quem bate pode não ser o GitHub.
  """
  use CommitCraftWeb, :controller

  require Logger

  alias CommitCraft.Game.Rules
  alias CommitCraft.Projects

  @doc """
  Recebe uma entrega do GitHub.

  A resposta é sempre rápida e curta: o GitHub desiste de entregas lentas e
  passa a considerar o webhook quebrado.
  """
  def github(conn, %{"token" => token}) do
    evento = get_req_header(conn, "x-github-event") |> List.first()
    assinatura = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with {:ok, project} <- achar_projeto(token),
         :ok <- conferir_assinatura(conn, project, assinatura) do
      processar(conn, project, evento)
    else
      {:error, :nao_encontrado} ->
        # Não dizemos se o token existe: quem está tentando adivinhar não ganha
        # nenhuma pista de qual tentativa chegou mais perto.
        responder(conn, 404, "no")

      {:error, :assinatura} ->
        Logger.warning("webhook com assinatura inválida em #{inspect(token)}")
        responder(conn, 401, "no")
    end
  end

  defp processar(conn, project, evento) do
    acontecimentos = Rules.events_for(to_string(evento), conn.body_params)

    case acontecimentos do
      [] ->
        # `ping` e eventos que o jogo ignora caem aqui. Responder 200 é o certo:
        # não houve erro, só não havia nada a pontuar.
        responder(conn, 200, "ok")

      lista ->
        {:ok, %{project: atualizado, events: novos}} = Projects.record_events(project, lista)

        Logger.info(
          "webhook #{evento} em #{project.repo_full_name}: " <>
            "#{length(novos)} de #{length(lista)} novos, XP agora #{atualizado.xp}"
        )

        responder(conn, 200, "ok")
    end
  end

  defp achar_projeto(token) do
    case Projects.get_project_by_webhook_token(token) do
      nil -> {:error, :nao_encontrado}
      project -> {:ok, project}
    end
  end

  # A assinatura é HMAC-SHA256 do corpo cru com o segredo do projeto. Comparar
  # com `secure_compare` e não com `==` porque a comparação ingênua vaza, pelo
  # tempo que leva, quantos bytes iniciais estavam certos.
  defp conferir_assinatura(conn, project, "sha256=" <> recebida) do
    corpo = conn.assigns[:raw_body]
    segredo = project.webhook_secret

    cond do
      is_nil(segredo) or is_nil(corpo) ->
        {:error, :assinatura}

      true ->
        esperada =
          :hmac
          |> :crypto.mac(:sha256, segredo, corpo)
          |> Base.encode16(case: :lower)

        if Plug.Crypto.secure_compare(esperada, String.downcase(recebida)),
          do: :ok,
          else: {:error, :assinatura}
    end
  end

  defp conferir_assinatura(_conn, _project, _outra), do: {:error, :assinatura}

  defp responder(conn, status, corpo) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, corpo)
  end
end

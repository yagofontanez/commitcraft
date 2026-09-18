defmodule CommitCraft.Game.Rules do
  @moduledoc """
  A tabela de pontos, e como um evento do GitHub vira XP.

  Os valores vivem aqui e só aqui: a tabela que a página inicial mostra lê
  destas constantes, então a promessa e o motor não têm como discordar.

  Traduzir é função pura — recebe o que o GitHub mandou, devolve o que
  aconteceu no jogo. Nada de banco, nada de rede: é o pedaço mais fácil de
  errar e o mais barato de testar.
  """

  @xp %{
    commit: 5,
    issue_closed: 15,
    deploy: 25,
    pull_request_merged: 40,
    streak_week: 80,
    first_user: 100,
    first_sale: 250,
    broken_build: -30
  }

  @doc """
  Quanto vale cada tipo de acontecimento.

      iex> CommitCraft.Game.Rules.xp_for(:commit)
      5

      iex> CommitCraft.Game.Rules.xp_for(:broken_build)
      -30
  """
  def xp_for(kind) when is_map_key(@xp, kind), do: Map.fetch!(@xp, kind)

  @doc "A tabela inteira, para quem precisa mostrá-la."
  def table, do: @xp

  @doc """
  Traduz uma entrega do GitHub numa lista de acontecimentos do jogo.

  Devolve uma lista porque um único `push` carrega vários commits. Uma entrega
  que não interessa devolve lista vazia — não é erro: o GitHub manda `ping` ao
  criar o webhook, e manda eventos que o jogo simplesmente ignora.
  """
  def events_for("push", %{"commits" => commits} = payload) when is_list(commits) do
    if na_branch_principal?(payload) do
      commits
      |> Enum.filter(&novo?/1)
      |> Enum.map(&commit_event/1)
    else
      # Commit em branch de trabalho ainda não é progresso: o que conta é o que
      # chegou na branch principal. O pull request mesclado paga essa conta.
      []
    end
  end

  def events_for("pull_request", %{"action" => "closed", "pull_request" => pr}) do
    # "Fechado" e "mesclado" são coisas diferentes: fechar sem mesclar é
    # desistir, e desistir não dá XP.
    if pr["merged"] == true do
      [
        %{
          kind: "pull_request_merged",
          title: titulo(pr["title"], "Pull request ##{pr["number"]}"),
          xp: xp_for(:pull_request_merged),
          occurred_at: momento(pr["merged_at"]),
          external_id: "pr-#{pr["number"]}-merged"
        }
      ]
    else
      []
    end
  end

  def events_for("issues", %{"action" => "closed", "issue" => issue}) do
    [
      %{
        kind: "issue_closed",
        title: titulo(issue["title"], "Issue ##{issue["number"]}"),
        xp: xp_for(:issue_closed),
        occurred_at: momento(issue["closed_at"]),
        external_id: "issue-#{issue["number"]}-closed"
      }
    ]
  end

  def events_for(_evento, _payload), do: []

  defp na_branch_principal?(payload) do
    principal = get_in(payload, ["repository", "default_branch"])

    is_binary(principal) and payload["ref"] == "refs/heads/#{principal}"
  end

  # `distinct` é falso quando o commit já estava no repositório e só apareceu de
  # novo — num merge de branch, por exemplo. Contar isso pagaria duas vezes pelo
  # mesmo trabalho.
  defp novo?(commit), do: commit["distinct"] != false

  defp commit_event(commit) do
    %{
      kind: "commit",
      title: titulo(primeira_linha(commit["message"]), "Commit"),
      xp: xp_for(:commit),
      occurred_at: momento(commit["timestamp"]),
      external_id: to_string(commit["id"])
    }
  end

  defp primeira_linha(nil), do: nil
  defp primeira_linha(mensagem), do: mensagem |> String.split("\n", parts: 2) |> List.first()

  defp titulo(texto, padrao) do
    case texto |> to_string() |> String.trim() do
      "" -> padrao
      limpo -> String.slice(limpo, 0, 200)
    end
  end

  # O GitHub manda ISO-8601, mas nem sempre manda: um evento sem carimbo vale
  # agora, em vez de derrubar a entrega inteira.
  defp momento(nil), do: DateTime.utc_now(:second)

  defp momento(texto) when is_binary(texto) do
    case DateTime.from_iso8601(texto) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      {:error, _motivo} -> DateTime.utc_now(:second)
    end
  end

  defp momento(_outro), do: DateTime.utc_now(:second)
end

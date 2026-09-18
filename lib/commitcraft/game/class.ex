defmodule CommitCraft.Game.Class do
  @moduledoc """
  A classe de um projeto: um título de RPG tirado de como ele foi construído.

  Não é escolhida, é observada. Ninguém marca "quero ser Faxineiro" — o projeto
  vira Faxineiro porque os pull requests dele apagam mais do que escrevem. É a
  diferença entre um rótulo que você põe e um apelido que você ganha.

  Como tudo no jogo, é função pura sobre os acontecimentos já gravados: a classe
  pode mudar sozinha quando o jeito de trabalhar muda, e nada precisa ser
  guardado.
  """
  alias CommitCraft.Game.Streak

  @classes [
    %{
      key: "faxineiro",
      name: "Faxineiro",
      how: "Seus pull requests apagam mais código do que escrevem."
    },
    %{
      key: "bombeiro",
      name: "Bombeiro",
      how: "Você quebra a produção e conserta no mesmo dia, mais de uma vez."
    },
    %{
      key: "maratonista",
      name: "Maratonista",
      how: "Duas semanas seguidas sem deixar a sequência morrer."
    },
    %{
      key: "noturno",
      name: "Notívago",
      how: "A maior parte dos seus commits acontece depois das 22h."
    },
    %{
      key: "mercador",
      name: "Mercador",
      how: "Este projeto já trouxe dinheiro."
    },
    %{
      key: "arauto",
      name: "Arauto",
      how: "Você manda para produção com frequência incomum."
    },
    %{
      key: "artesao",
      name: "Artesão",
      how: "Commit atrás de commit, sem pressa e sem drama."
    }
  ]

  @doc "Todas as classes que existem."
  def catalog, do: @classes

  @doc """
  A classe de um projeto.

  A ordem do catálogo é a ordem de prioridade: as classes específicas vêm
  primeiro, e "Artesão" é a última porque é a que descreve qualquer um que
  simplesmente trabalha. Um projeto sem nenhum acontecimento ainda não tem
  classe — dizer que ele é Artesão seria elogiar o que não aconteceu.
  """
  def for_events([]), do: nil

  def for_events(eventos) when is_list(eventos) do
    Enum.find(@classes, &merece?(&1.key, eventos))
  end

  defp merece?("faxineiro", eventos) do
    pulls = Enum.filter(eventos, &(&1.kind == "pull_request_merged"))

    limpezas =
      Enum.count(pulls, &(numero(&1.meta["deletions"]) > numero(&1.meta["additions"])))

    pulls != [] and limpezas * 2 > length(pulls)
  end

  defp merece?("bombeiro", eventos) do
    quebras = dias_de(eventos, "broken_build")
    consertos = dias_de(eventos, "deploy")

    MapSet.size(MapSet.intersection(quebras, consertos)) >= 2
  end

  defp merece?("maratonista", eventos) do
    eventos
    |> Enum.filter(&(&1.kind == "commit"))
    |> Enum.map(& &1.occurred_at)
    |> Streak.longest() >= 14
  end

  defp merece?("noturno", eventos) do
    commits = Enum.filter(eventos, &(&1.kind == "commit"))
    # Poucos commits não dizem nada sobre horário de trabalho.
    tarde = Enum.count(commits, &(hora_local(&1) >= 22 or hora_local(&1) < 5))

    length(commits) >= 10 and tarde * 2 > length(commits)
  end

  defp merece?("mercador", eventos),
    do: Enum.any?(eventos, &(&1.kind in ["sale", "first_sale"]))

  defp merece?("arauto", eventos) do
    deploys = Enum.count(eventos, &(&1.kind == "deploy"))
    commits = Enum.count(eventos, &(&1.kind == "commit"))

    deploys >= 5 and deploys * 4 >= commits
  end

  defp merece?("artesao", eventos), do: Enum.any?(eventos, &(&1.kind == "commit"))

  defp dias_de(eventos, kind) do
    eventos
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map(&Streak.to_date(&1.occurred_at))
    |> MapSet.new()
  end

  defp hora_local(evento) do
    evento.occurred_at
    |> DateTime.add(Application.get_env(:commitcraft, :game_utc_offset_hours, -3) * 3600, :second)
    |> Map.fetch!(:hour)
  end

  defp numero(valor) when is_integer(valor), do: valor
  defp numero(_outro), do: 0
end

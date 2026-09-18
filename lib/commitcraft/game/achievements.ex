defmodule CommitCraft.Game.Achievements do
  @moduledoc """
  As conquistas: o catálogo e como saber se alguém as mereceu.

  Conquista **não dá XP**. XP mede quanto trabalho foi feito; conquista marca
  que tipo de coisa você fez. Misturar os dois faria uma medalha valer tantos
  commits, e aí ela vira farm em vez de piada.

  Cada regra é uma função pura sobre os acontecimentos já registrados, então o
  catálogo inteiro pode ser reavaliado a qualquer momento — inclusive para
  conquistas criadas depois de o projeto já estar em andamento.
  """
  alias CommitCraft.Game.Streak

  @catalogo [
    %{
      key: "madrugada",
      name: "Madrugada Adentro",
      how: "Um commit entre 3h e 5h da manhã.",
      rarity: "Raro"
    },
    %{
      key: "sexta_18h",
      name: "Sexta, 18h",
      how: "Deploy em produção numa sexta à noite.",
      rarity: "Lendário"
    },
    %{
      key: "faxina",
      name: "Faxina",
      how: "Um pull request que apaga mais linhas do que escreve.",
      rarity: "Incomum"
    },
    %{
      key: "nao_fui_eu",
      name: "Não Fui Eu",
      how: "Um commit que reverte outro.",
      rarity: "Comum"
    },
    %{
      key: "bombeiro",
      name: "Bombeiro",
      how: "Quebrar a produção e consertar no mesmo dia.",
      rarity: "Raro"
    },
    %{
      key: "primeira_moeda",
      name: "Primeira Moeda",
      how: "Alguém pagou por algo que você fez.",
      rarity: "Lendário"
    },
    %{
      key: "semana_cheia",
      name: "Semana Cheia",
      how: "Sete dias seguidos sem quebrar a sequência.",
      rarity: "Incomum"
    },
    %{
      key: "maratona",
      name: "Maratona",
      how: "Trinta dias seguidos sem quebrar a sequência.",
      rarity: "Lendário"
    }
  ]

  @doc "Todas as conquistas que existem."
  def catalog, do: @catalogo

  @doc "Uma conquista pela chave."
  def get(key), do: Enum.find(@catalogo, &(&1.key == key))

  @doc """
  Quais conquistas os acontecimentos de um projeto já merecem.

  Devolve a lista de chaves. Quem grava decide o que fazer com as que já eram
  conhecidas — aqui não há estado nenhum.
  """
  def earned(eventos) when is_list(eventos) do
    maior_sequencia = eventos |> commits() |> Enum.map(& &1.occurred_at) |> Streak.longest()

    @catalogo
    |> Enum.filter(&mereceu?(&1.key, eventos, maior_sequencia))
    |> Enum.map(& &1.key)
  end

  defp mereceu?("madrugada", eventos, _seq) do
    Enum.any?(commits(eventos), &(hora_local(&1) in 3..4))
  end

  defp mereceu?("sexta_18h", eventos, _seq) do
    Enum.any?(eventos, fn evento ->
      evento.kind == "deploy" and dia_da_semana(evento) == 5 and hora_local(evento) >= 18
    end)
  end

  defp mereceu?("faxina", eventos, _seq) do
    Enum.any?(eventos, fn evento ->
      evento.kind == "pull_request_merged" and
        numero(evento.meta["deletions"]) > numero(evento.meta["additions"])
    end)
  end

  defp mereceu?("nao_fui_eu", eventos, _seq) do
    # A mensagem que o próprio git escreve ao reverter começa com "Revert".
    Enum.any?(commits(eventos), &String.starts_with?(String.downcase(&1.title), "revert"))
  end

  defp mereceu?("bombeiro", eventos, _seq) do
    quebras = dias_de(eventos, "broken_build")
    consertos = dias_de(eventos, "deploy")

    not MapSet.disjoint?(quebras, consertos)
  end

  defp mereceu?("primeira_moeda", eventos, _seq),
    do: Enum.any?(eventos, &(&1.kind in ["first_sale", "sale"]))

  defp mereceu?("semana_cheia", _eventos, sequencia), do: sequencia >= 7
  defp mereceu?("maratona", _eventos, sequencia), do: sequencia >= 30

  defp commits(eventos), do: Enum.filter(eventos, &(&1.kind == "commit"))

  defp dias_de(eventos, kind) do
    eventos
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.map(&Streak.to_date(&1.occurred_at))
    |> MapSet.new()
  end

  # As conquistas falam de "madrugada" e "sexta à noite" — que são horas do
  # relógio de quem trabalha, não de UTC.
  defp hora_local(evento) do
    evento.occurred_at
    |> DateTime.add(Application.get_env(:commitcraft, :game_utc_offset_hours, -3) * 3600, :second)
    |> Map.fetch!(:hour)
  end

  defp dia_da_semana(evento), do: evento.occurred_at |> Streak.to_date() |> Date.day_of_week()

  defp numero(valor) when is_integer(valor), do: valor
  defp numero(_outro), do: 0
end

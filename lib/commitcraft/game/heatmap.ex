defmodule CommitCraft.Game.Heatmap do
  @moduledoc """
  O ano em quadradinhos: quanto XP cada dia rendeu.

  A grade é organizada por semana, como a do GitHub, porque é a forma que todo
  mundo que programa já sabe ler — não vale inventar uma leitura nova para uma
  informação que já tem convenção.

  A intensidade é por **faixa**, não proporcional ao maior dia. Proporcional
  parece justo mas mente: um único dia de 500 XP apagaria visualmente três meses
  de trabalho constante, e o mapa serve justamente para mostrar constância.
  """
  alias CommitCraft.Game.Streak

  # Cada faixa é "a partir de quanto XP". A escala é apertada de propósito: a
  # diferença entre um dia parado e um dia com um commit importa mais do que a
  # diferença entre 200 e 400.
  @faixas [{0, 0}, {1, 1}, {10, 2}, {30, 3}, {80, 4}]

  @doc """
  Monta a grade das últimas `semanas` semanas.

  Devolve uma lista de semanas, cada uma com sete dias (domingo a sábado), onde
  cada dia é `%{date:, xp:, level:}`. Dias fora da janela vêm como `nil`, para a
  tela não precisar adivinhar onde a grade começa.
  """
  def build(eventos, opts \\ []) do
    semanas = Keyword.get(opts, :weeks, 27)
    hoje = Keyword.get(opts, :today) || Streak.today()

    por_dia =
      eventos
      |> Enum.group_by(&Streak.to_date(&1.occurred_at))
      |> Map.new(fn {dia, do_dia} -> {dia, Enum.sum(Enum.map(do_dia, & &1.xp))} end)

    # A grade termina no sábado da semana atual, para a última coluna não ficar
    # pela metade.
    fim = Date.add(hoje, 7 - Date.day_of_week(hoje, :sunday))
    inicio = Date.add(fim, -(semanas * 7) + 1)

    inicio
    |> Date.range(fim)
    |> Enum.map(fn dia ->
      xp = Map.get(por_dia, dia, 0)

      %{date: dia, xp: xp, level: intensidade(xp), future: Date.compare(dia, hoje) == :gt}
    end)
    |> Enum.chunk_every(7)
  end

  @doc """
  A faixa de intensidade de um dia, de 0 a 4.

      iex> alias CommitCraft.Game.Heatmap
      iex> {Heatmap.intensidade(0), Heatmap.intensidade(5), Heatmap.intensidade(300)}
      {0, 1, 4}

  XP negativo não vira faixa negativa: um dia em que a produção quebrou ainda
  foi um dia em que você mexeu no projeto.
  """
  def intensidade(xp) when is_integer(xp) do
    absoluto = abs(xp)

    @faixas
    |> Enum.filter(fn {minimo, _faixa} -> absoluto >= minimo end)
    |> List.last()
    |> elem(1)
  end
end

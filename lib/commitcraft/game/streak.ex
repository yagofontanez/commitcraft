defmodule CommitCraft.Game.Streak do
  @moduledoc """
  A sequência de dias seguidos com commit.

  ## O fuso importa

  Um commit às 22h de terça no Brasil é 01h de quarta em UTC. Contar em UTC
  quebraria a sequência de quem trabalha à noite — justamente quem mais liga
  para ela. Por isso os dias são contados no fuso configurado.

  O Brasil não tem mais horário de verão desde 2019, então um deslocamento fixo
  basta e evita arrastar um banco de fusos inteiro como dependência. Se um dia o
  CommitCraft tiver gente em fuso com horário de verão, é aqui que muda.
  """

  @doc """
  A sequência atual, em dias, a partir de uma lista de momentos.

  A conta é feita a partir de `hoje`: uma sequência só continua viva se o último
  dia com commit foi hoje ou ontem. Dois dias sem nada e ela morre.

      iex> alias CommitCraft.Game.Streak
      iex> Streak.current([~U[2026-09-18 12:00:00Z]], ~D[2026-09-18])
      1

      iex> alias CommitCraft.Game.Streak
      iex> Streak.current([], ~D[2026-09-18])
      0
  """
  def current(momentos, hoje \\ nil) do
    hoje = hoje || today()
    dias = dias_com_commit(momentos)

    cond do
      MapSet.size(dias) == 0 -> 0
      MapSet.member?(dias, hoje) -> contar(dias, hoje, 0)
      MapSet.member?(dias, Date.add(hoje, -1)) -> contar(dias, Date.add(hoje, -1), 0)
      # A sequência morreu: o último commit foi anteontem ou antes.
      true -> 0
    end
  end

  @doc """
  A maior sequência que já houve, viva ou não.

      iex> alias CommitCraft.Game.Streak
      iex> Streak.longest([~U[2026-09-01 12:00:00Z], ~U[2026-09-02 12:00:00Z]])
      2
  """
  def longest(momentos) do
    dias = momentos |> dias_com_commit() |> MapSet.to_list() |> Enum.sort(Date)

    dias
    |> Enum.reduce({0, 0, nil}, fn dia, {maior, atual, anterior} ->
      atual = if anterior && Date.diff(dia, anterior) == 1, do: atual + 1, else: 1

      {max(maior, atual), atual, dia}
    end)
    |> elem(0)
  end

  @doc "O dia de hoje no fuso do jogo."
  def today, do: DateTime.utc_now() |> to_date()

  @doc "Em que dia do jogo um momento caiu."
  def to_date(%DateTime{} = momento) do
    momento
    |> DateTime.add(offset_horas() * 3600, :second)
    |> DateTime.to_date()
  end

  defp dias_com_commit(momentos), do: momentos |> Enum.map(&to_date/1) |> MapSet.new()

  defp contar(dias, dia, acumulado) do
    if MapSet.member?(dias, dia),
      do: contar(dias, Date.add(dia, -1), acumulado + 1),
      else: acumulado
  end

  defp offset_horas, do: Application.get_env(:commitcraft, :game_utc_offset_hours, -3)
end

defmodule CommitCraft.Game.Level do
  @moduledoc """
  A curva de níveis.

  Nível **não é guardado no banco** — é função do XP total. Guardar os dois
  convida os dois a discordarem, e aí não dá para saber qual está certo.

  ## A curva

  Para sair do nível `L` são precisos `300 * L - 100` de XP. O custo cresce de
  forma linear, então o XP acumulado cresce como uma parábola: subir de nível
  fica progressivamente mais caro, mas nunca vira parede.

      nível 1 → 2:    200 XP
      nível 2 → 3:    500 XP
      nível 6 → 7:  1.700 XP
      nível 7 → 8:  2.000 XP

  Os números foram escolhidos para bater com a promessa da página inicial —
  "LV 07 · 1.240 / 2.000 XP" — e calibrados pela tabela de XP real: uma semana
  ativa (uns 20 commits, 3 pull requests, 5 deploys e uma sequência de 7 dias)
  dá algo perto de 425 XP, o que põe o nível 7 a uns três meses de trabalho.

  Para mexer no ritmo do jogo, mude `xp_to_advance/1`; todo o resto se ajusta.
  """

  @doc """
  Quanto XP falta para sair deste nível.

      iex> CommitCraft.Game.Level.xp_to_advance(1)
      200

      iex> CommitCraft.Game.Level.xp_to_advance(7)
      2000
  """
  def xp_to_advance(level) when is_integer(level) and level >= 1, do: 300 * level - 100

  @doc """
  XP acumulado necessário para *chegar* a um nível.

      iex> CommitCraft.Game.Level.xp_to_reach(1)
      0

      iex> CommitCraft.Game.Level.xp_to_reach(7)
      5700
  """
  def xp_to_reach(level) when is_integer(level) and level >= 1,
    do: (level - 1) * (150 * level - 100)

  @doc """
  O nível de quem tem este tanto de XP.

      iex> CommitCraft.Game.Level.for_xp(0)
      1

      iex> CommitCraft.Game.Level.for_xp(199)
      1

      iex> CommitCraft.Game.Level.for_xp(200)
      2

      iex> CommitCraft.Game.Level.for_xp(6940)
      7
  """
  def for_xp(xp) when is_integer(xp) and xp <= 0, do: 1

  def for_xp(xp) when is_integer(xp) do
    # Invertendo xp_to_reach/1: L = (250 + √(2500 + 600·xp)) / 300. A conta sai
    # em ponto flutuante, então o palpite é corrigido contra a curva inteira —
    # assim nenhum arredondamento coloca alguém no nível errado na fronteira.
    (250 + :math.sqrt(2500 + 600 * xp))
    |> Kernel./(300)
    |> trunc()
    |> max(1)
    |> ajustar(xp)
  end

  @doc """
  Tudo que uma barra de XP precisa saber.

      iex> CommitCraft.Game.Level.progress(6940)
      %{level: 7, xp: 6940, into_level: 1240, to_advance: 2000, ratio: 0.62}

  `ratio` já vem entre 0 e 1, arredondado em duas casas — o suficiente para a
  largura de uma barra, e estável para comparar em teste.
  """
  def progress(xp) when is_integer(xp) do
    xp = max(xp, 0)
    level = for_xp(xp)
    into_level = xp - xp_to_reach(level)
    to_advance = xp_to_advance(level)

    %{
      level: level,
      xp: xp,
      into_level: into_level,
      to_advance: to_advance,
      ratio: Float.round(into_level / to_advance, 2)
    }
  end

  defp ajustar(level, xp) do
    cond do
      xp_to_reach(level) > xp -> ajustar(level - 1, xp)
      xp_to_reach(level + 1) <= xp -> ajustar(level + 1, xp)
      true -> level
    end
  end
end

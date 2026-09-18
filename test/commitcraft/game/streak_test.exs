defmodule CommitCraft.Game.StreakTest do
  use ExUnit.Case, async: true

  doctest CommitCraft.Game.Streak

  alias CommitCraft.Game.Streak

  # O jogo conta dias em UTC-3; estes horários são escolhidos para exercitar
  # justamente a virada.
  defp em(data, hora), do: DateTime.new!(data, Time.new!(hora, 0, 0), "Etc/UTC")

  describe "current/2" do
    test "um commit hoje é sequência de um" do
      assert Streak.current([em(~D[2026-09-18], 15)], ~D[2026-09-18]) == 1
    end

    test "dias seguidos somam" do
      momentos = for d <- 14..18, do: em(Date.new!(2026, 9, d), 15)

      assert Streak.current(momentos, ~D[2026-09-18]) == 5
    end

    test "vários commits no mesmo dia contam uma vez" do
      momentos = [em(~D[2026-09-18], 9), em(~D[2026-09-18], 15), em(~D[2026-09-18], 20)]

      assert Streak.current(momentos, ~D[2026-09-18]) == 1
    end

    test "continua viva se o último commit foi ontem" do
      # Ainda dá tempo de salvar a sequência hoje.
      assert Streak.current([em(~D[2026-09-17], 15)], ~D[2026-09-18]) == 1
    end

    test "morre depois de um dia inteiro sem nada" do
      assert Streak.current([em(~D[2026-09-16], 15)], ~D[2026-09-18]) == 0
    end

    test "um buraco no meio corta a sequência no buraco" do
      momentos = [
        em(~D[2026-09-10], 15),
        em(~D[2026-09-11], 15),
        # 12 e 13 sem nada
        em(~D[2026-09-14], 15),
        em(~D[2026-09-15], 15)
      ]

      assert Streak.current(momentos, ~D[2026-09-15]) == 2
    end

    test "sem commit nenhum, sequência é zero" do
      assert Streak.current([], ~D[2026-09-18]) == 0
    end
  end

  describe "o fuso do jogo" do
    test "commit às 22h no Brasil conta como hoje, não como amanhã" do
      # 22h em UTC-3 é 01h do dia seguinte em UTC. Contar em UTC quebraria a
      # sequência de quem trabalha à noite — justamente quem mais liga para ela.
      commit_de_terca_a_noite = em(~D[2026-09-16], 1)

      assert Streak.to_date(commit_de_terca_a_noite) == ~D[2026-09-15]
    end

    test "uma semana de commits noturnos é uma sequência inteira, não sete pedaços" do
      # Todo dia às 23h de Brasília, que em UTC cai no dia seguinte.
      momentos = for d <- 11..17, do: em(Date.new!(2026, 9, d), 2)

      assert Streak.current(momentos, ~D[2026-09-16]) == 7
    end
  end

  describe "longest/1" do
    test "acha a maior sequência mesmo depois de ela morrer" do
      momentos =
        for(d <- 1..10, do: em(Date.new!(2026, 9, d), 15)) ++
          [em(~D[2026-09-20], 15), em(~D[2026-09-21], 15)]

      assert Streak.longest(momentos) == 10
      assert Streak.current(momentos, ~D[2026-09-21]) == 2
    end

    test "sem commits, zero" do
      assert Streak.longest([]) == 0
    end
  end
end

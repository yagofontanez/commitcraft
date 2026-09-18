defmodule CommitCraft.Game.HeatmapTest do
  use ExUnit.Case, async: true

  doctest CommitCraft.Game.Heatmap

  alias CommitCraft.Game.Heatmap

  defp evento(data, xp), do: %{occurred_at: DateTime.new!(data, ~T[15:00:00], "Etc/UTC"), xp: xp}

  describe "intensidade/1" do
    test "dia parado é zero" do
      assert Heatmap.intensidade(0) == 0
    end

    test "um único commit já sai do zero" do
      # A diferença entre parado e "fiz alguma coisa" é a que mais importa.
      assert Heatmap.intensidade(5) == 1
    end

    test "sobe por faixa, e para no topo" do
      assert Heatmap.intensidade(15) == 2
      assert Heatmap.intensidade(50) == 3
      assert Heatmap.intensidade(100) == 4
      assert Heatmap.intensidade(100_000) == 4
    end

    test "dia negativo ainda foi um dia de trabalho" do
      # Quebrar a produção é mexer no projeto; apagar o quadradinho seria dizer
      # que o dia não existiu.
      assert Heatmap.intensidade(-30) == 3
    end
  end

  describe "build/2" do
    test "devolve semanas completas de sete dias" do
      grade = Heatmap.build([], weeks: 4, today: ~D[2026-09-18])

      assert length(grade) == 4
      assert Enum.all?(grade, &(length(&1) == 7))
    end

    test "cada semana começa no domingo" do
      grade = Heatmap.build([], weeks: 2, today: ~D[2026-09-18])

      assert Enum.all?(grade, fn [primeiro | _] -> Date.day_of_week(primeiro.date) == 7 end)
    end

    test "soma o XP do dia, venha de quantos eventos vier" do
      eventos = [
        evento(~D[2026-09-16], 5),
        evento(~D[2026-09-16], 5),
        evento(~D[2026-09-16], 40)
      ]

      grade = Heatmap.build(eventos, weeks: 4, today: ~D[2026-09-18])
      dia = grade |> List.flatten() |> Enum.find(&(&1.date == ~D[2026-09-16]))

      assert dia.xp == 50
      assert dia.level == 3
    end

    test "marca os dias que ainda não chegaram" do
      grade = Heatmap.build([], weeks: 2, today: ~D[2026-09-18])
      futuros = grade |> List.flatten() |> Enum.filter(& &1.future)

      # A grade fecha no sábado, então sobram dias por vir na última coluna.
      assert Enum.all?(futuros, &(Date.compare(&1.date, ~D[2026-09-18]) == :gt))
      assert Enum.all?(futuros, &(&1.xp == 0))
    end

    test "evento fora da janela não aparece" do
      antigo = evento(~D[2020-01-01], 500)

      grade = Heatmap.build([antigo], weeks: 4, today: ~D[2026-09-18])

      assert grade |> List.flatten() |> Enum.all?(&(&1.xp == 0))
    end

    test "um dia enorme não apaga os dias constantes" do
      # Escala proporcional parece justa e mente: um pico apagaria meses de
      # trabalho regular, e é justamente constância que o mapa mostra.
      eventos = [
        evento(~D[2026-09-15], 5000)
        | for(d <- 1..10, do: evento(Date.add(~D[2026-09-16], -d), 5))
      ]

      grade = Heatmap.build(eventos, weeks: 6, today: ~D[2026-09-18])
      constantes = grade |> List.flatten() |> Enum.filter(&(&1.xp == 5))

      assert constantes != []
      assert Enum.all?(constantes, &(&1.level == 1))
    end
  end
end

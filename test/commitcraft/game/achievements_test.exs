defmodule CommitCraft.Game.AchievementsTest do
  use ExUnit.Case, async: true

  alias CommitCraft.Game.Achievements

  defp evento(attrs) do
    Map.merge(
      %{kind: "commit", title: "feat: algo", occurred_at: ~U[2026-09-18 15:00:00Z], meta: %{}},
      Map.new(attrs)
    )
  end

  defp em(data, hora), do: DateTime.new!(data, Time.new!(hora, 0, 0), "Etc/UTC")

  test "o catálogo tem chaves únicas" do
    chaves = Enum.map(Achievements.catalog(), & &1.key)

    assert Enum.uniq(chaves) == chaves
  end

  test "projeto sem nada não ganha conquista nenhuma" do
    assert Achievements.earned([]) == []
  end

  describe "Madrugada Adentro" do
    test "commit às 3h da manhã no fuso do jogo destrava" do
      # 6h UTC é 3h em UTC-3.
      assert "madrugada" in Achievements.earned([evento(occurred_at: em(~D[2026-09-18], 6))])
    end

    test "commit de tarde não destrava" do
      refute "madrugada" in Achievements.earned([evento(occurred_at: em(~D[2026-09-18], 18))])
    end

    test "conta a hora local, não a UTC" do
      # 3h UTC é meia-noite em UTC-3 — não é madrugada adentro, é cedo demais.
      refute "madrugada" in Achievements.earned([evento(occurred_at: em(~D[2026-09-18], 3))])
    end
  end

  describe "Sexta, 18h" do
    test "deploy numa sexta à noite destrava" do
      # 2026-09-18 é uma sexta. 22h UTC = 19h local.
      sexta_a_noite = evento(kind: "deploy", occurred_at: em(~D[2026-09-18], 22))

      assert "sexta_18h" in Achievements.earned([sexta_a_noite])
    end

    test "deploy numa sexta de manhã não destrava" do
      sexta_cedo = evento(kind: "deploy", occurred_at: em(~D[2026-09-18], 13))

      refute "sexta_18h" in Achievements.earned([sexta_cedo])
    end

    test "deploy numa quinta à noite não destrava" do
      quinta = evento(kind: "deploy", occurred_at: em(~D[2026-09-17], 22))

      refute "sexta_18h" in Achievements.earned([quinta])
    end

    test "commit na sexta à noite não conta: tem que ser deploy" do
      commit = evento(occurred_at: em(~D[2026-09-18], 22))

      refute "sexta_18h" in Achievements.earned([commit])
    end
  end

  describe "Faxina" do
    test "pull request que apaga mais do que escreve destrava" do
      limpeza =
        evento(
          kind: "pull_request_merged",
          meta: %{"additions" => 12, "deletions" => 400}
        )

      assert "faxina" in Achievements.earned([limpeza])
    end

    test "pull request que escreve mais do que apaga não destrava" do
      normal =
        evento(kind: "pull_request_merged", meta: %{"additions" => 400, "deletions" => 12})

      refute "faxina" in Achievements.earned([normal])
    end

    test "sem números, não destrava" do
      sem_dados = evento(kind: "pull_request_merged", meta: %{})

      refute "faxina" in Achievements.earned([sem_dados])
    end
  end

  describe "Não Fui Eu" do
    test "um commit que reverte outro destrava" do
      assert "nao_fui_eu" in Achievements.earned([evento(title: "Revert \"feat: algo\"")])
    end

    test "commit comum não destrava" do
      refute "nao_fui_eu" in Achievements.earned([evento(title: "feat: algo")])
    end
  end

  describe "Bombeiro" do
    test "quebrar e consertar no mesmo dia destrava" do
      dia = ~D[2026-09-18]

      eventos = [
        evento(kind: "broken_build", occurred_at: em(dia, 14)),
        evento(kind: "deploy", occurred_at: em(dia, 20))
      ]

      assert "bombeiro" in Achievements.earned(eventos)
    end

    test "consertar no dia seguinte não destrava" do
      eventos = [
        evento(kind: "broken_build", occurred_at: em(~D[2026-09-17], 14)),
        evento(kind: "deploy", occurred_at: em(~D[2026-09-18], 20))
      ]

      refute "bombeiro" in Achievements.earned(eventos)
    end
  end

  describe "sequência" do
    test "sete dias seguidos destravam Semana Cheia, mas não Maratona" do
      eventos = for d <- 12..18, do: evento(occurred_at: em(Date.new!(2026, 9, d), 15))
      ganhas = Achievements.earned(eventos)

      assert "semana_cheia" in ganhas
      refute "maratona" in ganhas
    end

    test "trinta dias destravam as duas" do
      eventos = for d <- 1..30, do: evento(occurred_at: em(Date.new!(2026, 9, d), 15))
      ganhas = Achievements.earned(eventos)

      assert "semana_cheia" in ganhas
      assert "maratona" in ganhas
    end

    test "a maior sequência vale, mesmo que já tenha morrido" do
      # Conquista não se perde: ter feito trinta dias seguidos em janeiro conta
      # para sempre.
      antigos = for d <- 1..30, do: evento(occurred_at: em(Date.new!(2026, 1, d), 15))

      assert "maratona" in Achievements.earned(antigos)
    end
  end

  describe "Primeira Moeda" do
    test "qualquer venda destrava" do
      assert "primeira_moeda" in Achievements.earned([evento(kind: "first_sale")])
      assert "primeira_moeda" in Achievements.earned([evento(kind: "sale")])
    end
  end
end

defmodule CommitCraft.Game.ClassTest do
  use ExUnit.Case, async: true

  alias CommitCraft.Game.Class

  defp evento(attrs) do
    Map.merge(
      %{kind: "commit", title: "feat: algo", occurred_at: ~U[2026-09-18 15:00:00Z], meta: %{}},
      Map.new(attrs)
    )
  end

  defp em(data, hora), do: DateTime.new!(data, Time.new!(hora, 0, 0), "Etc/UTC")

  # `for_events/1` devolve nil quando nada casa, então comparar chave exige
  # cuidado — um projeto pode simplesmente não ter classe ainda.
  defp classe(eventos) do
    case Class.for_events(eventos) do
      nil -> nil
      %{key: key} -> key
    end
  end

  defp commits(n, hora \\ 15) do
    for i <- 1..n, do: evento(occurred_at: em(Date.add(~D[2026-09-01], rem(i, 5)), hora))
  end

  test "projeto sem nada ainda não tem classe" do
    # Chamar de Artesão quem não fez nada seria elogiar o que não aconteceu.
    assert is_nil(Class.for_events([]))
  end

  test "quem só commita é Artesão" do
    assert %{key: "artesao"} = Class.for_events(commits(5))
  end

  test "pull requests que apagam mais do que escrevem fazem um Faxineiro" do
    limpezas =
      for _ <- 1..3 do
        evento(kind: "pull_request_merged", meta: %{"additions" => 10, "deletions" => 300})
      end

    assert %{key: "faxineiro"} = Class.for_events(limpezas ++ commits(5))
  end

  test "um único pull request de limpeza no meio de muitos não muda a classe" do
    normais =
      for _ <- 1..5 do
        evento(kind: "pull_request_merged", meta: %{"additions" => 300, "deletions" => 10})
      end

    limpeza = evento(kind: "pull_request_merged", meta: %{"additions" => 1, "deletions" => 90})

    refute classe([limpeza | normais]) == "faxineiro"
  end

  test "quebrar e consertar no mesmo dia duas vezes faz um Bombeiro" do
    eventos =
      for d <- [~D[2026-09-10], ~D[2026-09-14]] do
        [
          evento(kind: "broken_build", occurred_at: em(d, 14)),
          evento(kind: "deploy", occurred_at: em(d, 20))
        ]
      end
      |> List.flatten()

    assert %{key: "bombeiro"} = Class.for_events(eventos)
  end

  test "uma vez só ainda não é padrão" do
    eventos = [
      evento(kind: "broken_build", occurred_at: em(~D[2026-09-10], 14)),
      evento(kind: "deploy", occurred_at: em(~D[2026-09-10], 20))
    ]

    refute classe(eventos) == "bombeiro"
  end

  test "duas semanas de sequência fazem um Maratonista" do
    seguidos = for d <- 1..14, do: evento(occurred_at: em(Date.new!(2026, 9, d), 15))

    assert %{key: "maratonista"} = Class.for_events(seguidos)
  end

  test "commits de madrugada fazem um Notívago" do
    # 2h UTC é 23h do dia anterior em UTC-3.
    noturnos = for i <- 1..12, do: evento(occurred_at: em(Date.new!(2026, 9, rem(i, 7) + 1), 2))

    assert %{key: "noturno"} = Class.for_events(noturnos)
  end

  test "poucos commits não dizem nada sobre horário" do
    # Três commits de madrugada podem ser uma noite atípica, não um hábito.
    poucos = for i <- 1..3, do: evento(occurred_at: em(Date.new!(2026, 9, i), 2))

    refute classe(poucos) == "noturno"
  end

  test "venda faz um Mercador" do
    assert %{key: "mercador"} = Class.for_events([evento(kind: "first_sale") | commits(5)])
  end

  test "deploy frequente faz um Arauto" do
    deploys =
      for i <- 1..6, do: evento(kind: "deploy", occurred_at: em(Date.new!(2026, 9, i), 15))

    assert %{key: "arauto"} = Class.for_events(deploys ++ commits(4))
  end

  test "o catálogo tem chaves únicas" do
    chaves = Enum.map(Class.catalog(), & &1.key)

    assert Enum.uniq(chaves) == chaves
  end
end

defmodule CommitCraft.Game.RulesTest do
  use ExUnit.Case, async: true

  doctest CommitCraft.Game.Rules

  alias CommitCraft.Game.Rules

  defp push(attrs) do
    Map.merge(
      %{
        "ref" => "refs/heads/main",
        "repository" => %{"default_branch" => "main"},
        "commits" => []
      },
      attrs
    )
  end

  defp commit(attrs \\ %{}) do
    Map.merge(
      %{
        "id" => "a3f1c2" <> Integer.to_string(System.unique_integer([:positive])),
        "message" => "feat: uma coisa",
        "timestamp" => "2026-09-18T10:00:00Z",
        "distinct" => true
      },
      attrs
    )
  end

  describe "push" do
    test "cada commit na branch principal vale XP" do
      eventos = Rules.events_for("push", push(%{"commits" => [commit(), commit()]}))

      assert length(eventos) == 2
      assert Enum.all?(eventos, &(&1.kind == "commit"))
      assert Enum.all?(eventos, &(&1.xp == 5))
    end

    test "ignora push em branch que não é a principal" do
      fora = push(%{"ref" => "refs/heads/minha-feature", "commits" => [commit()]})

      assert Rules.events_for("push", fora) == []
    end

    test "respeita a branch principal declarada pelo repositório" do
      # Nem todo mundo usa "main"; quem ainda está em "master" não pode ficar
      # sem pontuar.
      antigo =
        push(%{
          "ref" => "refs/heads/master",
          "repository" => %{"default_branch" => "master"},
          "commits" => [commit()]
        })

      assert [%{kind: "commit"}] = Rules.events_for("push", antigo)
    end

    test "não paga por commit que já estava no repositório" do
      # `distinct: false` aparece quando um merge traz commits antigos junto;
      # contar isso pagaria duas vezes pelo mesmo trabalho.
      misturado =
        push(%{"commits" => [commit(), commit(%{"distinct" => false}), commit()]})

      assert length(Rules.events_for("push", misturado)) == 2
    end

    test "o identificador do evento é o SHA, para o reenvio não pagar de novo" do
      mesmo = commit(%{"id" => "abc123"})

      [primeiro] = Rules.events_for("push", push(%{"commits" => [mesmo]}))
      [repetido] = Rules.events_for("push", push(%{"commits" => [mesmo]}))

      assert primeiro.external_id == "abc123"
      assert repetido.external_id == primeiro.external_id
    end

    test "usa só a primeira linha da mensagem" do
      longo = commit(%{"message" => "fix: corrige o cálculo\n\nExplicação longa\naqui embaixo"})

      assert [%{title: "fix: corrige o cálculo"}] =
               Rules.events_for("push", push(%{"commits" => [longo]}))
    end

    test "commit sem mensagem ainda aparece com um nome" do
      assert [%{title: "Commit"}] =
               Rules.events_for("push", push(%{"commits" => [commit(%{"message" => "  "})]}))
    end

    test "corta título gigante em vez de estourar a coluna" do
      enorme = commit(%{"message" => String.duplicate("a", 500)})

      assert [%{title: titulo}] = Rules.events_for("push", push(%{"commits" => [enorme]}))
      assert String.length(titulo) == 200
    end
  end

  describe "pull request" do
    test "mesclado vale XP" do
      payload = %{
        "action" => "closed",
        "pull_request" => %{
          "number" => 7,
          "title" => "Motor de XP",
          "merged" => true,
          "merged_at" => "2026-09-18T10:00:00Z"
        }
      }

      assert [evento] = Rules.events_for("pull_request", payload)
      assert evento.kind == "pull_request_merged"
      assert evento.xp == 40
      assert evento.title == "Motor de XP"
      assert evento.external_id == "pr-7-merged"
    end

    test "fechado sem mesclar não vale nada" do
      # Desistir de um pull request não é entregar nada.
      payload = %{
        "action" => "closed",
        "pull_request" => %{"number" => 7, "title" => "Abandonado", "merged" => false}
      }

      assert Rules.events_for("pull_request", payload) == []
    end

    test "abrir um pull request ainda não é entregar" do
      payload = %{
        "action" => "opened",
        "pull_request" => %{"number" => 7, "title" => "Começando", "merged" => false}
      }

      assert Rules.events_for("pull_request", payload) == []
    end
  end

  describe "issue" do
    test "fechada vale XP" do
      payload = %{
        "action" => "closed",
        "issue" => %{
          "number" => 12,
          "title" => "Barra não enche",
          "closed_at" => "2026-09-18T10:00:00Z"
        }
      }

      assert [evento] = Rules.events_for("issues", payload)
      assert evento.kind == "issue_closed"
      assert evento.xp == 15
      assert evento.external_id == "issue-12-closed"
    end

    test "abrir uma issue não vale" do
      payload = %{"action" => "opened", "issue" => %{"number" => 12, "title" => "Achei um bug"}}

      assert Rules.events_for("issues", payload) == []
    end
  end

  describe "entregas que não interessam" do
    test "o ping da criação do webhook não vira evento" do
      assert Rules.events_for("ping", %{"zen" => "Design for failure."}) == []
    end

    test "evento desconhecido não derruba nada" do
      assert Rules.events_for("star", %{"action" => "created"}) == []
      assert Rules.events_for("push", %{}) == []
    end
  end

  describe "carimbo de tempo" do
    test "usa o que o GitHub mandou" do
      [evento] =
        Rules.events_for(
          "push",
          push(%{"commits" => [commit(%{"timestamp" => "2020-05-05T12:00:00Z"})]})
        )

      assert evento.occurred_at == ~U[2020-05-05 12:00:00Z]
    end

    test "carimbo ausente ou quebrado vale agora, em vez de derrubar a entrega" do
      for ruim <- [nil, "ontem", 12_345] do
        [evento] =
          Rules.events_for("push", push(%{"commits" => [commit(%{"timestamp" => ruim})]}))

        assert %DateTime{} = evento.occurred_at
      end
    end
  end
end

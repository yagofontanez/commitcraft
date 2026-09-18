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
      eventos = Rules.events_for("github", "push", push(%{"commits" => [commit(), commit()]}))

      assert length(eventos) == 2
      assert Enum.all?(eventos, &(&1.kind == "commit"))
      assert Enum.all?(eventos, &(&1.xp == 5))
    end

    test "ignora push em branch que não é a principal" do
      fora = push(%{"ref" => "refs/heads/minha-feature", "commits" => [commit()]})

      assert Rules.events_for("github", "push", fora) == []
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

      assert [%{kind: "commit"}] = Rules.events_for("github", "push", antigo)
    end

    test "não paga por commit que já estava no repositório" do
      # `distinct: false` aparece quando um merge traz commits antigos junto;
      # contar isso pagaria duas vezes pelo mesmo trabalho.
      misturado =
        push(%{"commits" => [commit(), commit(%{"distinct" => false}), commit()]})

      assert length(Rules.events_for("github", "push", misturado)) == 2
    end

    test "o identificador do evento é o SHA, para o reenvio não pagar de novo" do
      mesmo = commit(%{"id" => "abc123"})

      [primeiro] = Rules.events_for("github", "push", push(%{"commits" => [mesmo]}))
      [repetido] = Rules.events_for("github", "push", push(%{"commits" => [mesmo]}))

      assert primeiro.external_id == "abc123"
      assert repetido.external_id == primeiro.external_id
    end

    test "usa só a primeira linha da mensagem" do
      longo = commit(%{"message" => "fix: corrige o cálculo\n\nExplicação longa\naqui embaixo"})

      assert [%{title: "fix: corrige o cálculo"}] =
               Rules.events_for("github", "push", push(%{"commits" => [longo]}))
    end

    test "commit sem mensagem ainda aparece com um nome" do
      assert [%{title: "Commit"}] =
               Rules.events_for(
                 "github",
                 "push",
                 push(%{"commits" => [commit(%{"message" => "  "})]})
               )
    end

    test "corta título gigante em vez de estourar a coluna" do
      enorme = commit(%{"message" => String.duplicate("a", 500)})

      assert [%{title: titulo}] =
               Rules.events_for("github", "push", push(%{"commits" => [enorme]}))

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

      assert [evento] = Rules.events_for("github", "pull_request", payload)
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

      assert Rules.events_for("github", "pull_request", payload) == []
    end

    test "abrir um pull request ainda não é entregar" do
      payload = %{
        "action" => "opened",
        "pull_request" => %{"number" => 7, "title" => "Começando", "merged" => false}
      }

      assert Rules.events_for("github", "pull_request", payload) == []
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

      assert [evento] = Rules.events_for("github", "issues", payload)
      assert evento.kind == "issue_closed"
      assert evento.xp == 15
      assert evento.external_id == "issue-12-closed"
    end

    test "abrir uma issue não vale" do
      payload = %{"action" => "opened", "issue" => %{"number" => 12, "title" => "Achei um bug"}}

      assert Rules.events_for("github", "issues", payload) == []
    end
  end

  describe "Vercel" do
    defp deploy(tipo, attrs \\ %{}) do
      Map.merge(
        %{
          "type" => tipo,
          "id" => "evt_#{System.unique_integer([:positive])}",
          "createdAt" => 1_789_000_000_000,
          "payload" => %{
            "target" => "production",
            "deployment" => %{"id" => "dpl_abc", "name" => "commitcraft"}
          }
        },
        attrs
      )
    end

    test "deploy em produção vale 25" do
      assert [evento] =
               Rules.events_for("vercel", "deployment.succeeded", deploy("deployment.succeeded"))

      assert evento.kind == "deploy"
      assert evento.xp == 25
      assert evento.external_id == "deploy-dpl_abc"
    end

    test "deploy de preview não vale nada" do
      # Preview é rascunho; publicar rascunho não é colocar nada no mundo.
      previa = deploy("deployment.succeeded", %{"payload" => %{"target" => "preview"}})

      assert Rules.events_for("vercel", "deployment.succeeded", previa) == []
    end

    test "build quebrado em produção custa XP" do
      assert [evento] = Rules.events_for("vercel", "deployment.error", deploy("deployment.error"))
      assert evento.kind == "broken_build"
      assert evento.xp == -30
    end

    test "build quebrado em preview não pune ninguém" do
      previa = deploy("deployment.error", %{"payload" => %{"target" => "preview"}})

      assert Rules.events_for("vercel", "deployment.error", previa) == []
    end

    test "o identificador é o do deploy, para reenvio não pagar de novo" do
      entrega = deploy("deployment.succeeded")

      [um] = Rules.events_for("vercel", "deployment.succeeded", entrega)
      [outro] = Rules.events_for("vercel", "deployment.succeeded", entrega)

      assert um.external_id == outro.external_id
    end

    test "entende o carimbo em milissegundos" do
      [evento] =
        Rules.events_for("vercel", "deployment.succeeded", deploy("deployment.succeeded"))

      assert evento.occurred_at == ~U[2026-09-10 00:26:40Z]
    end
  end

  describe "Stripe" do
    defp venda(attrs \\ %{}) do
      %{
        "type" => "checkout.session.completed",
        "id" => "evt_1",
        "created" => 1_789_000_000,
        "data" => %{
          "object" =>
            Map.merge(%{"id" => "cs_abc", "amount_total" => 2900, "currency" => "brl"}, attrs)
        }
      }
    end

    test "a primeira venda vale 250" do
      assert [evento] =
               Rules.events_for("stripe", "checkout.session.completed", venda(), %{
                 first_sale?: true
               })

      assert evento.kind == "first_sale"
      assert evento.xp == 250
      assert evento.title == "Venda de R$ 29.00"
    end

    test "as seguintes viram rotina" do
      assert [evento] =
               Rules.events_for("stripe", "checkout.session.completed", venda(), %{
                 first_sale?: false
               })

      assert evento.kind == "sale"
      assert evento.xp == 20
    end

    test "entende as várias formas de valor que a Stripe usa" do
      for {campo, esperado} <- [
            {"amount_total", "Venda de R$ 29.00"},
            {"amount_received", "Venda de R$ 29.00"},
            {"amount_paid", "Venda de R$ 29.00"}
          ] do
        objeto = %{"id" => "x", campo => 2900, "currency" => "brl"}
        payload = put_in(venda()["data"]["object"], objeto)

        assert [%{title: ^esperado}] =
                 Rules.events_for("stripe", "checkout.session.completed", payload, %{})
      end
    end

    test "venda sem valor legível ainda aparece" do
      payload = put_in(venda()["data"]["object"], %{"id" => "cs_x"})

      assert [%{title: "Venda"}] =
               Rules.events_for("stripe", "checkout.session.completed", payload, %{})
    end

    test "o identificador é o do objeto, para reenvio não pagar de novo" do
      [um] = Rules.events_for("stripe", "checkout.session.completed", venda(), %{})
      [outro] = Rules.events_for("stripe", "payment_intent.succeeded", venda(), %{})

      assert um.external_id == "stripe-cs_abc"
      assert outro.external_id == um.external_id
    end
  end

  describe "entregas que não interessam" do
    test "o ping da criação do webhook não vira evento" do
      assert Rules.events_for("github", "ping", %{"zen" => "Design for failure."}) == []
    end

    test "evento desconhecido não derruba nada" do
      assert Rules.events_for("github", "star", %{"action" => "created"}) == []
      assert Rules.events_for("github", "push", %{}) == []
      assert Rules.events_for("vercel", "project.created", %{}) == []
      assert Rules.events_for("stripe", "customer.created", %{}) == []
      assert Rules.events_for("fonte-que-nao-existe", "qualquer", %{}) == []
    end
  end

  describe "carimbo de tempo" do
    test "usa o que o GitHub mandou" do
      [evento] =
        Rules.events_for(
          "github",
          "push",
          push(%{"commits" => [commit(%{"timestamp" => "2020-05-05T12:00:00Z"})]})
        )

      assert evento.occurred_at == ~U[2020-05-05 12:00:00Z]
    end

    test "carimbo ausente ou quebrado vale agora, em vez de derrubar a entrega" do
      for ruim <- [nil, "ontem", 12_345] do
        [evento] =
          Rules.events_for(
            "github",
            "push",
            push(%{"commits" => [commit(%{"timestamp" => ruim})]})
          )

        assert %DateTime{} = evento.occurred_at
      end
    end
  end
end

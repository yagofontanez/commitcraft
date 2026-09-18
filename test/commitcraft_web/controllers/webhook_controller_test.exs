defmodule CommitCraftWeb.WebhookControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Projects

  @secret "segredo-de-teste"

  setup do
    user = user_fixture()
    project = project_fixture(user, %{name: "Meu"})

    {:ok, project} =
      Projects.connect_repo(user, project.slug, %{
        id: 7,
        full_name: "yagofontanez/commitcraft",
        private: false
      })

    {:ok, _webhook} =
      Projects.put_webhook(project, "github", %{
        token: "token-do-webhook",
        secret: @secret,
        external_id: "555"
      })

    %{user: user, project: project}
  end

  # Entrega como o GitHub monta: corpo cru, assinado com HMAC-SHA256.
  defp entregar(conn, token, evento, payload, opts \\ []) do
    corpo = Jason.encode!(payload)

    assinatura =
      Keyword.get_lazy(opts, :signature, fn ->
        segredo = Keyword.get(opts, :secret, @secret)
        "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, segredo, corpo), case: :lower)
      end)

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", evento)
    |> then(fn c ->
      if assinatura, do: put_req_header(c, "x-hub-signature-256", assinatura), else: c
    end)
    |> post("/webhooks/github/#{token}", corpo)
  end

  defp push_payload(commits) do
    %{
      "ref" => "refs/heads/main",
      "repository" => %{"default_branch" => "main"},
      "commits" => commits
    }
  end

  defp commit(id, mensagem) do
    %{
      "id" => id,
      "message" => mensagem,
      "timestamp" => "2026-09-18T10:00:00Z",
      "distinct" => true
    }
  end

  describe "assinatura" do
    test "aceita entrega assinada com o segredo do projeto", %{conn: conn, project: project} do
      conn =
        entregar(conn, "token-do-webhook", "push", push_payload([commit("abc", "feat: algo")]))

      assert response(conn, 200)
      assert Projects.get_project(user_do(project), "meu").xp == 5
    end

    test "recusa entrega com assinatura de outro segredo", %{conn: conn, project: project} do
      conn =
        entregar(conn, "token-do-webhook", "push", push_payload([commit("abc", "feat: algo")]),
          secret: "segredo-errado"
        )

      assert response(conn, 401)
      assert Projects.get_project(user_do(project), "meu").xp == 0
    end

    test "recusa entrega sem assinatura nenhuma", %{conn: conn, project: project} do
      conn =
        entregar(conn, "token-do-webhook", "push", push_payload([commit("abc", "x")]),
          signature: nil
        )

      assert response(conn, 401)
      assert Projects.get_project(user_do(project), "meu").xp == 0
    end

    test "recusa assinatura em formato estranho", %{conn: conn} do
      for falsa <- ["", "sha1=abc", "abc", "sha256=", "sha256=naoehex"] do
        conn =
          build_conn()
          |> entregar("token-do-webhook", "push", push_payload([commit("abc", "x")]),
            signature: falsa
          )

        assert response(conn, 401), "deveria recusar #{inspect(falsa)}"
      end

      _ = conn
    end

    test "o corpo tem que ser exatamente o que foi assinado", %{conn: conn} do
      # Assina um corpo e entrega outro: é o que um ataque de repetição
      # alterada pareceria.
      assinatura =
        "sha256=" <>
          Base.encode16(:crypto.mac(:hmac, :sha256, @secret, Jason.encode!(%{"a" => 1})),
            case: :lower
          )

      conn =
        entregar(conn, "token-do-webhook", "push", push_payload([commit("abc", "x")]),
          signature: assinatura
        )

      assert response(conn, 401)
    end
  end

  describe "token na URL" do
    test "token desconhecido responde 404 sem contar nada", %{conn: conn} do
      conn = entregar(conn, "token-que-nao-existe", "push", push_payload([commit("abc", "x")]))

      assert response(conn, 404)
    end

    test "entrega para um projeto não pontua em outro", %{conn: conn, user: user} do
      outro = project_fixture(user, %{name: "Outro"})

      conn = entregar(conn, "token-do-webhook", "push", push_payload([commit("abc", "x")]))

      assert response(conn, 200)
      assert Projects.get_project(user, outro.slug).xp == 0
      assert Projects.get_project(user, "meu").xp == 5
    end
  end

  describe "contagem de XP" do
    test "vários commits somam", %{conn: conn, user: user} do
      payload = push_payload([commit("a", "um"), commit("b", "dois"), commit("c", "três")])

      entregar(conn, "token-do-webhook", "push", payload)

      assert Projects.get_project(user, "meu").xp == 15
    end

    test "reenviar a mesma entrega não paga de novo", %{conn: conn, user: user} do
      payload = push_payload([commit("a", "um"), commit("b", "dois")])

      # O GitHub reenvia entregas — por falha de rede, ou porque alguém clicou
      # em "redeliver". O mesmo commit não pode valer duas vezes.
      entregar(build_conn(), "token-do-webhook", "push", payload)
      entregar(build_conn(), "token-do-webhook", "push", payload)
      entregar(build_conn(), "token-do-webhook", "push", payload)

      assert Projects.get_project(user, "meu").xp == 10
      assert length(Projects.list_events(Projects.get_project(user, "meu"))) == 2

      _ = conn
    end

    test "commits novos numa entrega repetida contam só os novos", %{conn: conn, user: user} do
      entregar(build_conn(), "token-do-webhook", "push", push_payload([commit("a", "um")]))

      entregar(
        build_conn(),
        "token-do-webhook",
        "push",
        push_payload([commit("a", "um"), commit("b", "dois")])
      )

      assert Projects.get_project(user, "meu").xp == 10

      _ = conn
    end

    test "pull request mesclado vale 40", %{conn: conn, user: user} do
      payload = %{
        "action" => "closed",
        "pull_request" => %{
          "number" => 7,
          "title" => "Motor de XP",
          "merged" => true,
          "merged_at" => "2026-09-18T10:00:00Z"
        }
      }

      entregar(conn, "token-do-webhook", "pull_request", payload)

      project = Projects.get_project(user, "meu")
      assert project.xp == 40

      assert [%{kind: "pull_request_merged", title: "Motor de XP"}] =
               Projects.list_events(project)
    end

    test "o ping da criação do webhook responde ok sem pontuar", %{conn: conn, user: user} do
      conn = entregar(conn, "token-do-webhook", "ping", %{"zen" => "Design for failure."})

      assert response(conn, 200)
      assert Projects.get_project(user, "meu").xp == 0
    end

    test "evento que o jogo ignora responde ok", %{conn: conn} do
      conn = entregar(conn, "token-do-webhook", "star", %{"action" => "created"})

      assert response(conn, 200)
    end
  end

  describe "Vercel e Stripe" do
    setup %{user: user, project: project} do
      {:ok, _} = Projects.put_webhook(project, "vercel", %{token: "tok-vercel", secret: @secret})
      {:ok, _} = Projects.put_webhook(project, "stripe", %{token: "tok-stripe", secret: @secret})
      :ok
    end

    test "deploy de produção da Vercel pontua", %{conn: conn, user: user} do
      corpo =
        Jason.encode!(%{
          "type" => "deployment.succeeded",
          "id" => "evt_1",
          "createdAt" => 1_789_000_000_000,
          "payload" => %{"target" => "production", "deployment" => %{"id" => "dpl_1"}}
        })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header(
          "x-vercel-signature",
          Base.encode16(:crypto.mac(:hmac, :sha, @secret, corpo), case: :lower)
        )
        |> post("/webhooks/vercel/tok-vercel", corpo)

      assert response(conn, 200)
      assert Projects.get_project(user, "meu").xp == 25
    end

    test "a primeira venda vale 250 e a segunda vira rotina", %{user: user} do
      for id <- ["cs_1", "cs_2"] do
        corpo =
          Jason.encode!(%{
            "type" => "checkout.session.completed",
            "id" => "evt_#{id}",
            "created" => System.system_time(:second),
            "data" => %{
              "object" => %{"id" => id, "amount_total" => 2900, "currency" => "brl"}
            }
          })

        carimbo = System.system_time(:second)

        assinatura =
          Base.encode16(:crypto.mac(:hmac, :sha256, @secret, "#{carimbo}.#{corpo}"), case: :lower)

        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "t=#{carimbo},v1=#{assinatura}")
        |> post("/webhooks/stripe/tok-stripe", corpo)
      end

      # 250 pela primeira, 20 pela segunda.
      assert Projects.get_project(user, "meu").xp == 270

      tipos = Projects.get_project(user, "meu") |> Projects.list_events() |> Enum.map(& &1.kind)
      assert "first_sale" in tipos
      assert "sale" in tipos
    end

    test "token de uma fonte não vale para outra", %{conn: conn, user: user} do
      corpo = Jason.encode!(%{"type" => "deployment.succeeded"})

      # Entregar um token de Vercel na rota da Stripe: sem esta conferência a
      # assinatura seria checada com o algoritmo errado.
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("stripe-signature", "t=1,v1=abc")
        |> post("/webhooks/stripe/tok-vercel", corpo)

      assert response(conn, 404)
      assert Projects.get_project(user, "meu").xp == 0
    end

    test "fonte que não existe responde 404", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/webhooks/inventada/tok-vercel", Jason.encode!(%{}))

      assert response(conn, 404)
    end
  end

  defp user_do(project), do: CommitCraft.Accounts.get_user(project.user_id)
end

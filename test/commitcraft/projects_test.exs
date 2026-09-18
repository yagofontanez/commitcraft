defmodule CommitCraft.ProjectsTest do
  use CommitCraft.DataCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  doctest CommitCraft.Projects

  alias CommitCraft.Projects

  describe "create_project/2" do
    test "cria com o apelido derivado do nome" do
      user = user_fixture()

      assert {:ok, project} = Projects.create_project(user, %{"name" => "Minha Loja"})
      assert project.name == "Minha Loja"
      assert project.slug == "minha-loja"
      assert project.xp == 0
      assert project.user_id == user.id
      assert is_nil(project.repo_full_name)
    end

    test "recusa nome vazio ou curto demais" do
      user = user_fixture()

      assert {:error, changeset} = Projects.create_project(user, %{"name" => ""})
      assert changeset.errors[:name]

      assert {:error, changeset} = Projects.create_project(user, %{"name" => "  a  "})
      assert changeset.errors[:name]
    end

    test "dois projetos com o mesmo nome ganham apelidos diferentes" do
      user = user_fixture()

      {:ok, primeiro} = Projects.create_project(user, %{"name" => "Site"})
      {:ok, segundo} = Projects.create_project(user, %{"name" => "Site"})
      {:ok, terceiro} = Projects.create_project(user, %{"name" => "Site"})

      assert primeiro.slug == "site"
      assert segundo.slug == "site-2"
      assert terceiro.slug == "site-3"
    end

    test "o apelido só precisa ser único dentro da conta" do
      uma = user_fixture()
      outra = user_fixture()

      {:ok, dela} = Projects.create_project(uma, %{"name" => "Site"})
      {:ok, dele} = Projects.create_project(outra, %{"name" => "Site"})

      assert dela.slug == "site"
      assert dele.slug == "site", "o projeto de uma pessoa não deve empurrar o da outra"
    end

    test "o erro de apelido nunca vaza para quem digitou" do
      user = user_fixture()
      {:ok, _} = Projects.create_project(user, %{"name" => "Site"})

      # Quem preenche o formulário vê um campo "nome", não um campo "apelido";
      # mostrar erro de slug seria falar de algo que a pessoa nunca viu.
      {:ok, segundo} = Projects.create_project(user, %{"name" => "Site"})
      assert segundo.slug == "site-2"
    end
  end

  describe "list_projects/1 e get_project/2" do
    test "só enxerga os próprios projetos" do
      dona = user_fixture()
      estranho = user_fixture()

      meu = project_fixture(dona, %{name: "Meu"})
      _dele = project_fixture(estranho, %{name: "Dele"})

      assert [encontrado] = Projects.list_projects(dona)
      assert encontrado.id == meu.id

      assert Projects.get_project(dona, meu.slug).id == meu.id
      assert is_nil(Projects.get_project(estranho, meu.slug))
    end

    test "lista do mais recente para o mais antigo" do
      user = user_fixture()

      antigo = project_fixture(user, %{name: "Antigo"})
      # O carimbo tem precisão de segundo; sem empurrar, a ordem fica ao acaso.
      antigo
      |> Ecto.Changeset.change(inserted_at: ~U[2020-01-01 00:00:00Z])
      |> CommitCraft.Repo.update!()

      novo = project_fixture(user, %{name: "Novo"})

      assert [primeiro, segundo] = Projects.list_projects(user)
      assert primeiro.id == novo.id
      assert segundo.id == antigo.id
    end
  end

  describe "record_events/2" do
    defp commit_em(data, hora, sha) do
      %{
        kind: "commit",
        title: "feat: #{sha}",
        xp: 5,
        occurred_at: DateTime.new!(data, Time.new!(hora, 0, 0), "Etc/UTC"),
        external_id: sha,
        meta: %{}
      }
    end

    test "soma o XP e devolve só o que era novo" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Meu"})

      eventos = [commit_em(~D[2026-09-18], 15, "a"), commit_em(~D[2026-09-18], 16, "b")]

      assert {:ok, %{project: atualizado, events: novos}} =
               Projects.record_events(project, eventos)

      assert atualizado.xp == 10
      assert length(novos) == 2

      # De novo, os mesmos: nada novo, XP igual.
      assert {:ok, %{project: outra_vez, events: []}} = Projects.record_events(project, eventos)
      assert outra_vez.xp == 10
    end

    test "sete dias seguidos rendem o XP de sequência, uma vez só" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Meu"})

      hoje = CommitCraft.Game.Streak.today()
      eventos = for d <- 6..0//-1, do: commit_em(Date.add(hoje, -d), 15, "sha-#{d}")

      {:ok, %{project: atualizado}} = Projects.record_events(project, eventos)

      # 7 commits (35) + o marco de sete dias (80).
      assert atualizado.xp == 115
      assert Projects.current_streak(project) == 7

      # Reprocessar não paga o marco de novo.
      {:ok, %{project: de_novo}} = Projects.record_events(project, eventos)
      assert de_novo.xp == 115
    end

    test "destrava conquista e não destrava duas vezes" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Meu"})

      # 6h UTC é 3h em UTC-3: madrugada adentro.
      madrugada = commit_em(~D[2026-09-18], 6, "sha-madrugada")

      {:ok, %{achievements: primeiras}} = Projects.record_events(project, [madrugada])
      assert Enum.map(primeiras, & &1.key) == ["madrugada"]

      {:ok, %{achievements: segundas}} =
        Projects.record_events(project, [commit_em(~D[2026-09-19], 6, "outra")])

      assert segundas == [], "conquista não se ganha duas vezes"
      assert length(Projects.list_achievements(project)) == 1
    end

    test "XP negativo não some no total" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Meu"})

      eventos = [
        commit_em(~D[2026-09-18], 15, "a"),
        %{
          kind: "broken_build",
          title: "Build quebrado",
          xp: -30,
          occurred_at: ~U[2026-09-18 16:00:00Z],
          external_id: "quebrou",
          meta: %{}
        }
      ]

      {:ok, %{project: atualizado}} = Projects.record_events(project, eventos)

      # O total é honesto, mesmo negativo; quem segura o piso é a curva de nível.
      assert atualizado.xp == -25
      assert CommitCraft.Game.Level.for_xp(atualizado.xp) == 1
    end
  end

  describe "rename_project/3" do
    test "troca o nome e o apelido junto" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Teste"})
      assert project.slug == "teste"

      assert {:ok, renomeado} = Projects.rename_project(user, "teste", %{"name" => "Minha Loja"})
      assert renomeado.id == project.id
      assert renomeado.name == "Minha Loja"
      assert renomeado.slug == "minha-loja"
    end

    test "preserva o XP acumulado" do
      user = user_fixture()
      project_fixture(user, %{name: "Veterano", xp: 6940})

      assert {:ok, renomeado} =
               Projects.rename_project(user, "veterano", %{"name" => "Outro Nome"})

      assert renomeado.xp == 6940
    end

    test "salvar o mesmo nome não quebra no apelido dele próprio" do
      user = user_fixture()
      project_fixture(user, %{name: "Igual"})

      assert {:ok, renomeado} = Projects.rename_project(user, "igual", %{"name" => "Igual"})
      assert renomeado.slug == "igual"
    end

    test "desvia do apelido de um projeto que já existe" do
      user = user_fixture()
      project_fixture(user, %{name: "Site"})
      project_fixture(user, %{name: "Outro"})

      assert {:ok, renomeado} = Projects.rename_project(user, "outro", %{"name" => "Site"})
      assert renomeado.slug == "site-2"
    end

    test "recusa nome inválido sem mexer no projeto" do
      user = user_fixture()
      project_fixture(user, %{name: "Intacto"})

      assert {:error, changeset} = Projects.rename_project(user, "intacto", %{"name" => "x"})
      assert changeset.errors[:name]
      refute changeset.errors[:slug]

      assert Projects.get_project(user, "intacto").name == "Intacto"
    end

    test "não renomeia o projeto de outra pessoa" do
      dona = user_fixture()
      estranho = user_fixture()
      project_fixture(dona, %{name: "Meu"})

      assert Projects.rename_project(estranho, "meu", %{"name" => "Roubado"}) ==
               {:error, :not_found}

      assert Projects.get_project(dona, "meu").name == "Meu"
    end

    test "apelido inexistente e apelido alheio respondem igual" do
      user = user_fixture()
      alheio = project_fixture(user_fixture(), %{name: "Alheio"})

      assert Projects.rename_project(user, "nunca-existiu", %{"name" => "Oi"}) ==
               {:error, :not_found}

      assert Projects.rename_project(user, alheio.slug, %{"name" => "Oi"}) ==
               {:error, :not_found}
    end
  end

  describe "delete_project/2" do
    test "apaga o próprio projeto" do
      user = user_fixture()
      project = project_fixture(user, %{name: "Descartável"})

      assert {:ok, apagado} = Projects.delete_project(user, project.slug)
      assert apagado.id == project.id
      assert Projects.list_projects(user) == []
    end

    test "não apaga o projeto de outra pessoa" do
      dona = user_fixture()
      estranho = user_fixture()
      project = project_fixture(dona, %{name: "Meu"})

      assert Projects.delete_project(estranho, project.slug) == :error
      assert [ainda_la] = Projects.list_projects(dona)
      assert ainda_la.id == project.id
    end

    test "apelido inexistente e apelido alheio respondem igual" do
      user = user_fixture()
      alheio = project_fixture(user_fixture(), %{name: "Alheio"})

      assert Projects.delete_project(user, "nunca-existiu") == :error
      assert Projects.delete_project(user, alheio.slug) == :error
    end
  end

  describe "slugify/1" do
    test "tira acento, pontuação e espaço sobrando" do
      assert Projects.slugify("Ração & Cia — 2024") == "racao-cia-2024"
      assert Projects.slugify("  Espaço   Demais  ") == "espaco-demais"
      assert Projects.slugify("JÁ-ESTÁ-COM-HÍFEN") == "ja-esta-com-hifen"
    end

    test "nome sem letra latina ainda vira um apelido usável" do
      assert Projects.slugify("🎮🎮🎮") =~ ~r/^projeto-[a-z0-9]+$/
      assert Projects.slugify("...") =~ ~r/^projeto-[a-z0-9]+$/
    end
  end
end

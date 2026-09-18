defmodule CommitCraft.RankingTest do
  use CommitCraft.DataCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Ranking

  defp com_xp(login, xp) do
    user = user_fixture(login: login)
    project_fixture(user, %{name: "Projeto de #{login}", xp: xp})
    user
  end

  describe "top/1" do
    test "ordena do maior XP para o menor" do
      com_xp("meio", 500)
      com_xp("primeiro", 900)
      com_xp("ultimo", 100)

      assert ["primeiro", "meio", "ultimo"] =
               Ranking.top() |> Enum.map(& &1.user.github_login)
    end

    test "numera as posições a partir de um" do
      com_xp("a", 300)
      com_xp("b", 200)

      assert [%{position: 1}, %{position: 2}] = Ranking.top()
    end

    test "soma todos os projetos da mesma pessoa" do
      user = user_fixture(login: "produtivo")
      project_fixture(user, %{name: "Um", xp: 300})
      project_fixture(user, %{name: "Dois", xp: 450})

      assert [%{xp: 750, projects: 2}] = Ranking.top()
    end

    test "quem não tem projeto fica de fora" do
      # Uma lista cheia de gente que entrou e nunca começou nada não é um
      # ranking, é uma lista de cadastros.
      user_fixture(login: "so-entrou")
      com_xp("comecou", 100)

      assert ["comecou"] = Ranking.top() |> Enum.map(& &1.user.github_login)
    end

    test "empate desempata pelo login, sempre na mesma ordem" do
      com_xp("zulmira", 500)
      com_xp("amanda", 500)

      # Sem desempate estável, as duas trocariam de lugar a cada carregamento.
      primeira = Ranking.top() |> Enum.map(& &1.user.github_login)
      segunda = Ranking.top() |> Enum.map(& &1.user.github_login)

      assert primeira == ["amanda", "zulmira"]
      assert primeira == segunda
    end

    test "respeita o limite pedido" do
      for i <- 1..5, do: com_xp("dev#{i}", i * 100)

      assert length(Ranking.top(3)) == 3
    end

    test "projeto com XP zero ainda entra" do
      com_xp("novato", 0)

      assert [%{xp: 0, position: 1}] = Ranking.top()
    end
  end

  describe "position_of/1" do
    test "acha a posição mesmo fora dos primeiros" do
      for i <- 1..5, do: com_xp("dev#{i}", i * 100)

      # dev1 tem o menor XP, então é o último dos cinco.
      lanterna = Enum.find(Ranking.top(), &(&1.user.github_login == "dev1"))

      assert lanterna.position == 5
      assert Ranking.position_of(lanterna.user) == 5
    end

    test "a posição não depende de quantos cabem na primeira página" do
      for i <- 1..5, do: com_xp("dev#{i}", i * 100)

      lanterna = Enum.find(Ranking.top(), &(&1.user.github_login == "dev1"))

      # Mesmo mostrando só os três primeiros, quem ficou de fora precisa saber
      # onde está — é justamente aí que a informação importa.
      assert length(Ranking.top(3)) == 3
      assert Ranking.position_of(lanterna.user) == 5
    end

    test "devolve nil para quem ainda não tem projeto" do
      sozinho = user_fixture(login: "so-entrou")

      assert is_nil(Ranking.position_of(sozinho))
    end
  end
end

defmodule CommitCraftWeb.RankingControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  setup %{conn: conn} do
    user = user_fixture(login: "yagofontanez", name: "Yago")
    %{conn: log_in_user(conn, user), user: user}
  end

  test "exige estar logado", %{} do
    assert build_conn() |> get(~p"/ranking") |> redirected_to() == ~p"/"
  end

  test "mostra as pessoas e o XP delas", %{conn: conn, user: user} do
    project_fixture(user, %{name: "Meu", xp: 6940})

    outra = user_fixture(login: "outra-pessoa", name: "Outra Pessoa")
    project_fixture(outra, %{name: "Dela", xp: 100})

    html = conn |> get(~p"/ranking") |> html_response(200)

    assert html =~ "Yago"
    assert html =~ "Outra Pessoa"
    assert html =~ "6.940 XP"
    assert html =~ "LV 07"
  end

  test "nunca mostra nome de projeto nem repositório", %{conn: conn, user: user} do
    outra = user_fixture(login: "outra-pessoa")
    project = project_fixture(outra, %{name: "Projeto Secreto Dela", xp: 500})

    {:ok, _} =
      CommitCraft.Projects.connect_repo(outra, project.slug, %{
        id: 7,
        full_name: "outra-pessoa/repo-privado",
        private: true
      })

    project_fixture(user, %{name: "Meu", xp: 10})

    html = conn |> get(~p"/ranking") |> html_response(200)

    # Saber que alguém trabalha muito é bem diferente de saber no quê.
    refute html =~ "Projeto Secreto Dela"
    refute html =~ "repo-privado"
    assert html =~ "outra-pessoa"
  end

  test "diz onde você está quando ainda não pontuou", %{conn: conn} do
    html = conn |> get(~p"/ranking") |> html_response(200)

    assert html =~ "Ninguém pontuou ainda"
  end

  test "o pódio recebe metal e o resto não", %{conn: conn, user: user} do
    project_fixture(user, %{name: "Meu", xp: 1000})

    for {login, xp} <- [{"segundo", 800}, {"terceiro", 600}, {"quarto", 400}] do
      outra = user_fixture(login: login)
      project_fixture(outra, %{name: "Projeto", xp: xp})
    end

    html = conn |> get(~p"/ranking") |> html_response(200)

    # Três sprites de pódio — um troféu e duas medalhas. O quarto é só número.
    assert html =~ "quarto"
    assert Regex.scan(~r/viewBox="0 0 12 12"/, html) |> length() >= 3
  end
end

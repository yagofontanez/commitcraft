defmodule CommitCraftWeb.BadgeControllerTest do
  use CommitCraftWeb.ConnCase

  import CommitCraft.AccountsFixtures
  import CommitCraft.ProjectsFixtures

  alias CommitCraft.Projects

  test "entrega o selo de um projeto público, sem login", %{conn: conn} do
    user = user_fixture(login: "yagofontanez")
    project = project_fixture(user, %{name: "Minha Loja", xp: 6940})
    {:ok, _} = Projects.set_visibility(user, project.slug, true)

    conn = get(conn, ~p"/p/yagofontanez/minha-loja/badge.svg")

    assert response(conn, 200) =~ "LV 07"
    assert response_content_type(conn, :svg) =~ "image/svg+xml"
    assert [cache] = get_resp_header(conn, "cache-control")
    assert cache =~ "max-age"
  end

  test "projeto fechado devolve selo de não encontrado, não erro", %{conn: conn} do
    user = user_fixture(login: "yagofontanez")
    project_fixture(user, %{name: "Privado"})

    conn = get(conn, ~p"/p/yagofontanez/privado/badge.svg")

    # Um selo quebrado no README de alguém é pior do que um selo que explica.
    assert response(conn, 404) =~ "<svg"
    assert response(conn, 404) =~ "não encontrado"
    refute response(conn, 404) =~ "Privado"
  end
end

defmodule CommitCraft.AccountsTest do
  use CommitCraft.DataCase

  import CommitCraft.AccountsFixtures

  alias CommitCraft.Accounts
  alias CommitCraft.Accounts.User
  alias CommitCraft.Repo

  describe "upsert_from_github/2" do
    test "cria a conta na primeira vez" do
      perfil = github_profile(login: "yagofontanez", name: "Yago")

      assert {:ok, %User{} = user} = Accounts.upsert_from_github(perfil, github_credentials())
      assert user.github_id == perfil.id
      assert user.github_login == "yagofontanez"
      assert user.name == "Yago"
    end

    test "entrar de novo atualiza a conta em vez de criar outra" do
      perfil = github_profile(login: "antigo", name: "Nome Antigo")
      {:ok, primeiro} = Accounts.upsert_from_github(perfil, github_credentials())

      # Mesma pessoa, que trocou o @login e o nome no GitHub.
      renomeado = %{perfil | login: "novo", name: "Nome Novo"}
      {:ok, segundo} = Accounts.upsert_from_github(renomeado, github_credentials())

      assert segundo.id == primeiro.id, "trocar de @login não pode criar conta nova"
      assert segundo.github_login == "novo"
      assert segundo.name == "Nome Novo"
      assert Repo.aggregate(User, :count) == 1
    end

    test "guarda os escopos concedidos junto do token" do
      {:ok, user} =
        Accounts.upsert_from_github(
          github_profile(),
          github_credentials(token: "gho_abc", scopes: ["read:user", "repo"])
        )

      assert user.github_token == "gho_abc"
      assert user.github_scopes == ["read:user", "repo"]
    end
  end

  describe "o token guardado" do
    test "não fica legível no banco" do
      {:ok, user} =
        Accounts.upsert_from_github(github_profile(), github_credentials(token: "gho_segredo"))

      [cru] = Repo.all(from u in "users", where: u.id == ^user.id, select: u.github_token)

      refute cru == "gho_segredo"
      refute String.contains?(cru, "gho_segredo")

      # E continua legível pela aplicação.
      assert Accounts.get_user(user.id).github_token == "gho_segredo"
    end

    test "some quando a pessoa sai" do
      user = user_fixture()
      assert user.github_token

      assert {:ok, esquecido} = Accounts.forget_github_token(user)
      assert is_nil(esquecido.github_token)
      assert esquecido.github_scopes == []
      assert Accounts.get_user(user.id).github_login == user.github_login
    end
  end

  describe "display_name/1" do
    test "prefere o nome, cai para o login" do
      assert User.display_name(%User{name: "Yago", github_login: "yagofontanez"}) == "Yago"
      assert User.display_name(%User{name: nil, github_login: "yagofontanez"}) == "yagofontanez"
      assert User.display_name(%User{name: "", github_login: "yagofontanez"}) == "yagofontanez"
    end
  end
end

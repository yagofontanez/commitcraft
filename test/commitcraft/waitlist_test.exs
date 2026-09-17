defmodule CommitCraft.WaitlistTest do
  use CommitCraft.DataCase

  alias CommitCraft.Waitlist

  describe "waitlist_signups" do
    alias CommitCraft.Waitlist.Signup

    import CommitCraft.WaitlistFixtures

    @invalid_attrs %{email: nil}

    test "list_waitlist_signups/0 returns all waitlist_signups" do
      signup = signup_fixture()
      assert Waitlist.list_waitlist_signups() == [signup]
    end

    test "get_signup!/1 returns the signup with given id" do
      signup = signup_fixture()
      assert Waitlist.get_signup!(signup.id) == signup
    end

    test "create_signup/1 with valid data creates a signup" do
      valid_attrs = %{email: "alguem@exemplo.com"}

      assert {:ok, %Signup{} = signup} = Waitlist.create_signup(valid_attrs)
      assert signup.email == "alguem@exemplo.com"
    end

    test "create_signup/1 guarda o e-mail sem espaços e em minúsculas" do
      assert {:ok, %Signup{} = signup} =
               Waitlist.create_signup(%{email: "  Alguem@Exemplo.COM  "})

      assert signup.email == "alguem@exemplo.com"
    end

    test "create_signup/1 recusa o que não é endereço de e-mail" do
      for nao_email <- ["", "alguem", "alguem@", "@exemplo.com", "alguem@exemplo", "a b@c.com"] do
        assert {:error, %Ecto.Changeset{}} = Waitlist.create_signup(%{email: nao_email}),
               "deveria recusar #{inspect(nao_email)}"
      end
    end

    test "create_signup/1 recusa o mesmo e-mail duas vezes, ignorando maiúsculas" do
      assert {:ok, _} = Waitlist.create_signup(%{email: "repetido@exemplo.com"})

      assert {:error, changeset} = Waitlist.create_signup(%{email: "REPETIDO@exemplo.com"})
      assert [email: {_, [constraint: :unique, constraint_name: _]}] = changeset.errors
    end

    test "create_signup/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Waitlist.create_signup(@invalid_attrs)
    end

    test "update_signup/2 with valid data updates the signup" do
      signup = signup_fixture()
      update_attrs = %{email: "outro@exemplo.com"}

      assert {:ok, %Signup{} = signup} = Waitlist.update_signup(signup, update_attrs)
      assert signup.email == "outro@exemplo.com"
    end

    test "update_signup/2 with invalid data returns error changeset" do
      signup = signup_fixture()
      assert {:error, %Ecto.Changeset{}} = Waitlist.update_signup(signup, @invalid_attrs)
      assert signup == Waitlist.get_signup!(signup.id)
    end

    test "delete_signup/1 deletes the signup" do
      signup = signup_fixture()
      assert {:ok, %Signup{}} = Waitlist.delete_signup(signup)
      assert_raise Ecto.NoResultsError, fn -> Waitlist.get_signup!(signup.id) end
    end

    test "change_signup/1 returns a signup changeset" do
      signup = signup_fixture()
      assert %Ecto.Changeset{} = Waitlist.change_signup(signup)
    end
  end
end

defmodule CommitCraft.AccountsFixtures do
  @moduledoc """
  Contas de teste, criadas pelo mesmo caminho que o OAuth usa.
  """
  alias CommitCraft.Accounts

  def github_profile(attrs \\ %{}) do
    id = System.unique_integer([:positive])

    Enum.into(attrs, %{
      id: id,
      login: "dev#{id}",
      name: "Pessoa #{id}",
      avatar_url: "https://avatars.githubusercontent.com/u/#{id}"
    })
  end

  def github_credentials(attrs \\ %{}) do
    Enum.into(attrs, %{
      token: "gho_token_#{System.unique_integer([:positive])}",
      scopes: ["read:user"]
    })
  end

  def user_fixture(profile_attrs \\ %{}) do
    {:ok, user} =
      Accounts.upsert_from_github(github_profile(profile_attrs), github_credentials())

    user
  end
end

defmodule CommitCraft.WaitlistFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `CommitCraft.Waitlist` context.
  """

  @doc """
  Generate a unique signup email.
  """
  def unique_signup_email, do: "pessoa#{System.unique_integer([:positive])}@exemplo.com"

  @doc """
  Generate a signup.
  """
  def signup_fixture(attrs \\ %{}) do
    {:ok, signup} =
      attrs
      |> Enum.into(%{
        email: unique_signup_email()
      })
      |> CommitCraft.Waitlist.create_signup()

    signup
  end
end

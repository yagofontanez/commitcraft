defmodule CommitCraft.Accounts.User do
  @moduledoc """
  Uma pessoa, identificada pela conta do GitHub.

  Não existe senha: a única porta de entrada é o OAuth do GitHub. O identificador
  estável é o `github_id` numérico — o `github_login` muda quando a pessoa renomeia
  a conta, então ele nunca é chave de nada.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "users" do
    field :github_id, :integer
    field :github_login, :string
    field :name, :string
    field :avatar_url, :string

    field :github_token, CommitCraft.EncryptedBinary, redact: true
    field :github_scopes, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  Monta o usuário a partir do que o GitHub devolveu depois do OAuth.
  """
  def github_changeset(user, attrs) do
    user
    |> cast(attrs, [:github_id, :github_login, :name, :avatar_url, :github_token, :github_scopes])
    |> validate_required([:github_id, :github_login])
    |> unique_constraint(:github_id)
  end

  @doc """
  Como chamar a pessoa na tela: o nome que ela escolheu, ou o login.
  """
  def display_name(%__MODULE__{name: name}) when is_binary(name) and name != "", do: name
  def display_name(%__MODULE__{github_login: login}), do: login
end

defmodule CommitCraft.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :github_id, :bigint, null: false
      add :github_login, :string, null: false
      add :name, :string
      add :avatar_url, :string

      # Cifrado pela aplicação — ver CommitCraft.EncryptedBinary.
      add :github_token, :binary
      add :github_scopes, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:github_id])
  end
end

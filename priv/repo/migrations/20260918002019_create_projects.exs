defmodule CommitCraft.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :xp, :integer, null: false, default: 0
      add :repo_full_name, :string

      timestamps(type: :utc_datetime)
    end

    create index(:projects, [:user_id])

    # O slug só precisa ser único dentro da conta: dois desenvolvedores
    # diferentes podem ter, cada um, o seu "site".
    create unique_index(:projects, [:user_id, :slug])
  end
end

defmodule CommitCraft.Repo.Migrations.CreateWaitlistSignups do
  use Ecto.Migration

  def change do
    create table(:waitlist_signups) do
      add :email, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:waitlist_signups, [:email])
  end
end

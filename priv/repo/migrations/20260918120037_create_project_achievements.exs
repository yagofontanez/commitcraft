defmodule CommitCraft.Repo.Migrations.CreateProjectAchievements do
  use Ecto.Migration

  def change do
    # Detalhes do acontecimento que as conquistas precisam ler — quantas linhas
    # um pull request apagou, por exemplo. Fora das colunas fixas porque cada
    # fonte carrega coisas diferentes, e nenhuma delas é consultada por si só.
    alter table(:project_events) do
      add :meta, :map, null: false, default: %{}
    end

    create table(:project_achievements) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :unlocked_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # Conquista não se ganha duas vezes.
    create unique_index(:project_achievements, [:project_id, :key])
  end
end

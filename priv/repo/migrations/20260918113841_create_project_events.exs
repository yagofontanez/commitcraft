defmodule CommitCraft.Repo.Migrations.CreateProjectEvents do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # O identificador do hook no GitHub, para conseguir removê-lo depois.
      add :webhook_id, :bigint
      # Vai na URL do webhook e serve só para achar o projeto. Quem autentica
      # a entrega é a assinatura, não este valor.
      add :webhook_token, :string
      # Cifrado pela aplicação — ver CommitCraft.EncryptedBinary.
      add :webhook_secret, :binary
      add :webhook_installed_at, :utc_datetime
    end

    create unique_index(:projects, [:webhook_token])

    create table(:project_events) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      # O que aconteceu, na linguagem do jogo — não na do GitHub.
      add :kind, :string, null: false
      add :title, :string, null: false
      add :xp, :integer, null: false
      add :occurred_at, :utc_datetime, null: false

      # A identidade daquilo que aconteceu: o SHA de um commit, o número de um
      # pull request. É o que impede o mesmo acontecimento de valer XP duas
      # vezes quando o GitHub reenvia a entrega — e ele reenvia.
      add :external_id, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:project_events, [:project_id, :external_id])
    create index(:project_events, [:project_id, "occurred_at desc"])
  end
end

defmodule CommitCraft.Repo.Migrations.AddPublicToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # Privado por padrão, e sempre. Tornar público é um ato, nunca um
      # esquecimento.
      add :public, :boolean, null: false, default: false
    end

    create index(:projects, [:public], where: "public")
  end
end

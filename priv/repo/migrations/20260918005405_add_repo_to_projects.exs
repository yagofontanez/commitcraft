defmodule CommitCraft.Repo.Migrations.AddRepoToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      # O identificador numérico é o que não muda: repositório renomeado
      # continua o mesmo, e `repo_full_name` é só o rótulo de hoje.
      add :repo_id, :bigint
      add :repo_private, :boolean
      add :repo_connected_at, :utc_datetime
    end

    # Um repositório por projeto, e um projeto por repositório dentro da conta —
    # dois projetos apontando para o mesmo repo contariam o mesmo commit duas vezes.
    create unique_index(:projects, [:user_id, :repo_id],
             where: "repo_id is not null",
             name: :projects_user_id_repo_id_index
           )
  end
end

defmodule CommitCraft.Projects.Event do
  @moduledoc """
  Uma coisa que aconteceu no projeto e valeu (ou custou) XP.

  A tabela é o registro de tudo: o `xp` de um projeto é a soma do que está aqui.
  Guardar o evento além do total permite mostrar a linha do tempo e recalcular
  se a tabela de pontos mudar.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias CommitCraft.Projects.Project

  schema "project_events" do
    field :kind, :string
    field :title, :string
    field :xp, :integer
    field :occurred_at, :utc_datetime
    field :external_id, :string

    belongs_to :project, Project

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:kind, :title, :xp, :occurred_at, :external_id])
    |> validate_required([:kind, :title, :xp, :occurred_at, :external_id])
    |> validate_length(:title, max: 200)
    |> unique_constraint([:project_id, :external_id],
      name: :project_events_project_id_external_id_index
    )
  end
end

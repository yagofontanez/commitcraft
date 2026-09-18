defmodule CommitCraft.Projects.Project do
  @moduledoc """
  Um projeto: a partida que a pessoa está jogando.

  O nível não mora aqui — é calculado a partir do `xp` por
  `CommitCraft.Game.Level`. Guardar os dois convidaria os dois a discordarem.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias CommitCraft.Accounts.User

  schema "projects" do
    field :name, :string
    field :slug, :string
    field :xp, :integer, default: 0

    # Preenchido quando a pessoa conectar um repositório. Até lá o projeto
    # existe, mas nada alimenta o XP dele.
    field :repo_full_name, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :slug])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 60)
    |> unique_constraint(:slug, name: :projects_user_id_slug_index)
  end
end

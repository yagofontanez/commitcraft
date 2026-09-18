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

    # Preenchidos quando a pessoa conectar um repositório. Até lá o projeto
    # existe, mas nada alimenta o XP dele.
    field :repo_id, :integer
    field :repo_full_name, :string
    field :repo_private, :boolean
    field :repo_connected_at, :utc_datetime
    field :public, :boolean, default: false

    has_many :events, CommitCraft.Projects.Event
    has_many :webhooks, CommitCraft.Projects.Webhook

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Liga um repositório do GitHub a este projeto.

  Guarda o id numérico junto do nome: o nome muda quando alguém renomeia o
  repositório, o id não.
  """
  def repo_changeset(project, repo) do
    project
    |> change(
      repo_id: repo.id,
      repo_full_name: repo.full_name,
      repo_private: repo.private,
      repo_connected_at: DateTime.utc_now(:second)
    )
    |> validate_required([:repo_id, :repo_full_name])
    |> unique_constraint([:user_id, :repo_id], name: :projects_user_id_repo_id_index)
  end

  @doc "Desliga o repositório, mantendo o projeto e o XP já conquistado."
  def disconnect_changeset(project) do
    change(project,
      repo_id: nil,
      repo_full_name: nil,
      repo_private: nil,
      repo_connected_at: nil
    )
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

defmodule CommitCraft.Projects.Achievement do
  @moduledoc """
  Uma conquista que um projeto já conseguiu.

  Só a chave e o momento moram no banco. Nome, descrição e raridade vivem em
  `CommitCraft.Game.Achievements` — mudar o texto de uma medalha não deveria
  exigir migração.
  """
  use Ecto.Schema

  schema "project_achievements" do
    field :key, :string
    field :unlocked_at, :utc_datetime

    belongs_to :project, CommitCraft.Projects.Project

    timestamps(type: :utc_datetime, updated_at: false)
  end
end

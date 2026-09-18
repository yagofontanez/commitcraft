defmodule CommitCraft.ProjectsFixtures do
  @moduledoc """
  Projetos de teste.
  """
  alias CommitCraft.Projects
  alias CommitCraft.Repo

  def project_fixture(user, attrs \\ %{}) do
    xp = Map.get(attrs, :xp, 0)
    attrs = Map.delete(attrs, :xp)

    {:ok, project} =
      Projects.create_project(
        user,
        Enum.into(attrs, %{name: "Projeto #{System.unique_integer([:positive])}"})
      )

    if xp == 0 do
      project
    else
      # XP escrito direto, para montar um estado inicial. Cuidado: o primeiro
      # `record_events/2` recalcula o total como a soma dos eventos, então este
      # valor some. Para um estado que sobreviva a novos eventos, grave eventos.
      project |> Ecto.Changeset.change(xp: xp) |> Repo.update!()
    end
  end
end

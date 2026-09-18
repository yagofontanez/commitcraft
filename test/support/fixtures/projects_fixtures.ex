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
      # Ainda não existe caminho pelo domínio para dar XP — isso chega com os
      # eventos do GitHub. Até lá, o teste escreve direto.
      project |> Ecto.Changeset.change(xp: xp) |> Repo.update!()
    end
  end
end

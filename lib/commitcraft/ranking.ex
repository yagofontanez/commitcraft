defmodule CommitCraft.Ranking do
  @moduledoc """
  Quem está na frente.

  O XP de uma pessoa é a soma do XP dos projetos dela. Nome de projeto nunca
  sai daqui: repositório privado é privado, e saber que alguém trabalha muito é
  bem diferente de saber no quê.
  """
  import Ecto.Query, warn: false

  alias CommitCraft.Accounts.User
  alias CommitCraft.Projects.Project
  alias CommitCraft.Repo

  @doc """
  A tabela, da maior pontuação para a menor.

  Só entra quem tem ao menos um projeto: uma lista cheia de gente que entrou e
  nunca começou nada não é um ranking, é uma lista de cadastros.

  O desempate é pelo login, e não pela ordem que o banco devolver — sem isso,
  duas pessoas empatadas trocariam de lugar a cada carregamento da página.
  """
  def top(limite \\ 50) do
    consulta()
    |> limit(^limite)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {linha, posicao} -> Map.put(linha, :position, posicao) end)
  end

  @doc """
  A posição de uma pessoa, ou `nil` se ela ainda não tem projeto.

  Serve para mostrar onde você está quando ficou fora dos primeiros — que é
  quase sempre, e é justamente quando a informação importa.
  """
  def position_of(%User{} = user) do
    consulta()
    |> Repo.all()
    |> Enum.find_index(&(&1.user.id == user.id))
    |> case do
      nil -> nil
      indice -> indice + 1
    end
  end

  defp consulta do
    from u in User,
      join: p in Project,
      on: p.user_id == u.id,
      group_by: u.id,
      select: %{
        user: u,
        xp: coalesce(sum(p.xp), 0),
        projects: count(p.id)
      },
      order_by: [desc: coalesce(sum(p.xp), 0), asc: u.github_login]
  end
end

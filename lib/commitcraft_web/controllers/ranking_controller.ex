defmodule CommitCraftWeb.RankingController do
  @moduledoc """
  A tabela de quem está na frente.

  Exige estar logado: a página conta quem usa o CommitCraft e o quanto essa
  pessoa trabalha, e deixar isso aberto na internet seria decidir pelos outros.
  """
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Level
  alias CommitCraft.Ranking

  def index(conn, _params) do
    user = conn.assigns.current_user
    linhas = Ranking.top()

    conn
    |> assign(:page_title, "Ranking")
    |> assign(:rows, Enum.map(linhas, &Map.put(&1, :progress, Level.progress(&1.xp))))
    |> assign(:my_position, Ranking.position_of(user))
    |> render(:index)
  end
end

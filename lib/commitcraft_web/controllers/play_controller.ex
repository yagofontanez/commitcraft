defmodule CommitCraftWeb.PlayController do
  @moduledoc """
  A tela que vem depois de entrar.

  Num jogo, depois da tela de título vem a seleção de save. Aqui vai ser a lista
  de projetos — por enquanto é uma vaga vazia, porque projeto ainda não existe.
  """
  use CommitCraftWeb, :controller

  def index(conn, _params) do
    conn
    |> assign(:page_title, "Seus projetos")
    |> render(:index)
  end
end

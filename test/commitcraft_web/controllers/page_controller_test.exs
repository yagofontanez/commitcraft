defmodule CommitCraftWeb.PageControllerTest do
  use CommitCraftWeb.ConnCase

  describe "GET /" do
    test "mostra a promessa e as âncoras do menu", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "CommitCraft"
      assert html =~ "Seu repositório já é um jogo"

      for ancora <- ~w(#grupo #pontos #conquistas #moeda) do
        assert html =~ ancora, "o menu deveria apontar para #{ancora}"
      end
    end

    test "a tabela de XP mostra os números, inclusive o negativo", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "Commit na branch principal"
      assert html =~ "+250"
      assert html =~ "-30"
    end

    test "as conquistas ainda não conseguidas aparecem com nome", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      # Esconder o nome de uma conquista bloqueada desperdiçaria justamente a
      # parte que faz graça — a página mostra todas e marca o estado à parte.
      assert html =~ "Maratona"
      assert html =~ "ainda não"
    end

    test "o texto da caixa de diálogo vem renderizado, sem depender de JS", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "Cada commit vira XP"
    end

    test "não promete lista de espera enquanto o jogo não existe", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      refute html =~ "fila"
      refute html =~ "<form"
    end

    test "todo link interno aponta para uma seção que existe na página", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      destinos = Regex.scan(~r/href="#([\w-]+)"/, html) |> Enum.map(&List.last/1) |> Enum.uniq()
      assert destinos != []

      for destino <- destinos do
        assert html =~ ~s(id="#{destino}"), "o link ##{destino} não leva a lugar nenhum"
      end
    end
  end
end

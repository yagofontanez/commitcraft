defmodule CommitCraftWeb.PageControllerTest do
  use CommitCraftWeb.ConnCase

  alias CommitCraft.Waitlist

  describe "GET /" do
    test "mostra a promessa e as âncoras do menu", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "CommitCraft"
      assert html =~ "Seu repositório já é um jogo"

      for ancora <- ~w(#grupo #pontos #conquistas #moeda #fila) do
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
  end

  describe "POST /fila" do
    test "guarda o e-mail e confirma", %{conn: conn} do
      conn = post(conn, ~p"/fila", %{"signup" => %{"email" => "novo@exemplo.com"}})

      assert redirected_to(conn) == "/#fila"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "está na fila"
      assert [%{email: "novo@exemplo.com"}] = Waitlist.list_waitlist_signups()
    end

    test "quem já está na fila recebe confirmação, não erro", %{conn: conn} do
      {:ok, _} = Waitlist.create_signup(%{email: "repetido@exemplo.com"})

      conn = post(conn, ~p"/fila", %{"signup" => %{"email" => "Repetido@Exemplo.com"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "já estava na fila"
      refute Phoenix.Flash.get(conn.assigns.flash, :error)
      assert length(Waitlist.list_waitlist_signups()) == 1
    end

    test "explica o que houve quando o endereço não é um e-mail", %{conn: conn} do
      conn = post(conn, ~p"/fila", %{"signup" => %{"email" => "isso não é e-mail"}})

      assert redirected_to(conn) == "/#fila"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "não parece um endereço de e-mail"
      assert Waitlist.list_waitlist_signups() == []
    end
  end
end

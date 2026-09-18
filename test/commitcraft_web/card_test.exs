defmodule CommitCraftWeb.CardTest do
  use ExUnit.Case, async: true

  alias CommitCraft.Game.Level
  alias CommitCraftWeb.Card

  defp dimensoes(png) do
    <<_assinatura::binary-size(8), _tamanho::32, "IHDR", largura::32, altura::32, _resto::binary>> =
      png

    {largura, altura}
  end

  defp render(opts) do
    Card.render(
      Keyword.merge(
        [name: "Ração & Cia", login: "yagofontanez", progress: Level.progress(720)],
        opts
      )
    )
  end

  test "entrega um PNG no tamanho que as redes esperam" do
    assert dimensoes(render([])) == {1200, 630}
  end

  test "nome comprido não muda o tamanho da imagem" do
    # Se o corte falhasse, o desenho vazaria da moldura em vez de crescer — mas
    # o tamanho fixo é o que garante que nada escapou da grade.
    longo = String.duplicate("nome absurdamente comprido ", 10)

    assert dimensoes(render(name: longo)) == {1200, 630}
  end

  test "nome vazio não quebra" do
    assert dimensoes(render(name: "")) == {1200, 630}
  end

  test "nome só de emoji não quebra" do
    # A fonte descarta o que não tem desenho; sobra string vazia.
    assert dimensoes(render(name: "🎮🎮🎮")) == {1200, 630}
  end

  test "funciona com e sem classe" do
    assert dimensoes(render(class: nil)) == {1200, 630}
    assert dimensoes(render(class: %{name: "Faxineiro"})) == {1200, 630}
  end

  test "barra vazia e barra cheia geram imagens diferentes" do
    vazia = render(progress: Level.progress(0))
    quase_cheia = render(progress: Level.progress(199))

    refute vazia == quase_cheia
  end

  test "projetos diferentes geram imagens diferentes" do
    refute render(name: "Um") == render(name: "Outro")
  end

  test "o mesmo projeto gera sempre a mesma imagem" do
    # Determinismo importa: o robô que busca o card pode pedir duas vezes, e
    # uma imagem que muda sozinha viraria cache confuso.
    assert render([]) == render([])
  end
end

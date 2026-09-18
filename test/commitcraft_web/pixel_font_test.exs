defmodule CommitCraftWeb.PixelFontTest do
  use ExUnit.Case, async: true

  doctest CommitCraftWeb.PixelFont

  alias CommitCraftWeb.PixelFont

  test "tira acento e sobe para maiúscula" do
    assert PixelFont.normalizar("Ração & Cia") == "RACAO & CIA"
    assert PixelFont.normalizar("João Pedro") == "JOAO PEDRO"
  end

  test "descarta o que não tem desenho, em vez de virar caixa" do
    assert PixelFont.normalizar("oi 🎮 tudo bem") == "OI  TUDO BEM"
  end

  test "texto vazio não ocupa espaço nem acende pixel" do
    assert PixelFont.medir("") == 0
    assert PixelFont.pixels("") == []
  end

  test "a medida cresce um caractere de cada vez" do
    # Cinco de largura mais um de respiro, menos o respiro do fim.
    assert PixelFont.medir("A") == 5
    assert PixelFont.medir("AB") == 11
    assert PixelFont.medir("ABC") == 17
  end

  test "os pixels cabem dentro da medida" do
    texto = "COMMITCRAFT LV 07"
    largura = PixelFont.medir(texto)

    for {x, y} <- PixelFont.pixels(texto) do
      assert x >= 0 and x < largura, "pixel em #{x} escapa da largura #{largura}"
      assert y >= 0 and y < PixelFont.altura()
    end
  end

  test "letras diferentes desenham coisas diferentes" do
    refute PixelFont.pixels("A") == PixelFont.pixels("B")
  end

  test "o espaço não acende nada" do
    assert PixelFont.pixels(" ") == []
  end

  test "todo dígito tem desenho" do
    for d <- 0..9 do
      assert PixelFont.pixels(Integer.to_string(d)) != [],
             "o dígito #{d} não tem glifo"
    end
  end

  test "toda letra do alfabeto tem desenho" do
    for letra <- ?A..?Z do
      texto = <<letra>>
      assert PixelFont.pixels(texto) != [], "a letra #{texto} não tem glifo"
    end
  end
end

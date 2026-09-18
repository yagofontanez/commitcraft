defmodule CommitCraftWeb.PngTest do
  use ExUnit.Case, async: true

  alias CommitCraftWeb.Png

  @assinatura <<137, 80, 78, 71, 13, 10, 26, 10>>

  defp cabecalho(png) do
    <<_assinatura::binary-size(8), _tamanho::32, "IHDR", largura::32, altura::32, profundidade,
      cor, _resto::binary>> = png

    %{largura: largura, altura: altura, profundidade: profundidade, cor: cor}
  end

  test "começa com a assinatura que todo leitor de PNG procura" do
    png = Png.encode([[{0, 0, 0}]])

    assert <<@assinatura, _resto::binary>> = png
  end

  test "declara as dimensões da grade" do
    linhas = for _ <- 1..3, do: for(_ <- 1..5, do: {0, 0, 0})

    assert %{largura: 5, altura: 3, profundidade: 8, cor: 2} = cabecalho(Png.encode(linhas))
  end

  test "a escala multiplica os dois eixos" do
    linhas = for _ <- 1..3, do: for(_ <- 1..5, do: {0, 0, 0})

    assert %{largura: 50, altura: 30} = cabecalho(Png.encode(linhas, 10))
  end

  test "termina com IEND, senão o arquivo está truncado" do
    png = Png.encode([[{1, 2, 3}]])

    assert String.ends_with?(png, <<0::32, "IEND", 174, 66, 96, 130>>)
  end

  test "os dados descomprimem de volta nos pixels originais" do
    linhas = [[{255, 0, 0}, {0, 255, 0}], [{0, 0, 255}, {9, 9, 9}]]

    idat = extrair_idat(Png.encode(linhas))

    # Cada linha começa com o byte de filtro, aqui sempre zero.
    assert :zlib.uncompress(idat) ==
             <<0, 255, 0, 0, 0, 255, 0, 0, 0, 0, 255, 9, 9, 9>>
  end

  test "a escala repete o pixel, não interpola" do
    # Interpolar borraria a arte; num jogo de pixel isso é o defeito, não o
    # recurso.
    idat = extrair_idat(Png.encode([[{255, 0, 0}]], 3))

    assert :zlib.uncompress(idat) ==
             <<0, 255, 0, 0, 255, 0, 0, 255, 0, 0>> <>
               <<0, 255, 0, 0, 255, 0, 0, 255, 0, 0>> <>
               <<0, 255, 0, 0, 255, 0, 0, 255, 0, 0>>
  end

  defp extrair_idat(<<_assinatura::binary-size(8), resto::binary>>), do: procurar_idat(resto)

  defp procurar_idat(
         <<tamanho::32, tipo::binary-size(4), dados::binary-size(tamanho), _crc::32,
           resto::binary>>
       ) do
    if tipo == "IDAT", do: dados, else: procurar_idat(resto)
  end
end

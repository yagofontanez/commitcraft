defmodule CommitCraftWeb.Png do
  @moduledoc """
  Um codificador de PNG, escrito à mão.

  Parece exagero até olhar o que a alternativa custava: renderizar imagem em
  Elixir significa arrastar libvips ou um navegador sem cabeça, e isso vira uma
  dependência de sistema que precisa existir também no servidor.

  E o CommitCraft desenha *pixel art*. Um PNG sem compressão com perdas é
  literalmente uma grade de cores seguida de zlib — que a própria OTP já traz.
  São trinta linhas para não depender de nada.

  A imagem é desenhada pequena e ampliada na hora de codificar: é o que mantém
  o traço quadrado, e é como qualquer jogo de 16 bits chega numa tela moderna.
  """

  @assinatura <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Codifica uma grade de cores.

  `linhas` é uma lista de linhas, cada uma uma lista de `{r, g, b}`. `escala`
  repete cada pixel nos dois eixos.
  """
  def encode(linhas, escala \\ 1) when is_list(linhas) and escala >= 1 do
    largura = linhas |> List.first() |> length() |> Kernel.*(escala)
    altura = length(linhas) * escala

    dados =
      linhas
      |> Enum.flat_map(&List.duplicate(scanline(&1, escala), escala))
      |> IO.iodata_to_binary()

    IO.iodata_to_binary([
      @assinatura,
      chunk("IHDR", <<largura::32, altura::32, 8, 2, 0, 0, 0>>),
      chunk("IDAT", :zlib.compress(dados)),
      chunk("IEND", "")
    ])
  end

  # O zero na frente é o filtro da linha. PNG permite cinco, e "nenhum" é o
  # certo aqui: arte com áreas chapadas já comprime bem, e filtro só faria a
  # conta ficar maior.
  defp scanline(linha, escala) do
    [0 | Enum.flat_map(linha, fn {r, g, b} -> List.duplicate(<<r, g, b>>, escala) end)]
  end

  defp chunk(tipo, dados) do
    [<<byte_size(dados)::32>>, tipo, dados, <<:erlang.crc32([tipo, dados])::32>>]
  end
end

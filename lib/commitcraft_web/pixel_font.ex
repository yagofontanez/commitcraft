defmodule CommitCraftWeb.PixelFont do
  @moduledoc """
  Uma fonte de 5x7, desenhada como grade de texto.

  Existe porque a imagem de compartilhamento é gerada sem nenhuma biblioteca, e
  desenhar texto exige ter as letras. Segue a mesma regra dos sprites: a arte
  mora legível no código, não num binário.

  Só maiúsculas, dígitos e alguns símbolos. Acento é transliterado — "Ração"
  vira "RACAO" na imagem. É uma perda real, e a alternativa seria desenhar à mão
  cada letra acentuada do português para um card que a pessoa olha por dois
  segundos.
  """

  @largura 5
  @altura 7

  glifos = %{
    "A" => ~w(.###. #...# #...# ##### #...# #...# #...#),
    "B" => ~w(####. #...# #...# ####. #...# #...# ####.),
    "C" => ~w(.#### #.... #.... #.... #.... #.... .####),
    "D" => ~w(####. #...# #...# #...# #...# #...# ####.),
    "E" => ~w(##### #.... #.... ####. #.... #.... #####),
    "F" => ~w(##### #.... #.... ####. #.... #.... #....),
    "G" => ~w(.#### #.... #.... #.### #...# #...# .###.),
    "H" => ~w(#...# #...# #...# ##### #...# #...# #...#),
    "I" => ~w(##### ..#.. ..#.. ..#.. ..#.. ..#.. #####),
    "J" => ~w(....# ....# ....# ....# #...# #...# .###.),
    "K" => ~w(#...# #..#. #.#.. ##... #.#.. #..#. #...#),
    "L" => ~w(#.... #.... #.... #.... #.... #.... #####),
    "M" => ~w(#...# ##.## #.#.# #...# #...# #...# #...#),
    "N" => ~w(#...# ##..# #.#.# #..## #...# #...# #...#),
    "O" => ~w(.###. #...# #...# #...# #...# #...# .###.),
    "P" => ~w(####. #...# #...# ####. #.... #.... #....),
    "Q" => ~w(.###. #...# #...# #...# #.#.# #..#. .##.#),
    "R" => ~w(####. #...# #...# ####. #.#.. #..#. #...#),
    "S" => ~w(.#### #.... #.... .###. ....# ....# ####.),
    "T" => ~w(##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..),
    "U" => ~w(#...# #...# #...# #...# #...# #...# .###.),
    "V" => ~w(#...# #...# #...# #...# #...# .#.#. ..#..),
    "W" => ~w(#...# #...# #...# #...# #.#.# ##.## #...#),
    "X" => ~w(#...# #...# .#.#. ..#.. .#.#. #...# #...#),
    "Y" => ~w(#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..),
    "Z" => ~w(##### ....# ...#. ..#.. .#... #.... #####),
    "0" => ~w(.###. #...# #..## #.#.# ##..# #...# .###.),
    "1" => ~w(..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.),
    "2" => ~w(.###. #...# ....# ...#. ..#.. .#... #####),
    "3" => ~w(####. ....# ....# .###. ....# ....# ####.),
    "4" => ~w(#..#. #..#. #..#. ##### ...#. ...#. ...#.),
    "5" => ~w(##### #.... ####. ....# ....# #...# .###.),
    "6" => ~w(.###. #.... #.... ####. #...# #...# .###.),
    "7" => ~w(##### ....# ...#. ..#.. .#... .#... .#...),
    "8" => ~w(.###. #...# #...# .###. #...# #...# .###.),
    "9" => ~w(.###. #...# #...# .#### ....# ....# .###.),
    "&" => ~w(.##.. #..#. #..#. .##.. #..#. #...# .###.),
    "." => ~w(..... ..... ..... ..... ..... .##.. .##..),
    "," => ~w(..... ..... ..... ..... .##.. .##.. .#...),
    "-" => ~w(..... ..... ..... ##### ..... ..... .....),
    "+" => ~w(..... ..#.. ..#.. ##### ..#.. ..#.. .....),
    "/" => ~w(....# ....# ...#. ..#.. .#... #.... #....),
    ":" => ~w(..... ..#.. ..#.. ..... ..#.. ..#.. .....),
    "!" => ~w(..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..),
    "?" => ~w(.###. #...# ....# ..##. ..#.. ..... ..#..),
    "'" => ~w(..#.. ..#.. ..... ..... ..... ..... .....),
    "(" => ~w(...#. ..#.. .#... .#... .#... ..#.. ...#.),
    ")" => ~w(.#... ..#.. ...#. ...#. ...#. ..#.. .#...),
    "·" => ~w(..... ..... ..... ..##. ..##. ..... .....),
    " " => ~w(..... ..... ..... ..... ..... ..... .....)
  }

  @glifos glifos
  @desconhecido ~w(##### #...# #...# #...# #...# #...# #####)

  @doc "A largura e a altura de um caractere, em pixels."
  def largura, do: @largura
  def altura, do: @altura

  @doc """
  Quanto espaço um texto ocupa, contando um pixel de respiro entre letras.

      iex> CommitCraftWeb.PixelFont.medir("AB")
      11
  """
  def medir(texto) do
    caracteres = texto |> normalizar() |> String.length()

    max(caracteres * (@largura + 1) - 1, 0)
  end

  @doc """
  As posições acesas de um texto, relativas a `{0, 0}`.

  Devolve uma lista de `{x, y}` — quem desenha decide a cor.
  """
  def pixels(texto) do
    texto
    |> normalizar()
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.flat_map(fn {char, indice} ->
      deslocamento = indice * (@largura + 1)

      @glifos
      |> Map.get(char, @desconhecido)
      |> Enum.with_index()
      |> Enum.flat_map(fn {linha, y} ->
        linha
        |> String.graphemes()
        |> Enum.with_index()
        |> Enum.filter(fn {pixel, _x} -> pixel == "#" end)
        |> Enum.map(fn {_pixel, x} -> {x + deslocamento, y} end)
      end)
    end)
  end

  @doc """
  Prepara um texto para a fonte: maiúsculas e sem acento.

      iex> CommitCraftWeb.PixelFont.normalizar("Ração & Cia")
      "RACAO & CIA"
  """
  def normalizar(texto) do
    texto
    |> to_string()
    # NFD separa o acento da letra; o filtro seguinte descarta só o acento.
    |> :unicode.characters_to_nfd_binary()
    |> String.upcase()
    |> String.replace(~r/[^A-Z0-9 &.,\-+\/:!?'()·]/u, "")
  end
end

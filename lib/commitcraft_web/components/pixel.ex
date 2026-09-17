defmodule CommitCraftWeb.Pixel do
  @moduledoc """
  Sprites desenhados como grades de texto.

  Cada sprite é uma lista de strings — uma linha por linha de pixels, um caractere
  por pixel — traduzida para `<rect>` de 1x1 num SVG. Isso mantém a arte editável
  no próprio editor (dá para "ver" o sprite lendo o código), nítida em qualquer
  escala, e sem nenhum binário no repositório.

      iex> CommitCraftWeb.Pixel.sprite_rows(:coin) |> length()
      12
  """
  use Phoenix.Component

  @ink "#0d0a1a"
  @bone "#f2e9dc"
  @gold "#ffc24b"
  @gold_deep "#c8871f"
  @violet "#7c6be8"
  @violet_deep "#5b4cb8"
  @skin "#f2c79a"
  @leather "#6b4a2f"
  @wood "#8a5a38"
  @steel "#c9d4e8"
  @muted "#a396c7"

  @palette %{
    "k" => @ink,
    "c" => @violet,
    "d" => @violet_deep,
    "s" => @skin,
    "e" => @ink,
    "b" => @leather,
    "w" => @wood,
    "m" => @steel,
    "g" => @gold,
    "o" => @gold_deep,
    "n" => @bone,
    "l" => @muted
  }

  # O artesão encapuzado, quadro A: pernas abertas.
  #
  # Ele andou com um martelo no ombro por uma versão. O martelo lia como placa
  # de rua, não como ferramenta — a silhueta limpa conta melhor a viagem.
  @crafter_a [
    "................",
    "....kkkkkk......",
    "...kcccccck.....",
    "...kcccccck.....",
    "...kccsssck.....",
    "...kcsssesk.....",
    "...kccsssck.....",
    "...kcccccck.....",
    "..kcccccccck....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "...kccccccdk....",
    "...kbbkkbbk.....",
    "...kbbkkbbk....."
  ]

  # Quadro B: pernas juntas. Alternar os dois é o ciclo de caminhada inteiro.
  @crafter_b [
    "................",
    "....kkkkkk......",
    "...kcccccck.....",
    "...kcccccck.....",
    "...kccsssck.....",
    "...kcsssesk.....",
    "...kccsssck.....",
    "...kcccccck.....",
    "..kcccccccck....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "..kcccccccdk....",
    "...kccccccdk....",
    "....kbbbbk......",
    "....kbbbbk......"
  ]

  # Moeda com furo quadrado — dinheiro que também parece um bloco.
  @coin [
    "....kkkk....",
    "..kkggggkk..",
    ".kgggggggok.",
    "kgggggggggok",
    "kggkkkkkkook",
    "kggkggggkook",
    "kggkggggkook",
    "kggkkkkkkook",
    "kgggggggoook",
    ".kgoooooook.",
    "..kkooookk..",
    "....kkkk...."
  ]

  # Um grafo de branch: linha principal, um desvio, um nó em cada uma.
  @commits [
    "...ll.......",
    "..nnnn......",
    "..nnnn......",
    "...ll.......",
    "...llllll...",
    "...ll...ll..",
    "...ll...ll..",
    "..nnnn.nnnn.",
    "..nnnn.nnnn.",
    "...ll...ll..",
    "...ll.......",
    "............"
  ]

  # Triângulo: a marca do deploy.
  @triangle [
    ".....kk.....",
    ".....nn.....",
    "....nnnn....",
    "....nnnn....",
    "...nnnnnn...",
    "...nnnnnn...",
    "..nnnnnnnn..",
    "..nnnnnnnn..",
    ".nnnnnnnnnn.",
    ".nnnnnnnnnn.",
    "nnnnnnnnnnnn",
    "kkkkkkkkkkkk"
  ]

  # Cartão com chip: a venda.
  @card [
    "............",
    ".kkkkkkkkkk.",
    ".knnnnnnnnk.",
    ".kkkkkkkkkk.",
    ".knnnnnnnnk.",
    ".knnnnnnnnk.",
    ".knnkknnnnk.",
    ".knnkknnnnk.",
    ".knnnnnnnnk.",
    ".kkkkkkkkkk.",
    "............",
    "............"
  ]

  @sprites %{
    crafter_a: @crafter_a,
    crafter_b: @crafter_b,
    coin: @coin,
    commits: @commits,
    triangle: @triangle,
    card: @card
  }

  @doc "As linhas cruas de um sprite, úteis para testes."
  def sprite_rows(name), do: Map.fetch!(@sprites, name)

  @doc """
  Desenha um sprite nomeado.

  A cor pode ser trocada por caractere com `recolor`, para reaproveitar a mesma
  grade em estados diferentes (um ícone apagado, por exemplo).
  """
  attr :name, :atom, required: true
  attr :class, :string, default: nil
  attr :recolor, :map, default: %{}
  attr :rest, :global

  def sprite(assigns) do
    rows = Map.fetch!(@sprites, assigns.name)
    palette = Map.merge(@palette, assigns.recolor)

    assigns =
      assign(assigns,
        width: rows |> List.first() |> String.length(),
        height: length(rows),
        cells: cells(rows, palette)
      )

    ~H"""
    <svg
      viewBox={"0 0 #{@width} #{@height}"}
      class={@class}
      aria-hidden="true"
      focusable="false"
      {@rest}
    >
      <rect :for={{x, y, fill} <- @cells} x={x} y={y} width="1" height="1" fill={fill} />
    </svg>
    """
  end

  @doc """
  O artesão andando: os dois quadros empilhados, alternados por CSS.
  """
  attr :class, :string, default: nil

  def crafter(assigns) do
    ~H"""
    <div class={["relative walker", @class]}>
      <.sprite name={:crafter_a} class="absolute inset-0 w-full h-full flick-a" />
      <.sprite
        name={:crafter_b}
        class="absolute inset-0 w-full h-full flick-b"
      />
    </div>
    """
  end

  # Só os pixels pintados viram <rect>; `Map.get/2` devolve nil para "." e a
  # própria comprehension descarta, porque nil não passa no filtro.
  defp cells(rows, palette) do
    for {row, y} <- Enum.with_index(rows),
        {char, x} <- row |> String.graphemes() |> Enum.with_index(),
        fill = Map.get(palette, char),
        do: {x, y, fill}
  end
end

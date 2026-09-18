defmodule CommitCraftWeb.Card do
  @moduledoc """
  A imagem que aparece quando alguém cola o link do projeto.

  Desenhada numa grade de 200x105 e ampliada seis vezes na codificação, dando os
  1200x630 que as redes esperam. Trabalhar pequeno é o que mantém o traço
  quadrado e o código legível: cada posição aqui é um pixel de arte, não uma
  coordenada em tela.
  """
  alias CommitCraftWeb.PixelFont
  alias CommitCraftWeb.Pixel
  alias CommitCraftWeb.Png

  @largura 200
  @altura 105
  @escala 6

  @fundo {0x15, 0x10, 0x2A}
  @painel {0x24, 0x1B, 0x3D}
  @borda {0x3D, 0x31, 0x60}
  @osso {0xF2, 0xE9, 0xDC}
  @apagado {0xA3, 0x96, 0xC7}
  @ouro {0xFF, 0xC2, 0x4B}
  @ouro_escuro {0xC8, 0x87, 0x1F}
  @musgo {0x6F, 0xBF, 0x73}

  @doc """
  Monta o PNG de um projeto.

  Recebe o que a tela já sabe: nome, dono, progresso e classe.
  """
  def render(opts) do
    nome = Keyword.fetch!(opts, :name)
    dono = Keyword.fetch!(opts, :login)
    progress = Keyword.fetch!(opts, :progress)
    classe = Keyword.get(opts, :class)

    %{}
    |> moldura()
    |> marca()
    |> nivel(progress)
    |> titulo(nome)
    |> autor(dono)
    |> barra(progress)
    |> rodape(progress, classe)
    |> materializar()
    |> Png.encode(@escala)
  end

  # ── peças ───────────────────────────────────────────────────────────
  #
  # O nível fica no alto, alinhado com a marca, e não ao lado do nome: dividir
  # a linha entre os dois espremia o nome do projeto, que é justamente o que a
  # pessoa quer mostrar.

  @margem 12

  defp moldura(tela) do
    tela
    |> retangulo(0, 0, @largura, @altura, @borda)
    |> retangulo(2, 2, @largura - 4, @altura - 4, @fundo)
  end

  defp marca(tela) do
    tela
    |> sprite(:coin, @margem, 10, 2)
    |> texto("COMMITCRAFT", @margem + 30, 18, @apagado)
  end

  defp nivel(tela, progress) do
    rotulo = "LV " <> String.pad_leading(Integer.to_string(progress.level), 2, "0")
    largura = PixelFont.medir(rotulo) * 2

    texto(tela, rotulo, @largura - @margem - largura, 14, @ouro, 2)
  end

  defp titulo(tela, nome) do
    # A linha inteira é do nome. O que não couber vira reticência, em vez de
    # vazar para fora da moldura.
    texto(tela, caber(nome, @largura - @margem * 2, 2), @margem, 44, @osso, 2)
  end

  defp autor(tela, dono) do
    texto(tela, caber("POR " <> dono, @largura - @margem * 2, 1), @margem, 64, @apagado)
  end

  defp barra(tela, progress) do
    y = 78
    largura = @largura - @margem * 2
    cheio = round(largura * progress.ratio)

    tela
    |> retangulo(@margem, y, largura, 9, @painel)
    |> retangulo(@margem, y, cheio, 9, @ouro)
    |> retangulo(@margem, y + 7, cheio, 2, @ouro_escuro)
    |> contorno(@margem, y, largura, 9, @borda)
  end

  defp rodape(tela, progress, classe) do
    esquerda = "#{numero(progress.into_level)} / #{numero(progress.to_advance)} XP"
    tela = texto(tela, esquerda, @margem, 94, @apagado)

    case classe do
      nil ->
        tela

      %{name: nome} ->
        nome = PixelFont.normalizar(nome)
        texto(tela, nome, @largura - @margem - PixelFont.medir(nome), 94, @musgo)
    end
  end

  # ── desenho ─────────────────────────────────────────────────────────

  defp retangulo(tela, x0, y0, largura, altura, cor) do
    for x <- x0..(x0 + largura - 1)//1,
        y <- y0..(y0 + altura - 1)//1,
        dentro?(x, y),
        into: tela,
        do: {{x, y}, cor}
  end

  defp contorno(tela, x0, y0, largura, altura, cor) do
    horizontais = for x <- x0..(x0 + largura - 1)//1, y <- [y0, y0 + altura - 1], do: {x, y}
    verticais = for y <- y0..(y0 + altura - 1)//1, x <- [x0, x0 + largura - 1], do: {x, y}

    for {x, y} <- horizontais ++ verticais, dentro?(x, y), into: tela, do: {{x, y}, cor}
  end

  defp texto(tela, conteudo, x0, y0, cor, escala \\ 1) do
    for {x, y} <- PixelFont.pixels(conteudo),
        dx <- 0..(escala - 1)//1,
        dy <- 0..(escala - 1)//1,
        px = x0 + x * escala + dx,
        py = y0 + y * escala + dy,
        dentro?(px, py),
        into: tela,
        do: {{px, py}, cor}
  end

  defp sprite(tela, nome, x0, y0, escala) do
    for {x, y, cor} <- Pixel.cells_of(nome),
        dx <- 0..(escala - 1)//1,
        dy <- 0..(escala - 1)//1,
        px = x0 + x * escala + dx,
        py = y0 + y * escala + dy,
        dentro?(px, py),
        into: tela,
        do: {{px, py}, hex(cor)}
  end

  defp materializar(tela) do
    for y <- 0..(@altura - 1) do
      for x <- 0..(@largura - 1), do: Map.get(tela, {x, y}, @fundo)
    end
  end

  defp dentro?(x, y), do: x >= 0 and y >= 0 and x < @largura and y < @altura

  defp hex("#" <> <<r::binary-size(2), g::binary-size(2), b::binary-size(2)>>) do
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  # Corta pela largura em pixels, não por contagem de caracteres: o que importa
  # é o que cabe na moldura, e isso depende da escala.
  defp caber(texto, largura_disponivel, escala) do
    limpo = PixelFont.normalizar(texto)

    if PixelFont.medir(limpo) * escala <= largura_disponivel do
      limpo
    else
      cabem =
        limpo
        |> String.length()
        |> Range.new(1, -1)
        |> Enum.find(1, fn n ->
          PixelFont.medir(String.slice(limpo, 0, n) <> ".") * escala <= largura_disponivel
        end)

      String.slice(limpo, 0, cabem) <> "."
    end
  end

  defp numero(valor), do: CommitCraftWeb.Game.numero(valor)
end

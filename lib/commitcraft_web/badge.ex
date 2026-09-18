defmodule CommitCraftWeb.Badge do
  @moduledoc """
  O selo que vai no README.

  É SVG montado como string, sem biblioteca: um selo é retângulo e texto, e
  arrastar um renderizador para isso seria desproporcional. A largura é
  calculada a partir do tamanho do texto, porque SVG não tem layout — se a
  conta estiver errada, a letra vaza para fora do fundo.

  O estilo é o do jogo, não o do shields.io: quem vê o selo já está vendo um
  pedaço do CommitCraft.
  """

  # Larguras médias por caractere, medidas para a fonte monoespaçada de
  # fallback. Não precisa ser exato — precisa não cortar.
  @largura_por_char 6.6
  @altura 20
  @padding 8

  @fundo "#15102a"
  @borda "#3d3160"
  @rotulo "#a396c7"
  @valor "#ffc24b"

  @doc """
  Monta o selo de um projeto.

  Recebe o rótulo (à esquerda, em cinza) e o valor (à direita, em dourado).
  """
  def render(rotulo, valor) do
    largura_rotulo = largura(rotulo)
    largura_valor = largura(valor)
    total = largura_rotulo + largura_valor

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{total}" height="#{@altura}" \
    viewBox="0 0 #{total} #{@altura}" role="img" aria-label="#{escapar(rotulo)}: #{escapar(valor)}">
      <title>#{escapar(rotulo)}: #{escapar(valor)}</title>
      <rect width="#{total}" height="#{@altura}" fill="#{@fundo}"/>
      <rect x="#{largura_rotulo}" width="#{largura_valor}" height="#{@altura}" fill="#241b3d"/>
      <rect width="#{total}" height="#{@altura}" fill="none" stroke="#{@borda}" stroke-width="2"/>
      <g font-family="ui-monospace,SFMono-Regular,Menlo,monospace" font-size="11">
        <text x="#{@padding}" y="14" fill="#{@rotulo}">#{escapar(rotulo)}</text>
        <text x="#{largura_rotulo + @padding}" y="14" fill="#{@valor}">#{escapar(valor)}</text>
      </g>
    </svg>
    """
  end

  defp largura(texto) do
    texto
    |> String.length()
    |> Kernel.*(@largura_por_char)
    |> Kernel.+(@padding * 2)
    |> ceil()
  end

  # Um selo carrega nome de projeto escrito por gente. Sem escapar, um nome com
  # `<` viraria marcação dentro do SVG.
  defp escapar(texto) do
    texto
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end

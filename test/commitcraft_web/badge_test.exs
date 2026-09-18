defmodule CommitCraftWeb.BadgeTest do
  use ExUnit.Case, async: true

  alias CommitCraftWeb.Badge

  test "monta um SVG válido" do
    svg = Badge.render("commitcraft", "LV 07")

    assert svg =~ ~s(<svg xmlns="http://www.w3.org/2000/svg")
    assert svg =~ "commitcraft"
    assert svg =~ "LV 07"
    assert svg =~ "</svg>"
  end

  test "a largura cresce com o texto" do
    curto = Badge.render("a", "b")
    longo = Badge.render("um nome de projeto bem comprido", "LV 42")

    assert largura(longo) > largura(curto)
  end

  test "escapa nome que quebraria a marcação" do
    # Nome de projeto é escrito por gente, e gente escreve `<`.
    svg = Badge.render(~s[<script>alert("oi")</script>], "LV 01")

    refute svg =~ "<script>"
    assert svg =~ "&lt;script&gt;"
    assert svg =~ "&quot;oi&quot;"
  end

  test "escapa o E comercial sem escapar duas vezes" do
    svg = Badge.render("Ração & Cia", "LV 03")

    assert svg =~ "Ração &amp; Cia"
    refute svg =~ "&amp;amp;"
  end

  test "descreve o selo para quem não enxerga a imagem" do
    svg = Badge.render("commitcraft", "LV 07")

    assert svg =~ ~s(role="img")
    assert svg =~ ~s(aria-label="commitcraft: LV 07")
    assert svg =~ "<title>commitcraft: LV 07</title>"
  end

  defp largura(svg) do
    [[_, largura]] = Regex.scan(~r/width="(\d+)"/, svg, capture: :all) |> Enum.take(1)
    String.to_integer(largura)
  end
end

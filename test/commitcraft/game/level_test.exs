defmodule CommitCraft.Game.LevelTest do
  use ExUnit.Case, async: true

  doctest CommitCraft.Game.Level

  alias CommitCraft.Game.Level

  describe "for_xp/1" do
    test "começa no nível 1" do
      assert Level.for_xp(0) == 1
      assert Level.for_xp(1) == 1
    end

    test "XP negativo não rebaixa ninguém abaixo do nível 1" do
      # A tabela de XP tem eventos negativos (build quebrado vale -30), então
      # um projeto novo pode, sim, ficar no vermelho por um instante.
      assert Level.for_xp(-30) == 1
      assert Level.for_xp(-100_000) == 1
    end

    test "sobe exatamente na fronteira, nunca um XP antes" do
      for level <- 2..40 do
        limite = Level.xp_to_reach(level)

        assert Level.for_xp(limite - 1) == level - 1,
               "um XP antes de #{limite} ainda deveria ser nível #{level - 1}"

        assert Level.for_xp(limite) == level,
               "#{limite} de XP deveria ser nível #{level}"
      end
    end

    test "aguenta números grandes sem escorregar no arredondamento" do
      # A inversão da curva passa por ponto flutuante; em XP alto é onde um
      # arredondamento mal corrigido apareceria.
      for level <- [100, 500, 1000, 5000] do
        assert Level.for_xp(Level.xp_to_reach(level)) == level
        assert Level.for_xp(Level.xp_to_reach(level) - 1) == level - 1
      end
    end

    test "nunca anda para trás quando o XP sobe" do
      niveis = Enum.map(0..20_000//137, &Level.for_xp/1)
      assert niveis == Enum.sort(niveis)
    end
  end

  describe "a curva" do
    test "xp_to_reach/1 é a soma de tudo que já foi preciso" do
      for level <- 1..40 do
        somado = Enum.sum(Enum.map(1..level, &Level.xp_to_advance/1)) - Level.xp_to_advance(level)
        assert Level.xp_to_reach(level) == somado
      end
    end

    test "fica mais caro a cada nível" do
      custos = Enum.map(1..20, &Level.xp_to_advance/1)
      assert custos == Enum.sort(custos)
      assert Enum.uniq(custos) == custos
    end
  end

  describe "progress/1" do
    test "entrega o que a barra de XP precisa desenhar" do
      assert Level.progress(6940) == %{
               level: 7,
               xp: 6940,
               into_level: 1240,
               to_advance: 2000,
               ratio: 0.62
             }
    end

    test "a barra começa vazia em cada nível novo" do
      for level <- 1..20 do
        assert %{into_level: 0, ratio: +0.0} = Level.progress(Level.xp_to_reach(level))
      end
    end

    test "a barra nunca passa de cheia" do
      for xp <- 0..12_000//97 do
        %{ratio: ratio, into_level: into, to_advance: falta} = Level.progress(xp)

        assert ratio >= 0.0 and ratio <= 1.0, "ratio fora da faixa com #{xp} de XP"
        assert into < falta, "com #{xp} de XP a barra estaria cheia sem subir de nível"
      end
    end

    test "trata XP negativo como zero" do
      assert Level.progress(-50) == Level.progress(0)
    end
  end
end

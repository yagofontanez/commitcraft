defmodule CommitCraftWeb.WebhookSignatureTest do
  use ExUnit.Case, async: true

  alias CommitCraftWeb.WebhookSignature

  @segredo "segredo"
  @corpo ~s({"type":"algo","data":1})

  defp hex(algoritmo, dados),
    do: Base.encode16(:crypto.mac(:hmac, algoritmo, @segredo, dados), case: :lower)

  describe "GitHub" do
    test "aceita HMAC-SHA256 do corpo" do
      cabecalhos = [{"x-hub-signature-256", "sha256=" <> hex(:sha256, @corpo)}]

      assert WebhookSignature.verify("github", @corpo, @segredo, cabecalhos) == :ok
    end

    test "aceita em maiúsculas, que é hex igual" do
      assinatura = "sha256=" <> String.upcase(hex(:sha256, @corpo))

      assert WebhookSignature.verify("github", @corpo, @segredo, [
               {"x-hub-signature-256", assinatura}
             ]) == :ok
    end

    test "recusa SHA1 disfarçado de SHA256" do
      # Se alguém conseguisse fazer o servidor aceitar o algoritmo mais fraco,
      # bastaria quebrar SHA1 para forjar entregas.
      cabecalhos = [{"x-hub-signature-256", "sha256=" <> hex(:sha, @corpo)}]

      assert WebhookSignature.verify("github", @corpo, @segredo, cabecalhos) ==
               {:error, :assinatura}
    end

    test "recusa corpo diferente do assinado" do
      cabecalhos = [{"x-hub-signature-256", "sha256=" <> hex(:sha256, @corpo)}]

      assert WebhookSignature.verify("github", ~s({"outro":1}), @segredo, cabecalhos) ==
               {:error, :assinatura}
    end

    test "recusa quando o cabeçalho falta ou está malformado" do
      for cabecalhos <- [
            [],
            [{"x-hub-signature-256", ""}],
            [{"x-hub-signature-256", "abc"}],
            [{"x-hub-signature-256", "sha1=" <> hex(:sha, @corpo)}]
          ] do
        assert {:error, _motivo} = WebhookSignature.verify("github", @corpo, @segredo, cabecalhos)
      end
    end
  end

  describe "Vercel" do
    test "aceita HMAC-SHA1, que é o que a Vercel usa" do
      cabecalhos = [{"x-vercel-signature", hex(:sha, @corpo)}]

      assert WebhookSignature.verify("vercel", @corpo, @segredo, cabecalhos) == :ok
    end

    test "não aceita SHA256 no lugar" do
      # Implementar SHA256 aqui por analogia com o GitHub faria toda entrega
      # legítima da Vercel ser recusada.
      cabecalhos = [{"x-vercel-signature", hex(:sha256, @corpo)}]

      assert WebhookSignature.verify("vercel", @corpo, @segredo, cabecalhos) ==
               {:error, :assinatura}
    end

    test "recusa sem cabeçalho" do
      assert {:error, _motivo} = WebhookSignature.verify("vercel", @corpo, @segredo, [])
    end
  end

  describe "Stripe" do
    defp stripe_header(carimbo, corpo \\ @corpo, segredo \\ @segredo) do
      assinado = "#{carimbo}.#{corpo}"
      v1 = Base.encode16(:crypto.mac(:hmac, :sha256, segredo, assinado), case: :lower)
      "t=#{carimbo},v1=#{v1}"
    end

    test "aceita assinatura do par carimbo+corpo" do
      agora = 1_789_000_000
      cabecalhos = [{"stripe-signature", stripe_header(agora)}]

      assert WebhookSignature.verify("stripe", @corpo, @segredo, cabecalhos, agora) == :ok
    end

    test "recusa entrega velha demais" do
      # É o que impede alguém que capturou uma entrega legítima de reenviá-la
      # meses depois: a assinatura ainda bate, o carimbo não.
      agora = 1_789_000_000
      velha = agora - WebhookSignature.tolerancia_segundos() - 1
      cabecalhos = [{"stripe-signature", stripe_header(velha)}]

      assert WebhookSignature.verify("stripe", @corpo, @segredo, cabecalhos, agora) ==
               {:error, :carimbo_velho}
    end

    test "aceita dentro da tolerância, para os dois lados" do
      agora = 1_789_000_000
      margem = WebhookSignature.tolerancia_segundos()

      for carimbo <- [agora - margem, agora, agora + margem] do
        cabecalhos = [{"stripe-signature", stripe_header(carimbo)}]
        assert WebhookSignature.verify("stripe", @corpo, @segredo, cabecalhos, agora) == :ok
      end
    end

    test "o carimbo entra na conta, não é só enfeite" do
      # Trocar o carimbo mantendo a assinatura tem que falhar; se não falhar,
      # a proteção contra reenvio não existe de verdade.
      agora = 1_789_000_000
      "t=" <> resto = stripe_header(agora)
      [_carimbo, v1] = String.split(resto, ",")
      forjado = "t=#{agora + 1},#{v1}"

      assert WebhookSignature.verify(
               "stripe",
               @corpo,
               @segredo,
               [{"stripe-signature", forjado}],
               agora
             ) ==
               {:error, :assinatura}
    end

    test "aceita quando uma de várias assinaturas bate" do
      # Durante rotação de segredo a Stripe manda mais de uma v1.
      agora = 1_789_000_000
      certa = stripe_header(agora)
      "t=" <> resto = certa
      [_, v1_certa] = String.split(resto, ",")

      cabecalhos = [{"stripe-signature", "t=#{agora},v1=deadbeef,#{v1_certa}"}]

      assert WebhookSignature.verify("stripe", @corpo, @segredo, cabecalhos, agora) == :ok
    end

    test "recusa cabeçalho malformado" do
      agora = 1_789_000_000

      for valor <- ["", "abc", "t=abc,v1=xx", "v1=#{hex(:sha256, @corpo)}", "t=#{agora}"] do
        assert {:error, _motivo} =
                 WebhookSignature.verify(
                   "stripe",
                   @corpo,
                   @segredo,
                   [{"stripe-signature", valor}],
                   agora
                 )
      end
    end
  end
end

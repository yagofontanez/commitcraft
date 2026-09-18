defmodule CommitCraftWeb.WebhookSignature do
  @moduledoc """
  Confere que uma entrega veio mesmo de quem diz ter vindo.

  Cada serviço assina de um jeito, e as diferenças não são detalhe:

    * **GitHub** — `X-Hub-Signature-256: sha256=<hex>`, HMAC-SHA256 do corpo cru.
    * **Vercel** — `x-vercel-signature: <hex>`, HMAC-**SHA1** do corpo cru. Sim,
      SHA1; é o que a Vercel usa, e implementar SHA256 aqui faria toda entrega
      ser recusada. No OTP o átomo é `:sha` — `:sha1` não existe e derruba a
      requisição inteira.
    * **Stripe** — `Stripe-Signature: t=<epoch>,v1=<hex>`, HMAC-SHA256 de
      `"<t>.<corpo>"`. O carimbo entra na conta de propósito: é o que permite
      recusar uma entrega antiga capturada e reenviada por outra pessoa.

  Todas as comparações são em tempo constante. `==` em binário para cedo no
  primeiro byte diferente, e esse tempo conta quantos bytes iniciais o atacante
  já acertou.
  """

  # Quanto tempo uma entrega da Stripe continua aceitável. Cinco minutos é o
  # que a própria Stripe recomenda: dá folga para relógio fora de hora sem
  # deixar uma captura antiga valer para sempre.
  @tolerancia_segundos 300

  @doc """
  Confere a assinatura de uma entrega.

  Devolve `:ok` ou `{:error, motivo}`.
  """
  def verify("github", corpo, segredo, cabecalhos) do
    with {:ok, "sha256=" <> recebida} <- cabecalho(cabecalhos, "x-hub-signature-256") do
      comparar(hmac(:sha256, segredo, corpo), recebida)
    else
      _outro -> {:error, :formato}
    end
  end

  def verify("vercel", corpo, segredo, cabecalhos) do
    with {:ok, recebida} <- cabecalho(cabecalhos, "x-vercel-signature") do
      comparar(hmac(:sha, segredo, corpo), recebida)
    else
      _outro -> {:error, :formato}
    end
  end

  def verify("stripe", corpo, segredo, cabecalhos, agora \\ nil) do
    agora = agora || System.system_time(:second)

    with {:ok, cabecalho} <- cabecalho(cabecalhos, "stripe-signature"),
         {:ok, carimbo, assinaturas} <- partes_da_stripe(cabecalho),
         :ok <- dentro_da_tolerancia(carimbo, agora) do
      esperada = hmac(:sha256, segredo, "#{carimbo}.#{corpo}")

      # A Stripe pode mandar várias assinaturas v1 durante uma rotação de
      # segredo; basta uma bater.
      if Enum.any?(assinaturas, &(comparar(esperada, &1) == :ok)),
        do: :ok,
        else: {:error, :assinatura}
    end
  end

  @doc "A tolerância de tempo usada nas entregas da Stripe, em segundos."
  def tolerancia_segundos, do: @tolerancia_segundos

  defp partes_da_stripe(cabecalho) do
    partes =
      cabecalho
      |> String.split(",")
      |> Enum.map(&String.split(String.trim(&1), "=", parts: 2))

    carimbo =
      Enum.find_value(partes, fn
        ["t", valor] -> Integer.parse(valor) |> elem_ou_nil()
        _outro -> nil
      end)

    assinaturas = for ["v1", valor] <- partes, do: valor

    if is_integer(carimbo) and assinaturas != [],
      do: {:ok, carimbo, assinaturas},
      else: {:error, :formato}
  end

  defp elem_ou_nil({numero, _resto}), do: numero
  defp elem_ou_nil(:error), do: nil

  defp dentro_da_tolerancia(carimbo, agora) do
    if abs(agora - carimbo) <= @tolerancia_segundos,
      do: :ok,
      else: {:error, :carimbo_velho}
  end

  defp hmac(algoritmo, segredo, dados) do
    :hmac
    |> :crypto.mac(algoritmo, segredo, dados)
    |> Base.encode16(case: :lower)
  end

  defp comparar(esperada, recebida) when is_binary(recebida) do
    if Plug.Crypto.secure_compare(esperada, String.downcase(recebida)),
      do: :ok,
      else: {:error, :assinatura}
  end

  defp comparar(_esperada, _recebida), do: {:error, :formato}

  defp cabecalho(cabecalhos, nome) do
    case Enum.find(cabecalhos, fn {chave, _valor} -> chave == nome end) do
      {_chave, valor} when is_binary(valor) and valor != "" -> {:ok, valor}
      _ausente -> {:error, :sem_cabecalho}
    end
  end
end

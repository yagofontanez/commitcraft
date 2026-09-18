defmodule CommitCraft.EncryptedBinary do
  @moduledoc """
  Um campo Ecto que guarda texto cifrado no banco.

  Usado para o token do GitHub. Hoje o token de login carrega só `read:user`,
  mas quando o usuário conectar um repositório ele vai carregar `repo` — e aí um
  dump do banco vazado daria acesso de escrita aos repositórios de todo mundo.
  Mais barato nascer cifrado do que migrar depois.

  A chave é derivada do `secret_key_base` do endpoint. Trocar esse segredo torna
  os tokens existentes ilegíveis; isso é tratado como "precisa entrar de novo",
  não como erro — ver `load/1`.
  """
  use Ecto.Type

  require Logger

  @impl true
  def type, do: :binary

  @impl true
  def cast(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    {:ok, Plug.Crypto.MessageEncryptor.encrypt(value, secret(), sign_secret())}
  end

  def dump(_value), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case Plug.Crypto.MessageEncryptor.decrypt(value, secret(), sign_secret()) do
      {:ok, plain} ->
        {:ok, plain}

      :error ->
        # Acontece quando o secret_key_base muda. Devolver nil faz o resto do
        # sistema tratar como "sem token", que leva a pessoa a autorizar de
        # novo — bem melhor do que derrubar a página com 500.
        Logger.warning("não foi possível decifrar um token guardado; será preciso reautorizar")
        {:ok, nil}
    end
  end

  # `embed_as` e `equal?` vêm do `use Ecto.Type` com o comportamento padrão.

  defp secret, do: derive("commitcraft encrypted field")
  defp sign_secret, do: derive("commitcraft encrypted field signature")

  defp derive(salt) do
    :commitcraft
    |> Application.fetch_env!(CommitCraftWeb.Endpoint)
    |> Keyword.fetch!(:secret_key_base)
    |> Plug.Crypto.KeyGenerator.generate(salt, length: 32)
  end
end

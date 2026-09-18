defmodule Mix.Tasks.Commitcraft.DevSecrets do
  @shortdoc "Cria config/dev.secret.exs para as credenciais locais"

  @moduledoc """
  Cria o arquivo de credenciais de desenvolvimento, se ele ainda não existir.

  O arquivo é ignorado pelo git e carregado automaticamente por `config/dev.exs`.
  Assim ninguém precisa lembrar de exportar variáveis no terminal certo — que é
  o jeito mais fácil de passar meia hora sem entender por que o login diz que
  "não está configurado".

      mix commitcraft.dev_secrets
  """
  use Mix.Task

  @destino "config/dev.secret.exs"

  @modelo """
  import Config

  # Credenciais do seu OAuth App do GitHub, criado em
  # https://github.com/settings/developers com a callback URL
  # http://localhost:4000/auth/github/callback
  #
  # Este arquivo é ignorado pelo git. Não versione, não cole em issue.
  config :commitcraft, CommitCraft.GitHub.OAuth,
    client_id: "COLE_AQUI_O_CLIENT_ID",
    client_secret: "COLE_AQUI_O_CLIENT_SECRET"
  """

  @impl Mix.Task
  def run(_args) do
    if File.exists?(@destino) do
      Mix.shell().info([:yellow, "#{@destino} já existe — nada a fazer."])
    else
      File.write!(@destino, @modelo)

      Mix.shell().info([
        :green,
        "criado #{@destino}\n",
        :reset,
        "Preencha o client_id e o client_secret, depois rode `mix phx.server`."
      ])
    end
  end
end

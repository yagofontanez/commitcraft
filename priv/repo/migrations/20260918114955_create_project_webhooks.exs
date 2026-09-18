defmodule CommitCraft.Repo.Migrations.CreateProjectWebhooks do
  use Ecto.Migration

  import Ecto.Query

  @moduledoc """
  Tira os campos de webhook de dentro de `projects`.

  Com uma fonte só (GitHub) quatro colunas soltas resolviam. Com três — GitHub,
  Vercel e Stripe — viraria doze, e cada fonte nova custaria outra migração na
  tabela principal.
  """

  def up do
    create table(:project_webhooks) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false

      add :source, :string, null: false
      # Vai na URL e serve só para achar o projeto. Quem autentica a entrega é
      # a assinatura.
      add :token, :string, null: false
      # Cifrado pela aplicação — ver CommitCraft.EncryptedBinary.
      add :secret, :binary
      # O identificador do hook no serviço, quando fomos nós que o criamos.
      add :external_id, :string
      add :installed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_webhooks, [:token])
    create unique_index(:project_webhooks, [:project_id, :source])

    flush()

    mover_webhooks_existentes()

    alter table(:projects) do
      remove :webhook_id
      remove :webhook_token
      remove :webhook_secret
      remove :webhook_installed_at
    end
  end

  def down do
    alter table(:projects) do
      add :webhook_id, :bigint
      add :webhook_token, :string
      add :webhook_secret, :binary
      add :webhook_installed_at, :utc_datetime
    end

    drop table(:project_webhooks)
  end

  # Os webhooks do GitHub já instalados continuam valendo: o segredo é o mesmo
  # que o GitHub usa para assinar, e perdê-lo obrigaria a reinstalar tudo.
  defp mover_webhooks_existentes do
    agora = DateTime.utc_now() |> DateTime.truncate(:second)

    linhas =
      repo().all(
        from(p in "projects",
          where: not is_nil(p.webhook_token),
          select: %{
            id: p.id,
            webhook_id: p.webhook_id,
            token: p.webhook_token,
            secret: p.webhook_secret,
            installed_at: p.webhook_installed_at
          }
        )
      )

    for linha <- linhas do
      repo().insert_all("project_webhooks", [
        %{
          project_id: linha.id,
          source: "github",
          token: linha.token,
          secret: linha.secret,
          external_id: linha.webhook_id && Integer.to_string(linha.webhook_id),
          installed_at: linha.installed_at || agora,
          inserted_at: agora,
          updated_at: agora
        }
      ])
    end
  end
end

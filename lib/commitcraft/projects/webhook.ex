defmodule CommitCraft.Projects.Webhook do
  @moduledoc """
  O canal por onde um serviço externo conta o que aconteceu num projeto.

  Um por fonte, por projeto. O `token` vai na URL e só serve para achar o
  projeto; quem prova que a entrega é legítima é a assinatura feita com o
  `secret`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias CommitCraft.Projects.Project

  @sources ~w(github vercel stripe)

  schema "project_webhooks" do
    field :source, :string
    field :token, :string
    field :secret, CommitCraft.EncryptedBinary, redact: true
    field :external_id, :string
    field :installed_at, :utc_datetime

    belongs_to :project, Project

    timestamps(type: :utc_datetime)
  end

  @doc "As fontes que o jogo entende."
  def sources, do: @sources

  @doc false
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:source, :token, :secret, :external_id, :installed_at])
    |> validate_required([:source, :token, :installed_at])
    |> validate_inclusion(:source, @sources)
    |> unique_constraint(:token)
    |> unique_constraint([:project_id, :source],
      name: :project_webhooks_project_id_source_index
    )
  end
end

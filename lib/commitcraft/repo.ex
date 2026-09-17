defmodule CommitCraft.Repo do
  use Ecto.Repo,
    otp_app: :commitcraft,
    adapter: Ecto.Adapters.Postgres
end

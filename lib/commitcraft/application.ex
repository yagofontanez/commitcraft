defmodule CommitCraft.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CommitCraftWeb.Telemetry,
      CommitCraft.Repo,
      {DNSCluster, query: Application.get_env(:commitcraft, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CommitCraft.PubSub},
      # Start a worker by calling: CommitCraft.Worker.start_link(arg)
      # {CommitCraft.Worker, arg},
      # Start to serve requests, typically the last entry
      CommitCraftWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CommitCraft.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CommitCraftWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

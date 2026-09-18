defmodule CommitCraftWeb.Router do
  use CommitCraftWeb, :router

  import CommitCraftWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CommitCraftWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # O GitHub não tem sessão nem token de CSRF; quem autentica a entrega é a
  # assinatura HMAC conferida no controller.
  pipeline :webhook do
    plug :accepts, ["json"]
  end

  scope "/webhooks", CommitCraftWeb do
    pipe_through :webhook

    post "/:source/:token", WebhookController, :receive
  end

  scope "/", CommitCraftWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/auth/github", AuthController, :request
    get "/auth/github/callback", AuthController, :callback
    delete "/auth/sair", AuthController, :delete
  end

  scope "/", CommitCraftWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/auth/github/ampliar", AuthController, :upgrade

    get "/ranking", RankingController, :index

    get "/jogar", ProjectController, :index
    post "/jogar", ProjectController, :create
    get "/jogar/:slug/repositorio", ProjectController, :choose_repo
    post "/jogar/:slug/repositorio", ProjectController, :connect_repo
    post "/jogar/:slug/webhook", ProjectController, :install_webhook

    # A tela do projeto é ao vivo: é nela que a barra sobe sozinha quando um
    # commit chega. As rotas acima seguem sendo HTTP porque falam com o GitHub
    # e terminam em redirecionamento.
    live_session :autenticado,
      on_mount: [{CommitCraftWeb.UserAuth, :require_authenticated}] do
      live "/jogar/:slug", ProjectLive.Show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", CommitCraftWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:commitcraft, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CommitCraftWeb.Telemetry
    end
  end
end

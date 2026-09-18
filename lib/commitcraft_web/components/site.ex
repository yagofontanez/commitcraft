defmodule CommitCraftWeb.Site do
  @moduledoc """
  A moldura do site: o cabeçalho e o rodapé que toda página usa.
  """
  use Phoenix.Component
  use CommitCraftWeb, :verified_routes

  import CommitCraftWeb.Pixel

  @doc """
  O cabeçalho.

  Os links de seção só fazem sentido na tela de título, então vêm por slot em vez
  de estarem embutidos aqui.
  """
  attr :current_user, :any, default: nil
  attr :width, :string, default: "contained", values: ~w(contained full)
  slot :nav

  def site_header(assigns) do
    ~H"""
    <header class="relative z-30 border-b-[3px] border-stone/60 bg-void/80 backdrop-blur-sm">
      <div class={[
        "flex items-center justify-between gap-4 px-4 py-4 sm:gap-6 sm:px-6",
        @width == "contained" && "mx-auto max-w-6xl",
        @width == "full" && "md:px-10"
      ]}>
        <a href={~p"/"} class="flex min-w-0 items-center gap-3">
          <.sprite name={:coin} class="h-6 w-6 shrink-0 coin-spin sm:h-7 sm:w-7" />
          <span class="truncate font-pixel text-sm text-bone sm:text-base md:text-lg">
            CommitCraft
          </span>
        </a>

        <nav :if={@nav != []} class="hidden items-center gap-8 text-sm text-muted md:flex">
          {render_slot(@nav)}
        </nav>

        <div :if={@current_user} class="flex shrink-0 items-center gap-5">
          <.link
            navigate={~p"/ranking"}
            class="hidden text-sm text-muted transition-colors hover:text-bone sm:inline"
          >
            Ranking
          </.link>

          <a href={~p"/jogar"} class="flex items-center gap-2.5">
            <img
              :if={@current_user.avatar_url}
              src={@current_user.avatar_url}
              alt=""
              width="28"
              height="28"
              class="h-7 w-7 shrink-0 border-2 border-stone"
            />
            <span class="hidden font-pixel text-[11px] text-bone sm:inline">
              {@current_user.github_login}
            </span>
          </a>
          <.link href={~p"/auth/sair"} method="delete" class="text-sm text-muted hover:text-bone">
            Sair
          </.link>
        </div>

        <a
          :if={is_nil(@current_user)}
          href={~p"/auth/github"}
          class="btn-craft shrink-0 !px-4 !py-3 text-[10px] sm:!px-5 sm:!py-3.5 sm:text-[11px]"
        >
          <.sprite name={:commits} class="h-4 w-4" recolor={%{"n" => "#0d0a1a", "l" => "#0d0a1a"}} />
          Entrar com GitHub
        </a>
      </div>
    </header>
    """
  end

  @doc "O rodapé."
  attr :width, :string, default: "contained", values: ~w(contained full)

  def site_footer(assigns) do
    ~H"""
    <footer class="border-t-[3px] border-stone/50 py-12">
      <div class={[
        "flex flex-col items-center justify-between gap-5 px-6 text-sm text-muted sm:flex-row",
        @width == "contained" && "mx-auto max-w-6xl",
        @width == "full" && "md:px-10"
      ]}>
        <div class="flex items-center gap-3">
          <.sprite name={:coin} class="h-5 w-5" />
          <span class="font-pixel text-xs text-bone">CommitCraft</span>
        </div>
        <p>Feito por diversão, em Elixir e Phoenix.</p>
      </div>
    </footer>
    """
  end

  @doc """
  As mensagens do sistema.

  Ficam aqui, e não no layout raiz, porque o layout raiz é compartilhado com o
  LiveView, que tem o próprio ciclo de flash.
  """
  attr :flash, :map, required: true

  def flashes(assigns) do
    ~H"""
    <%!-- Abaixo do cabeçalho, senão a mensagem cobre os links do menu. --%>
    <div class="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-24 pb-6">
      <p
        :for={{tipo, mensagem} <- visible(@flash)}
        role="alert"
        data-flash
        title="clique para fechar"
        class={[
          "frame pointer-events-auto max-w-md cursor-pointer px-6 py-4 text-sm",
          tipo == "error" && "text-ember",
          tipo == "info" && "text-moss"
        ]}
      >
        {mensagem}
      </p>
    </div>
    """
  end

  defp visible(flash) do
    for tipo <- ~w(info error), mensagem = Phoenix.Flash.get(flash, tipo), do: {tipo, mensagem}
  end
end

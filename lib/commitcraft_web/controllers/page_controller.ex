defmodule CommitCraftWeb.PageController do
  use CommitCraftWeb, :controller

  alias CommitCraft.Game.Achievements
  alias CommitCraft.Game.Level
  alias CommitCraft.Game.Rules

  # O chão do herói: a fita de commits por onde o artesão caminha. Os blocos
  # dourados e de musgo são os eventos raros — venda e deploy — para que a fita
  # já conte, sozinha, como o jogo pontua.
  @ground [
    %{hash: "a3f1c2", message: "feat: tela de projeto", xp: "+5", kind: :commit},
    %{hash: "7b9e04", message: "fix: webhook duplicado", xp: "+5", kind: :commit},
    %{hash: "c1d880", message: "test: cobre o cálculo de nível", xp: "+5", kind: :commit},
    %{hash: "deploy", message: "produção · v0.4.1", xp: "+25", kind: :deploy},
    %{hash: "e5a720", message: "refactor: extrai o motor de XP", xp: "+5", kind: :commit},
    %{hash: "2f66bd", message: "chore: sobe dependências", xp: "+2", kind: :commit},
    %{hash: "venda", message: "primeira venda · R$ 29", xp: "+250", kind: :gold},
    %{hash: "9c04ae", message: "docs: escreve o README", xp: "+5", kind: :commit},
    %{hash: "41b7f3", message: "feat: conquistas", xp: "+5", kind: :commit},
    %{hash: "deploy", message: "produção · v0.4.2", xp: "+25", kind: :deploy}
  ]

  # As integrações apresentadas como membros do grupo: cada uma entra para
  # cuidar de um tipo de evento, e é isso que a pessoa precisa entender.
  @party [
    %{
      sprite: :commits,
      name: "GitHub",
      role: "O Cronista",
      duty: "Anota cada commit, pull request e issue que você fecha.",
      feeds: "XP e sequência de dias",
      status: :ready
    },
    %{
      sprite: :triangle,
      name: "Vercel",
      role: "O Arauto",
      duty: "Avisa o grupo toda vez que alguma coisa vai pro mundo.",
      feeds: "Conquistas de envio",
      status: :ready
    },
    %{
      sprite: :card,
      name: "Stripe",
      role: "O Tesoureiro",
      duty: "Conta as moedas e avisa quando entra a primeira.",
      feeds: "Ouro e marcos de receita",
      status: :soon
    }
  ]

  # A tabela de pontos. Os números vêm de CommitCraft.Game.Rules, não escritos
  # à mão: a promessa da página e o motor do jogo não podem divergir.
  @xp_table [
    {:commit, "Commit na branch principal", "GitHub", :plain},
    {:issue_closed, "Issue fechada", "GitHub", :plain},
    {:sale, "Venda", "Stripe", :plain},
    {:deploy, "Deploy em produção", "Vercel", :good},
    {:pull_request_merged, "Pull request aprovado e mesclado", "GitHub", :good},
    {:streak_week, "Sete dias seguidos com commit", "CommitCraft", :good},
    {:first_user, "Primeiro usuário que não é você", "seu app", :great},
    {:first_sale, "Primeira venda", "Stripe", :great},
    {:broken_build, "Build quebrado em produção", "Vercel", :bad}
  ]

  defp xp_table do
    Enum.map(@xp_table, fn {chave, evento, fonte, tom} ->
      %{event: evento, source: fonte, xp: Rules.xp_for(chave), tone: tom}
    end)
  end

  # As conquistas vêm do catálogo do jogo. As duas últimas aparecem bloqueadas
  # só para a página mostrar como é ter uma medalha ainda por conquistar.
  @bloqueadas ~w(semana_cheia maratona)

  defp achievements do
    Enum.map(Achievements.catalog(), fn conquista ->
      Map.put(conquista, :unlocked, conquista.key not in @bloqueadas)
    end)
  end

  # O projeto de exemplo do topo da página. 6.940 de XP dá nível 7 com
  # 1.240 de 2.000 — os mesmos números que a página sempre mostrou, agora
  # vindos da curva.
  @demo_xp 6940

  @pitch "Cada commit vira XP. Cada deploy, uma conquista. Cada venda, ouro. O CommitCraft se liga no seu repositório e transforma meses de trabalho invisível numa barra que enche na sua frente."

  def home(conn, _params) do
    conn
    |> assign(:page_title, "CommitCraft — seu projeto, jogável")
    |> assign(:demo_progress, Level.progress(@demo_xp))
    |> assign(:pitch, @pitch)
    |> assign(:ground, @ground)
    |> assign(:party, @party)
    |> assign(:xp_table, xp_table())
    |> assign(:achievements, achievements())
    |> render(:home)
  end
end

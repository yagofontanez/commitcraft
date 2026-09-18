# CommitCraft

Um SaaS que transforma a construção de um projeto num jogo 2D. Commits viram XP,
deploys viram conquistas, vendas viram ouro — e o projeto ganha nível enquanto
você trabalha.

Sem assinatura e sem plano pago. Se o jogo for útil, dá para deixar uma moeda.

## Estado atual

Landing page e login com GitHub. O jogo em si ainda não existe: não há projeto,
integração com repositório nem motor de XP. Os números que aparecem na página
são ilustrativos e vivem em `lib/commitcraft_web/controllers/page_controller.ex`.

Depois de entrar, `/jogar` lista seus projetos. Dá para criar, renomear, apagar,
conectar três fontes de XP: **GitHub** (commit na branch principal, pull request
mesclado, issue fechada), **Vercel** (deploy em produção soma, build quebrado
custa) e **Stripe** (a primeira venda vale muito, as seguintes viram rotina).

Existem também **sequência de dias** (cada sete dias seguidos com commit rendem
XP) e **conquistas** — medalhas por *como* você trabalhou, não por quanto.

## Login

A única porta de entrada é o OAuth do GitHub: sem senha, sem e-mail, sem mailer.
Quem usa o CommitCraft tem GitHub por definição, e o token que sai do login é o
mesmo que vai ler commits mais tarde.

Duas coisas que valem a atenção de quem mexer aqui:

- **O login pede só `read:user`.** O escopo `repo` só é pedido quando a pessoa
  clica para conectar um repositório — um segundo fluxo de OAuth, que volta pela
  mesma URL de callback e se distingue pela intenção guardada na sessão. Por isso
  os escopos concedidos ficam junto do token: é assim que se sabe se já há
  permissão ou se é preciso mandar autorizar de novo.
- **A conta que autoriza tem que ser a que está logada.** A tela do GitHub deixa
  trocar de conta no meio do caminho; sem essa conferência, o token de uma conta
  grudaria na sessão de outra.
- **O repositório é buscado de novo pelo id, não aceito do formulário.** O nome
  vem do navegador; é o GitHub quem sabe se aquela pessoa tem acesso àquele id.
  E dois projetos não podem apontar para o mesmo repositório, senão cada commit
  contaria duas vezes.
- **O token é cifrado no banco** (`CommitCraft.EncryptedBinary`), com chave
  derivada do `secret_key_base`. Trocar esse segredo torna os tokens ilegíveis;
  isso é tratado como "precisa entrar de novo", não como erro.

### Configurando o OAuth App

Crie um em <https://github.com/settings/developers> → *New OAuth App*:

| Campo | Valor em desenvolvimento |
| --- | --- |
| Homepage URL | `http://localhost:4000` |
| Authorization callback URL | `http://localhost:4000/auth/github/callback` |

Depois guarde as credenciais localmente:

```sh
mix commitcraft.dev_secrets   # cria config/dev.secret.exs, ignorado pelo git
```

Preencha o `client_id` e o `client_secret` no arquivo e reinicie o servidor.
As variáveis de ambiente `GITHUB_CLIENT_ID`/`GITHUB_CLIENT_SECRET` também
funcionam, mas o arquivo evita o modo mais comum de errar: exportar no terminal
e subir o servidor em outro.

Sem credenciais o servidor sobe normalmente, o botão de entrar responde com um
aviso e o terminal explica o que fazer. Em produção, `config/runtime.exs` recusa
iniciar sem as duas.

## Rodando

Precisa de Elixir 1.20+ e um PostgreSQL em `127.0.0.1:5432` com o papel
`postgres`/`postgres`. No macOS:

```sh
brew install elixir postgresql@16
brew services start postgresql@16
psql -h 127.0.0.1 -d postgres -c "create role postgres with login superuser password 'postgres';"
```

Depois:

```sh
mix setup
mix phx.server
```

A página fica em <http://localhost:4000>.

> Um container Docker também funciona, mas no macOS o encaminhamento de porta do
> Docker Desktop custou ~6s por conexão nova (`localhost` tentando IPv6 antes de
> cair para IPv4) e derrubava `mix test` por timeout. Por isso a configuração
> aponta para `127.0.0.1` e o Postgres nativo.

## Como o visual é montado

Não há nenhuma imagem no repositório. Os sprites vivem em
`lib/commitcraft_web/components/pixel.ex` como grades de texto — um caractere
por pixel — que viram `<rect>` de SVG:

```elixir
@coin [
  "....kkkk....",
  "..kkggggkk..",
  ...
]
```

Dá para editar a arte lendo o código, e ela fica nítida em qualquer escala.
A paleta e as molduras de menu de 16 bits (cantos entalhados feitos com sombras
deslocadas, sem `border-radius`) estão em `assets/css/app.css`.

Decisões que valem saber antes de mexer:

- **Sem `scroll-behavior: smooth`.** O Chrome engasga com ele em páginas de
  animação contínua e as âncoras do menu ficavam paradas. Corte seco também
  combina mais com menu de 8 bits.
- **`overflow-x: clip`, nunca `hidden`.** `hidden` transforma o elemento em
  contêiner de rolagem e quebra o salto das âncoras.
- **O texto da caixa de diálogo vem renderizado do servidor.** O efeito de
  máquina de escrever só o reescreve; sem JS, ou com "reduzir movimento"
  ligado, a frase aparece inteira.

## A curva de níveis

Nível não é guardado no banco: é função do XP total, calculada por
`CommitCraft.Game.Level`. Guardar os dois convida os dois a discordarem, e aí
não dá para saber qual está certo.

Para sair do nível `L` são precisos `300 * L - 100` de XP — o custo cresce
linearmente, então o acumulado cresce como parábola. Os números foram calibrados
pela tabela de XP da landing page: uma semana ativa dá algo perto de 425 XP, o
que põe o nível 7 a uns três meses de trabalho. É o mesmo cálculo que desenha o
HUD da página inicial, então mexer em `xp_to_advance/1` muda a promessa da
página junto com o jogo.

## Os webhooks

As três fontes entregam em `/webhooks/:source/:token`.

**GitHub** é instalado por nós, com o escopo `repo` que a pessoa concede.
**Vercel e Stripe não pedem token de API nenhum**: quem cria o webhook é quem
opera, no painel do próprio serviço, e cola aqui só o segredo de assinatura.
Menos permissão nossa na conta alheia, e um passo a menos para dar errado.

Cada serviço assina de um jeito, e as diferenças não são detalhe:

| | Cabeçalho | Algoritmo | O que é assinado |
| --- | --- | --- | --- |
| GitHub | `X-Hub-Signature-256` | HMAC-SHA256 | corpo cru |
| Vercel | `x-vercel-signature` | HMAC-**SHA1** | corpo cru |
| Stripe | `Stripe-Signature` | HMAC-SHA256 | `"<carimbo>.<corpo>"` |

No OTP o átomo do SHA-1 é `:sha`; `:sha1` não existe e derruba a requisição
inteira. A Stripe põe o carimbo dentro do que é assinado, e a tolerância de
cinco minutos é o que impede uma entrega capturada de ser reenviada meses
depois.

Três cuidados que não são opcionais e explicam o desenho do código:

- **A assinatura é conferida sobre o corpo cru.** O GitHub assina os bytes que
  mandou; depois que o `Plug.Parsers` vira mapa, reserializar não devolve os
  mesmos bytes e a assinatura nunca confere. Por isso existe
  `CommitCraftWeb.CacheBodyReader`, que guarda o original — só nas rotas de
  webhook.
- **Reenvio não paga duas vezes.** O GitHub reenvia entregas. A identidade de um
  acontecimento é o SHA do commit ou o número do pull request, não a entrega, e
  um índice único em `(project_id, external_id)` garante. O `xp` do projeto é
  sempre recalculado como a soma dos eventos, nunca incrementado.
- **O token na URL só roteia.** Quem autentica é a assinatura, com segredo por
  projeto **e por fonte**, guardado cifrado. O token também precisa bater com a
  fonte da URL: sem isso, um token de GitHub entregue em `/webhooks/stripe`
  seria conferido com o algoritmo errado.

### Testando em desenvolvimento

O GitHub não alcança `localhost`. Suba um túnel e aponte o servidor para ele:

```sh
ngrok http 4000
WEBHOOK_BASE_URL=https://algo.ngrok-free.app mix phx.server
```

Sem `WEBHOOK_BASE_URL` o repositório conecta mas o webhook não é instalado — e a
tela do projeto diz exatamente isso, com um botão para tentar de novo.

## A vitrine pública

`/p/:login/:slug` é a única tela que qualquer pessoa abre. É **opt-in**: todo
projeto nasce privado e tornar público é um ato, nunca um esquecimento.

O cuidado que dita o desenho: **o mapa mostra mensagens de commit**. Publicar um
projeto ligado a um repositório privado arrastaria junto uma coisa que a pessoa
nunca pensou em publicar. Então `Projects.reveal_titles?/1` decide — repositório
público mostra as mensagens (que já eram públicas), privado mostra o caminho sem
as palavras, e a tela diz por quê antes e depois de publicar.

O nome do repositório segue a mesma regra. Um teste conecta um repo privado,
publica o projeto e verifica que nem a mensagem nem o nome do repositório
aparecem.

### O selo do README

`/p/:login/:slug/badge.svg` devolve um SVG montado como string — sem biblioteca,
porque um selo é retângulo e texto. Cuidados que os testes travam: a largura é
calculada a partir do texto (SVG não tem layout, e uma conta errada faz a letra
vazar para fora do fundo), e o nome do projeto é escapado, porque nome é escrito
por gente e gente escreve `<`.

Projeto fechado devolve um selo dizendo "não encontrado", não um erro — selo
quebrado no README de alguém é pior do que selo que explica.

## O caminho, o som e a classe

**O caminho** (`CommitCraftWeb.Game.journey/1`) é a linha do tempo desenhada
como chão de jogo: cada acontecimento vira um bloco, do mais antigo à esquerda
ao mais recente à direita, e o artesão fica de pé sobre o último. Build quebrado
afunda o bloco — vira um buraco no caminho, e lê como buraco sem legenda.

Um detalhe que custou um bug: **`phx-mounted` dispara para todo elemento que
entra no DOM, inclusive no primeiro carregamento**. Sem distinguir o que é
novidade, a tela inteira piscava ao abrir, como se o projeto todo tivesse
acontecido naquele instante. O LiveView guarda os ids do que acabou de chegar e
só esses recebem a animação.

**O som** é sintetizado no WebAudio, não tocado de arquivo — mesma razão dos
sprites serem grades de texto: nenhum binário no repositório, e dá para afinar
uma nota mexendo num número. Três regras: o contexto de áudio só nasce depois de
um gesto da pessoa (o navegador proíbe antes), a escolha de mudo fica no
`localStorage`, e quem pediu menos movimento no sistema começa mudo. É **um som
por entrega**, não por commit — um push com trinta commits viraria metralhadora.

**A classe** (`CommitCraft.Game.Class`) é um título de RPG observado, não
escolhido: ninguém marca "quero ser Faxineiro", o projeto vira Faxineiro porque
os pull requests dele apagam mais do que escrevem. Como tudo no jogo, é função
pura sobre os eventos — a classe muda sozinha quando o jeito de trabalhar muda.

## O ranking

`/ranking` soma o XP dos projetos de cada pessoa e ordena. Três decisões:

- **Exige estar logado.** A página conta quem usa o CommitCraft e o quanto essa
  pessoa trabalha; deixar isso aberto seria decidir pelos outros.
- **Nome de projeto e repositório nunca saem.** Saber que alguém trabalha muito
  é bem diferente de saber no quê — e tem gente com repositório privado. Um
  teste conecta um repo privado a outra conta e verifica que nada disso aparece.
- **Só entra quem tem projeto.** Uma lista cheia de gente que entrou e nunca
  começou nada não é ranking, é lista de cadastros.

O desempate é pelo login, não pela ordem que o banco devolver — sem isso, duas
pessoas empatadas trocariam de lugar a cada carregamento.

## A tela ao vivo

`/jogar/:slug` é um LiveView. Quando um webhook chega, o processo que atendeu a
entrega avisa pelo PubSub e a tela de quem estiver olhando se atualiza sozinha —
barra subindo, evento entrando na linha do tempo, medalha caindo. Sem recarregar
e sem consultar de tempos em tempos.

Dois detalhes que valem saber antes de mexer:

- **A assinatura do PubSub só acontece em `connected?(socket)`.** O primeiro
  render é HTTP e morre em seguida; inscrever ali deixaria assinatura órfã.
- **`on_mount` refaz a checagem de sessão.** O LiveView não passa pelos plugs do
  router depois do primeiro render, então sem isso o websocket seria uma porta
  sem porteiro.

As animações usam `phx-mounted`, que só dispara em elemento novo no DOM — é o
que faz a marcação acertar exatamente o que acabou de chegar, sem piscar o resto
da tela. E a barra sobe em `steps()`, não deslizando: num jogo de 16 bits o XP
entra em blocos.

## Sequência e conquistas

**Conquista não dá XP.** XP mede quanto trabalho foi feito; conquista marca que
tipo de coisa você fez. Misturar os dois faria uma medalha valer tantos commits,
e aí ela vira farm em vez de piada.

**O fuso importa mais do que parece.** Um commit às 22h no Brasil é 01h do dia
seguinte em UTC — contar em UTC quebraria a sequência de quem trabalha à noite,
justamente quem mais liga para ela. `CommitCraft.Game.Streak` conta os dias num
deslocamento fixo (UTC-3 por padrão, `:game_utc_offset_hours`). O Brasil não tem
horário de verão desde 2019, então isso evita arrastar um banco de fusos inteiro
como dependência.

Ambas são funções puras sobre os eventos já gravados
(`CommitCraft.Game.Achievements.earned/1`), então o catálogo pode ser reavaliado
a qualquer momento — inclusive para conquistas criadas depois de o projeto já
estar em andamento.

## Testes

```sh
mix test
```

## Próximos passos

1. Colocar no ar, para as integrações deixarem de depender de um túnel efêmero.
2. Reavaliar conquistas antigas quando o catálogo crescer — como são funções
   puras sobre os eventos, dá para destravar retroativamente.
3. A lista de projetos também ao vivo.

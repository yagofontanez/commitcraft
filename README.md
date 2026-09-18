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
conectar um repositório do GitHub e **ganhar XP de verdade** com o que acontece
nele: commit na branch principal, pull request mesclado e issue fechada.

O que ainda não existe: Vercel, Stripe, conquistas e sequência de dias.

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

## O webhook

O repositório conectado manda eventos para `/webhooks/github/:token`. Três
cuidados que não são opcionais e explicam o desenho do código:

- **A assinatura é conferida sobre o corpo cru.** O GitHub assina os bytes que
  mandou; depois que o `Plug.Parsers` vira mapa, reserializar não devolve os
  mesmos bytes e a assinatura nunca confere. Por isso existe
  `CommitCraftWeb.CacheBodyReader`, que guarda o original — só nas rotas de
  webhook.
- **Reenvio não paga duas vezes.** O GitHub reenvia entregas. A identidade de um
  acontecimento é o SHA do commit ou o número do pull request, não a entrega, e
  um índice único em `(project_id, external_id)` garante. O `xp` do projeto é
  sempre recalculado como a soma dos eventos, nunca incrementado.
- **O token na URL só roteia.** Quem autentica é a assinatura HMAC, com segredo
  sorteado por projeto e guardado cifrado.

### Testando em desenvolvimento

O GitHub não alcança `localhost`. Suba um túnel e aponte o servidor para ele:

```sh
ngrok http 4000
WEBHOOK_BASE_URL=https://algo.ngrok-free.app mix phx.server
```

Sem `WEBHOOK_BASE_URL` o repositório conecta mas o webhook não é instalado — e a
tela do projeto diz exatamente isso, com um botão para tentar de novo.

## Testes

```sh
mix test
```

## Próximos passos

1. Conectar um repositório a um projeto (aí sim pedindo escopo `repo`).
2. Webhook do GitHub virando eventos de XP.
3. O painel do projeto em LiveView, com a barra subindo ao vivo.
4. Conquistas, linha do tempo, Vercel e Stripe.

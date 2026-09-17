# CommitCraft

Um SaaS que transforma a construção de um projeto num jogo 2D. Commits viram XP,
deploys viram conquistas, vendas viram ouro — e o projeto ganha nível enquanto
você trabalha.

Sem assinatura e sem plano pago. Se o jogo for útil, dá para deixar uma moeda.

## Estado atual

A landing page está pronta e o formulário da lista de espera grava no banco.
O jogo em si ainda não existe: não há autenticação, integração com GitHub,
Vercel ou Stripe, nem motor de XP. Os números que aparecem na página são
ilustrativos e vivem em `lib/commitcraft_web/controllers/page_controller.ex`.

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

## Testes

```sh
mix test
```

## Próximos passos

1. Autenticação e o conceito de projeto.
2. Webhook do GitHub alimentando um motor de XP de verdade.
3. O painel do projeto em LiveView, com a barra de XP subindo ao vivo.
4. Vercel e Stripe.

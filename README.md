# CommitCraft

Um SaaS que transforma a construção de um projeto num jogo 2D. Commits viram XP,
deploys viram conquistas, vendas viram ouro — e o projeto ganha nível enquanto
você trabalha.

Sem assinatura e sem plano pago. Se o jogo for útil, dá para deixar uma moeda.

## Estado atual

Landing page e login com GitHub. O jogo em si ainda não existe: não há projeto,
integração com repositório nem motor de XP. Os números que aparecem na página
são ilustrativos e vivem em `lib/commitcraft_web/controllers/page_controller.ex`.

Depois de entrar, `/jogar` mostra uma vaga de save vazia — é ali que os projetos
vão aparecer.

## Login

A única porta de entrada é o OAuth do GitHub: sem senha, sem e-mail, sem mailer.
Quem usa o CommitCraft tem GitHub por definição, e o token que sai do login é o
mesmo que vai ler commits mais tarde.

Duas coisas que valem a atenção de quem mexer aqui:

- **O login pede só `read:user`.** O escopo `repo`, que dá acesso ao código, só
  será pedido quando a pessoa for de fato conectar um repositório. Por isso os
  escopos concedidos são guardados junto do token: é assim que se sabe, depois,
  se já há permissão ou se é preciso mandar autorizar de novo.
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

## Testes

```sh
mix test
```

## Próximos passos

1. Autenticação e o conceito de projeto.
2. Webhook do GitHub alimentando um motor de XP de verdade.
3. O painel do projeto em LiveView, com a barra de XP subindo ao vivo.
4. Vercel e Stripe.

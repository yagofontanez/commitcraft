# Colocando o CommitCraft no ar

O alvo é o Fly.io. A razão é específica: a tela do projeto é LiveView e mantém
websocket aberto, o PubSub precisa de processo vivo, e o webhook exige URL
estável com TLS. Isso elimina serverless de saída, e o Fly resolve release,
Postgres, certificado e domínio sem virar trabalho de operação.

## O que já está pronto no repositório

- `Dockerfile` e `.dockerignore` (de `mix phx.gen.release --docker`)
- `fly.toml` com as opções que este app precisa
- `config/runtime.exs` recusando subir sem as variáveis críticas

## Passo a passo

```sh
# 1. Instale e entre na sua conta
brew install flyctl
fly auth login

# 2. Crie o app sem subir ainda (ele ajusta o nome no fly.toml se já existir)
fly launch --no-deploy

# 3. Banco de dados
fly postgres create --name commitcraft-db --region gru
fly postgres attach commitcraft-db     # isto define DATABASE_URL sozinho

# 4. Segredos
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly secrets set GITHUB_CLIENT_ID="..." GITHUB_CLIENT_SECRET="..."
fly secrets set WEBHOOK_BASE_URL="https://SEU-DOMINIO"

# 5. Suba
fly deploy
```

As migrações rodam antes de cada deploy, pelo `release_command` no `fly.toml`.
O script `bin/server` **não migra** — ele só inicia o sistema. Sem esse comando
o banco ficaria na versão antiga e o app subiria quebrado na primeira consulta a
uma coluna que ainda não existe.

## As variáveis, e por que cada uma existe

| Variável | Para quê |
| --- | --- |
| `DATABASE_URL` | O Postgres. O `fly postgres attach` define. |
| `SECRET_KEY_BASE` | Assina os cookies **e deriva a chave que cifra os tokens do GitHub**. |
| `PHX_HOST` | O domínio. Vai nos links, no `og:image` e na callback do OAuth. |
| `WEBHOOK_BASE_URL` | O endereço que GitHub, Vercel e Stripe chamam. |
| `GITHUB_CLIENT_ID` / `_SECRET` | O OAuth App de produção. |
| `ECTO_IPV6` | O Fly liga as máquinas por IPv6 interno. |

O `config/runtime.exs` **recusa subir** sem `PHX_HOST`, `SECRET_KEY_BASE`,
`DATABASE_URL`, `WEBHOOK_BASE_URL` e as credenciais do GitHub. É de propósito:
subir sem saber para onde o GitHub entrega, ou com host errado, seria um bug
silencioso que só aparece quando alguém tenta entrar.

## O cuidado que mais importa

**Nunca troque o `SECRET_KEY_BASE` depois do primeiro acesso.**

Os tokens do GitHub são guardados cifrados, com chave derivada dele. Trocá-lo
torna todos ilegíveis — o código trata isso sem quebrar (devolve `nil` e manda
autorizar de novo, ver `CommitCraft.EncryptedBinary`), mas todo mundo precisaria
reconectar. Guarde o valor.

## Antes do primeiro deploy

1. **Crie um OAuth App novo, de produção**, em <https://github.com/settings/developers>.
   O de desenvolvimento aponta para `localhost` e não serve. A callback é
   `https://SEU-DOMINIO/auth/github/callback`.
2. **Domínio próprio** (opcional, mas vale): `fly certs add commitcraft.com.br`.
   A vitrine pública e o selo de README existem para serem vistos, e
   `algo.fly.dev` entrega menos do que eles merecem.
3. **Reinstale os webhooks.** Os que existem hoje apontam para o túnel do ngrok.
   Em cada projeto: trocar → reconectar.

## Depois que subir

- `fly logs` acompanha as entregas de webhook, que são registradas com origem,
  quantos eventos eram novos e o XP resultante.
- `fly ssh console` abre shell; `/app/bin/commitcraft remote` entra no IEx do
  release, com o sistema rodando.

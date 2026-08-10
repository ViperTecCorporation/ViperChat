# Viper Push Relay

O relay é um serviço central: uma única instância atende todas as instalações do
ViperChat vinculadas ao projeto Firebase `viperchat-f0ce4`. Cada celular ainda
recebe mensagens pelo seu próprio token FCM. O segredo do relay autentica os
servidores Chatwoot e nunca é embarcado no APK.

## Imagem publicada pelo GitHub

O workflow `.github/workflows/publish_viper_push_relay.yml` roda junto aos mesmos
eventos de publicação do Chatwoot: pushes em `develop` e `uno`, tags `v*` e
execução manual. Ele testa o serviço, publica `amd64` e `arm64` e cria um
manifest multi-plataforma em:

```text
ghcr.io/viperteccorporation/viper-push-relay:<branch-ou-tag>
```

Uma tag `v*` também atualiza `:latest`. Nenhum arquivo ou segredo Firebase é
copiado para a imagem.

## Preparação da VPS

No diretório do Compose do Chatwoot:

```bash
mkdir -p secrets
chmod 700 secrets
```

Copie a conta de serviço Firebase para:

```text
secrets/firebase-service-account.json
```

Restrinja a leitura e gere o segredo compartilhado:

```bash
chmod 600 secrets/firebase-service-account.json
openssl rand -hex 32
```

Configure no `.env` do Compose, usando o valor gerado nos dois componentes:

```dotenv
VIPER_NATIVE_PUSH_ENABLED=true
VIPER_PUSH_RELAY_URL=https://relay.vipertec.net/v1/push
VIPER_PUSH_RELAY_TOKEN=COLE_AQUI_O_TOKEN_GERADO

VIPER_PUSH_RELAY_IMAGE_TAG=latest
VIPER_PUSH_RELAY_PORT=3100
VIPER_FIREBASE_PROJECT_ID=viperchat-f0ce4
VIPER_FIREBASE_CREDENTIALS_PATH=./secrets/firebase-service-account.json
```

O serviço possui um token padrão somente quando iniciado fora de produção. O
Compose define `NODE_ENV=production`, portanto se recusa a iniciar sem
`VIPER_PUSH_RELAY_TOKEN`. Isso impede que o endpoint público fique aberto com
uma credencial conhecida.

## Subida junto ao Chatwoot

Se o pacote GHCR estiver privado, autentique a VPS uma vez com um PAT que tenha
somente permissão de leitura de pacotes:

```bash
echo "$GHCR_READ_TOKEN" | docker login ghcr.io -u SEU_USUARIO --password-stdin
```

Use o arquivo de produção já adotado na VPS e acrescente o overlay do relay:

```bash
docker compose \
  -f docker-compose.production.yaml \
  -f docker-compose.viper-push-relay.yaml \
  pull viper-push-relay

docker compose \
  -f docker-compose.production.yaml \
  -f docker-compose.viper-push-relay.yaml \
  up -d
```

O container escuta internamente em `3100`; no host a porta fica limitada a
`127.0.0.1:3100`, apropriada para um Cloudflare Tunnel executado na mesma VPS.
O filesystem do container permanece somente leitura e a credencial Firebase é
montada com `:ro`. Em hosts com Docker instalado via Snap, não acrescente
`cap_drop: ALL` ou `no-new-privileges`: essa combinação impede a execução do
entrypoint oficial da imagem Node.

## Cloudflare Tunnel

Crie o hostname público:

```text
Hostname: relay.vipertec.net
Service:  http://localhost:3100
```

Se o `cloudflared` estiver em outro container, conecte-o à mesma rede do relay e
use `http://viper-push-relay:3100`; nesse cenário a publicação da porta no host
pode ser removida do overlay.

Não é necessário liberar a porta 3100 no firewall ao usar Tunnel. A única rota
de envio é `POST /v1/push`; `GET /healthz` serve para monitoramento.

## Validação

Na VPS:

```bash
curl --fail http://127.0.0.1:3100/healthz
curl --fail https://relay.vipertec.net/healthz
```

O resultado esperado inclui `"status":"ok"` e o projeto Firebase. Uma chamada
sem autenticação deve retornar HTTP 401:

```bash
curl -i -X POST https://relay.vipertec.net/v1/push
```

Depois disso, instale o APK, permita notificações e envie uma mensagem a um
usuário com o aplicativo em segundo plano. Web/PWA continua usando
`browser_push`; o relay processa somente inscrições `viper_native`.

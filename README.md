<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="./public/brand-assets/logo_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="./public/brand-assets/logo.svg">
    <img src="./public/brand-assets/logo.svg" alt="ViperChat" height="72">
  </picture>

  <h1>ViperChat</h1>

  <p><strong>Atendimento omnichannel self-hosted, com uma experiência completa para WhatsApp e UnoAPI (ViperConnect).</strong></p>

  <p>
    <a href="https://github.com/ViperTecCorporation/ViperChat/releases"><img src="https://img.shields.io/github/v/release/ViperTecCorporation/ViperChat?display_name=tag&style=flat-square" alt="Latest release"></a>
    <a href="https://github.com/ViperTecCorporation/ViperChat/actions/workflows/publish_foss_docker.yml"><img src="https://img.shields.io/github/actions/workflow/status/ViperTecCorporation/ViperChat/publish_foss_docker.yml?style=flat-square&label=container" alt="Container build"></a>
    <a href="https://github.com/ViperTecCorporation/ViperChat/pkgs/container/chatwoot"><img src="https://img.shields.io/badge/GHCR-ViperChat-7b3531?style=flat-square&logo=github" alt="GitHub Container Registry"></a>
    <a href="./LICENSE"><img src="https://img.shields.io/badge/licenca-proprietaria-475569?style=flat-square" alt="Licença proprietária"></a>
  </p>

  <p>
    <a href="#início-rápido">Instalação</a> ·
    <a href="#recursos-em-destaque">Recursos</a> ·
    <a href="#integração-com-a-unoapi">UnoAPI</a> ·
    <a href="#documentação">Documentação</a> ·
    <a href="#desenvolvimento">Desenvolvimento</a>
  </p>
</div>

---

O ViperChat é uma distribuição do Chatwoot mantida pela Viper Tec. Ela preserva a central de atendimento omnichannel do projeto original e adiciona integrações, fluxos e interfaces voltados à operação brasileira de WhatsApp.

O projeto atende equipes que precisam manter seus dados e sua infraestrutura sob controle, conectar a UnoAPI, trabalhar com grupos e mensagens interativas e usar a mesma experiência no navegador, PWA e aplicativos nativos.

> [!IMPORTANT]
> Este repositório não é uma distribuição oficial da Chatwoot Inc. O ViperChat possui [licença proprietária](./LICENSE); os componentes de terceiros e suas respectivas licenças estão descritos em [THIRD_PARTY_NOTICES](./THIRD_PARTY_NOTICES).

## O que o ViperChat entrega

| Área | Capacidades |
| --- | --- |
| **Atendimento omnichannel** | WhatsApp, chat do site, e-mail, Instagram, Facebook, Telegram, API e demais canais herdados do Chatwoot. |
| **WhatsApp com UnoAPI** | Conversas individuais e em grupo, mensagens interativas, contatos, mídias, ecos de outros dispositivos e configuração independente por caixa de entrada. |
| **Produtividade** | Editor compacto, mensagens privadas, áudio, anexos, contatos, Pix, IA, encaminhamento de mensagens, equipes, filtros e respostas prontas. |
| **Operação** | Automações, campanhas, relatórios, SLA, central de notificações, temas por usuário e recursos configuráveis por conta. |
| **Aplicativos** | Web responsiva, PWA e cliente Android baseado em Capacitor; fundação iOS compartilhando o mesmo dashboard Vue. |
| **Implantação** | Imagens Docker versionadas para `linux/amd64` e `linux/arm64`, PostgreSQL, Redis e armazenamento compatível com Active Storage. |

## Recursos em destaque

### Conversas e equipe

- Editor de mensagens compacto, responsivo e compatível com o editor clássico por configuração da conta.
- Mensagens privadas, menções, labels, respostas prontas, automações e horário de atendimento.
- Encaminhamento de texto e mídia entre conversas, preservando os anexos no storage.
- Atribuição por agente ou equipe, inclusive por origem externa para integrações como Typebot.
- Lista **Minhas** integrada às filas das equipes do agente.
- Reabertura ou criação de conversa conforme a regra configurada na caixa de entrada.

### WhatsApp avançado

- Grupos, participantes, imagens e eventos recebidos pela UnoAPI.
- Renderização de botões, listas, carrosséis, catálogos, pedidos e pagamentos.
- Contatos anexados à conversa, figurinhas, Pix e mensagens de voz.
- Tratamento de mensagens enviadas por outros dispositivos e conexões, sem duplicar a conversa.
- Sincronização bidirecional de contatos com telefone, LID, nome, username e foto de perfil.
- Campanhas UnoAPI com texto livre, variáveis por contato e variação opcional de texto por IA.

### Experiência ViperChat

- Identidade visual ViperChat com temas claro, escuro e cor personalizada por usuário.
- Layout móvel otimizado para ampliar a área da conversa.
- Central de notificações com contador na barra lateral.
- Notificações em tempo real por Action Cable e recuperação da lista após reconexão.
- Limite de upload configurável e suporte a upload direto para storage compatível.

## Integração com a UnoAPI (ViperConnect)

A UnoAPI é um provider adicional do canal WhatsApp. Uma mesma instalação pode manter caixas oficiais do WhatsApp Cloud e caixas UnoAPI, cada uma com sua própria configuração.

### Precedência de configuração

1. URL ou token definidos na caixa de entrada UnoAPI.
2. URL ou token globais definidos no Super Admin.
3. Valor padrão do recurso, quando aplicável.

As configurações globais ficam em **Super Admin → App Config → UnoAPI**. Uma configuração preenchida diretamente na caixa de entrada sempre prevalece sobre o valor global correspondente.

```env
UNOAPI_API_URL=https://sua-unoapi.exemplo.com
UNOAPI_AUTH_TOKEN=troque-por-um-token-seguro
```

> [!CAUTION]
> Não publique tokens em arquivos versionados, logs, issues ou exemplos compartilhados. Use secrets da plataforma ou variáveis de ambiente.

Consulte a [sincronização de contatos](./docs/unoapi-contact-sync.md), a [arquitetura de grupos](./docs/uno-group-conversations-architecture.md) e a [atribuição de conversa por origem](./docs/unoapi-assign-conversation-by-source.md) para conhecer os contratos operacionais.

## Início rápido

### Requisitos

- Docker Engine com Docker Compose v2;
- PostgreSQL 14 ou superior e Redis 7;
- domínio HTTPS para uso em produção;
- SMTP configurado para e-mails transacionais;
- storage persistente local ou compatível com S3 para anexos;
- uma instância UnoAPI somente se esse provider for utilizado.

### Instalação com Docker Compose

Clone o projeto e crie o arquivo de ambiente:

```bash
git clone https://github.com/ViperTecCorporation/ViperChat.git
cd ViperChat
cp .env.example .env
```

No `docker-compose.production.yaml`, use a mesma imagem versionada nos processos Web e Sidekiq por meio do serviço base:

```yaml
services:
  base: &base
    image: ghcr.io/viperteccorporation/chatwoot:v4.16.12-viper.15-ce
```

Revise o `.env`, configure senhas fortes para PostgreSQL e Redis e prepare o banco antes de iniciar a aplicação:

```bash
docker compose -f docker-compose.production.yaml run --rm rails \
  bundle exec rails db:chatwoot_prepare

docker compose -f docker-compose.production.yaml up -d
```

Em produção, mantenha Web e Sidekiq obrigatoriamente na mesma tag. Consulte a página de [releases](https://github.com/ViperTecCorporation/ViperChat/releases) antes de escolher uma versão.

### Atualização

Faça backup do banco e do storage, altere a tag da imagem e execute:

```bash
docker compose -f docker-compose.production.yaml pull rails sidekiq
docker compose -f docker-compose.production.yaml run --rm rails \
  bundle exec rails db:chatwoot_prepare
docker compose -f docker-compose.production.yaml up -d
```

> [!WARNING]
> Não use tags diferentes entre Web e Sidekiq. Antes de atualizar uma instalação existente, leia as notas da versão e preserve um caminho de rollback do banco e dos volumes.

## Imagens publicadas

| Componente | Imagem | Finalidade |
| --- | --- | --- |
| ViperChat CE | `ghcr.io/viperteccorporation/chatwoot:<tag>-ce` | Aplicação Rails/Vue e workers Sidekiq. |
| Viper Push Relay | `ghcr.io/viperteccorporation/viper-push-relay:<tag>` | Entrega de push FCM para clientes nativos self-hosted. |

As imagens de release são publicadas para `linux/amd64` e `linux/arm64`. Prefira sempre uma tag imutável em vez de depender de `latest`.

## Aplicativos nativos

O cliente Android usa Capacitor e carrega um bundle Vue local, mantendo autenticação, upload, Share Sheet e push integrados à instalação self-hosted. A sessão é protegida pelo Android Keystore e isolada por instalação.

O projeto iOS compartilha a mesma base, mas assinatura, push APNs e publicação dependem das credenciais Apple/Firebase de cada distribuição. Consulte a [documentação nativa](./docs/native/README.md) para requisitos, comandos e limitações atuais.

## Documentação

| Tema | Documento |
| --- | --- |
| Aplicativos Android e iOS | [ViperChat Native](./docs/native/README.md) |
| Instalação nativa self-hosted | [Discovery e configuração](./docs/native/self-hosted.md) |
| Push nativo | [Viper Push Relay](./docs/native/push-relay.md) |
| Sincronização de contatos | [UnoAPI contact sync](./docs/unoapi-contact-sync.md) |
| Atribuição por origem | [API `assign_by_source`](./docs/unoapi-assign-conversation-by-source.md) |
| Conversas em grupo | [Arquitetura de grupos UnoAPI](./docs/uno-group-conversations-architecture.md) |
| Fotos de perfil por metadata | [UnoAPI profile pictures](./docs/uno-profile-picture-metadata.md) |
| Chat interno | [API do chat interno](./docs/internal-chat-api.md) |
| Diagnóstico de recursos premium | [Health check](./docs/uno-premium-features-health-check.md) |
| Notas da linha 4.16 | [Changelog Viper](./docs/v4.14.8-to-v4.16.1-viper-changelog.md) |

Para funcionalidades herdadas sem customização ViperChat, consulte também a [documentação oficial do Chatwoot](https://www.chatwoot.com/docs/).

## Desenvolvimento

O backend utiliza Ruby on Rails, PostgreSQL, Redis e Sidekiq. O frontend utiliza Vue 3, Vite e pnpm.

```bash
# dependências
bundle install
pnpm install

# ambiente de desenvolvimento
pnpm start:dev

# validações principais
bundle exec rspec
pnpm eslint
pnpm test
```

Comandos do cliente nativo:

```bash
pnpm build:native
pnpm native:sync:android
pnpm native:build:android
pnpm native:bundle:android
pnpm native:sync:ios
```

Antes de abrir uma contribuição, mantenha a mudança focada, inclua testes proporcionais ao risco e valide o comportamento no canal afetado.

## Recursos experimentais

Algumas bases de integração, como voz customizada WebRTC/SIP e chamadas em segundo plano nos aplicativos, ainda estão em evolução. Elas não devem ser tratadas como recursos prontos para produção sem validação específica do ambiente.

## Segurança

Não abra uma issue pública com vulnerabilidades, credenciais ou dados de clientes. Siga o processo descrito em [SECURITY.md](./SECURITY.md).

## Licença e atribuições

O código e a documentação específicos do ViperChat estão sujeitos à [ViperChat Proprietary License](./LICENSE). O produto inclui componentes de terceiros, entre eles o Chatwoot, cujos avisos e licenças aplicáveis estão em [THIRD_PARTY_NOTICES](./THIRD_PARTY_NOTICES).

ViperChat © 2025–2026 ViperTec Corporation. Todos os direitos reservados.

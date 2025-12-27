<img src="./.github/screenshots/header.png#gh-light-mode-only" width="100%" alt="Header light mode"/>
<img src="./.github/screenshots/header-dark.png#gh-dark-mode-only" width="100%" alt="Header dark mode"/>

___


# Chatwoot Uno
  - essa versão do chatwoot que esta sendo usada aqui tem algumas customizações que ainda não foram aceitas pelo time do chatwoot e para um melhor uso com a unoapi(http://github.com/clairton/unoapi-cloud):
    - funciona as conversas em grupo
    - trata a mensagem enviadas por outras conexões, inclusive o aplicativo
    - desabilita a janela de 24 horas do whatsapp cloud oficial
    - sincroniza as imagens de perfil dos grupos e usuarios
    - possibilidade de editar o endereço da caixa de entrada do whatsapp, assim pode usar a oficial e a unoapi na mesma instalação(não usar a env WHATSAPP_CLOUD_BASE_URL)
    - opção no superadmin de habilitar para colocar o nome do agente na mensagem
    - opção no superadmin de habilitar para marcar as mensagem no whatsapp como lido quando o agente visualiza a conversa
    - opção no superadmin de esconder para a aba de todas as conversas
    - opção no superadmin de esconder para o filtro de conversas
    - opção no superadmin de esconder a parte de contatos
    - da opção de alterar logo e nome da empresa
  Exemplo de stack com os dois projetos integrados: https://github.com/clairton/unoapi-cloud/tree/main/examples/unochat

## Canal de Voz Custom (WebRTC/SIP) com credenciais por inbox

Este fork adiciona um provedor de voz **custom** que usa WebRTC/SIP, com suporte a:
- JWT por agente (ou gerado pela inbox).
- Usuário WebRTC por agente (por inbox) com fallback para perfil.
- Transferência de chamadas via **SIP REFER** ou **ARI**.
- Chamadas internas entre agentes (estilo mensagens privadas).

### Configurar a inbox de voz (provider custom)

1) Crie uma caixa de entrada do tipo **Voice** e selecione **Custom** como provider.
2) Preencha os campos do WebRTC/SIP:
   - **WebRTC WS URL** (`webrtc_ws_url`)
   - **SIP Domain** (`sip_domain`)
   - **SIP Outbound Proxy** (opcional)
   - **SIP Transport** (`wss` ou `ws`)
3) Escolha o **tipo de autenticacao**:
   - **JWT** (padrao) ou **Usuario/Senha** (recomendado para Issabel/Magnus/Asterisk).
4) Transferência:
    - **Transfer Mode**: `sip_refer` (padrão) ou `ari`.
    - Se `ari`, informe **Transfer API URL** e **Transfer API Token**.
5) JWT:
   - **Usar JWT do agente**: quando marcado, o token vem do agente (por inbox ou perfil).
   - Se desmarcado, informe **JWT Secret** (opcionalmente `iss`, `aud`, `ttl`) para gerar o token na própria inbox.

### Credenciais WebRTC por agente (por inbox)

Em **Configurações > Inboxes > [sua inbox de voz] > Agentes**:
- Configure **WebRTC Username** e **JWT** ou **Senha** por agente.
- Esses dados são salvos por inbox (ou seja, o mesmo agente pode ter credenciais diferentes em caixas distintas).

**Fallback de credenciais**

Ordem usada para buscar as credenciais:
1) **Inbox Member** (credenciais salvas no agente da inbox).
2) **Perfil do agente** (`custom_attributes` com `webrtc_username`, `webrtc_jwt` ou `webrtc_password`).
3) **Token gerado pela inbox** (se `jwt_secret` estiver configurado e auth type = JWT).

Se o `webrtc_username` não existir, o fallback final é o email do agente.

### Chamadas internas entre agentes

Em conversas internas:
- O botão de chamada permite iniciar uma ligação com outro agente.
- Se houver mais de uma inbox de voz ou mais de um agente, o sistema pede seleção.
- O agente de destino precisa ser participante da conversa e membro da inbox de voz.

### Transferência de chamadas

Durante uma chamada:
- **SIP REFER**: o destino é montado como `sip:USERNAME@SIP_DOMAIN`.
  - `USERNAME` segue o mesmo fallback de credenciais.
- **ARI**: a chamada é enviada para a API configurada na inbox.

## Campanhas WhatsApp com Unoapi

Este fork adiciona um fluxo específico de campanhas para caixas de entrada WhatsApp com provider `unoapi`.

### Como usar

- Habilite a feature `whatsapp_campaign` para a conta no super admin.
- Crie ou use uma caixa de entrada WhatsApp com provider `unoapi`.
- No dashboard, acesse `Campanhas → WhatsApp` e clique em **Create campaign**.
- Selecione a inbox `unoapi` no campo **Select Inbox**.
- Para inbox `unoapi`, o formulário muda para:
  - **Message**: texto livre da campanha (conteúdo base da mensagem).
  - **Audience list (Unoapi)**: lista de contatos, um por linha, no formato:
    ```
    phone_number;name;identifier;email;value;due_at;scheduled_at;wait_for_seconds
    ```
    Exemplo simples:
    ```
    +5511999998888;João
    +351912345678;Maria
    ```
    O último campo (`wait_for_seconds`) é opcional e define o atraso, em segundos, apenas para aquele contato.

### Lógica de disparo

- Serviço responsável: `Whatsapp::OneoffUnoapiCampaignService`.
- Para cada contato da audiência:
  - Se houver `wait_for_seconds` na linha, ele é usado diretamente como atraso do job.
  - Se não houver, é aplicado um atraso incremental aleatório entre **10 segundos e 3 minutos**:
    ```ruby
    interval = audience[:wait_for_seconds] || (interval + rand(10..180))
    ```
  - Cada contato é enviado via `CampaignMessageJob` com o texto da campanha já interpolado (`##name`, `##identifier`, etc.).

### Variação de texto com Groq (apenas Unoapi)

Para campanhas WhatsApp com provider `unoapi`, o envio pode usar a API da Groq para reescrever cada mensagem com sinônimos, mantendo o mesmo significado.

- Serviço: `Groq::TextVariationService`.
- Integração: `CampaignMessageJob` aplica a variação apenas quando:
  - `inbox.channel_type == 'Channel::Whatsapp'`
  - `inbox.channel.provider == 'unoapi'`
  - `GROQ_API_KEY` está definido.
- Fluxo:
  - O texto final da mensagem é calculado com `bind(content, audience)` (substitui `##name`, `##value`, etc.).
  - Se as condições acima forem verdadeiras, o texto é enviado para a Groq e a resposta é usada como conteúdo da mensagem.

### Variáveis de ambiente para Groq

- `GROQ_API_KEY` (obrigatório para habilitar a variação)
  - Token da API Groq, usado no header `Authorization: Bearer ...`.
- `GROQ_API_BASE_URL` (opcional)
  - Endpoint base da API, default: `https://api.groq.com/openai/v1`.
- `GROQ_CHAT_MODEL` (opcional)
  - Modelo usado na chamada, default: `openai/gpt-oss-120b`.
- `GROQ_WHATSAPP_CAMPAIGN_PROMPT` (opcional)
  - Prompt usado para reescrever o texto. Deve conter o placeholder `{{text}}`, que será substituído pelo conteúdo original da mensagem.
  - Exemplo:
    ```text
    Reescreva a mensagem abaixo em pt-BR usando sinônimos, mantendo exatamente o mesmo significado, links e números.
    Responda apenas com o texto reescrito, sem explicações:
    "{{text}}"
    ```

Se `GROQ_API_KEY` não estiver definido, as campanhas Unoapi continuam funcionando normalmente, apenas sem variação automática de texto.

## Encaminhar mensagens entre conversas

Este fork adiciona uma forma de encaminhar mensagens (texto e mídias) de uma conversa para outra, inclusive em caixas de entrada WhatsApp com provider `unoapi`.

### Como usar

- No painel de conversas, clique com o **botão direito** sobre uma mensagem (ou use o botão de **menu de contexto** da bolha).
- Escolha a opção **“Encaminhar mensagens”**.
- Um modo de seleção é ativado:
  - A mensagem clicada já vem selecionada.
  - Você pode marcar ou desmarcar outras mensagens usando os checkboxes ao lado das bolhas.
- Na barra que aparece acima da lista de mensagens, clique em **Encaminhar**.
- No modal:
  - Escolha o **contato** de destino (pode pesquisar ou criar um novo).
  - Escolha a **caixa de entrada** (inbox) pela qual deseja encaminhar.
  - Revise o **preview de texto** (apenas texto; anexos serão encaminhados mesmo sem aparecer no preview).
  - Clique em **Encaminhar** para confirmar.

### O que é encaminhado

- Para cada mensagem selecionada, o sistema cria uma nova mensagem de saída na conversa de destino com:
  - Mesmo tipo de conteúdo (`content_type`) e texto (`outgoing_content`), quando houver.
  - Metadados indicando de qual conversa/mensagem original o conteúdo foi encaminhado.
- Todos os anexos suportados são clonados:
  - Imagens, vídeos, documentos e áudios.
  - Os arquivos são copiados em nível de storage para a nova mensagem, como se tivessem sido enviados novamente.

### Reaproveitamento de conversas (lock_to_single_conversation)

O comportamento da conversa de destino respeita a configuração `lock_to_single_conversation` do inbox:

- **Quando `lock_to_single_conversation` está ativo** no inbox de destino:
  - Se existir uma conversa anterior para aquele contato/inbox, o encaminhamento **reabre a última conversa** (se estiver resolvida).
  - Essa conversa é **atribuída ao agente** que está encaminhando.
  - As mensagens encaminhadas são adicionadas **nessa** conversa reaproveitada.
- **Quando `lock_to_single_conversation` está desativado**:
  - Se já houver **uma conversa aberta** para o contato nesse inbox, ela é reutilizada e atribuída ao agente que está encaminhando.
  - Se não houver conversa aberta, é criada **uma nova conversa aberta**, já atribuída ao agente.

Esse fluxo funciona também para caixas de entrada WhatsApp com provider `unoapi`, reaproveitando a mesma lógica de envio usada nas respostas normais.

## Tamanho máximo de anexos

Este fork permite configurar o tamanho máximo de anexos (tanto no dashboard quanto no widget) via variável de ambiente.

- Variável: `MAXIMUM_FILE_UPLOAD_SIZE`
- Unidade: **MB**
- Default (se não definida): `150`

### Comportamento

- **Frontend (dashboard e widget)**:
  - O limite exibido na mensagem de erro (`CONVERSATION.FILE_SIZE_LIMIT` / `FILE_SIZE_LIMIT`) usa o valor de `MAXIMUM_FILE_UPLOAD_SIZE`.
  - Uploads acima desse valor são bloqueados e o usuário vê o alerta com o limite em MB.

- **Backend (Rails / ActiveStorage)**:
  - O modelo `Attachment` valida o tamanho do arquivo com base na mesma env:
    - Arquivos com tamanho maior que `MAXIMUM_FILE_UPLOAD_SIZE` MB recebem erro `size is too big`.

### Exemplo de configuração

 .env ou variáveis da stack
MAXIMUM_FILE_UPLOAD_SIZE=150


# Chatwoot

The modern customer support platform, an open-source alternative to Intercom, Zendesk, Salesforce Service Cloud etc.

<p>
  <a href="https://codeclimate.com/github/chatwoot/chatwoot/maintainability"><img src="https://api.codeclimate.com/v1/badges/e6e3f66332c91e5a4c0c/maintainability" alt="Maintainability"></a>
  <img src="https://img.shields.io/circleci/build/github/chatwoot/chatwoot" alt="CircleCI Badge">
    <a href="https://hub.docker.com/r/chatwoot/chatwoot/"><img src="https://img.shields.io/docker/pulls/chatwoot/chatwoot" alt="Docker Pull Badge"></a>
  <a href="https://hub.docker.com/r/chatwoot/chatwoot/"><img src="https://img.shields.io/docker/cloud/build/chatwoot/chatwoot" alt="Docker Build Badge"></a>
  <img src="https://img.shields.io/github/commit-activity/m/chatwoot/chatwoot" alt="Commits-per-month">
  <a title="Crowdin" target="_self" href="https://chatwoot.crowdin.com/chatwoot"><img src="https://badges.crowdin.net/e/37ced7eba411064bd792feb3b7a28b16/localized.svg"></a>
  <a href="https://discord.gg/cJXdrwS"><img src="https://img.shields.io/discord/647412545203994635" alt="Discord"></a>
  <a href="https://status.chatwoot.com"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fchatwoot%2Fstatus%2Fmaster%2Fapi%2Fchatwoot%2Fuptime.json" alt="uptime"></a>
  <a href="https://status.chatwoot.com"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fchatwoot%2Fstatus%2Fmaster%2Fapi%2Fchatwoot%2Fresponse-time.json" alt="response time"></a>
  <a href="https://artifacthub.io/packages/helm/chatwoot/chatwoot"><img src="https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/artifact-hub" alt="Artifact HUB"></a>
</p>


<p>
  <a href="https://heroku.com/deploy?template=https://github.com/chatwoot/chatwoot/tree/master" alt="Deploy to Heroku">
     <img width="150" alt="Deploy" src="https://www.herokucdn.com/deploy/button.svg"/>
  </a>
  <a href="https://marketplace.digitalocean.com/apps/chatwoot?refcode=f2238426a2a8" alt="Deploy to DigitalOcean">
     <img width="200" alt="Deploy to DO" src="https://www.deploytodo.com/do-btn-blue.svg"/>
  </a>
</p>

<img src="./.github/screenshots/dashboard.png#gh-light-mode-only" width="100%" alt="Chat dashboard dark mode"/>
<img src="./.github/screenshots/dashboard-dark.png#gh-dark-mode-only" width="100%" alt="Chat dashboard"/>

---

Chatwoot is the modern, open-source, and self-hosted customer support platform designed to help businesses deliver exceptional customer support experience. Built for scale and flexibility, Chatwoot gives you full control over your customer data while providing powerful tools to manage conversations across channels.

### ✨ Captain – AI Agent for Support

Supercharge your support with Captain, Chatwoot’s AI agent. Captain helps automate responses, handle common queries, and reduce agent workload—ensuring customers get instant, accurate answers. With Captain, your team can focus on complex conversations while routine questions are resolved automatically. Read more about Captain [here](https://chwt.app/captain-docs).

### 💬 Omnichannel Support Desk

Chatwoot centralizes all customer conversations into one powerful inbox, no matter where your customers reach out from. It supports live chat on your website, email, Facebook, Instagram, Twitter, WhatsApp, Telegram, Line, SMS etc.

### 📚 Help center portal

Publish help articles, FAQs, and guides through the built-in Help Center Portal. Enable customers to find answers on their own, reduce repetitive queries, and keep your support team focused on more complex issues.

### 🗂️ Other features

#### Collaboration & Productivity

- Private Notes and @mentions for internal team discussions.
- Labels to organize and categorize conversations.
- Keyboard Shortcuts and a Command Bar for quick navigation.
- Canned Responses to reply faster to frequently asked questions.
- Auto-Assignment to route conversations based on agent availability.
- Multi-lingual Support to serve customers in multiple languages.
- Custom Views and Filters for better inbox organization.
- Business Hours and Auto-Responders to manage response expectations.
- Teams and Automation tools for scaling support workflows.
- Agent Capacity Management to balance workload across the team.

#### Customer Data & Segmentation
- Contact Management with profiles and interaction history.
- Contact Segments and Notes for targeted communication.
- Campaigns to proactively engage customers.
- Custom Attributes for storing additional customer data.
- Pre-Chat Forms to collect user information before starting conversations.

#### Integrations
- Slack Integration to manage conversations directly from Slack.
- Dialogflow Integration for chatbot automation.
- Dashboard Apps to embed internal tools within Chatwoot.
- Shopify Integration to view and manage customer orders right within Chatwoot.
- Use Google Translate to translate messages from your customers in realtime.
- Create and manage Linear tickets within Chatwoot.

#### Reports & Insights
- Live View of ongoing conversations for real-time monitoring.
- Conversation, Agent, Inbox, Label, and Team Reports for operational visibility.
- CSAT Reports to measure customer satisfaction.
- Downloadable Reports for offline analysis and reporting.


## Documentation

Detailed documentation is available at [chatwoot.com/help-center](https://www.chatwoot.com/help-center).

## Translation process

The translation process for Chatwoot web and mobile app is managed at [https://translate.chatwoot.com](https://translate.chatwoot.com) using Crowdin. Please read the [translation guide](https://www.chatwoot.com/docs/contributing/translating-chatwoot-to-your-language) for contributing to Chatwoot.

## Branching model

We use the [git-flow](https://nvie.com/posts/a-successful-git-branching-model/) branching model. The base branch is `develop`.
If you are looking for a stable version, please use the `master` or tags labelled as `v1.x.x`.

## Deployment

### Heroku one-click deploy

Deploying Chatwoot to Heroku is a breeze. It's as simple as clicking this button:

[![Deploy](https://www.herokucdn.com/deploy/button.svg)](https://heroku.com/deploy?template=https://github.com/chatwoot/chatwoot/tree/master)

Follow this [link](https://www.chatwoot.com/docs/environment-variables) to understand setting the correct environment variables for the app to work with all the features. There might be breakages if you do not set the relevant environment variables.


### DigitalOcean 1-Click Kubernetes deployment

Chatwoot now supports 1-Click deployment to DigitalOcean as a kubernetes app.

<a href="https://marketplace.digitalocean.com/apps/chatwoot?refcode=f2238426a2a8" alt="Deploy to DigitalOcean">
  <img width="200" alt="Deploy to DO" src="https://www.deploytodo.com/do-btn-blue.svg"/>
</a>

### Other deployment options

For other supported options, checkout our [deployment page](https://chatwoot.com/deploy).

## Security

Looking to report a vulnerability? Please refer our [SECURITY.md](./SECURITY.md) file.

## Community

If you need help or just want to hang out, come, say hi on our [Discord](https://discord.gg/cJXdrwS) server.

## Contributors

Thanks goes to all these [wonderful people](https://www.chatwoot.com/docs/contributors):

<a href="https://github.com/chatwoot/chatwoot/graphs/contributors"><img src="https://opencollective.com/chatwoot/contributors.svg?width=890&button=false" /></a>


*Chatwoot* &copy; 2017-2025, Chatwoot Inc - Released under the MIT License.

## Configuration

### Attachment availability (m?dias S3/CDN)
- `ATTACHMENT_AVAILABILITY_ATTEMPTS` (padr?o: 5) ? n?mero de tentativas para confirmar que o blob foi propagado no storage antes de marcar a mensagem como `sent`.
- `ATTACHMENT_AVAILABILITY_BASE_DELAY` (padr?o: 0.5 segundos) ? atraso inicial entre tentativas; usa backoff exponencial at? 8x.


# Arquitetura de conversas em grupo com Uno

## Contexto

Hoje o ViperChat ja aceita mensagens de grupos do WhatsApp vindas da Uno API, mas
a implementacao atual adapta grupos para dentro do modelo existente de conversa
um-para-um.

O comportamento atual e:

- A Uno envia um payload de webhook parecido com o WhatsApp Cloud.
- Uma mensagem de grupo e detectada quando `contacts[0].group_id` esta presente.
- O proprio grupo e armazenado como contato/contact inbox da conversa.
- O participante real e armazenado como remetente da mensagem quando disponivel.
- O conteudo de texto recebido recebe um prefixo com o nome do participante, por
  exemplo `*Maria*: hello`, para a UI antiga conseguir mostrar quem enviou a
  mensagem no grupo.

Isso funciona, mas faz o grupo parecer um contato falso e impede que a nova UI de
conversas em grupo do Chatwoot mostre membros estruturados, titulo do grupo,
contador de participantes e labels de remetente.

O objetivo e manter o comportamento existente como fallback enquanto introduzimos
um novo schema de conversas em grupo que pode ser habilitado por caixa de entrada
Uno.

## Capacidades da Uno API 3.0.61

O projeto local da Uno API em `../unoapi-cloud` esta na versao `3.0.61` e inclui
endpoints de grupos em cache.

Rotas:

```http
GET /v15.0/{phone}/groups
GET /v15.0/{phone}/groups/{groupId}/participants
```

Os endpoints estao registrados em `src/router.ts`:

```ts
router.get('/:version/:phone/groups', middleware, groupsController.list.bind(groupsController))
router.get('/:version/:phone/groups/:groupId/participants', middleware, groupsController.participants.bind(groupsController))
```

`GET /v15.0/{phone}/groups` retorna os grupos em cache para a sessao:

```json
{
  "phone": "5549988290955",
  "groups": [
    {
      "jid": "120363040468224422@g.us",
      "subject": "Equipe",
      "participantsCount": 12
    }
  ]
}
```

`GET /v15.0/{phone}/groups/{groupId}/participants` retorna os participantes do
cache do grupo:

```json
{
  "phone": "5549988290955",
  "group": {
    "jid": "120363040468224422@g.us",
    "subject": "Equipe"
  },
  "participants": [
    { "jid": "5566996269251", "name": "Fulano" },
    { "jid": "123456789012345@lid", "name": "Ciclano" }
  ]
}
```

Comportamentos importantes desses endpoints:

- `groupId` aceita tanto `1203...` quanto `1203...@g.us`.
- Participantes PN retornam apenas digitos, sem `@s.whatsapp.net`.
- Participantes LID retornam com `@lid`.
- `name` e resolvido a partir do cache de contatos da Uno, com fallback de
  mapeamento PN/LID.
- Se o grupo nao estiver em cache no Redis, a Uno retorna `404`.

Esses endpoints nao sao endpoints oficiais do Meta Graph. Eles sao endpoints de
cache Uno/Baileys expostos pelo servico da Uno API.

## Alinhamento com a documentacao oficial da Meta

A arquitetura nao deve tratar grupos como uma extensao proprietaria da Uno. O
modelo interno do Chatwoot e os endpoints da Uno devem ser desenhados para ficar
o mais proximo possivel do contrato oficial de grupos da WhatsApp Business
Platform.

Contrato oficial/compatibilidade esperada:

- Envio de mensagem para grupo usa o endpoint de envio de mensagens, mas com
  `recipient_type: "group"` em vez de `recipient_type: "individual"`.
- O campo `to` deve receber o `GROUP_ID`.
- Webhooks de mensagens recebidas em grupo trazem `messages[].group_id`.
- O campo `messages[].from` representa o participante que enviou a mensagem.
- Webhooks de status de mensagem para grupo trazem `recipient_id` com o id do
  grupo e `recipient_type: "group"`.
- Eventos de status em grupo podem ser agregados para reduzir fan-out de
  webhooks.

Isso significa que, no Chatwoot, a modelagem deve usar nomes neutros e
compativeis com o conceito oficial:

- `group_source_id` deve armazenar o `GROUP_ID` externo.
- `group_title` deve armazenar o nome/assunto do grupo quando disponivel.
- `messages.sender` deve representar o participante real.
- `conversation.group?` deve decidir a renderizacao e o envio, sem depender de o
  grupo estar disfarçado como contato.

Para a Uno, a recomendacao e expor/aceitar uma camada compativel com a Meta,
mesmo que a implementacao interna continue usando Baileys:

- aceitar payload outbound com `recipient_type: "group"` e `to: "<GROUP_ID>"`;
- emitir webhooks inbound com `messages[].group_id`;
- emitir status com `recipient_type: "group"` e `recipient_id: "<GROUP_ID>"`;
- manter endpoints extras de cache, como `/groups` e `/groups/{groupId}/participants`,
  como recursos complementares para hidratar membros, nao como o contrato
  principal de mensagem.

Com isso, o Chatwoot fica preparado para dois cenarios:

- Uno/Baileys usando contrato compativel com a Meta;
- futura troca para uma API oficial/BSP que implemente grupos sem precisar
  remodelar novamente o banco e a UI.

## Acoes oficiais de gerenciamento de grupo

A documentacao de gerenciamento de grupos cobre mais do que envio e recebimento
de mensagens. A arquitetura deve reservar espaco para essas capacidades, mesmo
que nem todas sejam implementadas no primeiro rollout.

Acoes oficiais relevantes:

- Criar grupo:
  - `POST /groups`
  - campos principais: `subject`, `description`, `join_approval_mode`;
  - ao criar o grupo, a plataforma gera um `invite_link`;
  - o telefone business usado para criar o grupo entra como criador e admin.
  - status no Chatwoot/ViperChat: fluxo desativado na UI enquanto a
    plataforma Baileys/WhatsApp nao oferecer suporte estavel; nos testes com
    UnoAPI, a chamada pode falhar com `rate-overlimit` mesmo apos normalizar
    participantes e tentar fallback de LID para phone JID.
- Criar template de convite de grupo:
  - template com `library_template_name: "group_invite_link"`;
  - usado para convidar usuarios ao grupo via mensagem aprovada.
- Solicitudes de entrada:
  - `GET /groups/{group_id}/join_requests`;
  - `POST /groups/{group_id}/join_requests` para aprovar;
  - `DELETE /groups/{group_id}/join_requests` para rejeitar;
  - `join_approval_mode` pode ser `approval_required` ou `auto_approve`.
- Link de convite:
  - `GET /groups/{group_id}/invite_link`;
  - `POST /groups/{group_id}/invite_link` para resetar o link.
- Remover participantes:
  - `DELETE /groups/{group_id}/participants`;
  - payload com `participants`;
  - limite documentado de ate 8 participantes por chamada;
  - participante removido nao consegue voltar usando o link de convite antigo.
- Buscar informacoes do grupo:
  - `GET /groups/{group_id}?fields=...`;
  - campos documentados incluem `subject`, `description`, `participants`,
    `join_approval_mode`, `suspended`, `creation_timestamp` e
    `total_participant_count`.
- Listar grupos ativos:
  - `GET /groups`;
  - suporte a paginacao por `limit`, `before` e `after`.
- Atualizar configuracoes do grupo:
  - `POST /groups/{group_id}`;
  - atualiza `subject`, `description` e foto do grupo;
  - foto deve seguir as regras de upload de midia, com JPEG, ate 5MB, quadrada e
    tamanho minimo de 192x192.
- Apagar grupo:
  - `DELETE /groups/{group_id}`;
  - remove todos os participantes, incluindo o business.

Webhooks oficiais/compativeis que devem ser refletidos no modelo:

- `group_lifecycle_update`: criacao, delecao e falhas de ciclo de vida.
- `group_participants_update`: entrada, aprovacao/remocao e mudancas de
  participantes.
- `group_settings_update`: mudancas de assunto, descricao ou foto.

Observacoes importantes:

- O contrato oficial enfatiza convite e aprovacao de entrada, nao adicao manual
  livre de participantes.
- A informacao de admin/creator aparece claramente para o numero business que
  cria o grupo, mas a lista de participantes documentada retorna `wa_id`; papel
  de admin por participante nao deve ser assumido como campo oficial sem validar
  no provedor real.
- Se a Uno/Baileys expuser campos extras de admin/role, eles podem entrar como
  metadados opcionais, mas o core do Chatwoot deve continuar alinhado ao contrato
  oficial.

## Modelo alvo no Chatwoot

O modelo alvo deve seguir a ideia nova de conversas em grupo do Chatwoot:

- `conversations.group`: marca a conversa como grupo.
- `conversations.group_source_id`: armazena o JID externo do grupo, por exemplo
  `120363040468224422@g.us`.
- `conversations.group_title`: armazena o assunto/nome do grupo.
- `group_contacts`: armazena contatos adicionais que participam do grupo.
- `messages.sender`: aponta para o contato real que enviou a mensagem.

Campos futuros opcionais, caso as acoes oficiais sejam implementadas:

- `group_description`
- `group_invite_link`
- `group_join_approval_mode`
- `group_suspended`
- `group_created_at_external`
- `group_participants_count`
- metadados opcionais por membro, como `role`/`is_admin`, apenas se o provedor
  retornar isso de forma confiavel.

Por compatibilidade, a primeira implementacao deve manter o contato falso antigo
do grupo como `conversation.contact`, em vez de permitir imediatamente
`contact_id`/`contact_inbox_id` nulos. Isso reduz risco porque muitos pontos do
codigo existente do Chatwoot ainda assumem que essas relacoes estao presentes.

## Flag de rollout

Adicionar uma flag no `provider_config` das caixas de entrada Uno:

```json
{
  "use_group_conversation_schema": true
}
```

Comportamento:

- `false` ou ausente: mantem o comportamento legado atual para grupos.
- `true`: usa o comportamento estruturado de conversas em grupo para novas
  mensagens recebidas em grupos.

O checkbox pode ficar na UI de configuracao da caixa de entrada Uno e ser
persistido em `channel_whatsapp.provider_config`.

Label sugerida:

```text
Usar novo modelo de conversas em grupo
```

Texto de ajuda sugerido:

```text
Armazena grupos como conversas estruturadas, com membros e remetente real. Use
somente com Uno API 3.0.61 ou superior.
```

## Arquitetura de entrada

### Modo legado

Manter o fluxo existente:

- `contacts[0].group_id` vira o source id do contact inbox do grupo.
- `contacts[0].group_subject` vira o nome do contato falso.
- `contacts[0].group_picture` vira o avatar do contato falso.
- O texto da mensagem recebe prefixo `*nome do remetente*:` em mensagens
  recebidas de grupo.

### Modo estruturado

Quando `use_group_conversation_schema` estiver habilitado e
`contacts[0].group_id` estiver presente:

1. Sincronizar o contato real do participante a partir de `contacts[0].wa_id`.
2. Manter o participante real como `@contact` e `@sender`.
3. Encontrar ou criar a conversa de grupo por `inbox_id + group_source_id`.
4. Definir metadados do grupo:
   - `group: true`
   - `group_source_id: contacts[0].group_id`
   - `group_title: contacts[0].group_subject || contacts[0].group_id`
5. Manter o contato/contact inbox legado do grupo como contato primario da
   conversa para compatibilidade.
6. Criar ou atualizar `group_contacts` para o contato remetente.
7. Criar a mensagem com `sender: @sender`.
8. Nao prefixar o conteudo da mensagem com `*nome do remetente*:` no modo
   estruturado.

A nova UI entao consegue renderizar nomes dos remetentes a partir de
`message.sender` e metadados do grupo a partir do JSON da conversa.

## Hidratacao de membros do grupo pela Uno

O webhook traz o remetente atual, mas nao necessariamente inclui todos os membros
do grupo. A Uno 3.0.61 pode preencher essa lacuna usando o endpoint de
participantes.

Servico sugerido:

```ruby
Whatsapp::Unoapi::GroupParticipantsSyncService
```

Entradas:

- `inbox`
- `group_source_id`
- `group_title`, opcional

Responsabilidades:

1. Montar a URL base da Uno a partir de `channel.provider_config['url']`.
2. Usar o numero da caixa de entrada como `{phone}`.
3. Chamar:

```http
GET /v15.0/{phone}/groups/{group_source_id}/participants
```

4. Para cada participante:
   - se `jid` for composto por digitos, mapear para contato/source id normal do
     WhatsApp;
   - se `jid` terminar com `@lid`, armazenar como identidade no estilo
     email/source-id, seguindo o tratamento atual de LID;
   - usar `name` quando estiver presente;
   - criar/atualizar `Contact` e `ContactInbox`;
   - criar `GroupContact`.
5. Se a Uno retornar `404`, manter a conversa de grupo e sincronizar apenas o
   remetente do webhook atual.

Gatilhos recomendados:

- Na primeira mensagem de uma nova conversa de grupo.
- Atualizacao periodica em background para conversas de grupo ativas.
- Acao manual no admin futuramente, se necessario.

Evitar chamar o endpoint de participantes da Uno em toda mensagem. Em grupos
grandes isso pode adicionar carga desnecessaria.

Politica de frescor sugerida:

- Armazenar `group_contacts_synced_at` depois, ou usar uma chave leve de cache.
- Atualizar quando nenhuma sincronizacao tiver acontecido ou quando a ultima
  sincronizacao for mais antiga que um intervalo configuravel, por exemplo 24
  horas.

## Arquitetura de saida

A logica atual de envio pode depender de `conversation.contact_inbox.source_id`
para definir o destinatario. No modo estruturado, essa nao deve ser a unica fonte
da verdade.

Para conversas em grupo:

- o destino deve ser `conversation.group_source_id`;
- o payload `to` deve ser o JID do grupo quando o envio usar o formato compativel
  com Uno Cloud;
- payloads de status/update devem usar `group_source_id` como `group_id`.

Isso evita acoplar a entrega outbound ao contato falso legado do grupo.

## Migracao historica

Conversas antigas de grupo podem ser migradas porque a implementacao antiga usava
o JID do grupo como `contact_inbox.source_id`.

Candidatos para deteccao:

```ruby
Conversation
  .joins(:contact_inbox)
  .where("contact_inboxes.source_id LIKE ?", "%@g.us")
```

Passos de backfill:

1. Marcar a conversa como `group: true`.
2. Definir `group_source_id` a partir de `conversation.contact_inbox.source_id`.
3. Definir `group_title` a partir de `conversation.contact.name`.
4. Criar `group_contacts` a partir dos contatos distintos em `messages.sender`.
5. Opcionalmente chamar o endpoint de participantes da Uno para enriquecer a
   lista completa de membros.
6. Manter `contact_id` e `contact_inbox_id` existentes por compatibilidade.
7. Nao reescrever o conteudo das mensagens antigas na primeira migracao.

Mensagens antigas ainda podem conter prefixos `*Nome*:`. Isso e aceitavel no
primeiro rollout. Uma limpeza posterior pode normalizar o historico se a UI
precisar.

## Mudancas de banco

Schema minimo necessario:

```ruby
add_column :conversations, :group, :boolean, default: false, null: false
add_column :conversations, :group_source_id, :string
add_column :conversations, :group_title, :string
add_index :conversations, :group
add_index :conversations, [:inbox_id, :group_source_id],
          unique: true,
          where: "group_source_id IS NOT NULL"
```

Nova tabela:

```ruby
create_table :group_contacts do |t|
  t.references :account, null: false, foreign_key: true
  t.references :conversation, null: false, foreign_key: true
  t.references :contact, null: false, foreign_key: true
  t.timestamps
end

add_index :group_contacts, [:conversation_id, :contact_id], unique: true
```

Nota de implementacao:

- Nao editar migrations antigas.
- Adicionar novas migrations usando timestamp atual do fork.
- Manter `contact_id` e `contact_inbox_id` obrigatorios no rollout inicial, a
  menos que todos os pontos sensiveis a nil sejam auditados.

## Formato da API/frontend

Respostas de conversa devem incluir:

```json
{
  "group": true,
  "group_title": "Equipe",
  "group_source_id": "120363040468224422@g.us",
  "group_contacts": [
    {
      "id": 1,
      "contact_id": 10,
      "contact": {
        "id": 10,
        "name": "Fulano",
        "thumbnail": "..."
      }
    }
  ]
}
```

Por performance, evitar embutir todos os membros de grupos grandes em toda
resposta de lista de conversas. Preferir:

- `group_contacts_count` nos payloads de lista/detalhe;
- primeiros membros para preview da sidebar;
- endpoint `/group_contacts` paginado para a lista completa de membros.

## Fases de implementacao

## Matriz de responsabilidades

Esta matriz separa o que a Uno precisa entregar, o que o Chatwoot precisa
implementar e quais pontos devem seguir contrato Meta-like para permitir trocar
ou adicionar um canal oficial no futuro.

### Uno API

A Uno deve expor uma camada de API/webhook compativel com a semantica oficial da
Meta, mesmo que internamente use Baileys.

Obrigatorio para a nova UI funcionar bem:

- Emitir webhooks inbound de grupo no formato Meta-like:
  - `object: "whatsapp_business_account"`;
  - `entry[].changes[].field: "messages"`;
  - `value.metadata.display_phone_number`;
  - `value.metadata.phone_number_id`;
  - `value.contacts[0].wa_id` com o participante real;
  - `value.contacts[0].profile.name`;
  - `value.contacts[0].profile.picture`, quando disponivel;
  - `value.messages[0].from` com o participante real;
  - `value.messages[0].group_id` com o id externo do grupo;
  - `value.messages[0].id`;
  - `value.messages[0].timestamp`;
  - `value.messages[0].type`;
  - conteudo especifico por tipo, como `text.body`.
- Emitir metadados de grupo no webhook quando disponivel:
  - `group_subject` ou campo equivalente mapeavel para `group_title`;
  - `group_picture`, quando disponivel;
  - manter `group_id` como identificador estavel do grupo.
- Aceitar envio outbound Meta-like para grupos:
  - `POST /v15.0/{phone}/messages`;
  - `recipient_type: "group"`;
  - `to: "<GROUP_ID>"`;
  - `type` e corpo seguindo o formato de mensagens suportadas.
- Emitir status outbound Meta-like para grupos:
  - `statuses[].recipient_id: "<GROUP_ID>"`;
  - `statuses[].recipient_type: "group"`;
  - `statuses[].id`;
  - `statuses[].status`;
  - `statuses[].timestamp`;
  - `statuses[].errors`, quando falhar.
- Manter endpoints de cache/hidratacao de grupos:
  - `GET /v15.0/{phone}/groups`;
  - `GET /v15.0/{phone}/groups/{groupId}/participants`;
  - `groupId` aceitando com ou sem `@g.us`;
  - resposta de participante com `jid` e `name`;
  - `404` quando o grupo nao estiver em cache.

Recomendado para aproximar do contrato oficial de gerenciamento:

- `GET /groups` para listar grupos ativos em formato Meta-like, com paginacao.
- `GET /groups/{group_id}?fields=...` para retornar:
  - `id`;
  - `subject`;
  - `description`;
  - `participants`;
  - `total_participant_count`;
  - `join_approval_mode`;
  - `suspended`;
  - `creation_timestamp`.
- `GET /groups/{group_id}/invite_link`.
- `POST /groups/{group_id}/invite_link` para resetar link.
- `DELETE /groups/{group_id}/participants` para remover membros.
- `POST /groups/{group_id}` para atualizar assunto, descricao e foto.
- Webhooks Meta-like:
  - `group_lifecycle_update`;
  - `group_participants_update`;
  - `group_settings_update`.

Opcional/futuro:

- `POST /groups` para criar grupo.
- `GET/POST/DELETE /groups/{group_id}/join_requests`.
- Template `group_invite_link`.
- Campos extras de Baileys como `is_admin`, `role`, `lid`, `pn`, desde que
  venham como metadados opcionais e nao substituam o contrato principal.

### Chatwoot backend

O Chatwoot deve transformar o contrato Meta-like em um modelo interno de grupo,
sem depender de detalhes exclusivos da Uno.

Obrigatorio para a nova UI:

- Criar migrations novas:
  - `conversations.group`;
  - `conversations.group_source_id`;
  - `conversations.group_title`;
  - tabela `group_contacts`;
  - indice unico por `inbox_id + group_source_id`;
  - indice unico por `conversation_id + contact_id`.
- Criar modelos/associacoes:
  - `Conversation#group?`;
  - `Conversation#group_contacts`;
  - `Conversation#additional_contacts`;
  - `GroupContact`;
  - validacao de mesma conta;
  - evitar duplicidade de membros.
- Adicionar flag por inbox:
  - `channel.provider_config['use_group_conversation_schema']`.
- Adaptar inbound WhatsApp/Uno:
  - detectar `messages[0].group_id`;
  - criar/encontrar conversa por `inbox_id + group_source_id`;
  - preencher `group`, `group_source_id`, `group_title`;
  - manter contato fake legado como contato primario inicialmente;
  - gravar o participante real como `message.sender`;
  - criar/atualizar `group_contacts` para o remetente;
  - parar de prefixar `*Nome*:` em mensagens novas no modo estruturado.
- Criar service/job de hidratacao de membros:
  - chamar Uno `GET /v15.0/{phone}/groups/{groupId}/participants`;
  - criar/atualizar `Contact`, `ContactInbox` e `GroupContact`;
  - tratar `404` como cache miss;
  - evitar chamada a cada mensagem;
  - controlar frescor por cache ou campo futuro.
- Adaptar outbound:
  - se `conversation.group?`, enviar para `conversation.group_source_id`;
  - usar `recipient_type: "group"`;
  - manter caminho legado quando a flag estiver desligada.
- Adaptar status inbound:
  - aceitar `recipient_type: "group"`;
  - localizar conversa por `group_source_id`;
  - atualizar mensagem por `source_id`;
  - tratar status agregado sem gerar duplicidade.
- Expor API/JSON para frontend:
  - `group`;
  - `group_title`;
  - `group_source_id`;
  - `group_contacts_count`;
  - preview de poucos membros;
  - endpoint paginado de membros.

Recomendado para compatibilidade futura:

- Criar uma camada de normalizacao independente do provider:
  - `Whatsapp::GroupPayloadNormalizer`, por exemplo;
  - entrada Uno, WhatsApp Cloud oficial ou BSP;
  - saida interna padronizada para conversa/mensagem/grupo.
- Evitar nomes de campo no banco que sejam Uno-specific.
- Nao editar migrations antigas.
- Manter `contact_id` e `contact_inbox_id` obrigatorios no primeiro rollout.
- Criar pontos de extensao para providers que suportem gerenciamento oficial de
  grupos.

Opcional/futuro:

- API interna para:
  - listar participantes;
  - atualizar assunto/descricao/foto;
  - remover participante;
  - buscar/resetar link de convite;
  - aprovar/rejeitar entrada;
  - sincronizar grupo manualmente.
- Guardar campos extras:
  - `group_description`;
  - `group_invite_link`;
  - `group_join_approval_mode`;
  - `group_suspended`;
  - `group_created_at_external`;
  - metadados por membro.

### Chatwoot frontend

Obrigatorio para a nova UI:

- Usar `conversation.group === true` para trocar visual de conversa individual
  para grupo.
- Mostrar `group_title` no card e cabecalho.
- Mostrar icone/avatar de grupo.
- Mostrar `group_contacts_count`.
- Mostrar nome do remetente da mensagem usando `message.sender`, sem depender de
  prefixo textual.
- Criar/usar painel de grupo:
  - preview dos primeiros membros;
  - lista paginada;
  - busca local ou remota;
  - indicacao do contato primario legado apenas se necessario.
- Adicionar traducoes `en` e `pt_BR` no mesmo commit.

Recomendado:

- Nao carregar todos os membros na lista de conversas.
- Usar endpoint paginado para modal/lista completa.
- Mostrar estados de cache:
  - carregando membros;
  - membros indisponiveis;
  - sincronizacao recente/pendente, se exposto pelo backend.

Opcional/futuro:

- UI de gerenciamento:
  - atualizar titulo/descricao/foto;
  - copiar/resetar link de convite;
  - remover participante;
  - aprovar/rejeitar solicitacoes;
  - sincronizar participantes manualmente.

### Migracao e rollout

Obrigatorio:

- Migration/backfill para conversas antigas cujo `contact_inbox.source_id`
  termina com `@g.us`.
- Preencher:
  - `group: true`;
  - `group_source_id`;
  - `group_title`;
  - `group_contacts` a partir de `messages.sender`.
- Nao reescrever conteudo antigo no primeiro rollout.
- Ativar o novo modo por flag, caixa por caixa.
- Manter fallback legado.

Recomendado:

- Job opcional para enriquecer historico com participantes vindos da Uno.
- Logs especificos para:
  - grupo estruturado criado;
  - participante sincronizado;
  - cache miss da Uno;
  - status de grupo recebido;
  - fallback para modo legado.

### Contrato minimo de compatibilidade futura

Para o Chatwoot poder usar Uno hoje e WhatsApp Cloud/BSP oficial no futuro, este
e o contrato minimo que qualquer provider deve entregar:

Inbound:

```json
{
  "messages": [
    {
      "id": "wamid...",
      "from": "556699999999",
      "group_id": "120363040468224422@g.us",
      "timestamp": "1710000000",
      "type": "text",
      "text": { "body": "Mensagem" }
    }
  ],
  "contacts": [
    {
      "wa_id": "556699999999",
      "profile": {
        "name": "Maria",
        "picture": "https://..."
      }
    }
  ],
  "metadata": {
    "display_phone_number": "556600000000",
    "phone_number_id": "123"
  }
}
```

Outbound:

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "group",
  "to": "120363040468224422@g.us",
  "type": "text",
  "text": {
    "body": "Mensagem"
  }
}
```

Status:

```json
{
  "statuses": [
    {
      "id": "wamid...",
      "recipient_id": "120363040468224422@g.us",
      "recipient_type": "group",
      "status": "delivered",
      "timestamp": "1710000000"
    }
  ]
}
```

### Fase 1 - Modelo de dados e compatibilidade

- Adicionar campos `group` em conversations.
- Adicionar `group_contacts`.
- Adicionar validacoes de modelo.
- Adicionar campos no JSON da conversa com contador/preview, nao dump completo
  de membros.
- Adicionar flag de `provider_config` para Uno.

### Fase 2 - Modo estruturado no inbound da Uno

- Adicionar bifurcacao no servico de entrada WhatsApp/Uno.
- No modo estruturado, criar/encontrar conversa por id do grupo.
- Armazenar remetente como contato real.
- Parar de prefixar nome do remetente nas novas mensagens estruturadas de grupo.
- Sincronizar remetente atual em `group_contacts`.

### Fase 3 - Sincronizacao de participantes da Uno

- Adicionar metodo no cliente Uno para `GET /groups/{groupId}/participants`.
- Adicionar job/servico em background para hidratar membros.
- Executar na primeira mensagem do grupo e em atualizacao periodica.
- Tratar `404` como cache miss, nao como falha dura.

### Fase 4 - Envio outbound para grupo

- Enviar para `conversation.group_source_id` quando `conversation.group?`.
- Manter caminho de envio legado quando a flag estiver desligada.
- Validar caminhos de texto, anexo, reaction/status update.

### Fase 5 - Migracao historica

- Fazer backfill das conversas antigas `@g.us` para metadados estruturados de
  grupo.
- Criar `group_contacts` a partir dos remetentes historicos das mensagens.
- Opcionalmente enriquecer usando endpoint de participantes da Uno.
- Manter contato falso legado do grupo por compatibilidade.

### Fase 6 - Integracao de UI

- Mostrar titulo/icone/contador do grupo na lista e no cabecalho da conversa.
- Mostrar nome estruturado do remetente nos bubbles de mensagem.
- Adicionar painel de informacoes do grupo com participantes paginados.
- Adicionar traducoes `pt_BR` junto com `en`.

## Riscos e mitigacoes

- **Regressoes por contact/contact inbox nil**: manter contato primario legado no
  rollout inicial.
- **Payloads grandes de grupo**: evitar embutir todos os participantes em toda
  resposta de conversa.
- **Cache miss da Uno**: tratar `404` do endpoint de participantes como falha
  suave.
- **Divergencia de identidade LID/PN**: preservar o `jid` retornado pela Uno;
  normalizar digitos PN, mas manter LID quando nao houver mapeamento PN.
- **Membros duplicados**: impor indice unico em
  `group_contacts(conversation_id, contact_id)`.
- **Mensagens antigas com prefixo de nome**: manter inalteradas na migracao
  inicial.
- **Warnings de traducao**: adicionar chaves `pt_BR` no mesmo commit das chaves
  de UI.

## Decisoes em aberto

- `group_contacts` deve incluir o contato falso legado do grupo? Resposta
  proposta: nao, apenas participantes reais.
- Mensagens historicas devem ser limpas para remover prefixos `*Nome*:`?
  Resposta proposta: nao no primeiro rollout.
- A sincronizacao de membros deve ser somente automatica, ou a UI admin deve
  expor uma atualizacao manual? Resposta proposta: automatica primeiro, manual
  depois se a operacao precisar.
- Devemos introduzir `group_contacts_synced_at` agora? Resposta proposta: apenas
  se o job inicial de sincronizacao precisar de um marcador de frescor no banco;
  caso contrario, usar uma chave de cache primeiro.

# VoIP: contrato de webhooks recebidos pelo ViperChat — v1 em dev

22/10/2026 — America/Cuiaba. **Contrato v1 em desenvolvimento:** autenticação por `api_access_token` de administrador; serviço VoIP entrega por RabbitMQ com outbox e retentativas. Cadastro por empresa, restrito aos ramais vinculados; gravação e IA podem usar esse mesmo caminho, sem envio legado simultâneo. As seções 8–11 especificam todas as opções e a evolução de artefatos. Não confundir código/testes com publicação, implantação na VPS ou aceite nativo em segundo plano.

## 1. Responsabilidades e fluxo

```text
Centrais legadas → responsável pela central transforma AMI/CEL/CDR em nosso contrato
Nosso serviço   → produz o mesmo contrato a partir dos estados e registros reais
                                      ↓ HTTPS + api_access_token
                                ViperChat recebe
                           inbox persistente → processamento
                             histórico próprio + notificações

Nosso serviço → REST existente com modo incremental → recuperação de falhas
```

- O ViperChat não se conecta à AMI nem ao banco das centrais legadas. Não exige schema, usuário SQL, parser de dialplan ou instalação de conector pela nossa equipe.
- O dono/integrador da central escolhe como produzir e entregar os eventos: AMI, CEL, CDR ou funcionalidades existentes da sua instalação. AMI/CEL/CDR são fontes internas dele, não três endpoints distintos exigidos pelo ViperChat.
- Não exigir que nosso serviço emule Asterisk/AMI apenas para esta integração; preservar seu motor SIP/WebRTC e bridge Zapo.
- SIP/WebRTC continua sendo o transporte da chamada/áudio; receber um webhook não origina, transfere ou encerra uma chamada na central.

## 2. Cadastro administrativo no ViperChat

- Endpoint: `POST /api/v1/accounts/:account_id/voip/services/:service_id/events`. Reutilizar a autenticação de API do ViperChat, exigir token explícito pertencente a `User` administrador da conta da URL, API da conta habilitada e serviço encontrado dentro dessa conta. Bot, usuário agente, token inválido e sessão de browser sem token não podem gravar eventos.
- Cabeçalhos obrigatórios: `api_access_token: <token-do-usuario-admin>` e `Content-Type: application/json`. **Não usar `Authorization: Bearer` neste endpoint.** HTTPS obrigatório na entrega; loopback HTTP permitido exclusivamente em dev/teste controlado.
- Preferir usuário técnico administrador dedicado. O token tem os poderes administrativos do usuário: armazenar somente no produtor autorizado, nunca em RabbitMQ, payload, logs ou resposta da configuração. Revogação/rotação seguem o token de usuário já existente; não criar token paralelo/HMAC obrigatório nesta versão.
- Cadastro ViperChat usa `integration_provider` (`none`, `webhook`, `viperconnect`) e `webhook_source_instance_id` persistente para vincular a origem. Retornar URL específica para o serviço existente; novo cadastro precisa salvar antes de obter seu ID/URL. Não devolver o token do usuário no formulário.
- Cadastro do produtor fica na **empresa**, em `viperchatWebhook`: `enabled`, `baseUrl`, `accountId`, `serviceId`, `sourceInstanceId`, `apiAccessToken` e `artifactsDelivery` (`legacy` ou `webhook`). Somente participações de ramais comprovadamente vinculados à empresa podem sair por seu webhook. Token omitido/branco preserva; remoção é explícita. Não inferir acesso de notas legadas nem escolher uma linha como fallback para chamada interna sem linha.
- URL HTTPS base/token REST do nosso serviço permanecem para recuperação no sentido inverso; essa consulta continua usando `Authorization: Bearer <token-do-servico-voip>`. Não confundir com `api_access_token` recebido pelo ViperChat ou senha SIP do agente.
- Retirar host/porta/usuário AMI do formulário final desta arquitetura. Não há configuração de banco legado. O formulário direto AMI recém-construído é trabalho anterior ainda não publicado, não o cadastro final aprovado.
- Identidade de conta/serviço vem da integração confiável cadastrada, nunca de um `account_id` livre informado pelo remetente.

## 3. Envelope comum proposto

Campos obrigatórios: `schema_version`, `event_id`, `event_type`, `occurred_at`, `source_instance_id`, `call_id`, `revision` e snapshot normalizado de `call`/`participants` pertinente ao evento.

| Campo | Regra v1 |
| --- | --- |
| `schema_version` | Inteiro `1`. |
| `event_id` | String estável de 1–200 caracteres, única por origem/serviço; UUID ou hash técnico. |
| `event_type` | Um dos tipos listados abaixo, não nome AMI arbitrário. |
| `occurred_at` | ISO 8601 em UTC, terminado em `Z` ou `+00:00`. Horário da mudança na origem, não da tentativa HTTP. |
| `source_instance_id` | String estável, igual à origem configurada no serviço; não muda após restart. |
| `call_id` | String técnica estável e namespaced de 1–200 caracteres, sem deduplicar só pelo telefone. |
| `revision` | Inteiro positivo crescente por ligação; não reiniciar após restart. |
| `call.direction` | `inbound`, `outbound` ou `internal`. |
| `call.state` | `routing`, `ringing`, `active`, `completed`, `missed`, `failed` ou `cancelled`. |
| `call.started_at` | ISO 8601; `answered_at`/`ended_at` opcionais quando confirmados. |
| `call.from` / `call.to` | Opcionais: `{kind: phone|extension|unknown, value: string, name?: string}`. |
| `call.participants` | Array de no máximo 100 participações com `id` estável, `extension` quando conhecido, `state`, tempos opcionais e `sip_call_id` exato quando disponível. |
| `call.recording` | Opcional: `{status, record_id}`; sem bytes de áudio, senha, path local ou credencial S3. |
| `call.artifacts` | Opcional: gravação, IA e destino privado comprovado; especificação fechada na seção 9. |

Estados de participação: `offered`, `ringing`, `active`, `completed`, `missed`, `failed`, `cancelled`, `answered_elsewhere`. IDs/SIP IDs não são números de telefone. O contrato precisa preservar diferenças de legs e ramais; `sip_call_id` permite associar uma observação do webphone existente sem recriar seu ID.

Schema fechado: somente os campos documentados são aceitos, inclusive nos objetos aninhados. `call.end_reason` é opcional (até 128 caracteres). `recording.status`: `disabled`, `recording`, `processing`, `available` ou `failed`; `record_id` obrigatório nesse objeto. Tempos opcionais seguem a mesma regra UTC. `phone` exige 10–15 dígitos com `+` opcional; ramais usam `extension` e identificadores não comprovados usam `unknown`. Não incluir `account_id`, tokens, URLs assinadas ou áudio no corpo.

Exemplo sintético de atendimento (nenhum token real):

```json
{
  "schema_version": 1,
  "event_id": "evt-lab-0003",
  "event_type": "participant.answered",
  "occurred_at": "2026-10-22T16:00:05Z",
  "source_instance_id": "central-lab",
  "call_id": "central-lab:call-001",
  "revision": 3,
  "call": {
    "direction": "internal",
    "state": "active",
    "started_at": "2026-10-22T16:00:00Z",
    "answered_at": "2026-10-22T16:00:05Z",
    "from": {"kind": "extension", "value": "1001"},
    "to": {"kind": "extension", "value": "1002"},
    "participants": [
      {"id": "leg-1001", "extension": "1001", "state": "active", "sip_call_id": "sip-leg-1001"},
      {"id": "leg-1002", "extension": "1002", "state": "active", "sip_call_id": "sip-leg-1002"}
    ]
  }
}
```

- `event_id` imutável em toda retentativa; revisão crescente por ligação e identidade persistente entre reinícios do produtor. Não gerar novo ID por tentativa HTTP.
- IDs da central, SIP Call-ID por leg, IDs de participantes e relações de transferência entram como referências técnicas explícitas. Não associar pessoas/chamadas por semelhança de texto, nome ou proximidade temporal.
- Snapshot inclui direção, origem/destino, ramais oferecidos/participantes, estado global, resultado por participante, tempos reais e motivos brutos/normalizados disponíveis. Campos desconhecidos ficam ausentes/nulos, sem inventar atendimento ou duração.
- Eventos: `call.created`, `call.ringing`, `participant.answered`, `participant.released`, `call.transferred`, `call.ended`, `call.updated`, `recording.updated` e `call.artifacts.updated`. Sem áudio/base64 no JSON. O evento de artefatos solicita processamento privado e obtenção autenticada da mídia quando disponível, conforme seção 9.
- Revisão e sequência servem para rejeitar atualização obsoleta, não para transformar canal desligado em fim de toda ligação. URA atendida não equivale a agente atendendo; transferência conserva participantes anteriores.
- Payloads de CDR apenas finais podem consolidar histórico, mas não habilitam alerta de chamada recebida ao vivo. Capacidades de tempo real, participantes, histórico e recuperação precisam ser declaradas separadamente.
- Mapear mensagens para registros atuais com IDs preservados; a implementação aditiva da ligação autoritativa/participantes não deve forçar agente fictício nem recriar `VoipCall` existente.

## 4. Segurança, durabilidade e retentativas

- HTTPS e token no cabeçalho, com autenticação e autorização completas em cada entrega, inclusive duplicadas. Token de admin não autoriza acessar outra conta à qual esse usuário não pertence como administrador. Não aceitar token em query string ou body.
- Corpo limitado a 256 KiB e strings/arrays validados; o produtor deve enviar snapshot completo pertinente à revisão. Reenvio conserva `event_id` e conteúdo lógico; guardar fingerprint canônico, independente da ordem de chaves JSON.
- Receber e validar → gravar inbox durável → responder **202 `{event_id,status:"accepted"}`**. Duplicata idêntica: **200 `{event_id,status:"duplicate"}`**. Mesmo ID/revisão com conteúdo divergente: **409**, sem sobrescrever. Aceite HTTP não significa histórico/UI atualizado.
- **401** token ausente/inválido; **403** usuário sem autorização/API desabilitada; **404** serviço fora do escopo/inexistente; **413** corpo excedido; **422** schema/origem/serviço inválido; **429** limite temporário; **5xx** falha temporária de recepção. Sem `202` antes do commit da inbox. Respostas não incluem segredos ou payload completo.
- Enfileirar após commit e recuperar inbox persistida que ficou sem job após crash. Processar por ligação com ordenação/revisão e isolamento de conta/serviço, emitindo atualização autorizada da UI após persistência.
- Produtor mantém outbox persistente na mesma transação do estado/journal quando estiverem no mesmo banco. Backoff com jitter, timeout, próxima tentativa e último resultado; rede/429/5xx retentam, respeitando Retry-After. Autenticação/schema inválidos ficam sinalizados/quarentenados, sem loop infinito.
- A implementação do responsável pela central precisa cumprir essas garantias se quiser entrega confiável. Um POST disparado sem persistência não ganha recuperação apenas porque o ViperChat possui inbox.
- Sem segredos, corpos completos ou URLs de gravação assinadas em logs. Credenciais REST administrativas nunca chegam ao browser. Rejeitar redirects e aplicar política SSRF no cliente REST.

### RabbitMQ no nosso serviço

1. Registrar mudança e outbox local na mesma transação SQLite. Produtor formata o contrato v1 antes da entrega, sem depender do browser.
2. Publicar job **somente com ID da outbox** numa fila/exchange exclusiva (prefixo padrão `viperconnect.voip.webhooks`), com mensagem persistente e publisher confirm. Nunca colocar token ou corpo completo no job RabbitMQ.
3. Consumidor com prefetch limitado e ACK manual obtém a outbox/configuração atual, valida que o destino continua sendo a mesma instalação/conta/serviço e faz POST com `api_access_token`.
4. Em 200/202 com recibo correspondente, marcar entregue e ACK. Resposta perdida pode gerar repetição idempotente, não entrega exatamente uma vez.
5. Rede, timeout, 429 e 5xx: próxima tentativa persistida, backoff limitado com jitter e Retry-After quando válido; republicação de retry confirmada antes do ACK original. Falha de publicar não consome/apaga o job original.
6. Erros permanentes ou limite de tentativas: registrar erro sanitizado e fila `.dead`. Nunca disparar mensagem real WhatsApp ao cliente com payload/segredos para avisar falha.
7. Outbox recupera crash antes/depois de publicação e broker indisponível. Confirm RabbitMQ não equivale a aceite HTTP. Mudança de destino pausa/quarentena pendências, sem entregá-las a outro cliente; rotação do token da mesma integração não altera o evento.
8. Reaproveitar as estratégias verificadas no ViperConnect (`src/amqp.ts` e `services/amqp_confirmed_publish.ts`): filas duráveis, publicação confirmada/mandatory, ACK manual e ACK somente após retry/dead confirmado. Não copiar seus logs de erro completos nem compartilhar fila de mensagens de WhatsApp. Desenvolvimento usa o RabbitMQ existente, sem criar container.

## 5. Recuperação de falhas e limites

- Nosso serviço reutiliza `GET /v1/console/history?sync=changes&cursor=...&limit=100`: snapshot inicial e alterações persistidas por cursor, conforme o bloco já iniciado em dev. A rota paginada anterior e a rota de gravação por ID permanecem.
- Implementado em dev: webhook e REST passam pelo mesmo reconciliador usando exatamente o envelope canônico persistido pelo produtor. Checkpoint REST avança somente na mesma transação que persiste a página na inbox; webhook isolado não avança cursor. Job periódico a cada minuto, lease e cursor criptografados permitem retomada após reinício. Replay não repete ação SIP nem toque de ligação encerrada. Ver seção 12.
- O feed entrega snapshots completos das alterações de CDR retidas; journal e outbox são persistentes. Participações observadas no SIP/UDP e SIP/WebRTC incluem Call-ID real e preservam legs anteriores em transferência. Não é uma exportação raw CEL nem uma emulação de Asterisk.
- Para legadas, recuperação depende de outbox/reenvio ou API oferecidos pelo integrador. Sem acesso SQL pelo ViperChat, sem API e sem outbox, eventos perdidos no produtor permanecem uma lacuna explícita.
- Se o produtor coletar AMI e perder sua conexão com o Asterisk, o webhook não reconstrói eventos que ele nunca recebeu. Ele precisa recuperar localmente por meios autorizados ou informar intervalo sem cobertura. Browser fechado com backend conectado é cenário diferente de produtor offline.
- Cursor expirado/escopo alterado exige snapshot e reconciliação sem apagar histórico. Definir retenção e dimensionamento com cada produtor.

## 6. Web e nativos

O backend recebe e grava mesmo com navegador/app fechados. Eventos ao vivo válidos podem alimentar notificações web e push; sincronização histórica pode atualizar o histórico sem simular nova chamada.

Receber e atender em segundo plano continua exigindo PushKit/CallKit no iOS, telefonia nativa Android, oferta expirada/cancelada e entrega SIP após despertar. Webhook por si só não mantém ramal registrado nem garante chamada disponível. O responsável pela central precisa declarar essa capacidade separadamente.

## 7. Implementação e validação desta entrega

- Preservar o modo incremental da rota REST existente do serviço e o cliente HTTP protegido no ViperChat: continuam úteis na arquitetura revisada.
- Cadastro final substitui os campos AMI por webhook externo/ViperConnect, origem estável, URL específica e REST opcional. Credenciais antigas permanecem protegidas, sem reaproveitamento silencioso.
- ViperChat: autenticação de admin, inbox durável, replay/revisão, recuperação de jobs e ligação canônica. Projeção no histórico por agente exige SIP Call-ID exato e vínculo único; sem essa prova, guardar a ligação canônica sem adivinhar agente/chamada. Atualização ActionCable autorizada recarrega lista/detalhe sem F5 e sem disparar chamada/toque.
- `last_observed_at` usa o horário do evento limitado ao relógio atual: evento antigo reenviado não finge chamada ao vivo; relógio futuro não mantém chamada indefinidamente.
- Serviço: outbox SQLite atômica, confirmação RabbitMQ, ACK manual, filas de retry/dead, reconexão e erros sanitizados. Cadastro no Manager movido de linha para empresa; configuração legada de linhas preservada para compatibilidade, mas não reaproveitada silenciosamente. O modo webhook de artefatos substitui os dois publicadores antigos (gravação e nota de IA), mantendo a geração/armazenamento de IA.
- Validação: 78 exemplos Ruby e 126 testes frontend sem falhas; 19 arquivos RuboCop limpos e ESLint dos acréscimos sem erros (avisos existentes de UI/i18n). Serviço: 220 testes, 219 aprovados e um skip pré-existente por ffmpeg indisponível; typecheck/build aprovados. Teste integrado real no RabbitMQ existente + Rails isolado: 503 seguido de retry, três eventos aceitos, repetição com 200 e uma chamada encerrada com o mesmo ID desde o ringing.
- Formulário responsivo verificado por imagens 320/360/390/412/430/1280 px em harness real de componentes; não equivale ao aceite nativo. Evidências completas em `output/validation/voip-webhook-receiver-20261022.md` e `voip-webhook-form-20261022.md`.
- Ainda pendentes: aceite com chamadas reais pelo operador, homologação de envio por central legada, ensaio de indisponibilidade prolongada e push/CallKit/Telecom em segundo plano. Recuperação REST/checkpoint e falhas sintéticas de transporte já têm implementação/aceite dev; não confundir isso com cobertura nativa em segundo plano.
- A ativação dev posterior desta implementação está sendo validada na réplica existente, com backup antes das migrations. O envio de artefatos e o vínculo por empresa têm aceite próprio; números históricos de testes acima referem-se ao bloco inicial. Sem VPS, publicação ou commit/push por esta documentação.

## 8. Referência completa de campos e opções

### Cadastro da empresa no produtor

Manager: **Telefonia → Empresas → Editar → Eventos de chamadas no ViperChat**.
A API administrativa existente recebe `viperchatWebhook` dentro da empresa.

| Campo | Tipo / regra |
| --- | --- |
| `enabled` | Booleano; padrão `false`; habilita eventos dos ramais da empresa. |
| `baseUrl` | URL base HTTPS da instalação; sem credenciais, query ou fragmento, não o endpoint completo. HTTP somente loopback dev/teste. |
| `accountId` | String com inteiro positivo: conta no ViperChat. Não é o ID da empresa local. |
| `serviceId` | String com inteiro positivo: serviço VoIP daquela conta. |
| `sourceInstanceId` | Identidade estável até 200 caracteres, igual ao serviço no destino. |
| `apiAccessToken` | Token admin ViperChat somente de escrita; omitido/vazio preserva valor existente. |
| `clearApiAccessToken` | Comando de edição booleano; remoção explícita, com envio desativado. Não entra no evento. |
| `hasApiAccessToken` | Flag somente de leitura; nunca devolve o segredo. |
| `activatedAt` | Horário de ativação mantido pelo servidor; não fabricar/reiniciar no cliente. |
| `artifactsDelivery` | `legacy` (compatibilidade, padrão) ou `webhook` (processador ViperChat). Selecionar `webhook` exige integração habilitada. Nunca executar ambos os envios de nota para a mesma empresa. |

Exemplo de configuração, não de evento:

```json
{
  "viperchatWebhook": {
    "enabled": true,
    "baseUrl": "https://chat.exemplo.com.br",
    "accountId": "1",
    "serviceId": "206",
    "sourceInstanceId": "central-empresa-a",
    "apiAccessToken": "<TOKEN_ADMIN_VIPERCHAT>",
    "artifactsDelivery": "webhook"
  }
}
```

Credenciais antigas por linha não são unidas automaticamente. A mudança não
apaga `chatwootRecording`, tokens, caixas ou histórico. O caminho antigo fica
**inativo efetivamente** enquanto o modo webhook estiver selecionado, inclusive
para jobs legados já enfileirados e publicação de IA. Não usar fallback legado
em caso de erro do webhook, pois ele causaria duplicação. Voltar ao modo legado
é decisão explícita; pendências de outro destino exigem avaliação separada.

### Envelope e snapshot

| Campo | Obrigatório | Tipo / limite |
| --- | --- | --- |
| `schema_version` | Sim | Inteiro exatamente `1`, não string ou booleano. |
| `event_id` | Sim | String não vazia, até 200 caracteres, sem controles. |
| `event_type` | Sim | Uma das nove opções da seção 10. |
| `occurred_at` | Sim | ISO 8601 UTC com `Z` ou `+00:00`, até 40 caracteres. |
| `source_instance_id` | Sim | String não vazia até 200; deve coincidir com cadastro. |
| `call_id` | Sim | String técnica estável até 200; não é telefone. |
| `revision` | Sim | Inteiro de 1 a 9223372036854775807, crescente por chamada; lacunas permitidas. |
| `call` | Sim | Objeto fechado com os campos a seguir. |
| `call.direction` | Sim | `inbound`, `outbound`, `internal`. |
| `call.state` | Sim | `routing`, `ringing`, `active`, `completed`, `missed`, `failed`, `cancelled`. |
| `call.started_at` | Sim | ISO UTC real de início. |
| `call.answered_at` | Não | ISO UTC de atendimento comprovado, não inferido pela URA. |
| `call.ended_at` | Não | ISO UTC de encerramento comprovado. |
| `call.end_reason` | Não | String técnica não vazia até 128; sem enum fechado. |
| `call.from`, `call.to` | Não | Objetos de endereço abaixo; não determinam o tenant. |
| `call.participants` | Sim | Array com 0–100 participações, IDs únicos; vazio quando não há prova. |
| `call.recording` | Não | Objeto fechado com `status` e `record_id`, conforme contrato inicial. |
| `call.artifacts` | Não | Objeto fechado definido na seção 9. |

Campos opcionais desconhecidos devem ser omitidos. Não enviar propriedades
extras; `null` não substitui obrigatórios. Strings técnicas não aceitam controles.

| Endereço `from`/`to` | Obrigatório no objeto | Regra |
| --- | --- | --- |
| `kind` | Sim | `phone`, `extension`, `unknown`. |
| `value` | Sim | String 1–128; `phone` exige 10–15 dígitos com `+` inicial opcional. |
| `name` | Não | String 1–128 de apresentação, nunca chave de correlação. |

Ramal conserva zeros à esquerda, sem regra de nono dígito. LID/JID não é
telefone: usar `unknown`, sem extrair seus dígitos para inventar E.164.

| Participação | Obrigatório | Regra |
| --- | --- | --- |
| `id` | Sim | String técnica 1–200 da leg; estável na chamada. |
| `state` | Sim | `offered`, `ringing`, `active`, `completed`, `missed`, `failed`, `cancelled`, `answered_elsewhere`. |
| `extension` | Não | String 1–128 do ramal comprovado e vinculado à empresa. |
| `sip_call_id` | Não | String 1–256 do Call-ID SIP real dessa leg. |
| `started_at`, `answered_at`, `ended_at` | Não | ISO UTC, conforme fatos observados por participação. |

Uma chamada pode ter várias legs/SIP Call-IDs, inclusive vários dispositivos do
mesmo ramal. Preservar as legs anteriores em transferência e o resultado
`answered_elsewhere`. Nunca fabricar `sip_call_id` para forçar associação.

## 9. Gravação, transcrição e resumo via webhook

Evento **`call.artifacts.updated`**, sempre com o snapshot completo da chamada.
O objeto `call.artifacts` admite somente as opções abaixo:

| Objeto/campo | Regra |
| --- | --- |
| `recording` | Opcional: `status`, `record_id`; opcionais `mime_type`, `size_bytes`, `sha256`. |
| `recording.status` | `disabled`, `recording`, `processing`, `available`, `failed`. |
| `recording.record_id` | String estável 1–200; usada na consulta autenticada da mídia. |
| `recording.mime_type` | `audio/mpeg`, `audio/mp3`, `audio/wav`, `audio/wave`, `audio/x-wav`, `audio/gsm`, `audio/x-gsm` ou `audio/ogg`; não HTML. |
| `recording.size_bytes` | Inteiro de 1 a 52428800 (50 MiB). |
| `recording.sha256` | Opcional, 64 caracteres hexadecimais minúsculos do conteúdo. |
| `ai` | Opcional: `status`; opcionais `transcript`, `summary`, `transcription_model`, `summary_model`, `completed_at`. |
| `ai.status` | `disabled`, `queued`, `processing`, `completed`, `failed`. |
| `ai.transcript` | Texto até 64000 caracteres; quebras de linha/tab permitidas. Sem HTML executável. |
| `ai.summary` | Texto até 16000 caracteres; não publicar automaticamente como resposta ao cliente. |
| `ai.transcription_model`, `ai.summary_model` | Identificadores opcionais até 128 caracteres; nunca chave de API. |
| `ai.completed_at` | ISO UTC do término da geração, quando comprovado. |
| `note_target` | Opcional: `business_phone` e `remote_phone`, ambos telefones completos, derivados dos snapshots imutáveis da ligação. |

Não transportar áudio/base64, URL arbitrária/assinada, caminho local, bucket,
token, prompt secreto, `conversation_id`, `inbox_id`, `agent_id` ou flag pública.
A nota desse fluxo é **sempre privada**. A conta vem da URL/cadastro confiável.

Exemplo completo com todas as opções de artefatos:

```json
{
  "schema_version": 1,
  "event_id": "empresa-a:artefatos-008",
  "event_type": "call.artifacts.updated",
  "occurred_at": "2026-10-22T16:01:05Z",
  "source_instance_id": "central-empresa-a",
  "call_id": "central-empresa-a:call-001",
  "revision": 8,
  "call": {
    "direction": "inbound",
    "state": "completed",
    "started_at": "2026-10-22T16:00:00Z",
    "answered_at": "2026-10-22T16:00:05Z",
    "ended_at": "2026-10-22T16:01:00Z",
    "from": { "kind": "phone", "value": "+5566999990000", "name": "Contato de exemplo" },
    "to": { "kind": "extension", "value": "1001", "name": "Atendimento" },
    "end_reason": "normal_clearing",
    "participants": [
      {
        "id": "call-001:leg-1001",
        "extension": "1001",
        "state": "completed",
        "sip_call_id": "sip-real-leg-1001",
        "started_at": "2026-10-22T16:00:00Z",
        "answered_at": "2026-10-22T16:00:05Z",
        "ended_at": "2026-10-22T16:01:00Z"
      }
    ],
    "artifacts": {
      "recording": { "status": "available", "record_id": "gravacao-call-001", "mime_type": "audio/wav", "size_bytes": 16044 },
      "ai": { "status": "completed", "transcript": "Texto sintético da chamada.", "summary": "Resumo sintético.", "transcription_model": "modelo-transcricao", "summary_model": "modelo-resumo", "completed_at": "2026-10-22T16:01:05Z" },
      "note_target": { "business_phone": "5566999991111", "remote_phone": "5566999990000" }
    }
  }
}
```

O exemplo não inclui `sha256` porque ele deve ser calculado sobre o áudio real,
não preenchido com um hash fictício. Também é válido omitir nomes, modelos e
tempos opcionais. Gravação e IA podem chegar em revisões distintas da mesma
chamada; repetir a entrega não cria outra nota ou outro anexo.

### Processamento no ViperChat

1. Persistir evento/snapshot e agendar artefatos em fila durável separada; 202
   significa recepção, não que download/nota já terminaram.
2. Validar o número empresarial dentro da mesma conta e resolver a caixa
   operacional existente. Caixa unificada segue seu vínculo canônico; não criar
   outra conversa Meta/ViperConnect nem duplicar bolha entre parceiras.
3. Correlacionar somente com contato/conversa existentes e prova telefônica
   segura. Não usar nome, semelhança de texto ou primeiro resultado de busca.
   Sem prova/ambíguo: pendente, sem criar contato/conversa nem publicar na errada.
4. Fixar o vínculo comprovado da chamada com conversa/contato/caixa. Atualização
   tardia de IA/gravação conserva esse vínculo mesmo após edição do telefone;
   não migrar histórico para a pessoa que recebeu o número antigo.
5. Obter áudio apenas na rota configurada do serviço
   `GET /v1/console/history-records/{record_id}/recording`, com Bearer protegido,
   limites de tamanho/MIME/hash e sem seguir redirect. Não usar URL do payload.
6. Criar uma nota privada por chamada e atualizar essa mesma mensagem com IA e
   anexo. Preservar seus IDs; deduplicação precisa sobreviver a retries/crash.
   Não reabrir atendimento nem disparar mensagem externa.
7. Mostrar estado, gravação, transcrição e resumo junto do histórico na central
   de chamadas, com autorização da conta/agente. URLs locais não expõem Bearer.

Se a conversa não for comprovada, os artefatos permanecem associados à chamada
na central e aguardam resolução; não simular que foram publicados como nota.
Chamadas internas sem telefone externo não criam nota WhatsApp automaticamente.

## 10. Semântica de todas as opções de evento/estado

| Evento | Uso |
| --- | --- |
| `call.created` | Primeira observação; pode começar em `routing` ou `ringing`. |
| `call.ringing` | Oferta tocando, sem afirmar atendimento. |
| `participant.answered` | Leg atendida; estado/tempo reais dessa participação. |
| `participant.released` | Leg liberada; outras podem continuar ativas. |
| `call.transferred` | Mudança de legs; manter participantes anteriores. |
| `call.ended` | Encerramento global com estado final. |
| `call.updated` | Correção/complemento, inclusive CDR conhecido somente ao final. |
| `recording.updated` | Metadados de gravação no contrato inicial. Não implica postagem privada por si só. |
| `call.artifacts.updated` | Publicação/atualização de gravação e IA pelo processador privado. |

O receptor aceita tipos que um produtor pode não emitir individualmente:
liberação/transferência no produtor próprio podem vir como `call.updated` com
snapshot atualizado. Não prometer suporte de todas as centrais a tempo real.

- `routing`: roteamento; `ringing`: oferta; `active`: atendimento comprovado.
- `completed`, `missed`, `failed`, `cancelled`: estados globais terminais.
- `offered` e `answered_elsewhere` são estados de participação, não globais.
- Revisão nova pode complementar artefatos de uma chamada terminada, mas nunca
  fazê-la voltar a tocar. Revisão obsoleta não sobrescreve estado novo.
- Este contrato ainda não inclui vídeo, hold/mute, DTMF, métricas de qualidade,
  comandos de controle, áudio inline ou identificador livre de caixa/usuário.

## 11. Stack, respostas, operação e aceite

| Opção do produtor | Padrão / comportamento |
| --- | --- |
| `VOIP_WEBHOOK_AMQP_ENABLED` | `false`; exatamente `true` ativa transporte. |
| `VOIP_AMQP_URL` | Obrigatória ao ativar: AMQP/AMQPS com credenciais fora do Git. |
| `VOIP_WEBHOOK_QUEUE_PREFIX` | `viperconnect.voip.webhooks`; namespace exclusivo, não fila WhatsApp. |
| `VOIP_WEBHOOK_MAX_ATTEMPTS` | `8`, intervalo 1–20. |
| `VOIP_SQLITE_PATH` | Banco persistente; backup antes de migrations; não apagar volume/mídias. |
| `VOICE_CONFIG_STORAGE`, `CALL_HISTORY_STORAGE` | Persistência SQLite para durabilidade do fluxo. |
| `NODE_EXTRA_CA_CERTS` | CA privada confiável quando necessária; não desativar TLS. |

No ViperChat, destinos VoIP HTTPS privados podem ser autorizados pelo operador
via `VOIP_TRUSTED_SERVICE_ORIGINS`, lista separada por vírgulas de origens exatas
(`https://host:porta`, sem path, credenciais, query ou fragmento). Padrão vazio.
A confiança vale somente para o cliente VoIP; não ampliar globalmente
`SAFE_FETCH_ALLOW_PRIVATE_NETWORK`. Esquema, host e porta devem coincidir, TLS
continua validado e redirects não são aceitos. Para CA interna, instalar uma
cadeia confiável no runtime; jamais usar `verify=false` ou equivalente.

HTTPS deve validar certificado. Proxy precisa preservar `api_access_token`;
em Nginx, conferir `underscores_in_headers on;`. Um proxy que descarta esse
cabeçalho produz 401 mesmo com token correto. Não remover segurança para corrigir.

HTTP do receptor: 202 aceito durável, 200 duplicata idêntica, 401 token ausente/
inválido, 403 sem permissão/API/serviço habilitado, 404 escopo inexistente,
409 ID/revisão divergente, 413 corpo excedido, 422 schema/origem inválidos.
408/429/5xx e rede/timeout são temporários. Não seguir 3xx; validar recibo JSON
com `event_id` e `status` correspondentes. HTML 200 não é recibo válido.

Transporte é pelo menos uma vez. Retry preserva evento/conteúdo; nova observação
usa ID/revisão novos. Publisher confirm não significa recebimento HTTP, e 202
não significa nota privada concluída. As duas fases precisam de estado persistido.

Produtor usa prefetch 4, timeout HTTP 15 s, recibo até 16 KiB, backoff exponencial
base 30 s com jitter 0,75–1,25, teto exponencial 15 min e Retry-After até 1 h.
Buckets de atraso: 1 s, 5 s, 30 s, 1 min, 2 min, 5 min, 15 min, 1 h; o bucket
pode alongar a espera. Permanente/limite vai para `.dead`, sem apagar outbox.
Não há replay automático da dead queue. Reprocessamento administrativo manual
com confirmação, empresa e destino originais é descrito na seção 12.

Validar com dados sintéticos: todos os tipos/estados, empresa/ramal estrangeiro,
gravação/IA em ordens diferentes, retry, nota/anexo únicos, caixa Meta e
ViperConnect unificadas, telefone editado, conversa resolvida sem reabertura,
ausência/ambiguidade pendente, MIME/hash/tamanho inválidos e credenciais erradas.
O teste real será realizado depois pelo operador; não chamar clientes para teste.

## 12. Consolidação, recuperação incremental e operação administrativa

Na configuração do serviço no ViperChat, selecionar `viperconnect` e informar
`history_api_url`, `history_api_token` e `history_company_id` (ID exato da empresa
no produtor). Não inferir empresa por telefone. Campos antigos permanecem
compatíveis; sem empresa explícita, a recuperação informa `configuration_required`
e não realiza consulta ampla. Serviço apenas `webhook` informa `unsupported`
para recuperação REST, sem afetar a recepção dos webhooks.

O cliente usa a rota existente:

```text
GET /v1/console/history?sync=webhook_events&company_id=empresa-a&account_id=1&service_id=206&source_instance_id=pbx-company-a&limit=100&cursor=<opaco-opcional>
Authorization: Bearer <TOKEN_DO_SERVICO_VOIP>
```

Resposta: `version: 1`, `phase: snapshot|changes`, `items` com
`sequence` e `webhook_event` idêntico ao envelope persistido/enviado, `nextCursor`,
`hasMore` e `scope` com os quatro identificadores da consulta. Páginas limitadas
a 100 itens e aproximadamente 1,5 MB de eventos. A preparação canônica, seleção
e marca d'água são atômicas; nunca avançar sobre eventos ainda não preparados.
Cursor assinado depende da instância, empresa e destino. O feed cobre os eventos
retidos/autorizados desde a ativação, não inventa eventos de histórico anterior.

No ViperChat, cursor criptografado, lease e fingerprint de configuração são
persistidos por serviço. Consulta HTTP fica fora do lock; antes de gravar a
página, conferir lease e configuração novamente. Inbox e checkpoint são gravados
juntos, e o enfileiramento ocorre depois do commit. Falha de Redis é recuperada
pelo scanner. Páginas seguintes são enfileiradas até alcançar a origem.

- `400`: cursor inválido; pausa e exige correção/reset explícito.
- `409`: escopo alterado; pausa, sem misturar destinos.
- `410`: retenção expirada; reler snapshot retido com `gap_detected: true`.
  Não apagar histórico local nem afirmar recuperação de dados já removidos na origem.
- `401/403`: bloqueio de configuração/autenticação; sem retry infinito.
- Rede/`5xx`: backoff persistido e retomada posterior.
- Mudança de configuração invalida lease; cursor anterior só é substituído
  após aceitar uma página do novo snapshot. Tokens/cursores não aparecem na UI.

### Operação no ViperChat

Rotas sob `/api/v1/accounts/:account_id/voip/services/:service_id`, somente
administrador daquela conta, com autorização de API existente:

| Rota | Contrato |
| --- | --- |
| `GET /diagnostics` | `counts`, até 25 eventos e 25 artefatos pendentes/falhos em `records`, `truncated`, `recovery` sanitizado. Sem conteúdo ou credenciais. |
| `POST /reprocess` | `{ "kind": "event" ou "artifact", "record_id": 123 }`; 202 `queued`. Preserva IDs, conteúdo, alvo e blobs. |
| `POST /recover_history` | `{ "reset_cursor": false }`; 202 `queued`. `true` somente após confirmação explícita para reler o histórico retido. |

Reprocessamento rejeita registro concluído, outra conta/serviço, origem alterada,
serviço desabilitado e repetição em menos de 30 segundos. Operador e horário são
auditados. Falhas de eventos/artefatos registram código sanitizado e param após
oito tentativas; reprocessar não contorna falta de evidência para a conversa.

### Operação na empresa do produtor

Rotas sob `/v1/console/companies/:companyId/viperchat-webhook`, com Bearer do
serviço VoIP; o Manager exige administrador antes de encaminhar:

- `GET /diagnostics?status=all&limit=50`: contagens e metadados técnicos;
  `status` aceita `all`, `pending`, `published`, `delivering`, `dead`.
- `POST /replay`: `eventIds` (1–20 hashes), `confirm: true` e `requestId` UUID
  idempotente. Revalidar empresa, ramais e destino original habilitado dentro
  da mesma transação. Preservar envelope, fingerprint, IDs e tentativas.
- Destino alterado/desabilitado, entrega em andamento ou já entregue: 409;
  nunca redirecionar a pendência para outra instalação. Confirmação RabbitMQ
  não equivale a recibo HTTP nem à conclusão da nota privada.

### Aceite dev da consolidação

Testes sintéticos de estados/participantes incluem recebida, efetuada, perdida,
falha/cancelada, transferência, atendimento por outro ramal, eventos tardios e
duplicados. RabbitMQ real validou 503, retry e reinício do consumidor com SQLite
persistido, mantendo o mesmo evento. REST real recuperou os seis envelopes
sintéticos sem novas bolhas/anexos; duas notas e seus blobs mantiveram os IDs.
Reprocessamento administrativo nas duas pontas foi validado, sem chamadas reais
e sem VPS. Dispositivos nativos e disponibilidade prolongada exigem aceite próprio.

# Auditoria local: REST, eventos e CDR VoIP

20/10/2026 — America/Cuiaba. Complemento do [plano do webphone por agente](plano-webphone-sip-agente-20261020.md).

## 1. Conclusão

**Já existe histórico persistido de chamadas no serviço VoIP e API REST de consulta. Não precisamos criar CDR do zero.** Há registro de chamadas externas e internas, horários de atendimento/término, duração, identidade remota, gravação e campos de IA.

Os eventos de ciclo de vida existem entre worker Zapo e serviço VoIP, mas esse WebSocket é uma bridge privada de controle/mídia, não uma assinatura durável de eventos para ViperChat. Não foi localizado, nos produtores/rotas pesquisados, um webhook genérico/outbox de ciclo de vida entregue ao ViperChat com replay e confirmação. O webhook de gravação e o aviso textual de chamada são fluxos diferentes.

Para o novo webphone: reutilizar SIP/WebRTC e CDR existentes; acrescentar sincronização confiável, escopo por conta/serviço/ramal, participações/legs e integração de perfil/histórico no ViperChat. O navegador fechado não impede o serviço de persistir as chamadas que recebe; isso pressupõe worker e bridge conectados. A bridge desconectada não oferece hoje replay durável de chamadas encerradas.

## 2. Fontes e alcance

| Repositório local | Revisão observada | Estado |
| --- | --- | --- |
| `C:/Users/caita/Nextcloud/Desenvolvimento/unoapi-voip-service` | `9615a6f78582fb84a9f10647f98744cc41e1befe`, pacote `viperconnect-voip-service` 0.1.67 | Sem alterações locais no momento da inspeção. |
| `C:/Users/caita/Nextcloud/Desenvolvimento/unoapi-cloud` | `b1668845d2b24b9b6b8b23a2b19d986d2cd417bf`, ViperConnect 4.0.37 | Alterações preexistentes em docs de IPv6, `.gitattributes` e `deploy/ipv6-ddns/`; preservadas. |

Inspeção de fontes, schemas, rotas, testes existentes e configuração de build, sem ler arquivos de credenciais, abrir bancos, conectar a centrais ou acessar VPS. Não prova a versão/configuração atualmente executada em produção.

O workflow da ViperConnect (`.github/workflows/main.yml:58`) fixa a revisão VoIP acima como padrão; o Dockerfile grava `io.vipertec.viperconnect.voip.revision` e `voip/SOURCE_REVISION`. Na implantação futura, conferir esses valores no artefato/runtime, não pressupor que o checkout equivale à imagem ativa.

Arquitetura encontrada:

```text
worker Zapo / client_zapo.ts
  chamadas WhatsApp e áudio
  ↓ bridge privada WS /v1/bridge/zapo + frames PCM
serviço VoIP
  roteamento, ramais, SIP/WebRTC e SIP/RTP, gravação e CDR
  ↓ /sip/ws para SIP.js                ↓ REST server-to-server
webphone do agente                    backend ViperChat (a integrar)
```

O processo VoIP não abre outra sessão WhatsApp; preserve essa divisão. Não confundir o worker WhatsApp com o transporte SIP do ramal ou com endpoints Graph API oficiais. O novo ViperChat usa a telefonia já oferecida pelo serviço.

## 3. REST existente no serviço VoIP

Rotas montadas em `src/app.ts:110–112`; definições em `src/routes/voice.ts`, `src/routes/zapo_bridge.ts`, `src/routes/console/history_recording.ts` e `src/routes/console/operations.ts`.

| Método/rota existente | Conteúdo e limite |
| --- | --- |
| `GET /v1/console/history` | CDR paginado, busca e intervalo por data de início. |
| `GET /v1/console/history-records/:recordId/recording` | Gravação de um registro exato, com verificação de escopo. Preferir este identificador. |
| `GET /v1/console/history/:callId/recording` | Compatibilidade por callId; não permitido com escopo Manager por sessões. Não usar para selecionar arbitrariamente uma leg. |
| `GET /v1/zapo/calls?session=...` | Inventário de chamadas externas ativas em memória; não é CDR nem feed completo de chamadas internas. |
| `POST /v1/zapo/calls` | Originação WhatsApp pelo serviço; exige sessão e destino. **Não chamar junto de INVITE SIP.js para o mesmo envio.** |
| `POST /v1/zapo/calls/:callId/:command` | `accept`, `reject`, `end`, `mute`, com sessão no corpo; este endpoint não constitui autorização por agente. |
| `GET /v1/voice/registrations` | Registros WebRTC vivos. Bootstrap do console agrega também registros SIP/RTP. |
| `GET /v1/voice/extensions` / `/:extensionId` | Inventário de ramais; listas removem senha. |
| `GET /v1/voice/extensions/:extensionId/webrtc-config` | Contrato de conexão para SIP.js, incluindo credencial; uso somente por backend autorizado. |
| `GET /v1/console/extensions/:extensionId/credentials` | Credencial e configuração do ramal, escopo administrativo de serviço; não expor diretamente ao agente. |
| `POST /v1/console/calls/:callId/transfer` | Transferência de chamada ativa para ramal; `targetExtensionId`, `requestedByExtensionId` opcional, com validações de destino/grupos. |
| `GET /v1/console/bootstrap` | Capacidades, configuração redigida, linhas, locks e registros. Não inclui um feed durável de eventos. |
| `WS /sip/ws` | Registro e sinalização SIP/WebRTC do ramal; não é o canal da bridge Zapo. |

`GET/PUT /v1/voice/config` devolvem **410/deprecated**; não usar como caminho de provisionamento.

### Histórico: parâmetros e envelope atuais

`GET /v1/console/history?page=1&pageSize=20&search=...&startDate=...&endDate=...`

- `limit` é alternativa a `pageSize`; máximo de 100 itens.
- Resposta: `items`, `total`, `page`, `pageSize`, `totalPages`, `search`, `startDate`, `endDate`; `scope` quando solicitado por contrato confiável.
- Ordenação por `startedAt` descendente. Busca inclui nome/número remoto, JID, ramal, labels e callId.
- Não há nesse contrato filtros públicos por `extensionId`, direção ou resultado, cursor de alterações, `updatedSince`, ordenação por atualização ou endpoint dedicado de detalhe por recordId sem gravação.
- Existe `updated_at` na tabela SQLite, mas o schema de `CallHistoryRecord` não o expõe. **Não tratar essa coluna como um contrato REST já disponível.**
- A busca atual aplica lowercase e comparação de dígitos; não garante equivalência sem acentos. Incluir essa adaptação no aceite da pesquisa do ViperChat.

### Autenticação e escopo

`src/app.ts:95` exige `Authorization: Bearer <VOIP_SERVICE_TOKEN>` nas rotas `/v1/`, salvo bridge. Sem token configurado devolve 503; token incorreto, 401. O contexto de `console_auth.ts` é administrativo de serviço: as funções de acesso por empresa não são autorização de agente.

O header confiável `X-Unoapi-Session-Scope` é uma lista JSON de números locais/linhas (`phoneNumber`), **não dos interlocutores**. `managerSessionHistoryScope: 1` anuncia suporte. O serviço aplica esse escopo antes de contar/paginar; vazio nega tudo. Isso ainda não define “ramal deste agente”, e chamadas internas podem não ter `phoneNumber`.

O backend ViperChat deverá guardar o token administrativo e definir a autorização de conta/serviço/empresa/ramais. Nunca entregar esse token ao navegador nem confiar em query/body para definir o próprio escopo. Filtrar uma página global depois de recebê-la não resolve contagens/vazamento nem visibilidade por agente.

## 4. Proxy REST existente na ViperConnect

`src/router.ts:181` e `src/controllers/voip_controller.ts` oferecem:

| Rota registrada | Destino/uso |
| --- | --- |
| `GET /admin/voip/bootstrap` | Bootstrap agregado do serviço. |
| `GET/POST /admin/voip/calls` | Consulta ativa/originação do serviço; não é lista histórica. |
| `POST /admin/voip/calls/:callId/:command` | Comandos do inventário ativo. |
| `GET /admin/voip/recordings/:recordId` | Stream da gravação exata. |
| `/admin/voip/console/*` | Proxy do console; histórico em `GET /admin/voip/console/history`. |

Acrescentar eventual prefixo externo configurado no deployment; as rotas acima são os caminhos registrados no router local.

`ManagerVoipAccess` e `ManagerVoipHistory` já restringem usuários Manager não administradores às sessões atribuídas, validam capability e eco de escopo, projetam campos e fecham acesso quando não podem provar autorização. Não são equivalentes à política de agente ViperChat, e não se deve relaxar essas restrições para fazer a nova tela funcionar.

**Escolha para a implementação:** backend ViperChat consome a API do serviço VoIP com configuração por serviço e escopo próprio seguro; o proxy ViperConnect continua compatível e pode ser usado por instalações que já o exijam. Não criar dois sincronizadores lendo o mesmo serviço via caminhos diferentes. Confirmar conectividade/autorização antes de escolher a URL operacional; nenhuma URL real foi acessada aqui.

## 5. Dados de CDR já persistidos

`src/services/call_history_store.ts:10–72`:

- Identidade: `id`, `callId`, `companyId`, `accountId`, `phoneNumber`, labels.
- Ramal atual: `extensionId`, `extensionUsername`, `extensionLabel`; grupos de linha/ramal.
- Remoto: `remoteNumber`, `remoteName`, `remoteNameSource`, `remoteJid`. Snapshot remoto preservado nos upserts; LID não é telefone confirmado.
- Direção: `inbound`, `outbound`, `internal`.
- Estado: `routing`, `ringing`, `active`, `completed`, `missed`, `failed`, `cancelled`.
- Tempos: `startedAt`, `answeredAt`, `endedAt`, `durationSeconds`; resultado detalhado em `endReason`/`error`.
- Gravação: disponibilidade/provedor/chave, mime, tamanho, duração e tempos; IA tem status, transcrição e resumo.

IDs externos produzidos em `zapo_bridge_call_service.ts:877`: `inbound:<session>:<callId>` ou `outbound:<session>:<callId>`. Chamada interna WebRTC usa `internal:<callId>` (`sip_webrtc_gateway.ts:1254`). Guardar o **recordId exato** como referência externa, junto de conta/serviço. `callId` sozinho não identifica necessariamente registro/leg.

Backend padrão de histórico é SQLite; há importação de JSON e fallback de arquivo. SQLite tem tabelas de histórico, gravações e IA. O histórico tem limite padrão **1000 registros por empresa**, configurável por `CALL_HISTORY_MAX_RECORDS`; não confundir com dias de retenção de áudio. Há prune de linhas antigas — sincronização precisa ocorrer antes desse descarte.

`finishAll` fecha registros por id/callId; entrada sem atendimento é normalizada para `missed`. Duração é calculada de `answeredAt` a `endedAt`, não desde o toque. Há proteção parcial contra regredir ativo para toque e fechamento de stale records no startup/tarefa periódica. Não é um log imutável de todos os eventos.

**Limite importante:** o registro tem um único `extensionId`, não um histórico de todos os ramais ofertados/registrations/transferências. `recordHistory(..., 'active', extensionId)` volta a informar `answeredAt` a cada ativação, inclusive na transferência: revisar para preservar o primeiro atendimento e acrescentar segmentos, em vez de perder a origem ou recalcular duração incorretamente.

## 6. Eventos do worker e do serviço

### Worker Zapo → bridge VoIP

Wiring em `unoapi-cloud/src/services/client_zapo.ts:782–846`; encoder em `src/services/zapo/voice/zapo_voice_bridge_client.ts` e validação em `zapo_voice_bridge_codec.ts`.

| Evento | Dados observados |
| --- | --- |
| `bridge.hello` / `bridge.ready` | Protocolo v1, sessão, geração/worker, capacidades e handshake. |
| `session.status` | Online/offline da sessão. |
| `call.incoming` | Sessão, callId, direção, peerJid, telefone/nome confirmado quando conhecido, mídia áudio e canAccept. |
| `call.state` | Sessão, callId, state e direção. Não transporta os timestamps de atendimento/fim que existem no objeto interno do vendor. |
| `call.ended` | Sessão, callId, motivo. Não inclui duração/ramal vencedor. |
| `call.error` | Código/mensagem e callId opcional; a ligação em `client_zapo.ts` publica erro sem fornecer callId. |
| `call.command` / `call.command.result` | Start/accept/reject/end/mute, requestId, callId, sucesso/erro. requestId correlaciona comando, não torna os eventos de ciclo de vida duráveis. |
| `audio.stream.open/close` | Associação de stream PCM; não substituir por uma conexão de mídia no ViperChat. |

Os eventos não têm eventId/sequence/timestamp de ocorrência durável para replay de ciclo de vida. A sequência dos frames PCM é outra coisa. Se o WS não estiver ready, `publish*` retorna false; na reconexão publica estado das chamadas ainda abertas, não uma fila de encerradas/perdidas. Não reaproveitar esse WS como assinatura adicional ViperChat: ele tem dono de sessão/geração e também transporta áudio.

### SIP/WebRTC → domínio VoIP

`sip_webrtc_gateway.ts` e `zapo_bridge_call_service.ts:79–96`:

- `extensionRegistered` após REGISTER autenticado; registro por SIP Digest e senha de ramal, não JWT bearer arbitrário.
- `inviteAccepted`, `inviteRejected`, `dialogEnded`, `outboundInviteAccepted`, handler de originação e handler de transferência.
- Eventos SIP carregam `sipCallId`, ramal e contexto da chamada; `legId` aparece em alguns caminhos. As informações são usadas para arbitrar fanout/transferência, mas não todas persistidas no CDR atual.
- Suporte a múltiplos registros por ramal e encerramento `answered_elsewhere` já existem. **Preservar**, em vez de bloquear todos os dispositivos ao acrescentar o webphone. A regra “uma aba dona” do ViperChat evita duplicar a própria sessão web; não elimina ramais de hardware ou outro dispositivo autorizado.

## 7. Integrações que não substituem o CDR

1. `client_zapo.ts:849`, `emitCallWebhook`: publica uma mensagem textual configurada (`messageCallsWebhook`/`rejectCallsWebhook`) no pipeline de mensagens. Não é um evento de chamada com status/tempos/ramal. Se a política `rejectCalls` rejeitar antes da bridge, a ligação não segue o caminho normal de histórico do serviço; revisar cobertura sem ignorar essa política.
2. `chatwoot_recording_service.ts:108`: fila persistente/retry para **gravação disponível**. Procura contato/conversa e pode criar conversa para anexar áudio como nota privada. Não cobre chamada perdida sem gravação e não deve criar conversa para tornar a aba Chamadas possível.
3. Gravação local/S3 já pertence ao serviço. A nova aba deve usar referência/stream autorizado; não baixar e duplicar automaticamente no Active Storage/S3 do ViperChat. Manter a integração legada de notas quando configurada, sem produzir uma segunda cópia por causa da nova UI.

## 8. Lacunas a implementar antes de declarar histórico completo

| Prioridade | Lacuna constatada | Trabalho planejado |
| --- | --- | --- |
| P0 | Sem contrato público durável de mudanças/replay para ViperChat. REST atual pagina por início. | Acrescentar feed incremental versionado e persistido com cursor estável, recordId, revisão/updatedAt e snapshot, filtro server-side por conta/serviço/ramais autorizados e detalhe por recordId. Consumidor no backend ViperChat, não no browser. |
| P0 | Consulta periódica apenas dos últimos inícios perde atualizações de chamadas antigas, áudio/IA tardios e registros descartados pelo limite. | Cursor por alteração, paginação estável e checkpoint só após persistir; recuperação inicial/backfill com marca d'água, revisão de retenção e lacunas explícitas. Não alegar garantia com janela móvel aproximada. |
| P0 | Um ramal por CDR não guarda toda participação. | Persistir ofertas, atendimento vencedor, legs/SIP Call-ID e transferências com horários e resultado por agente/registro. Preservar o primeiro answeredAt. |
| P0 | Token REST é administrativo; Manager é escopo de linha, não de agente. | Mapeamento explícito serviço→empresa/linhas/ramais; filtro/autorização antes de paginação/contagem e bootstrap restrito ao binding. Token no servidor. |
| P0 | Janela de perda quando worker/bridge desconecta; erro pode não ter callId. | Outbox/seq/ack de ciclo de vida no produtor ou mecanismo de recuperação equivalente; propagar timestamps/callId quando disponíveis, reconciliar startup sem inventar eventos. |
| P0 | Entrada rejeitada por capacidade retorna antes do `recordHistory`; espelhamentos são ignorados intencionalmente. | Registrar rejeições reais/capacidade com identidade suficiente sem transformar espelhamentos da mesma ligação em nova tentativa. Testes diferenciando os dois casos. |
| P1 | Estados busy/rejected/answered_elsewhere não são todos tipos próprios de CDR. | Tabela de normalização baseada em endReason/código/participação; manter motivo bruto e distinguir saída não atendida de entrada perdida. |
| P1 | Duração/identidade de origem podem mudar em transferência e `finishAll` pesquisa callId sem sessão. | Escopar correlação de legs por serviço/sessão, revisar encerramento e múltiplas linhas sem alterar IDs atuais nem quebrar a regra de espelhamento. |
| P1 | Falta filtro de ramal/direção/status, busca sem acentos e detalhe completo no REST. | Novos parâmetros versionados, consulta eficiente no SQLite com índices e testes de escopo/paginação; preservar contrato Manager atual. |
| P1 | Histórico interno está em CDR, mas não no inventário `/v1/zapo/calls`. | Adaptador de estado/detalhe distingue interno/externo, autoriza os dois ramais envolvidos e evita sumir chamadas internas da nova UI. |

### Estratégia de entrega

Atualização de prioridade definida pelo usuário em 20/10/2026: **primeiro implementar o mecanismo SIP/WebRTC e a interface no ViperChat; depois incrementar a integração do serviço com webhooks duráveis e REST incremental.** A primeira entrega persiste apenas observações do cliente conectado, com origem/limitações explícitas e contratos sintéticos preparados; não promete histórico completo de navegador fechado.

Na segunda entrega, o serviço envia webhooks por fila persistente/outbox, com eventId/revisão, assinatura, confirmação durável, backoff/retentativas e quarentena de falhas. O ViperChat aplica eventos idempotentemente e usa consulta REST incremental server-side com cursor/checkpoint para backfill e recuperação de falhas. Não avançar cursor por webhook isolado nem repetir ação SIP durante replay. Webhook e REST compartilham o mesmo reconciliador; áudio não passa por esse webhook. A especificação detalhada e a nova sequência estão nas seções 7.1 e 12 do plano.

Reaproveitar a persistência e o pipeline atual; não criar outra engine WhatsApp, outro worker de mídia ou uma segunda sessão Zapo. Preservar fila global `serializeVoiceConfigMutation`, recursos automáticos gerenciados, regras avançadas e capacidade compartilhada 2..32.

## 9. Testes encontrados e validação realizada

Testes existentes relevantes, ainda sem comprovação de execução neste levantamento:

- Serviço: `call_history_store.test.ts`, `call_history_sqlite_store.test.ts`, `manager_session_history_scope.test.ts`, `zapo_bridge_call_service.test.ts`, `sip_webrtc_gateway.test.ts`.
- Worker: `zapo_voice_bridge_client.ts`, `zapo_voice_bridge_codec.ts`, `zapo_voice_adapter.ts`, `manager_voip_history.ts`, `manager_voip_access.ts`, `voip_controller.ts` nos diretórios `__tests__` correspondentes.
- Há casos de duração após atendimento, perdida sem atendimento, preservação de chamada ativa em stale cleanup, escopo antes de count/page, transferência e aceite único/fanout. Isso não equivale a testar o novo ViperChat.

Foi tentada a execução de três suítes existentes de histórico/escopo com dados temporários isolados. O executor rejeitou o comando por política **antes de iniciar o processo**. Não foi repetido por outro caminho; não houve testes executados, arquivos temporários criados por essa tentativa ou bancos acessados. Inspeção estática concluída, validação executável pendente.

Acrescentar aos sintéticos futuros: navegador fechado, bridge offline/replay, mesma chamada espelhada, capacidade esgotada, erro sem callId, chamada longa fora da janela por início, atualização tardia de áudio/IA, reordenação, transferência A→B e múltiplas registrations com apenas um vencedor. Verificar que histórico não depende de gravação nem de conversa.

## 10. Efeito no planejamento

O contrato atual foi mapeado; não precisamos redescobrir nem reconstruir CDR. Conforme a nova ordem solicitada, a próxima implementação é exclusivamente ViperChat em dev: cadastro multi-serviço, modal do agente, sessão SIP/WebRTC, histórico observado e layout. Os gaps de sincronização/participação/escopo do serviço passam para a segunda entrega com webhooks/outbox/retentativas e REST incremental. O aceite de histórico completo continua dependendo dos P0 acima; a mudança de prioridade não os considera resolvidos.

Somente este relatório e o plano ViperChat foram alterados. Sem alteração funcional nos dois projetos inspecionados, sem commit/push, sem chamadas/registro reais e sem acesso ou mudanças na VPS. Nenhuma configuração/senha foi coletada e nenhum temporário foi criado pela análise estática.

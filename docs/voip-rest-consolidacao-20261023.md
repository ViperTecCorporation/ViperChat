# REST de consolidação VoIP e eventos na conversa

## Endpoint usado pelo ViperChat

`GET https://SUA-CENTRAL/v1/console/history?sync=webhook_events&company_id=EMPRESA&account_id=CONTA&service_id=SERVICO&source_instance_id=ORIGEM&limit=100`

O endereço configurado no Serviço VoIP é a raiz HTTPS da central, sem acrescentar
`/voip-api`. Autenticação dessa consulta: `Authorization: Bearer TOKEN_DO_SERVICO`.
É o token configurado em `history_api_token`, não o api_access_token do ViperChat.
O sentido inverso, POST ao webhook do ViperChat, usa api_access_token de admin.
Não colocar tokens na URL, exemplos reais, logs ou envelopes RabbitMQ.

`company_id` é o ID exato da empresa na central, possivelmente UUID; `account_id`
e `service_id` identificam o destino ViperChat; `source_instance_id` deve ser
idêntico ao cadastro do produtor. Todos os quatro são obrigatórios. O produtor
revalida empresa, vínculo dos ramais e fingerprint do destino em cada página.

Primeira consulta sem cursor inicia snapshot limitado ao journal ainda retido.
As seguintes enviam `cursor=VALOR_DE_nextCursor`. O cursor é opaco, assinado e
vinculado ao escopo/destino. Limite 1–100. Resposta usa Cache-Control: no-store:

```json
{
  "version": 1,
  "phase": "snapshot",
  "scope": { "company_id": "empresa-exemplo", "account_id": "1", "service_id": "10", "source_instance_id": "pbx-exemplo" },
  "items": [],
  "nextCursor": "cursor-opaco-assinado",
  "hasMore": false
}
```

Cada item não vazio contém `sequence` e `webhook_event`: o mesmo envelope v1 de
POST, incluindo event_id, call_id, revision e snapshot completo. `sequence`
corresponde à revision. `phase` informa a página atual; quando hasMore=false,
o próximo cursor já permite seguir em changes. Persistir o cursor apenas depois
de receber/processar com segurança a página; manter consultas periódicas mesmo
em páginas vazias. Nunca deduplicar por telefone/texto/horário: usar serviço,
origem, event_id/revision e identidade da chamada. Repetição webhook/REST não
cria outra chamada, bolha, nota, anexo ou blob.

Erros: 400 parâmetros/cursor/limite inválidos; 401/403 autenticação/escopo;
409 mudança de escopo/destino; 410 expiração de epoch/retention; 422 envelope
grande demais; 501 outbox persistente indisponível (exige SQLite); falhas de
conexão/5xx usam retentativa com backoff. Não descartar checkpoint nem reiniciar
snapshot silenciosamente: requer decisão explícita e aviso de possível lacuna.

Gravações disponíveis são obtidas separadamente por
`GET /v1/console/history-records/:recordId/recording`, com Bearer e escopo da
central; não aceitar URL arbitrária do envelope. IA acompanha os snapshots.
O player da conversa reutiliza o blob autenticado, sem novo download por bolha.

## Bolha e regra de abertura

O Serviço VoIP do **ViperChat** tem `reopen_on_incoming`, desligado por padrão.
O número da linha (`call.business_phone`, novo campo opcional v1) e o telefone
remoto comprovado determinam caixa/contato. Compatibilidade com produtores
anteriores: aceita também `call.artifacts.note_target`. Caixas parceiras são
normalizadas para a principal antes da resolução; ambiguidade não autoriza
associar pessoas ou abrir atendimento.

- Opção ligada e chamada de entrada ainda em routing/ringing/active: conversa
  única reutiliza/reabre; modo nova conversa cria exatamente uma por chamada.
- Opção desligada: registra na conversa existente sem reabrir, sem criar contato
  ou conversa automaticamente. Sem conversa identificável, mantém na central.
- Snapshot histórico terminal recebido primeiro não reabre atendimentos antigos.
- Atualizações, retentativas, gravação e IA nunca reabrem de novo a mesma chamada.

Mensagem interna privada `voice_call`, com source_id `voip-call:<external_id>`;
identidade persistida por FK na chamada, não por semelhança temporal. Exibe
routing, ringing, active, completed, missed, failed e cancelled com ícones no
padrão Voice, sem acionar controles Twilio/Meta. Sem enviar mensagem ao cliente.
A nota privada de gravação/IA continua para compatibilidade, no mesmo atendimento.

Implantar primeiro receptor + migração aditiva e depois produtor do novo campo.
Esta implementação é dev; publicação/VPS e aceite físico nativo são separados.

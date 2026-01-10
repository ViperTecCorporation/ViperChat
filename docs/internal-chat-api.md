# API de Chat Interno (Backend)

Este documento descreve as rotas do chat interno e exemplos de uso via `curl`.
Substitua os placeholders (`BASE_URL`, `ACCOUNT_ID`, etc.) pelos valores do seu ambiente.

## Autenticacao

Os exemplos usam os headers de autenticacao padrao do Chatwoot:
- `access-token`
- `client`
- `uid`

## Listar conversas internas

```bash
curl -X GET "BASE_URL/api/v1/accounts/ACCOUNT_ID/internal_conversations" \
  -H "Content-Type: application/json" \
  -H "access-token: ACCESS_TOKEN" \
  -H "client: CLIENT" \
  -H "uid: UID"
```

## Criar conversa interna

```bash
curl -X POST "BASE_URL/api/v1/accounts/ACCOUNT_ID/internal_conversations" \
  -H "Content-Type: application/json" \
  -H "access-token: ACCESS_TOKEN" \
  -H "client: CLIENT" \
  -H "uid: UID" \
  -d '{
    "inbox_id": 123,
    "participant_ids": [45, 67],
    "title": "Alinhamento Suporte",
    "message": {
      "content": "Oi, vamos alinhar esse caso?",
      "content_type": "text",
      "private": true
    }
  }'
```

Notas:
- `title` e `message` sao opcionais.
- Se `message` for enviado, ela e criada como lida.
- O inbox precisa ser do tipo interno (Channel::Internal).

## Listar mensagens da conversa interna

```bash
curl -X GET "BASE_URL/api/v1/accounts/ACCOUNT_ID/conversations/CONVERSATION_ID/messages" \
  -H "Content-Type: application/json" \
  -H "access-token: ACCESS_TOKEN" \
  -H "client: CLIENT" \
  -H "uid: UID"
```

## Enviar mensagem na conversa interna

```bash
curl -X POST "BASE_URL/api/v1/accounts/ACCOUNT_ID/conversations/CONVERSATION_ID/messages" \
  -H "Content-Type: application/json" \
  -H "access-token: ACCESS_TOKEN" \
  -H "client: CLIENT" \
  -H "uid: UID" \
  -d '{
    "content": "Mensagem no chat interno",
    "content_type": "text",
    "private": true
  }'
```

Notas:
- Use o `CONVERSATION_ID` (display_id) retornado na criacao da conversa interna.
- `private: true` mantem a mensagem apenas para agentes.

## Iniciar chamada de voz na conversa interna (Enterprise)

```bash
curl -X POST "BASE_URL/api/v1/accounts/ACCOUNT_ID/internal_conversations/INTERNAL_CONVERSATION_ID/voice_call" \
  -H "Content-Type: application/json" \
  -H "access-token: ACCESS_TOKEN" \
  -H "client: CLIENT" \
  -H "uid: UID" \
  -d '{
    "target_agent_id": 45,
    "voice_inbox_id": 789
  }'
```

Notas:
- `INTERNAL_CONVERSATION_ID` e o `display_id` da conversa interna.
- `voice_inbox_id` e opcional; se nao vier, o sistema usa o primeiro inbox de voz atribuido ao agente.

# Atribuir uma conversa a um time pela origem

Esta API localiza uma conversa a partir do número da caixa de entrada UnoAPI e do identificador do contato. Assim, integrações como Typebot e webhooks podem atribuir um time sem conhecer previamente os IDs internos da caixa, do contato ou da conversa.

Disponível a partir da tag `v4.16.10-viper` e da imagem Docker:

```text
ghcr.io/viperteccorporation/chatwoot:v4.16.10-viper-ce
```

## Endpoint

```http
POST /api/v1/accounts/{account_id}/conversations/assign_by_source
```

Substitua `{account_id}` pelo ID da conta no Chatwoot.

## Autenticação

Envie o token no cabeçalho `api_access_token`:

```http
api_access_token: SEU_TOKEN
Content-Type: application/json
```

O endpoint aceita:

- token pessoal de um usuário com acesso à conta;
- token de Agent Bot vinculado à conta ou a uma caixa de entrada da conta.

Nunca exponha um token real em exemplos, logs ou repositórios públicos.

## Parâmetros

| Campo | Local | Obrigatório | Descrição |
| --- | --- | --- | --- |
| `account_id` | URL | Sim | ID da conta no Chatwoot. |
| `inbox_phone_number` | JSON | Sim | Número da sessão/caixa de entrada WhatsApp com provider `unoapi`. Pode conter `+` e formatação. |
| `contact_identifier` | JSON | Sim | Identificador do contato. A busca considera `source_id`, telefone, `bsuid`/LID e `whatsapp_username`. |
| `team_name` | JSON | Sim | Nome completo ou trecho único do nome do time. |

## Exemplo completo com cURL

```bash
curl --request POST \
  --url 'https://chatwoot.exemplo.com/api/v1/accounts/16/conversations/assign_by_source' \
  --header 'api_access_token: SEU_TOKEN' \
  --header 'Content-Type: application/json' \
  --data '{
    "inbox_phone_number": "5566999424178",
    "contact_identifier": "5566996269251",
    "team_name": "departamento pessoal"
  }'
```

## Resposta de sucesso

```http
HTTP/1.1 200 OK
```

```json
{
  "success": true,
  "conversation_id": 12345,
  "inbox_id": 48,
  "team_id": 7,
  "team_name": "departamento pessoal"
}
```

`conversation_id` é o identificador visível da conversa dentro da conta, usado nas rotas de conversa da API do Chatwoot.

## Exemplo para Typebot

No bloco de requisição HTTP do Typebot, selecione o método `POST`, configure os cabeçalhos de autenticação e envie o corpo como JSON. Mantenha as variáveis entre aspas para que o resultado continue sendo um JSON válido:

```json
{
  "inbox_phone_number": "{{sessao}}",
  "contact_identifier": "{{contato}}",
  "team_name": "{{departamento}}"
}
```

Exemplo de URL:

```text
https://chatwoot.exemplo.com/api/v1/accounts/16/conversations/assign_by_source
```

## Como a conversa é localizada

O endpoint executa as seguintes etapas:

1. Localiza, dentro da conta informada, uma caixa WhatsApp com provider `unoapi` pelo `inbox_phone_number`.
2. Localiza o contato vinculado à caixa usando o `contact_identifier` como `source_id`, telefone, `bsuid`/LID ou `whatsapp_username`.
3. Seleciona a conversa individual mais recente desse contato na caixa, ordenada pela última atividade.
4. Procura primeiro um time pelo nome normalizado. Se não encontrar, faz uma busca parcial sem diferenciar maiúsculas e minúsculas.
5. Atribui o time encontrado à conversa.

Para telefones móveis brasileiros informados com 12 dígitos, no formato `55 + DDD + 8 dígitos`, a busca também considera a forma normalizada com o nono dígito.

## Regras e limitações

- Funciona somente com caixas WhatsApp cujo provider seja `unoapi`.
- Conversas de grupo não são consideradas.
- A conversa mais recente pode estar aberta, pendente ou resolvida.
- A rota não cria contato nem conversa.
- A rota não altera o status da conversa.
- A rota atribui somente o time. Ela não cria nem substitui o atendente definido em `assignee_id`.
- Uma busca parcial por `team_name` precisa retornar exatamente um time. Se nenhum ou mais de um time corresponder ao trecho, a requisição retorna `404`.
- O token precisa ter acesso à conta informada na URL.

## Possíveis erros

### Token inválido ou sem acesso

```http
HTTP/1.1 401 Unauthorized
```

```json
{
  "error": "Invalid Access Token"
}
```

Um Agent Bot sem permissão para a conta também recebe `401`.

### Recurso não encontrado

```http
HTTP/1.1 404 Not Found
```

```json
{
  "error": "Resource could not be found"
}
```

Esse retorno pode indicar que a caixa, o contato, a conversa ou o time não foi encontrado. Também ocorre quando o trecho informado em `team_name` corresponde a mais de um time.

### Parâmetro obrigatório ausente

```http
HTTP/1.1 422 Unprocessable Entity
```

Exemplo:

```json
{
  "error": "param is missing or the value is empty: team_name"
}
```

# ViperChat — Agendamento de mensagens via HTTP

Guia de integração para clientes. Contrato conferido no código em 09/10/2026.
Confirme que sua instalação utiliza uma versão que contém este módulo. Os exemplos são ilustrativos; nenhum envio real foi realizado para produzir este guia.

## 1. O que o módulo faz

Programa uma sequência de uma a cinco mensagens para um contato em uma caixa WhatsApp. O agendamento guarda uma conversa de referência, remetente, horário e etiqueta. No momento da execução, o sistema determina a conversa de destino.

Não é necessário que a conversa esteja aberta. É necessário que exista uma conversa de referência do contato na caixa desejada. Não há endpoint de agendamento diretamente por telefone.

### Coleção do Postman

Importe [ViperChat-Agendamento.postman_collection.json](./ViperChat-Agendamento.postman_collection.json) pelo menu **Import** do Postman.

Configure as variáveis da coleção:

| Variável | Valor esperado |
|---|---|
| `base_url` | Domínio da instalação, sem barra final, por exemplo `https://SEU_DOMINIO` |
| `api_access_token` | Token de API de um usuário autorizado |
| `account_id` | ID da conta/empresa |
| `inbox_id` | ID da caixa WhatsApp |
| `contact_id` | ID do contato |
| `conversation_id` | Número público da conversa, exibido na interface |
| `sender_id` | ID do operador que enviará as mensagens |
| `team_id` | ID da equipe, se utilizada |
| `label_id` | ID da etiqueta do agendamento |
| `label_title` | Título da etiqueta, utilizado ao etiquetar a conversa |
| `scheduled_message_id` | ID retornado ao criar o agendamento |
| `phone_number` | Telefone completo com `+` e DDI |
| `scheduled_at` | Data futura em ISO 8601 com fuso |
| `date`, `start_at`, `end_at` | Período para consultar agendamentos |

A coleção também possui variáveis de nome do contato, motivo e textos. Se `scheduled_at` estiver vazio, o script gera um horário cerca de uma hora no futuro e os filtros correspondentes em UTC. Se definir o horário manualmente, ajuste também os filtros de consulta.

As requisições de criação salvam IDs retornados como variáveis da coleção. A busca de contato não escolhe um resultado automaticamente: confira o telefone e copie o ID correto.

**Não execute a coleção inteira pelo Runner.** Existem exemplos alternativos de atribuição/remoção e cancelamento. Execute somente as etapas necessárias. Proteja o token; não o publique nem exporte a coleção com credenciais reais.

## 2. Autenticação e convenções

Base das rotas:

```text
{{base_url}}/api/v1/accounts/{{account_id}}
```

Headers:

```http
api_access_token: TOKEN_DO_USUARIO
Content-Type: application/json
```

Use token de **usuário**, não de bot. A conta precisa ter acesso à API habilitado. As operações também dependem das permissões do usuário e dos recursos disponíveis na conta.

Todos os IDs de conta, contato, caixa, agente e etiqueta devem corresponder à mesma conta. O `conversation_id` é o número público da conversa (`display_id`), não a chave interna do banco. O ID do agendamento é um identificador diferente.

Nos exemplos seguintes, os caminhos são relativos à base acima. Troque as datas por datas futuras ao criar ou reagendar.

## 3. Rotas de apoio

| Método | Caminho | Uso |
|---|---|---|
| GET | `/inboxes` | Consultar caixas |
| GET | `/agents` | Consultar operadores da conta |
| GET | `/inboxes/ID_CAIXA/assignable_agents` | Consultar operadores atribuíveis à caixa |
| GET | `/teams` | Consultar equipes |
| GET | `/labels` | Consultar etiquetas |
| POST | `/labels` | Criar etiqueta |
| GET | `/contacts/search?q=BUSCA` | Buscar contato por telefone, nome ou outros identificadores |
| GET | `/contacts/ID_CONTATO` | Consultar contato e vínculos com caixas |
| POST | `/contacts` | Criar contato |
| POST | `/contacts/ID_CONTATO/contact_inboxes` | Vincular contato a uma caixa |
| GET | `/contacts/ID_CONTATO/conversations` | Consultar conversas do contato |
| POST | `/conversations` | Criar ou obter conversa de referência |
| GET | `/conversations/ID_CONVERSA` | Consultar conversa |
| POST | `/conversations/ID_CONVERSA/toggle_status` | Definir status da conversa |
| POST | `/conversations/ID_CONVERSA/assignments` | Atribuir/remover operador ou equipe |
| GET | `/conversations/ID_CONVERSA/labels` | Consultar etiquetas da conversa |
| POST | `/conversations/ID_CONVERSA/labels` | Substituir etiquetas da conversa |

### Localizar ou criar contato

```http
GET /contacts/search?q=5566996269251
```

A busca é parcial e retorna os contatos em `payload`. Confira o telefone completo antes de selecionar. Use `page` para paginar; a busca retorna até 15 resultados por página e informa `meta.has_more`.

Se não existe contato:

```http
POST /contacts
```

```json
{
  "name": "Cliente de exemplo",
  "phone_number": "+5566996269251",
  "inbox_id": 3
}
```

O ID criado fica em `payload.contact.id`. O campo `inbox_id` também cria o vínculo com a caixa. Não use criação como substituto da busca: o comportamento de reaproveitamento de contatos depende dos identificadores encontrados.

Para um contato existente sem vínculo:

```http
POST /contacts/456/contact_inboxes
```

```json
{ "inbox_id": 3 }
```

Na caixa WhatsApp, o sistema normalmente gera o `source_id` a partir do telefone do contato. Não é necessário informá-lo no fluxo comum.

### Obter a conversa de referência

```http
GET /contacts/456/conversations
```

Retorna em `payload` até 20 conversas visíveis, ordenadas por atividade recente. Escolha uma da caixa desejada usando `inbox_id`. A conversa pode estar resolvida; não precisa reabri-la para agendar.

Se não existe conversa nessa caixa:

```http
POST /conversations
```

```json
{
  "contact_id": 456,
  "inbox_id": 3,
  "status": "resolved"
}
```

Guarde o `id` retornado como `conversation_id`. Não inclua `message` se deseja somente criar a referência, sem enviar uma mensagem agora.

Cuidados:

- Com conversa única habilitada, o POST pode retornar a conversa existente sem aplicar os atributos enviados.
- Uma caixa com bot ativo pode definir o status inicial como `pending`. Confira o retorno.
- Criar conversa gera eventos e pode acionar automações configuradas na instalação.
- Não crie uma conversa nova a cada agendamento se já existe uma referência válida.

Para definir um status explicitamente:

```http
POST /conversations/17280/toggle_status
```

```json
{ "status": "resolved" }
```

Esse endpoint altera o atendimento real; não resolva uma conversa em andamento apenas para preparar um agendamento. Ao abrir uma conversa com token de agente, o fluxo pode atribuí-la ao próprio usuário.

## 4. Operador responsável e remetente do agendamento

São dois conceitos distintos:

- `assignee_id`: responsável da conversa **agora**.
- `sender_id`: operador que enviará o agendamento e será atribuído à conversa **na execução**.

### Alterar a atribuição atual

Todos os exemplos abaixo usam:

```http
POST /conversations/17280/assignments
```

Atribuir operador:

```json
{ "assignee_id": 7 }
```

Remover operador:

```json
{ "assignee_id": null }
```

Atribuir equipe:

```json
{ "team_id": 2 }
```

Remover equipe:

```json
{ "team_id": null }
```

Use requisições separadas para operador e equipe: se ambos forem enviados juntos, o controller prioriza `assignee_id`. Para atribuir ambos, configure primeiro a equipe, depois um operador pertencente a ela. A equipe pode acionar distribuição automática conforme sua configuração.

### Limites do agendamento

| Intenção | Comportamento atual |
|---|---|
| Deixar a conversa sem operador enquanto aguarda | Remover atribuição pela rota de assignments; automações da instalação podem voltar a atribuir |
| Escolher quem enviará no horário | Definir `scheduled_message.sender_id` |
| Não enviar `sender_id` na criação | Utiliza o usuário do token |
| Enviar `sender_id: null` na criação | Também utiliza o usuário do token |
| Manter conversa sem responsável após executar | Não existe opção no agendamento atual |
| Preservar responsável diferente do remetente | O serviço de agendamento sobrescreve a atribuição com o remetente |

Somente administrador pode selecionar outro usuário como remetente. Um agente comum agenda em seu próprio nome. Alterar `assignee_id` não muda o `sender_id` de um agendamento já criado.

O agendamento não possui `team_id`. Se o destino final for uma nova conversa, o serviço não copia explicitamente a equipe da conversa de referência; não presuma que a atribuição anterior será transportada.

## 5. Etiquetas: ID, título e momento da aplicação

Consulte:

```http
GET /labels
```

Exemplo ilustrativo de resposta:

```json
{
  "payload": [
    {
      "id": 5,
      "title": "retorno-agendado",
      "description": "Retornos programados",
      "color": "#0891B2",
      "show_on_sidebar": true
    }
  ]
}
```

Para criar:

```http
POST /labels
```

```json
{
  "label": {
    "title": "retorno-agendado",
    "description": "Retornos programados",
    "color": "#0891B2",
    "show_on_sidebar": true
  }
}
```

Guarde o `id` retornado. O título deve ser único na conta e é convertido para minúsculas. Use letras/números, hífen ou underscore, sem espaços. Criação depende das permissões e do recurso de etiquetas habilitado.

No agendamento, `label_id` é obrigatório e aponta para uma etiqueta da conta. Essa etiqueta é adicionada à **conversa efetivamente utilizada após concluir o envio de todos os itens**, preservando as etiquetas existentes. Não é adicionada imediatamente ao criar o agendamento.

Se precisa etiquetar a referência imediatamente, use:

```http
POST /conversations/17280/labels
```

```json
{ "labels": ["cliente", "retorno-agendado"] }
```

Nessa rota são usados **títulos**, não IDs. Ela substitui a lista atual: consulte antes `GET /conversations/17280/labels` e envie a lista completa para não remover outras etiquetas. Etiquetar a referência não garante a mesma etiqueta em outra conversa criada futuramente; a etiqueta do agendamento é aplicada ao destino final na conclusão.

## 6. Criar o agendamento

```http
POST /scheduled_messages
```

```json
{
  "conversation_id": 17280,
  "scheduled_message": {
    "scheduled_at": "2026-10-15T09:00:00-04:00",
    "sender_id": 7,
    "label_id": 5,
    "reason": "Retorno solicitado pelo cliente",
    "messages": [
      {
        "content": "Olá! Estou retornando conforme combinamos.",
        "content_type": "text"
      },
      {
        "content": "Podemos continuar nosso atendimento?",
        "content_type": "text"
      }
    ]
  }
}
```

### Campos

| Campo | Obrigatório | Uso |
|---|---|---|
| `conversation_id` | Sim | Na raiz; referência para determinar contato e caixa |
| `scheduled_message` | Sim | Objeto que contém o agendamento |
| `scheduled_at` | Sim | Horário futuro; use ISO 8601 com fuso |
| `label_id` | Sim | Etiqueta da mesma conta |
| `sender_id` | Não | Padrão: usuário do token |
| `reason` | Não | Observação do agendamento; não é enviada como mensagem ao cliente |
| `messages` | Recomendado | Uma a cinco mensagens, em ordem |
| `messages[].content` | Texto ou anexo | Texto público enviado ao cliente |
| `messages[].content_type` | Sim no array | Para mensagens comuns, use `text` |
| `messages[].content_attributes` | Não | Atributos adicionais compatíveis com o processamento de mensagens |
| `messages[].attachment_blob_ids` | Não | IDs assinados de anexos já enviados ao armazenamento |
| `messages[].voice_message` | Não | Booleano para áudio enviado como mensagem de voz |

Cada item precisa ter conteúdo ou anexo. Em mídias comuns, mantenha `content_type: "text"`; o tipo do arquivo é obtido do anexo, não de valores como `image`, `audio` ou `pdf` nesse campo.

Existe também o formato de mensagem única com `content`, `content_type`, `content_attributes` e `attachment_blob_ids` diretamente em `scheduled_message`, sem array. Para novas integrações, prefira `messages` e não misture os dois formatos.

Sucesso retorna **201** com um objeto de agendamento. Guarde seu `id`. Isso confirma a criação, não que a mensagem já foi enviada.

O job verifica os agendamentos vencidos a cada minuto. A execução depende das filas e da disponibilidade do provedor; não há garantia de envio no segundo exato. O próximo item é programado 10 segundos após a confirmação de envio do anterior.

## 7. Caixa com e sem conversa única

O serviço procura a conversa **mais recente por data de criação** do contato na caixa no momento da execução. Não fixa o envio na conversa informada na criação do agendamento.

| Situação no momento da execução | Conversa única ligada | Conversa única desligada |
|---|---|---|
| Mais recente aberta ou pendente | Reutiliza | Reutiliza |
| Mais recente resolvida ou adiada | Reabre e reutiliza | Cria outra conversa |
| Nenhuma conversa encontrada | Cria outra | Cria outra |

Em todos os casos, o serviço atribui o remetente do agendamento ao destino. Bots, bloqueios e automações da instalação podem influenciar o estado de conversas criadas.

Exemplo: a referência é `17280`, resolvida, em caixa sem conversa única. Se ela continuar sendo a mais recente no horário, o sistema cria outra conversa. Se um atendimento novo surgir antes e estiver aberto, poderá reutilizá-lo.

`conversation_id` continua sendo a referência original. `target_conversation_id` informa o destino realmente utilizado e pode ser `null` antes da execução.

## 8. Listar e acompanhar

```http
GET /scheduled_messages?date=2026-10-15
```

Resposta: array JSON de agendamentos, ordenado por horário, sem envelope `payload` e sem paginação implementada nesse endpoint.

Filtros adicionais:

```http
GET /scheduled_messages?date=2026-10-15&status=scheduled&inbox_id=3&sender_id=7&label_id=5
```

Para intervalo, envie os dois parâmetros:

```text
start_at = 2026-10-15T00:00:00-04:00
end_at   = 2026-10-16T00:00:00-04:00
```

O início é incluído e o fim é exclusivo. Codifique os parâmetros de URL, principalmente se o fuso utilizar `+`. O Postman faz isso pelo editor de parâmetros.

Sem `date` e sem intervalo completo, o endpoint consulta **somente hoje**, no fuso configurado na conta. Uma lista vazia pode significar apenas que o filtro está no dia errado.

### Status e campos de acompanhamento

| Status | Significado |
|---|---|
| `scheduled` | Aguardando execução |
| `sending` | Sequência em processamento |
| `sent` | Sequência concluída pelo fluxo de envio |
| `failed` | Falha; consultar `error_message` e os itens |
| `cancelled` | Cancelado |

`sent` não comprova leitura pelo cliente. Os itens em `messages` possuem status próprios: `pending`, `dispatching`, `sent`, `failed` e `cancelled`.

Campos úteis: `id`, `scheduled_at`, `status`, `conversation_id`, `target_conversation_id`, `label`, `contact`, `inbox`, `sender`, `created_by_id`, `messages`, `message_count`, `attachment_count`, `error_message` e `can_manage`.

Não existe `GET /scheduled_messages/ID`. Para acompanhar um ID, consulte um período que inclua seu horário e localize o registro no array.

## 9. Alterar e cancelar

Somente criador ou administrador pode alterar/cancelar. Apenas estados `scheduled` e `failed` são editáveis/canceláveis.

### Alterar apenas horário

```http
PATCH /scheduled_messages/123
```

```json
{
  "scheduled_message": {
    "scheduled_at": "2026-10-15T14:00:00-04:00"
  }
}
```

Também aceita PUT. Campos omitidos são preservados. Não envie `conversation_id` para tentar trocar contato ou caixa: essa alteração não é suportada.

### Substituir sequência, etiqueta ou remetente

```json
{
  "scheduled_message": {
    "scheduled_at": "2026-10-15T14:00:00-04:00",
    "label_id": 5,
    "sender_id": 7,
    "reason": "Retorno reagendado",
    "messages": [
      { "content": "Olá! Podemos continuar?", "content_type": "text" }
    ]
  }
}
```

Informar um array `messages` não vazio substitui todos os itens anteriores. Para preservar a sequência, omita o array. Não use array vazio como comando de exclusão, nem altere apenas o campo legado `content` para editar uma sequência existente.

Ao alterar um agendamento `failed`, ele retorna a `scheduled` e limpa o erro geral. Informe horário futuro. Se houve envio parcial, confira os itens antes: a troca da sequência ou nova criação pode repetir mensagens já enviadas. Não trate o PATCH como retomada automática garantida do ponto da falha.

### Cancelar

```http
DELETE /scheduled_messages/123
```

Sem body. Sucesso retorna **204**, sem conteúdo. O registro permanece com status `cancelled`; não é exclusão física e não apaga mensagens já enviadas. Não é permitido cancelar uma sequência que já entrou em `sending`.

## 10. Anexos e áudio

O endpoint de agendamento não recebe arquivo multipart, Base64 nem URL de mídia diretamente. Primeiro faça o upload e obtenha o `signed_id` do blob.

Para upload direto comum:

```http
POST /conversations/17280/direct_uploads
```

```json
{
  "blob": {
    "filename": "documento.pdf",
    "byte_size": 12345,
    "checksum": "MD5_DOS_BYTES_EM_BASE64",
    "content_type": "application/pdf"
  }
}
```

`byte_size` e `checksum` devem corresponder aos bytes reais do arquivo; os valores acima são apenas exemplos. O checksum é MD5 codificado em Base64, não hexadecimal.

O retorno do upload direto contém `signed_id` e `direct_upload.url`/`direct_upload.headers`. Envie os bytes por PUT à URL retornada, usando exatamente os headers fornecidos. Não encaminhe o token do ViperChat para o endereço do armazenamento. Somente após concluir o upload use o `signed_id` no agendamento.

Exemplo de item com documento:

```json
{
  "content": "Segue o documento combinado.",
  "content_type": "text",
  "attachment_blob_ids": ["SIGNED_ID_DO_ARQUIVO"]
}
```

Exemplo de áudio como mensagem de voz:

```json
{
  "content_type": "text",
  "voice_message": true,
  "attachment_blob_ids": ["SIGNED_ID_DO_AUDIO"]
}
```

O provedor precisa aceitar o formato/tamanho da mídia. A coleção inclui a preparação do upload; o PUT dos bytes deve ser configurado com o arquivo real e a URL/headers retornados. Upload multipart em partes é outro fluxo e não é necessário para os exemplos básicos deste guia.

## 11. Restrições de canal e templates

O modelo de agendamento atual exige caixa WhatsApp; outros canais são rejeitados.

A API de agendamento não recebe `template_params`, e o serviço de sequência não encaminha esse campo ao construtor de mensagens. Portanto, não considere este contrato uma API de agendamento de templates aprovados. Em canais que exigem template para o envio, a sequência pode falhar no processamento do provedor. Valide as condições reais de envio da caixa antes de integrar; um POST 201 não garante aceitação futura pelo WhatsApp.

## 12. Erros e prevenção de duplicidade

| HTTP | Situação típica | Ação |
|---|---|---|
| 401 | Token inválido, bot não permitido ou ação não autorizada | Rever credencial e permissões |
| 403 | API desabilitada na conta | Solicitar habilitação ao administrador |
| 404 | Conta/recurso/ID não encontrado | Conferir IDs e número público da conversa |
| 422 | Campos inválidos, etiqueta ausente, data passada, caixa incompatível ou estado não editável | Corrigir parâmetros; ler `error` ou `message`/`attributes` |

Nem todos os erros utilizam o mesmo formato. Validações podem retornar `message` e `attributes`; outras falhas utilizam `error`. Registre status HTTP e corpo, sem registrar o token.

Não há chave de idempotência exposta na criação. Repetir um POST pode criar outro agendamento. Em timeout, não repita cegamente: consulte o período, reconcilie o resultado e só então decida se precisa criar novamente.

Guarde no seu sistema: ID do agendamento, contato, caixa, conversa de referência, horário e identificador do evento de negócio. Use esse vínculo para impedir que o mesmo evento dispare múltiplas criações.

## 13. Roteiro recomendado

1. Configurar domínio, conta e token de usuário.
2. Consultar caixas e escolher uma WhatsApp.
3. Consultar remetentes e escolher um autorizado.
4. Consultar/criar a etiqueta e guardar seu ID.
5. Buscar contato; criar somente se necessário.
6. Obter uma conversa de referência na caixa, mesmo resolvida; criar somente se não existir.
7. Se necessário, ajustar atribuição e etiquetas atuais da conversa, entendendo que são operações independentes.
8. Criar o agendamento com horário futuro e guardar o ID retornado.
9. Consultar o período correto para acompanhar status, itens e destino final.
10. Em falha, verificar o que já foi enviado antes de alterar ou repetir.

Faça a primeira validação em uma caixa de homologação, com contato de teste. Não execute todos os exemplos como uma sequência automática de produção.

# Falha HTTP do provedor sem erro JSON — 24/10/2026

Branch: `feat/agent-voip-webphone`. Somente desenvolvimento.

## Correção

`Whatsapp::Providers::BaseService#handle_error` agora usa uma descrição segura
com o código HTTP quando o provedor não fornece `error.message`. HTML, texto,
corpo vazio e JSON sem descrição deixam de encerrar silenciosamente o job com
a bolha ainda em `progress`. O HTML não é copiado para a bolha. Erros JSON
existentes continuam com a descrição do provedor.

Nas caixas parceiras, mantém-se a classificação de HTTP 502 como entrega
incerta: bolha em falha, sem fallback automático nem retentativa automática.
Não há confirmação suficiente para reenviar sem risco de duplicidade.

## Validação

- Antes do patch: quatro regressões reproduziram `progress` sem erro.
- Depois: 118 exemplos aprovados, zero falhas, nos specs dos provedores
  UnoAPI/Cloud e dos serviços de tentativa/estado da entrega unificada.
- Na réplica existente, uma cópia sintética em transação recebeu resposta
  HTML 502 simulada e persistiu `failed` com descrição HTTP; a transação foi
  revertida. Nenhuma requisição ao provedor foi realizada.
- A mensagem original `2429178`, conversa pública `17265`, foi conferida antes
  e depois: todos os atributos preservados. Continua no estado histórico
  `progress`; não foi corrigida retroativamente nem reenviada.
- Correção somente no backend; nenhum bundle web/Android/iOS alterado.
  Validação de estado/persistência, não um novo ensaio visual nos dispositivos.
- Sem VPS, novos containers, commit ou push. Nenhum arquivo temporário criado.

## Regularização posterior autorizada pelo usuário

Em 24/10/2026 o usuário autorizou marcar somente `2429178` como falha, sem
reenviar. Conferidos conta 1, conversa pública 17265, conteúdo `teste`, estado
`progress` e ausência de ID de provedor, sob lock de linha. Atualizados apenas
`status`, `content_attributes.external_error` e `updated_at`, preservando os
demais atributos. Erro: HTTP 502 sem confirmação de entrega.

Emitida somente a atualização pelo `ActionCableListener` para os clientes da
interface: um `ActionCableBroadcastJob`, sem `SendReplyJob`, callbacks de envio
ou webhooks externos. O payload de backend foi conferido com `status=failed`.

Confirmado que localhost serve o código corrigido. Ensaio Playwright isolado
com cache sintético `progress` e resposta `failed` após F5 terminou com
`memory=failed`, `indexedDB=failed`, erro HTTP 502 preservado e uma única bolha.
Nenhuma mensagem real reenviada. Esse ensaio não lê o IndexedDB do navegador
pessoal do usuário; se outra mensagem apresentar o sintoma, identificar o ID.

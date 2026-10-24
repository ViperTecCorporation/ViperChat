# Fila offline de textos — dev, 24/10/2026

Branch `feat/agent-voip-webphone`, aplicada na réplica existente. Sem VPS, novos
containers, commit/push ou disparo de mensagens sintéticas a contatos reais.

## Experiência

Textos e notas privadas são persistidos no IndexedDB antes de a ação retornar
sucesso ao editor. A bolha mostra “Aguardando conexão para enviar” e permite
cancelar enquanto não estiver em envio. No retorno da rede, ao reabrir o app ou
retomar a conexão, a fila tenta enviar automaticamente, em ordem. O app precisa
estar aberto/retomado: não há promessa de execução com Android/iOS encerrado.

Conversa, referência de resposta, natureza privada e transporte selecionado são
preservados. Há limite de 100 itens / aproximadamente 1 MiB por contexto local.
Textos com mais de 24 horas não são enviados automaticamente: ficam expirados,
para revisão. Anexos, templates, contatos, pagamentos e outros interativos não
entram nesta fila. Escritas externas continuam exigindo conexão e autorização.
Se o armazenamento falhar, não mostramos uma falsa bolha de sucesso; o editor
recupera o texto quando não há um rascunho mais recente.

## Segurança e consistência

- Base local `viper-offline-outbox-v1`, isolada pela origem/instalação/usuário/
  conta/revisão de sessão e fingerprint de permissão do cache. Não guarda tokens.
  Contém texto pessoal e privado; depende da proteção do perfil/dispositivo.
- Reabertura restaura as mesmas bolhas. Logout apaga a fila; troca de contexto
  impede o envio do contexto anterior. Dados de outra permissão não são retomados.
- Antes de cada tentativa há uma leitura autorizada da conversa. A sessão nativa
  precisa estar validada. Mudança de caixa, ausência da capacidade de resposta,
  401/403/404 ou erro definitivo interrompem a tentativa; não há loop automático
  para contornar permissão. O texto permanece na fila para revisão/cancelamento.
- Falha de rede, 408/429 e 5xx mantêm o item e aplicam espera progressiva até 60 s.
  Falha transitória preserva a ordem da fila. Uma mensagem recusada não bloqueia
  para sempre os itens seguintes.
- Cada intenção tem um UUID gerado uma vez, reaproveitado nas retentativas.
  A API anuncia `offline_outbox_version: 1`; o app só habilita a fila para um
  servidor conhecido como compatível, e confere novamente antes do POST.
  Instalações antigas continuam com seu envio online original; nunca repetimos
  automaticamente um POST para um backend que possa ignorar o UUID.
  O endpoint existente de mensagens aceita `client_message_id` para textos e
  serializa a criação com o lock da conversa. O identificador e o digest do pedido
  são persistidos na mensagem, sem prazo Redis, sobrevivendo ao restart do Rails.
- A mesma chave e intenção retornam o ID existente; mesma chave com texto,
  natureza privada ou transporte diferente é recusada. O escopo inclui a conversa
  e o remetente autenticado. A autorização é executada antes da deduplicação.
- Reutiliza `MessageBuilder`, políticas e jobs existentes. A identidade também é
  preservada nas ações existentes de apagar/repetir. Não altera IDs históricos.
- HTTP e websocket/histórico conciliam a bolha pelo UUID/echo/ID real. Reenvio
  após resposta perdida não cria outra mensagem nem outro job de criação.
  Isso não substitui as garantias de entrega do provedor externo.

Cancelar remove uma intenção local; não desfaz uma mensagem que o servidor já
tenha aceitado antes de uma resposta perdida. O cancelamento fica indisponível
durante o POST em andamento. Não existe nova rotina de exclusão de histórico.

## Validação

239 testes frontend / 22 arquivos e 35 exemplos backend passaram. Incluem
persistência/reabertura, resposta perdida com chave estável, ordem, chamada
concorrente ao pump, permissão revogada, isolamento, quota, expiração/cancelamento,
metadados visíveis em notas, ID real recebido sem echo e proteção da identidade
após apagar/repetir. Rails executado exclusivamente em `viperchat_voip_test` e
Redis 15, com verificação de ambiente antes do RSpec.

No navegador real da réplica, usando a entrada nativa e endpoints interceptados:
dois itens reapareceram offline; reconexão gerou três POSTs simulados porque a
primeira resposta foi perdida; restaram dois IDs únicos (991000/991001), nenhuma
pendência e duas bolhas. Uma terceira intenção foi cancelada sem POST. Capturas
em 320/360/390/430/844/1440 px, inclusive paisagem, no modo expandido da conversa.
Scripts e evidências em `output/validation/offline-outbox-20261024` e
`output/playwright/offline-outbox-*` (artefatos locais ignorados pelo Git).

Após o relato de lista em loop durante a simulação, retiradas as falhas forçadas:
seis leituras iniciais e nenhuma consulta adicional de lista/mensagens em 25 s
de observação normal na conversa 13954. Retentativas simuladas e HMR do Vite
não devem ser confundidos com validação de estabilidade prolongada.

Bundle compartilhado compilado e sincronizado Android/iOS. APK Debug compilado,
assinatura conferida, com apenas o bundle `dashboard-BIN3-kMI.js`.
SHA256: `4f613af49d97291dbd6e779bde483c16b69429096ad3890f5afd4ef5fb6713ad`.
Sem aparelho Android conectado; Mac de desenvolvimento inacessível por SSH,
portanto sem execução física nem build/Archive iOS. Plugins nativos indisponíveis
no navegador não foram considerados validação nativa concluída.

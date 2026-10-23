# Avatar do agente na chamada efetuada — 23/10/2026

Correção validada em dev na `feat/agent-voip-webphone`. Publicação por commit/push autorizada posteriormente pelo usuário em 23/10/2026. Sem VPS ou containers novos.

## Regra

- Em chamada efetuada, o remetente da bolha é o agente comprovado nos registros VoipCall vinculados à mesma chamada externa, conta e serviço, com direção outgoing.
- Quando o envelope identifica o ramal de origem, os registros são filtrados por esse ramal. Só um agent_id histórico distinto permite identificar o remetente. Não se escolhe o primeiro atendente ou o operador logado.
- São usados local_agent_id/local_extension registrados na própria chamada, não o novo proprietário de um ramal que tenha sido reatribuído depois.
- Sem prova única ou sem vínculo do usuário à conta, o remetente fica sem agente e a interface mostra ícone neutro. Não há fallback para foto do contato ou do usuário logado.
- A interface só aceita o avatar se o sender é User e seu ID corresponde ao agent_id dos metadados da chamada. Se o agente é conhecido, mas não possui foto, utiliza suas iniciais. Chamadas recebidas e mensagens comuns mantêm suas regras anteriores.

## Validação

Revalidação antes da publicação do restante: 13 exemplos do publicador e 22 testes frontend (Message + VoipCall) aprovados na réplica. O número fixo usado pela fixture antiga já existia no banco de teste; a fixture agora deriva um número por conta, mantendo as validações de coexistência e sem apagar dados do banco. Referências nativas geradas foram normalizadas para caminhos portáteis; APKs, capturas e saídas ficam preservados localmente, ignorados pelo Git.

- 127 exemplos backend aprovados na bateria VoIP/API; 13 exemplos do publicador aprovados novamente após ajuste final. Cobertura adicional: identificação antes de atendimento, reatribuição posterior do ramal, origem divergente, múltiplos agentes conflitantes, chamada desconhecida e preservação do contato nas recebidas.
- 23 testes frontend aprovados, incluindo foto de agente diferente do operador logado, contato incorreto, usuário sem prova, fallback neutro e ausência de impacto em mensagem comum.
- RuboCop sem infrações e ESLint sem erros nos arquivos alterados.
- Playwright no caso real: chamada externa 24, mensagem 2429132, ramal 1001, registro VoipCall 346, agente histórico 7. API passou de sender Contact 100 para User 7; data.agent_id é 7.
- O agente 7 não tem thumbnail/avatar_url cadastrados na réplica. A interface usa suas iniciais e não a imagem do contato. O teste unitário com URL sintética cobre a apresentação da foto quando existente.
- Sem identificação foi simulado apenas na resposta HTTP da sessão Playwright, sem alterar o banco: ícone neutro presente e nenhuma imagem de contato/agente. A interceptação foi removida depois.
- Desktop 1366 e mobile 320/360/390/412/430 px: alinhamento à direita preservado e nenhum overflow. Capturas em `output/playwright/voip-origin-agent-*.png` e `voip-origin-unknown-neutral.png`.

## Runtime, histórico e rollback

Atualizados somente o publicador e Message.vue na réplica. A mensagem do exemplo foi atualizada sob lock do serviço, sem criar outro registro. Permaneceram iguais message_id, source_id, conversation_id, contact_id, anexos, análise e privacidade.

Backup restrito antes da correção do exemplo: `/app/tmp/voip-origin-avatar-20261023/external-24-20261023T183740579195.json`. Para rollback, restaurar sender_type, sender_id e content_attributes dessa mensagem por ID, preservando os demais vínculos; não excluir bolhas, áudio ou contato. Não houve migração em massa das chamadas antigas.

## Nativos e limpeza

### Correção retroativa autorizada em dev

Revisadas as bolhas efetuadas existentes na réplica. A mensagem 2429132 (conversa 9470) já estava correta. Corrigido o remetente da mensagem 2429141, conversa pública 13954, chamada externa 30, de Contact 6 para User 7 (Rodrigo), comprovado pelo VoipCall 355, ramal histórico 1001. Não se utilizou o usuário logado nem apenas o vínculo atual do ramal.

Alteração sob lock/transação, somente no remetente; `data.agent_id` já era 7. Comparações antes/depois confirmaram preservação de todos os demais atributos da mensagem (exceto updated_at), das outras mensagens da conversa, anexos, artefato, referências ActiveStorage e contagens de mensagens, conversas, chamadas e mídias. Gravação, resumo e transcrição não foram reprocessados. Backup restrito (0600): `/app/tmp/voip-origin-avatar-20261023/message-2429141-20261023T185157324994.json`. Rollback: restaurar somente sender_type/sender_id pelos valores desse backup. Sem containers novos ou acesso à VPS. Nenhum intermediário temporário foi criado nesta correção; o backup permanece para recuperação.

Bundles Android/iOS regenerados com heap Node limitado a 3 GB, em cópia isolada. APK Debug recompilado com um worker e heap Gradle de 1 GB, assinatura verificada: `output/validation/voip-origin-avatar-20261023/viperchat-avatar-dev.apk` (SHA-256 `66a54b568cb87eb5e878b570caf6fe924ccc310d7d78a32c5e1a5e591f91b559`). Não houve dispositivo Android conectado, portanto sem instalação/aceite em aparelho. O Mac recusou a conexão configurada, portanto sem build/Archive e aceite iOS. Sem publicação de apps.

A cópia Linux de fontes/build e o runner temporário são removidos após validação. Preservados resultados, capturas, APK e backup para rollback. O staging Windows anteriormente bloqueado continua pendente, sem nova tentativa de contornar a proteção ou apagar dependências compartilhadas.

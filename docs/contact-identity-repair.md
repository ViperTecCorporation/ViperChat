# Recuperação de identidades de contato — migration 20260919010000

## Regra aprovada

- Consolidar contatos da mesma conta por e-mail igual (sem distinção de maiúsculas) ou vínculo repetido `(inbox_id, source_id)`, inclusive cadeias transitivas.
- Manter o contato de menor ID. Valores preenchidos do cadastro mais antigo prevalecem; valores ausentes são complementados. Atributos JSON são unidos no primeiro nível, com precedência do mais antigo. Divergências ficam preservadas na auditoria.
- Preservar bloqueio se qualquer contato consolidado estiver bloqueado.
- Remover `@lid` do campo e-mail, não dos `source_id` válidos da integração. Essa limpeza é pontual; não altera o contrato dos providers.
- Na primeira etapa, reatribuir conversas e remetentes ao contato principal, sem juntar os IDs das conversas. A etapa complementar abaixo consolida conversas somente conforme a configuração da caixa.
- Transferir vínculos, notas, chamadas, pesquisas de satisfação, agendamentos, referências de importação e referências polimórficas conhecidas, incluindo Enterprise. Não executar modelos, callbacks ou jobs durante a recuperação.
- Deduplicar vínculos preservando o menor ID. Os tokens dos vínculos removidos ficam na auditoria; sessões que usavam esses tokens podem precisar ser reabertas.
- Deduplicar associações idênticas de grupos, etiquetas e anexos, sem remover blobs. Avatares diferentes continuam armazenados; não há seleção visual de um novo avatar nesta migration.
- Inscrições de notificação: somente mesmo usuário/tipo; preservar a inscrição atualizada mais recentemente, incluindo suas chaves. Identificador compartilhado entre usuários/tipos diferentes aborta toda a operação.

## Segurança e implantação

A migration é transacional e cria `contact_identity_repair_audits` com a versão original de cada linha alterada e o ID de destino. A tabela contém dados pessoais e pode conter tokens de notificação; não expor por API, logs ou exportações públicas. Não há expurgo automático nem cópia dos dados reais no repositório.

**Antes de produção:** backup testado, janela de manutenção e suspensão de todas as instâncias escritoras (web, workers e outros consumidores). A rotina bloqueia gravações nas tabelas envolvidas e reconstrói apenas os três índices únicos identificados. Não é uma migration online sem impacto. O timeout de aquisição de lock é 5 segundos; por comando, 300 segundos. Falhas abortam a transação.

Em instalações com vínculos entre contas diferentes ou conflito de unicidade adicional, a migration falha explicitamente. Não ignora erros para marcar a versão como executada. Um índice único saudável é indispensável; essa recuperação não resolve a causa de corrupção física do PostgreSQL.

O `down` é irreversível: rollback durante a execução é automático; após commit e novas gravações, desfazer exige plano usando backup e auditoria, não um unmerge automático. Guardar o backup original fora da pasta sincronizada.

### Índices existentes com cobertura inconsistente

A execução inicial da imagem `.25` em produção falhou ao atualizar um vínculo
duplicado antes de removê-lo: o índice único existente rejeitou o UPDATE. A rotina
agora remove os três índices listados em `INDEXES` **depois de adquirir os locks e
validar as contas, antes de alterar registros**, reconstruindo-os ao final da mesma
transação. Não há janela de escrita concorrente sem unicidade: os locks permanecem
até o commit. Em erro, PostgreSQL restaura dados e DDL, inclusive os índices antigos.

Os testes usam índices parciais para simular cobertura incompleta sem provocar
corrupção física. Verificam a ordem das operações, reconstrução integral e rollback.
Uma restauração lógica não reproduz corrupção física de índice: ela reconstrói os
índices e pode rejeitar os três índices únicos por duplicidades existentes.

O serviço automático deve condicionar web e workers a
`chatwoot-migrate: { condition: service_completed_successfully }` no `depends_on`.
Isso impede a subida inicial após uma falha, mas não substitui uma janela de
manutenção: processos já em execução precisam ser parados antes deste reparo.

## Validação local

Backup pré-reparo restaurado em PostgreSQL 16.11, sem iniciar Rails/Sidekiq:

- Teste da migration real com rollback, execução repetida/idempotência e comparação de contagens e fingerprints do histórico, excluindo apenas colunas de vínculo autorizadas.
- Os três índices únicos recriados passaram em `bt_index_check(..., true)`.
- 7 cenários PostgreSQL independentes: união transitiva/menor ID; isolamento de contas/limpeza LID; colisão de grupos/bloqueio; notificações mais recentes; anexos/etiquetas; rollback em conflito de usuário; recusa de vínculo entre contas.
- RuboCop nos dois arquivos Ruby com a configuração do projeto: sem infrações.

Os testes em `spec/migrations/repair_duplicate_contact_identities_spec.rb` são **standalone**, sem carregar Rails. Exigem um banco vazio e descartável chamado `viper_identity_fixture_test`, com `PGHOST`, `PGUSER`, `PGPASSWORD` e `PGDATABASE` configurados. Rodar `bundle exec rspec spec/migrations/repair_duplicate_contact_identities_spec.rb`. Na suíte comum, sem esse banco explícito, são marcados como pendentes para não trocar a conexão nem tocar em fixtures compartilhadas. Todo DDL/dado de cada exemplo termina em rollback.

Resultados confirmados após commit local e registro da versão em `schema_migrations`: contatos 66.694 → 66.684; vínculos 153.430 → 153.417; inscrições 115 → 102. As 1.555.425 mensagens e 17.981 conversas foram preservadas. Nenhuma conversa referencia os contatos removidos, nenhum email `@lid` permanece, e os 432 índices B-tree públicos passaram em `bt_index_check(..., true)`. Auditoria: 3.292 linhas originais preservadas.

Mudança exclusivamente de dados/backend; não exige empacotamento Android/iOS. Não representa teste funcional dos apps ou autorização de deploy.

## Complemento: conversa única — migration 20260919020000

A migration complementar usa a auditoria da etapa anterior para limitar o escopo aos contatos corrigidos. Ela é separada porque a primeira já foi aplicada no dev.

- `lock_to_single_conversation=false`: não consolida conversas, nem mesmo resolvidas. Mantém IDs e histórico separados.
- `true`: consolida apenas dentro da mesma conta, caixa, contato e identidade de grupo. Não mistura grupos diferentes nem conversa individual com grupo.
- O contato continua sendo o de menor ID. Para a conversa, prevalece **created_at mais recente, com maior ID como desempate**, independentemente do source_id e da última atividade. A conversa atual conserva todos os seus atributos; a incorporação do histórico não atualiza sequer last_activity_at. O recebimento normal da próxima mensagem continua seguindo seus próprios callbacks.
- Mensagens mantêm IDs, conteúdo e anexos; conversation_id passa a apontar para a conversa principal. Demais referências diretas e polimórficas conhecidas, incluindo target_conversation_id dos agendamentos, são reatribuídas.
- Participantes, menções, etiquetas e membros antigos ficam preservados na auditoria, mas **não são acrescentados à conversa atual**, evitando ampliar acesso ou alterar sua configuração. Anexos com associação idêntica são deduplicados sem excluir blobs.
- Se a conversa antiga possui SLA aplicado ou avaliação CSAT, a consolidação é interrompida para preservar esse histórico separado e não fazê-lo assumir o lugar do SLA/avaliação atual. Conflitos adicionais de unicidade/FK também não são ignorados. Na migration, a operação aborta; no recebimento/sincronização, o savepoint do merge é desfeito e a conversa mais nova continua disponível para receber mensagens.
- Fixadas e arquivadas **da atual** prevalecem: são removidas somente as referências às conversas antigas excluídas, sem fixar ou silenciar a atual por herança. Outras contas e preferências não são alteradas.
- A auditoria própria `conversation_identity_repair_audits` preserva os registros originais, inclusive conversas removidas e preferências. Links antigos de conversa não recebem redirecionamento automático nesta migration.

Testes: 12 exemplos somando as duas migrations, sem falhas. Cenários ativado/desativado, isolamento de caixas/contas/grupos, conteúdo/IDs de mensagens, agendamentos, notificações, participantes, preferências, idempotência e rollback por conflito de SLA. RuboCop passou.

No backup real local, todas as caixas afetadas (2 e 17) estavam com a opção desligada. A etapa complementar deve ser um no-op sobre o histórico nessa base; não ativamos a opção para forçar consolidação de atendimentos reais. O cenário ativado foi exercitado no banco descartável de testes.

## Recebimento e sincronização

O recebimento WhatsApp e a importação/exportação UnoAPI usam `Conversations::SingleConversationMergeService`, com a mesma rotina de transferência `Conversations::HistoryMerge` da migration. No runtime, somente depois de transferir/arquivar os dependentes, a conversa antiga é excluída usando uma instância fresca, sem associações carregadas que possam agendar a destruição de mensagens transferidas. Isso preserva os eventos after-commit de atualização dos contadores. Na migration offline, a exclusão é SQL, sem callbacks. A rotina usa savepoint e lock do contato/conversas durante a consolidação. Nenhuma mudança de payload/provider foi feita.

A auditoria registra a origem, mas não altera a lógica dos relatórios: relatórios que inferem agente/time histórico apenas pela atribuição atual da conversa continuam tendo essa limitação. Avaliações e SLAs que exigem manutenção de contexto permanecem nas conversas separadas.

Validação final da política de conversa mais nova: 633 exemplos de regressão Ruby e 12 exemplos standalone das migrations, sem falhas; RuboCop em 11 arquivos, sem infrações. A migration foi novamente exercitada em transação com rollback no backup restaurado local: contagens e fingerprints integrais das 17.981 conversas e 1.555.425 mensagens permaneceram iguais, pois as caixas afetadas têm conversa única desligada. Nenhuma alteração foi aplicada em produção.

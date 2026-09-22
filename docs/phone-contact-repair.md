# Consolidação complementar por telefone

## A partir da v4.16.12-viper.27

`db:migrate` cria somente a tabela de auditoria, sem unir contatos ou conversas.
O reparo descrito abaixo é histórico/manual: sua execução exige chamar
`repair!(confirmation: 'MERGE_REVIEWED_CONTACTS')` após inventário, backup e
autorização. O método não possui filtro por conta nem simulação embutida.
Não adicioná-lo à inicialização automática. Reparos e auditorias existentes
permanecem intactos. As instruções antigas abaixo de execução via db:migrate
não se aplicam mais ao reparo de dados.

Migration: `20260921010000_repair_duplicate_phone_contacts`.

## Critério e preservação

- Contatos individuais da mesma conta e mesmo telefone, removendo somente formatação (`+`, espaços, pontos, parênteses e hífens).
- Considera números entre 8 e 15 dígitos, sem zero inicial. Ignora vazios, letras e formatos fora desse recorte. Não presume DDI, não acrescenta `55` e não faz equivalência com/sem nono dígito.
- Exclui perfis vinculados a grupos (`@g.us` ou conversa de grupo), que podem conter telefone herdado de participante.
- Preserva o menor ID e os seus atributos preenchidos; complementa valores ausentes, une JSON e preserva bloqueio. Não modifica identificadores telefone/LID dos vínculos.
- Transfere referências conhecidas de contatos, remetentes, notas, anexos, etiquetas e demais dependentes, sem callbacks nem envio de mensagens.
- Só consolida conversas nas caixas com `lock_to_single_conversation=true`, separadas por conta, caixa, contato e identidade de grupo. Mantém a conversa criada mais recentemente e as suas configurações/participantes, arquivando o estado das antigas.
- SLA/CSAT histórico que exige atendimento separado provoca rollback de toda a migration; conflitos adicionais não são ignorados.

## Auditoria e execução

`phone_contact_repair_audits` guarda os registros originais e IDs de destino. Contém dados pessoais: não expor por API nem versionar exportações. As auditorias das migrations anteriores permanecem inalteradas.

A execução é transacional e idempotente. Não remove/reconstrói índices: pressupõe o reparo de integridade anterior concluído. Adquire locks de escrita, com timeout de aquisição de 5s e timeout de comando de 300s.

Antes de aplicar: backup testado, inventário dos candidatos, janela de manutenção e suspensão de web/workers e demais escritores. Executar `RAILS_ENV=production bundle exec rails db:migrate`. Só reiniciar os escritores após validar fingerprints de mensagens/arquivos, auditoria, vínculos e conclusão da migration.

Reversão após commit não é automática: requer backup/auditoria e preservação das gravações posteriores. Não executar `db:rollback` como tentativa de unmerge.

## Limite do reparo

Esta migration corrige os cadastros existentes; não cria restrição única por telefone e não altera o tratamento de colisão no `ContactInboxBuilder`. Novas duplicidades exigem prevenção no fluxo de cadastro/criação de conversa em uma alteração separada. Clientes com IDs removidos em memória precisam atualizar a lista de contatos.

## Testes

Rodar `spec/migrations` no banco descartável `viper_identity_fixture_test`, conforme `docs/contact-identity-repair.md`. Casos da nova migration: normalização conservadora, menor ID, aliases telefone/LID, contas distintas, formatos inválidos, exclusão de grupos, conversa única ligada/desligada, preservação de mensagens/participantes, rollback por SLA, unicidade de e-mail e repetição idempotente.

Mudança somente de dados/backend: não modifica bundles Web/Android/iOS.

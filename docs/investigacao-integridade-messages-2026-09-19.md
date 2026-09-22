# Investigação de integridade de messages — 19/09/2026

## Escopo e conclusão

Inspeção somente leitura na VPS 192.168.0.50, container chatwoot-postgres,
base chatwoot_db, e revisão do código local e de trechos do serviço implantado.
Nenhum REINDEX, DELETE, migration, instalação de extensão ou alteração de configuração executado.
As alterações locais anteriores do frontend foram preservadas.

O relato de divergência entre índice e varredura sequencial no mesmo snapshot,
resolvida por REINDEX, é compatível com inconsistência do índice. Não reproduzimos
a condição anterior: o índice já foi reconstruído. A causa original continua aberta.
Não atribuir o incidente a concorrência da aplicação sem evidência adicional.

## Evidências atuais

- Aplicação web/workers: v4.16.12-viper.24-ce.
- PostgreSQL 16.11, Debian; glibc 2.36-9+deb12u13.
- Container criado em 22/07/2026; RestartCount=0. Postmaster iniciado em
  08/09/2026 05:30:10 UTC. Estes campos não demonstram ausência de reinícios históricos.
- Volume persistente unochat_postgres em /var/lib/postgresql/data.
- Banco en_US.utf8; datcollversion NULL, versão efetiva 2.36.
  source_id usa collation default. NULL não comprova compatibilidade nem mudança.
- fsync, full_page_writes e synchronous_commit ligados; data_checksums desligado.
  Checksums desligados reduzem a capacidade de diagnóstico; não provam corrupção.
- index_messages_on_source_id: B-tree não único, 76 MB, indisvalid/indisready=true.
- Todos os 15 índices de messages listados estão válidos/prontos no catálogo.
  Estas flags NÃO verificam integridade física/lógica.
- messages: heap 477 MB; tamanho total 1.768 MB incluindo índices/TOAST.
- amcheck 1.3 disponível, porém não instalado nessa base. Nenhum amcheck executado.
- Recorte de até 20.000 linhas do log PostgreSQL dos últimos sete dias sem
  correspondências para collation mismatch, invalid page, checksum, PANIC,
  recovery/interrupção e erros de leitura/escrita. Journal do kernel dos últimos
  sete dias sem correspondências para os padrões de I/O, filesystem, NVMe/OOM
  consultados. Ausência no recorte NÃO exclui eventos antigos ou logs perdidos.

### Inventário agregado de repetições

Consulta concluída em transação READ ONLY, statement_timeout=5s,
lock_timeout=1s, work_mem=16MB, paralelismo desligado e acessos indexscan,
indexonlyscan e bitmapscan desabilitados para não depender do índice investigado.
Agrupamento de todos os source_id não nulos/não vazios por inbox_id/source_id:

| Medida | Resultado |
|---|---:|
| Chaves repetidas | 601 |
| Mensagens nessas chaves | 1.331 |
| Linhas além da primeira por chave | 730 |

Não interpretar as 730 linhas como registros removíveis. O agregado não separa
contatos compartilhados, ecos legítimos e duplicações indevidas. Não foi feita
exclusão nem exportação de conteúdos ou identificadores pessoais.

## Revisão da aplicação

1. `incoming_message_service_helpers.rb#find_message_by_source_id` consulta
   `inbox.messages.where(source_id: ...).order(:created_at)`; escolhe primeiro
   registro sem external_echo. Não há unicidade no schema para messages.source_id.
2. `incoming_message_base_service.rb#process_messages` consulta existência ANTES
   do lock; a transação de criação começa depois. Não repete a consulta após
   adquirir o lock. Existe janela se uma consulta antiga for seguida da aquisição
   após expiração/perda da chave; não demonstra que isso causou o incidente.
3. `MessageDedupLock`: SET NX EX atômico por inbox/message ID, TTL de 24 horas.
   A chave não é revertida quando a transação SQL falha: uma tentativa posterior
   pode ser descartada sem registro persistido. É um risco de perda/retry separado
   do problema de integridade. Não basta apagar a chave indiscriminadamente.
4. `Webhooks::WhatsappEventsJob`: mutex por inbox/remetente, TTL de 30 segundos,
   retry de conflito em 2s até 20 tentativas. Pode expirar durante download lento.
   `Redis::LockManager#unlock` usa DELETE sem conferir proprietário: um detentor
   antigo pode remover o lock de um novo detentor após expiração.
5. `SendOnWhatsappService#persist_source_id` também adquire a chave de deduplicação,
   mas não condiciona update ao resultado. Revisar a corrida entre envio e eco
   antes de modificar semântica de locks.
6. `create_contact_messages` cria uma mensagem por contato compartilhado,
   reutilizando o mesmo source_id. Isto inviabiliza impor UNIQUE(inbox_id,source_id)
   genericamente sem redesenhar/classificar esse fluxo.

Trechos de consulta, lock de 24h e criação de contatos também conferidos no
container implantado. Demais observações são revisão do checkout; não equivalem
a teste de carga/concorrência nem a comprovação de exploração em produção.

## Plano para integridade — pendente de aprovação

1. Obter evidência original: SQL, EXPLAIN dos dois planos, IDs anonimizados,
   horários, resultado antes/depois do REINDEX e identificação do backup.
   Preservar cópia física/snapshot anterior, se existente. Restore lógico recria
   índices e não preserva sua estrutura corrompida para perícia.
2. Inventariar upgrades: versão que criou o cluster, pg_upgrade/restore, imagens
   e digests anteriores, versões glibc/ICU. Obter logs anteriores a sete dias e
   eventos do host/hipervisor/storage, incluindo saúde de disco e memória.
3. Antes de qualquer mudança: validar backup restaurável (base física + WAL ou
   snapshot consistente) em ambiente isolado; documentar retenção e recuperação.
   Este trabalho não confirmou a existência/recuperabilidade do backup relatado.
4. Com aprovação, instalar amcheck e testar em cópia isolada primeiro. Em janela
   de menor carga, executar bt_index_check no source_id, um índice por vez, com
   timeout e observação de latência/I/O/filas. Começar estrutural, depois
   heapallindexed=true para verificar cobertura do heap. Interromper por impacto,
   timeout ou erro; não reconstruir automaticamente.
5. Priorizar depois messages_pkey, índices inbox/account e identificação de
   contact_inboxes/conversations. bt_index_check não valida índices GIN.
   Não executar bt_index_parent_check em horário de atendimento.
6. Se houver erro: preservar logs e snapshot, classificar causa e apresentar
   plano específico de reparo, espaço extra, locks, janela e recuperação antes
   de aprovar REINDEX. Não restaurar índice defeituoso como rollback. Não executar
   REFRESH COLLATION VERSION apenas para ocultar avisos nem agendar REINDEX periódico.

Documentação PostgreSQL 16: bt_index_check usa AccessShareLock; heapallindexed
acrescenta custo de leitura e sua aprovação não prova ausência absoluta de erros.
bt_index_parent_check usa ShareLock e bloqueia escrita. Mudanças de collation
podem invalidar a ordenação; refresh de versão não reconstrói índices.

- https://www.postgresql.org/docs/16/amcheck.html
- https://www.postgresql.org/docs/16/sql-altercollation.html

## Plano para robustez de deduplicação — sem migration pronta

- Testar falha após adquirir lock/antes de commit, retry, expiração durante
  download, dois workers, eco concorrente ao envio e indisponibilidade do Redis.
- Preferir lock com token de proprietário e liberação condicional, com política
  explícita de duração/renovação; não confundir cache de evento processado com
  mutex de execução. Revalidar existência dentro da seção crítica.
- Classificar as 601 chaves por provider, direção, conta, anexos/vCards, eco,
  timestamps e relações antes de escolher unicidade. Não deduplicar só por texto.
- Avaliar um registro de evento recebido, único por canal/inbox/ID externo,
  separado das mensagens filhas. Seu processamento precisa ser transacional e
  recuperável, sem marcar concluído antes do commit. Alternativa: chave com
  discriminador de componente, apenas após validar todos os providers.
- Um índice único futuro protege concorrência sob banco íntegro; não resolve
  corrupção física ou semântica de collation. Apresentar migração concorrente,
  compatibilidade dos writers, tratamento de conflito e rollback antes do deploy.

## UnoAPI: ocorrência independente

Transcrições vazias com UUIDs diferentes para o mesmo áudio, conforme relato,
não serão eliminadas por unicidade de source_id nem por REINDEX. É necessário
correlacionar com ID original/áudio na origem, revisar reenvios e impedir emissão
de resultados vazios com semântica específica. Evitar filtro global de conteúdo
vazio no Chatwoot: mensagens legítimas de mídia podem não ter texto.

## Limites desta rodada

Não alteramos código de aplicação, banco ou infraestrutura. Não executamos testes
de aplicação porque a entrega é diagnóstico. Ainda faltam amcheck, classificação
dos repetidos, histórico anterior e reprodução controlada de concorrência. Não há
causa-raiz confirmada nem autorização implícita para reparo em produção.

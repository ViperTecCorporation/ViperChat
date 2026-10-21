# Echo sem destinatário explícito — eventos 463 e 468

Autorizado: corrigir em dev, validar os dois casos reais e aplicar via hostpath
com backup na VPS. Preservar contatos, IDs, histórico, todas as bolhas e mídias.
Não disparar mensagens reais de teste.

## Diagnóstico e decisão

- Conta 1/vínculo 1/caixas 1 e 65, contato 62583, conversa 37531 (`#16364`).
- Evento 463: original `CE646E4FEBE80643FD7D`, API 2498978 e echo 2498979.
- Evento 468: original `CEF602230379654F1521`, API 2498991 e echo 2498992.
- Meta informa BSUID, cujo alias já pertence ao contato com telefone conhecido.
  Uno informa o remetente empresarial sem `to`, mas há telefone nos recibos.
- O comparador interpretava a falta de peer como conflito com o recibo, impedindo
  inclusive a resolução por contraparte API comprovada pelo ID original.
- Agora o alias BSUID ativo, restrito à caixa/conta/papel de saída, pode provar
  o telefone. Ausência continua pendente; recibo contraditório continua bloqueado,
  inclusive quando o peer só é conhecido no outro canal. Aliases retirados por
  troca de telefone não são usados nem restaurados.
- Ecos novos desse formato adotam a bolha API já persistida. Para estes legados,
  resolver a pendência criando somente o alias técnico para a própria bolha do
  echo existente. Não apagar, esconder, mover ou renumerar nenhuma das bolhas.
- Resolver legado exige ID original único no par, mesmo atendimento, contato,
  direção/tipo, envio API reconhecido e transporte/generation confirmados. Sem
  comparação por texto ou aproximação temporal. Payload/observações preservados.

## Aceite dev

- 14 exemplos novos: eventos 463/468, ingestão futura sem duplicação, preservação
  de mídia e bloqueios por recibo/peer divergente, alias retirado/ausente,
  geração/ativação, nota privada, outro atendimento, tipo e contraparte ambígua.
- Regressão de 726 exemplos Ruby sem falhas, incluindo os 14 novos e os fluxos de
  contato 231, aliases, recibos, echoes, mídia, grupos, revisões e agendamentos.
- Cinco arquivos de aplicação, um spec e executor com RuboCop sem infrações;
  executor com sintaxe Ruby válida. Sem frontend, assets ou pacotes nativos novos.
- Runtime, Redis e banco sintético exclusivos, sem envio de mensagens externas.

## Operação

- Pacote: `/var/snap/docker/common/viperchat-hostpaths/sparse-echo-463-468-20261020/`.
- Backup PostgreSQL restrito `private/database.dump`: 251.264.559 bytes; catálogo
  `pg_restore --list` aprovado. Não houve ensaio de restauração.
- Inventariar Compose/containers; comparar as quatro fontes existentes com a
  base `a08454624044871d097a4dea92ee6256643b120a`, validar sintaxe do serviço novo.
- Cinco binds `:ro`; substituir somente o bind anterior do comparador de
  participantes e acrescentar os demais. Manter os outros 13 binds, `x-base`,
  imagem compartilhada `.33`, redes, variáveis e duas réplicas dos workers.
- Validar o Compose candidato antes do quiet. Drenar/recriar somente web e
  workers, liberando-os antes de tratar os dados. Não reiniciar banco, Redis ou
  ViperConnect. Conferir hashes, classes, workers e HTTP.
- Executor `script/validation/resolve_sparse_echo_events_20261020.rb`: prévia e
  fingerprint; aplicar somente os eventos 463 e 468. Validar inventários completos
  dos contatos 231/62583, seus aliases, atendimento, quatro mensagens, evidências
  e arquivos relacionados. Só concluir com prova segura; sem replay/provider IO.
- Rollback de código/Compose se necessário; nunca restaurar banco automaticamente.

## Execução

Aplicado em **20/10/2026 às 20:31 de Cuiabá** (21/10/2026 às 00:31 UTC),
por SSH/hostpath. Fontes locais baseadas em `a08454624044871d097a4dea92ee6256643b120a`,
branch `fix/whatsapp-sparse-outgoing-receipts`. Na aplicação operacional ainda
não havia commit/push; a publicação posterior na `4.16.0` foi autorizada pelo
administrador, sem nova execução na VPS.

- As quatro fontes existentes coincidiram com a base nos três containers; novo
  serviço ausente antes. Sintaxe dos cinco arquivos validada antes da troca.
- Prévia de produção em processo isolado com PostgreSQL somente leitura
  comprovou exatamente `463 -> 2498979` e `468 -> 2498992`; não executou replay.
- Compare resolvido dos dois Composes confirmou todos os serviços/configurações
  não relacionadas idênticos, inclusive os outros 13 binds. Compose salvo do
  Portainer mantém `x-base`, imagem única `.33` e agora 18 mounts por web/worker.
- Quiet às **20:31:15**, dois workers e zero trabalhos ativos. Web e dois workers
  recriados até **20:31:48**, sem reiniciar banco, Redis ou ViperConnect. Workers
  liberados antes da execução do reparo de dados; não permaneceram em quiet.
- Cinco hashes e os 18 mounts conferidos em cada container; classe nova carregada.
  Não houve assets, migração, nova imagem, atualização móvel ou envio externo.
- Executor aplicado com fingerprint da prévia atual e saída zero. Eventos 463 e
  468 agora `completed / correlated_existing_echo`, ambos com oito tentativas
  registradas no retrato final. Acrescentados somente os aliases técnicos dos
  echoes para suas próprias bolhas anteriores, sem unificar/excluir essas bolhas.
- Conferência antes/depois aprovou igualdade de todos os atributos dos dois
  contatos 231/62583 e seus aliases, conversa 37531, quatro mensagens, quatro
  identidades e payloads dos dois eventos; nenhum anexo/blob relacionado mudou.
  As mensagens **2498978, 2498979, 2498991 e 2498992** permanecem com IDs/source_id
  e conteúdo intactos, no mesmo atendimento. Contato 231 e sua nova identidade
  continuaram intactos. Nenhum contato foi mesclado ou mensagem/mídia apagada.
- Nova verificação às **20:35:10 de Cuiabá**: ambos os eventos concluídos, dois
  workers com `quiet=false`, login público HTTP 200. Não houve rollback.
- Evidências restritas na área `private/`: backup/catalog, Composes, inspeções de
  runtime, fontes anteriores, `preflight.preview.json`, `preview.fresh.json`,
  `apply.parsed.json`, `verification.after.json` e `state.final.log`.
- Removidos os dois containers exclusivos de testes, banco sintético
  `viperchat_sparse_echo_20261020` e pacotes/candidato de transferência. Redis
  sintético usou tmpfs, sem volume persistente. A cópia de preflight desapareceu
  com a recriação do web. Dados/serviços dev ativos, cache Docker compartilhado,
  backup de recuperação e arquivos efetivamente montados foram preservados.
  A limpeza não implica compactação do VHDX ou aumento de espaço no SSD.
- Aceite técnico e correlação dos legados aprovados. A prevenção de novas bolhas
  passou nos testes sintéticos; entrega externa posterior deve ser observada em
  tráfego legítimo, pois nenhuma mensagem real foi disparada para testar.

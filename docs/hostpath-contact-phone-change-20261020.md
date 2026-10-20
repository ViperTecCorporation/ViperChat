# Troca de telefone da mesma pessoa — identidade WhatsApp

Solicitação: manter o contato 231 e seu histórico ao trocar o telefone cancelado
por outro número da mesma pessoa. Implantação autorizada via SSH/hostpath depois
da validação em dev, com backup e sem apagar mensagens ou mídias.

## Regra geral

- Uma alteração real de telefone retira do uso ativo os aliases anteriores,
  limpa o BSUID/user_id e o username anteriores e registra a troca em JSON.
- Não remove aliases: ID, source_id e vínculos históricos permanecem intactos.
  Novos aliases telefônicos são criados nas caixas ViperConnect necessárias.
- A comparação preserva a equivalência brasileira com/sem nono dígito e a
  correção legada comprovada de nono dígito indevido em telefone fixo.
- Os próximos envios usam o telefone novo, sem user_id/username anteriores.
  Webhooks do novo número podem enriquecer o mesmo contato com a nova identidade.
  Webhooks e páginas de contatos atrasados não podem reativar aliases retirados.
- Uma colisão com outro contato cancela a alteração inteira; não mescla pessoas.
- Os dados já alterados antes do hotfix exigem manutenção específica. O executor
  desta entrega está limitado à conta 1, contato 231 e evento 486, com prévia e
  fingerprint. Não faz ContactMergeAction nem envia mensagem de teste.

## Evento 486

O original `3EB0110B8308CA4CD017DE` tem evidências divergentes: Uno informa
o telefone novo e Meta informa o cancelado. Não reescrever observações nem
inventar deduplicação. Após revisão autorizada, arquivar este conflito como
`disabled / retired_recipient_after_phone_change`, preservando integralmente
o payload e as identidades. Isso não comprova entrega ao telefone novo.

## Validação dev

- Docker local recuperado sem reset, exclusão de volumes ou limpeza de caches.
- Banco e Redis separados dos serviços ativos; dados sintéticos baseados no
  contato 231 e evento 486, sem envio externo.
- Regressão de 600 exemplos Ruby sem falhas, incluindo contatos, envio, grupos,
  identificação, echoes, mídias, transporte e agendamentos.
- Executor de manutenção validado separadamente com conversa, mensagem, anexo,
  associação Active Storage e blob: um exemplo sem falhas (601 casos distintos
  incluindo a regressão). Rodada final focada de 19 exemplos também aprovada;
  ela se sobrepõe às anteriores e não deve ser somada.
- RuboCop de 18 arquivos de aplicação/spec e dois executores sem infrações. Sem alteração do
  frontend, dependência ou pacote nativo nesta correção.

## Operação

1. Inventariar imagem, mounts e Compose efetivos. Preservar x-base, imagem única,
   réplicas, redes, variáveis e binds não conflitantes.
2. Backup PostgreSQL restrito, catálogo validado, Compose e fontes anteriores.
3. Conferir os arquivos ativos contra a base do patch. Não sobrepor divergências
   desconhecidas. Bind somente leitura dos 14 arquivos Ruby de aplicação.
4. Validar Compose, quiet/drain curto e recriar somente web e workers.
5. Conferir hashes, classes carregadas, HTTP e workers liberados.
6. Prévia do executor, fingerprint atualizado, aplicar somente o contato/evento
   autorizados. Conferir inventários de conversas, mensagens, anexos e blobs.
7. Consultar a identidade do telefone novo no provedor sem disparar mensagens.
   Persistir somente uma identidade confirmada e sem colisões; se não confirmada,
   manter user_id vazio para não reutilizar a identidade cancelada.
8. Rollback de código/Compose se necessário; nunca restaurar banco automaticamente.

## Execução

Aplicado em **20/10/2026**, por SSH, sem trocar a imagem `.33` nem publicar release.
Patch da branch local `fix/whatsapp-retire-changed-phone`, baseado em
`c67caa08004abcabc221356efdbe43e57388aa3d`. Na aplicação operacional ainda não
havia commit/push; publicação posterior na `4.16.0` autorizada pelo administrador,
sem nova execução na VPS ou alteração dos dados. Manifest dos 14 arquivos em
`script/validation/contact_phone_change_manifest_20261020.json`.

- Pacote ativo: `/var/snap/docker/common/viperchat-hostpaths/contact-phone-change-20261020/`.
  Backup PostgreSQL restrito em `private/database.dump`, **251.106.988 bytes**;
  `pg_dump` e catálogo `pg_restore --list` aprovados. Não houve ensaio de restauração.
- Fontes anteriores, inspeção do runtime e Compose guardados em `private/`.
  Os 13 arquivos já existentes coincidiram com a base do patch; o serviço novo
  não existia. Sintaxe Ruby validada antes da recriação.
- Compose salvo do Portainer atualizado preservando `x-base: &base`, imagem
  compartilhada, redes, variáveis, serviços e réplicas. Acrescentados somente
  os 14 binds Ruby `:ro` na base. Nenhuma migração de schema ou recompilação de assets.
- Quiet/drain iniciado **18:05:40 de Cuiabá (22:05:40 UTC)**, dois workers com
  zero trabalhos ativos. Recriação de web e dois workers concluída às **18:06:20**;
  o comando de recriação levou aproximadamente dez segundos. Banco, Redis e
  ViperConnect não foram reiniciados. Ambos os workers confirmados depois com
  `quiet=false`; o quiet não permaneceu ativo durante a manutenção dos dados.
- Quatorze hashes/binds conferidos nos três containers, serviço carregado,
  `/app/login` HTTP 200. Nova verificação final às **18:11:27 de Cuiabá**:
  ambos os workers disponíveis, `quiet=false`, login HTTP 200.
- Prévia atual revisada: apenas o contador/data de tentativa do evento mudou
  entre as leituras; contato, aliases e identidade capturada permaneceram iguais.
  Uma primeira aplicação foi recusada pelo fingerprint, antes de qualquer escrita.
  A aplicação com o fingerprint lido diretamente da prévia terminou com saída zero.
- Contato **231** mantido no mesmo cadastro e telefone novo **+5566996803524**.
  Aliases antigos `98444`, `103074` e `114286` retirados do uso ativo, sem alterar
  seus IDs, source_id ou vínculo histórico. O BSUID anterior foi limpo.
- Consulta de rede à ViperConnect confirmou um LID diferente para o telefone
  novo, sem colisões na conta. Esse novo LID foi associado ao próprio contato 231,
  com um alias ativo adicional na caixa 1. Os seis aliases anteriores permanecem.
  A consulta não disparou mensagens nem importou/mesclou contatos remotos.
- Evento **486** arquivado como
  `disabled / retired_recipient_after_phone_change`. Payload e observações da
  identidade mantidos byte/atributo por atributo; nenhuma deduplicação forçada.
- Inventário antes/depois da manutenção e após a nova identidade idêntico:
  **4 conversas, 2.532 mensagens, 329 anexos, 329 associações Active Storage e
  329 blobs**. Digest de todos os atributos:
  `c291b062392fbfa43eafbbeec293b71852d82d3cbdc9b5c1bed421bc73238006`.
  Payload construído em memória com mensagem real confirmou telefone novo e LID
  novo, sem envio externo. IDs/source_id, conteúdo e mídias não foram apagados ou movidos.
- Evidências restritas: `private/preview.fresh.json`, `apply.parsed.json`,
  `verification.provider.log`, `new_identity.apply.log`, `verification.summary.json`,
  `runtime.before.json`, `runtime.after.json` e `workers.final.log`.
- Nenhum rollback necessário. Validação técnica e consulta de identidade aprovadas;
  entrega externa de uma nova mensagem depende de tráfego legítimo posterior,
  pois não foi disparada mensagem de teste.
- Limpeza concluída: containers de testes/Redis, volume exclusivo desse Redis,
  banco sintético `viperchat_phone_change_20261020` e arquivos compactados de
  transferência removidos. Fontes, plano, testes, dados dev ativos, backups de
  recuperação, mounts ativos e cache Docker compartilhado preservados. A limpeza
  não comprova compactação do VHDX nem aumento do espaço livre do SSD.

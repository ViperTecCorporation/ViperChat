# Echo Meta de envio ViperConnect confirmado — event-460

## Escopo autorizado

Corrigir em dev, validar o caso real e aplicar via SSH/hostpath com backup.
Preservar IDs, contatos, histórico, bolhas, mensagens, anexos e blobs. Não enviar
mensagens reais de teste, trocar imagem, gerar migração ou mesclar contatos.

Base: `cf89f235d69287c8071e9f0ca244521cd69e8f09`, branch
`fix/whatsapp-meta-echo-uno-receipt`. A implantação ocorreu antes da publicação;
posteriormente o administrador autorizou commit e push na `4.16.0`, sem nova
execução na VPS.

## Evidências e regra

- Conta 1, vínculo 1, caixa principal 1 e Meta 65.
- Contato antigo 94129, Marcos Vinicius, telefone `+5566999356516`.
- Meta informa `556699356516` e BSUID `BR.2339818310092335`; aliases ativos
  apontam para o mesmo contato e a normalização do nono dígito já é equivalente.
- Original `3EB08C60E314204722BF0D`, identidade Uno 26019, Meta 26022.
- Envio API ViperConnect confirmado: mensagem 2498876, conversa 37692,
  `source_id=f4241120-ccb4-11f1-b3c4-63718cf5742f`, alias técnico 2219.
- A identidade Uno não tem `to`, mas o recibo tem `5566999356516`.
- A reserva canônica 2198 estava pendente, sem mensagem/aliases, e a comparação
  retornava `participant_identity_pending`. A adoção só contemplava o sentido
  inverso (envio Meta seguido de echo Uno), bloqueando este sentido.

Agora a adoção permite esse sentido com ID original único no par e destinatário
do recibo equivalente ao peer Meta. Exige mensagem pública no atendimento da
caixa principal, contato compatível, envio API confirmado, mesmo transporte,
vínculo e ativação. Recibo ausente/contraditório, outro contato, geração, tipo ou
contraparte ambígua continuam bloqueados. Não correlacionar por texto/horário.

O resolvedor associa o echo à bolha existente e conclui a pendência sem replay,
download, alteração de payload/observações, envio externo ou exclusão de bolhas.
A interface de revisão pode apresentar a conversa comprovada antes da resolução.

## Aceite dev

- 17 testes novos, incluindo os identificadores reais do event-460, execução
  idempotente, dados históricos intactos e imagem/documento já persistidos sem
  download duplicado. Rede externa bloqueada nos exemplos.
- Regressão relacionada: **584 exemplos, zero falhas**. Inclui ingestão única,
  contatos antigos/troca de telefone, aliases, recibos, eventos, revisão,
  transportes, mídias, grupos e os echoes 463/468.
- RuboCop de quatro arquivos de aplicação, spec e executor sem infrações;
  sintaxe do executor válida. Sem alteração de frontend/native.
- Ambiente exclusivo: container `viperchat-event-460-tests`, Redis em tmpfs
  `viperchat-event-460-redis`, banco `viperchat_event_460_test`.

## Procedimento operacional

Pacote restrito:
`/var/snap/docker/common/viperchat-hostpaths/meta-echo-event-460-20261020/`.

1. Inventariar os três containers e o Compose salvo do Portainer. Gerar backup
   PostgreSQL em `private/database.dump`, conferir catálogo com `pg_restore --list`.
2. Conferir fontes ativas com hashes da base e novas fontes pelo manifesto.
   Preservar imagem compartilhada, `x-base`, variáveis, redes e binds alheios.
3. Carregar somente o comparador de aliases e o resolvedor novos em runner
   isolado; executar executor em transação somente leitura. Prévia deve provar
   exclusivamente `event-460 -> mensagem 2498876`.
4. Quiet/drain curto, recriar apenas web e dois workers. Não parar banco, Redis
   ou ViperConnect. Liberar workers antes da manutenção do evento.
5. Conferir hashes/mounts/classes, workers e HTTP. Capturar nova prévia/fingerprint
   e aplicar somente o executor `resolve_meta_echo_event_460_20261020.rb`.
6. Verificar todos os atributos capturados do contato/aliases, conversa, mensagens,
   identidades, payload e anexos/blobs. Falha provoca rollback da transação de
   manutenção; não restaurar banco automaticamente. Rollback de código/Compose
   separado, mantendo backup e hostpaths necessários.

## Resultado operacional

- Aplicado em **20/10/2026 às 21:15 de Cuiabá**, por SSH/hostpath. Imagem
  `.33` mantida, ID `sha256:56d4de1689792fc90367ded5a253626bad852fa87bf3aeea73543d350493dda1`.
- Backup PostgreSQL restrito: **251.277.655 bytes**, catálogo aprovado. Não houve
  restauração de teste nem restauração automática do banco.
- As três fontes existentes coincidiram com a base nos três containers; nova
  classe ausente antes. Quatro fontes com sintaxe e hashes conferidos após a troca.
- Compose do Portainer mantém `x-base`, imagem compartilhada, variáveis, redes e
  todos os binds alheios. Agora 20 mounts por web/worker: dois binds substituídos
  e dois novos. Só web e dois workers foram recriados; banco, Redis e ViperConnect
  não foram interrompidos.
- Quiet solicitado às **21:14:51**, drenagem/quiet confirmado às **21:15:05**.
  Web e ambos os workers iniciados novamente até **21:15:09**.
  Os workers estavam novamente ativos antes de qualquer manutenção administrativa.
- Prévia de preflight em transação somente leitura comprovou
  `460 -> 2498876` antes da troca. Ao retomar o fluxo, às **21:15:48**, o evento
  já foi concluído pelo resolvedor (`completed / correlated_existing_echo`).
  A reserva 2198 ficou `ready`, apontando à mensagem 2498876; alias Uno 2219
  adotado e alias técnico Meta 2334 associado à mesma reserva.
- Por isso a prévia administrativa posterior retornou sem proposta: o evento já
  estava concluído. A trava impediu reaplicar o reparo; **nenhuma manutenção manual
  adicional foi executada**. Não houve replay ou mensagem de teste real.
- Comparação integral do preflight com o retrato posterior aprovada: contato
  94129, quatro aliases de contato, conversa 37692, **164 mensagens**, duas
  identidades, payload/evidências do evento, **30 anexos, 30 vínculos de armazenamento
  e 30 blobs** idênticos. Nova verificação diretamente no banco também aprovada.
  Nenhuma bolha foi excluída, ocultada, movida ou renumerada; nenhuma mídia apagada
  ou duplicada. Não houve mesclagem ou mudança de dados do contato antigo.
- HTTP `/app/login` 200 e dois workers fora de quiet após a troca. Evidências
  restritas em `private/`: backup/catalog, Composes, runtime, fontes anteriores,
  preflight, prévia posterior, verificação e estado final.
- Removidos os dois containers exclusivos, banco sintético (28.217.827 bytes,
  sem sessões ativas), arquivo local de fontes (107.417.600 bytes), pacote de
  transferência local/remoto, candidato redundante e JSONs intermediários do
  container. Evidências privadas, executor administrativo e backup de recuperação
  preservados. Dados/serviços dev, volumes, uploads e cache Docker compartilhado
  não foram removidos. Limpeza não implica compactação do VHDX nem garante ganho
  equivalente de espaço livre no SSD. Publicação posterior na `4.16.0` autorizada,
  incluindo a correção, testes, executor, runbook e plano atualizado.

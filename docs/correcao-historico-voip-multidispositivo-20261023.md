# Histórico VoIP multidispositivo — 23/10/2026

## Evidência e regra

A chamada externa local 3 gerou os registros 288 (WebSocket, atendida) e 289
(UDP, answered_elsewhere), ambos do mesmo vínculo de ramal 1001. Não eram
duas chamadas independentes. A lista agora omite somente a perna
answered_elsewhere quando há outra perna atendida da mesma chamada externa,
vínculo e direção. Isso ocorre antes de filtros, contagem e paginação.
Pernas de outros agentes/ramais, transferências atendidas e chamadas sem vínculo
externo não são fundidas. Todos os registros continuam acessíveis por ID.

O serviço VoIP sobrescrevia answeredAt com undefined na atualização terminal.
Os armazenamentos JSON e SQLite agora preservam o primeiro atendimento.
Um resumo missed só é corrigido mediante answeredAt da própria chamada ou de
um participante identificado. Nenhuma associação é inferida por telefone/horário.
O receptor também corrige esse resumo legado sem alterar os eventos recebidos.

## Validação

- ViperChat: 110 exemplos de API e serviços VoIP, zero falhas, banco isolado
  viperchat_voip_test e Redis 15, nos containers existentes.
- Serviço VoIP: typecheck/build aprovados; 245 testes, 244 aprovados e um
  ignorado porque FFmpeg não está disponível no Windows. Teste adicional de
  retenção WAV reproduz o encerramento com answeredAt undefined e preserva áudio.
- Fixture da chamada real reproduzida em diretório temporário isolado no
  container VoIP existente: completed, primeiro atendimento preservado,
  participantes intactos. Diretório temporário removido pelo teste.
- IDs 288/289, quatro observações e artefato 3 preservados. A consulta consolidada
  retorna apenas 288. Nenhuma mensagem, mídia ou conversa removida.
- Resumo externo 3 corrigido em dev para completed com o horário comprovado do
  participante atendido. Eventos originais e atributos das pernas permanecem
  idênticos. Backup restrito em
  /app/tmp/voip-history-consolidation-20261023/external-3-before.json.
- Alterações somente backend; nenhum bundle/app nativo recompilado nesta tarefa.

## Gravação e operação

O evento real recebido informa recording.status=disabled; o artefato 3 não tem
arquivo anexado. O produtor descarta áudio quando o resumo perde a evidência de
atendimento. O teste comprova a prevenção desse descarte após a correção, não a
existência nem a recuperação do arquivo antigo na central remota.

Atualizado o JS compilado do histórico no container VoIP local já existente,
sem chamada aberta no histórico no momento da atualização. Backup do JS anterior
em /tmp/call_history_store-before-consolidation-20261023.js para rollback.
Fontes Rails atualizados no volume da réplica. Sem novos containers, imagem
publicada, commit/push ou acesso/alteração na VPS. A central remota continua
precisando receber a correção em uma implantação futura autorizada.

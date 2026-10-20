# Hotfix: correlação de áudio antigo e conversa na revisão

Aplicado em 18/10/2026 via SSH/hostpath, sem trocar a imagem `viperchat:unified-20261018-r1`.

## Causa e limites da correção

O `event-1` era a contraparte Meta de um áudio já persistido. A identidade UnoAPI antiga conservava conflito de direção (`incoming`/`outgoing`) e remetente (contato/número empresarial), acompanhado de recibo `sent`. A correlação segura permanecia em revisão e a interface não mostrava a conversa.

`UnifiedEventResolutionService` só recupera essa forma específica de evidência antiga quando há um único registro canônico pronto, com ID original exato, geração atual do vínculo, envelope Meta de entrada reconhecido, payload correspondente, mesmo contato/telefone normalizado e tipo, alias Uno já associado e apenas os conflitos legados previstos. Não resolve por texto, proximidade de horário ou telefone isolado. Conflitos adicionais, outro destinatário, mensagem privada/grupo, outra geração ou ID divergente continuam bloqueados.

O resolvedor associa a identidade Meta ao registro existente e conclui a pendência, sem reexecutar o webhook, enviar mensagens, transferir arquivos, alterar IDs, mesclar contatos ou apagar evidências conflitantes. O painel pode mostrar a conversa provada antes dessa conclusão, sem escrever dados. A contagem de tentativas inclui avaliações que terminam diretamente em revisão ou conclusão; o limite e o backoff das falhas continuam preservados.

## Validação

- Dev: 116 testes aprovados, incluindo o caso real, rotina automática de cinco minutos, leitura administrativa sem escrita, preservação de mensagem/anexo/blob e cenários negativos. RuboCop: três serviços sem ocorrências.
- Prévia na VPS em transação somente leitura: mensagem `2489735`, conversa `8708`, um anexo.
- Após aplicar: `event-1` em `completed`, motivo `correlated`, uma tentativa, sem próxima tentativa. Vinculado à mesma mensagem `2489735`; atributos da mensagem, contato, anexos e metadados dos blobs conferidos antes/depois, sem alteração.
- Web HTTP 200. Web e dois workers recriados; hostpath do frontend de salvamento da prioridade Meta preservado. Nenhuma migração executada.

## Backup, aplicação e rollback

Diretório: `/var/snap/docker/common/viperchat-hostpaths/event-resolution-20261018`.

Backup PostgreSQL custom: **248.365.232 bytes**, catálogo pg_restore conferido; SHA-256 `ad167172a38368f9d685ef1e090979c0bab001969e69a5862d1d1588dd330a83`. Não houve ensaio de restauração. Arquivos de banco, compose e snapshot do evento ficam em `private/`, restritos ao root.

`stack-after.json` mantém os mounts anteriores e acrescenta, no web e nos workers, os três arquivos somente leitura:

```text
code/unified_event_resolution_service.rb -> /app/app/services/whatsapp/unified_event_resolution_service.rb
code/unified_event_service.rb -> /app/app/services/whatsapp/unified_event_service.rb
code/unified_review_service.rb -> /app/app/services/whatsapp/unified_review_service.rb
```

Rollback apenas de código, preservando o banco e o frontend anterior:

```sh
docker compose -p chatwoot-uno \
  -f /var/snap/docker/common/viperchat-hostpaths/event-resolution-20261018/private/stack-before.json \
  up -d --no-deps --pull never --force-recreate --scale chatwoot-worker=2 chatwoot-web chatwoot-worker
```

O rollback de código não desfaz o alias seguro nem reabre o evento concluído. Não restaurar automaticamente o banco de produção.

O compose armazenado no Portainer não foi atualizado. Antes de reimplantar por lá, incorporar os mounts de `stack-after.json` ou usar uma imagem que inclua estas correções e a correção anterior de frontend.

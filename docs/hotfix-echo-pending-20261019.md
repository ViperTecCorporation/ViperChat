# Echoes retidos e reavaliação de mídias — 19/10/2026

## Evidências e correções

- Eventos Meta 335–344, 348 e 370: doze mensagens já persistidas pela Uno, envolvendo três aliases BSUID legados. O ID original permite encontrar a mensagem e seu contato antigo, mas o dono técnico do alias Meta é outro contato sem telefone. A conclusão dessa deduplicação agora preserva o alias legado e ambos os contatos, sem exigir uma transferência de dono. A exceção exige BSUID técnico exato, dono sem telefone, contato humano mais antigo, mensagem canônica existente no contato comprovado e mesmo ID original. Contato humano divergente continua bloqueado.
- Eventos Uno 372/373: echoes sem destinatário, com mensagem pública já existente sob o WAMID Meta, enquanto o transporte confirmado está registrado como Uno. Permitir essa evidência exige envio Uno reconhecido (`acknowledged`), caixa Uno do vínculo, mesmo vínculo/ciclo, WAMID de saída reconhecido e mesmo ID original; continuam valendo as verificações de conta, contato, direção, mensagem pública e identidade única. Não alterar `source_id` nem metadados do transporte para fazer o teste passar.
- Mídia 1421: além do echo Uno real, existe um recibo sem conteúdo sob o próprio ID original, sem participante, direção ou vínculo de mensagem. Ele não é uma segunda mensagem candidata. Somente esse formato estrito, não vinculado e sem evidência conflitante, é excluído da lista de candidatos quando há mais de um. O recibo continua no banco. Evidência adicional, mensagem vinculada ou conflito real mantém a ambiguidade.
- Mídias 665/694: o contato já foi reconciliado na manutenção das 12h, mas o estado de revisão foi calculado anteriormente. Reavaliar com as mesmas provas de mídia, sem substituir arquivo quando já existe apenas uma cópia física. O job existente de cinco minutos também passa a solicitar reavaliação de mídias pendentes/em revisão, em lote limitado; não força sucesso e não reenfileira envios.
- Mídias sem contraparte e o registro 10 com conflito real de direção não recebem prova inventada para remover o aviso. Sua segurança continua sendo verificada pelo fluxo normal.

## Aceite em dev

- Os 18 cenários positivos derivados dos eventos reais reproduziram a falha antes da correção e passaram após o patch. Texto, áudio e documento cobertos, incluindo repetição, arquivo já persistido e ausência de download/purge.
- **461 exemplos aprovados** na rodada integrada: eventos reais, controles negativos de contato/ciclo/transporte/ID, mídia, recibos telefone/LID, ingestão, resolução de eventos, contato canônico e regra N. RuboCop dos quatro arquivos de produção sem infrações.
- Fontes alteradas: `unified_participant_service.rb`, `unified_message_alias_service.rb`, `message_identity_correlation_service.rb`, `recheck_unified_events_job.rb` e `unified_media_reconciliation_service.rb`. Backend apenas: sem alterações de frontend, bundles nativos ou imagem Docker.

## Implantação e preservação

- VPS por SSH/hostpath. Diretório: `/var/snap/docker/common/viperchat-hostpaths/echo-pending-20261019/`. Backup PostgreSQL restrito `private/database.dump`, **249.668.014 bytes**; `pg_dump` e leitura do catálogo por `pg_restore --list` concluídos com sucesso. Não houve restauração de teste.
- Preservar o Compose do Portainer com `x-base`, imagem compartilhada `viperchat:unified-20261018-r2`, duas réplicas e todos os mounts da manutenção anterior. Acrescentados somente quatro binds Ruby somente leitura em web/workers. Hashes conferidos nos três containers.
- Quiet iniciado às **17:53:11 de Cuiabá (21:53:11 UTC)**; ambos os processos confirmaram `busy=0, quiet=true` antes da recriação. Containers web e ambos os workers recriados/iniciados às **17:53:45**, sem reiniciar banco, Redis ou ViperConnect. A reavaliação é feita depois, com workers liberados, não durante uma longa pausa.
- Inventário restrito anterior: 14 eventos, nove registros de mídia, 14 contatos, 86 aliases, 11 conversas, 21 mensagens, nove anexos/associações Active Storage/blobs. Conferir antes/depois os dados imutáveis, vínculos de contato e arquivos. O executor desta manutenção não substitui múltiplas cópias físicas nem purga blobs.
- Reavaliação e conferência pós-aplicação concluídas. Os resultados efetivos estão abaixo; não confundir retenção segura de arquivo com confirmação de entrega de um novo envio.

## Complemento: arquivo único de echo BSUID sem telefone

Na primeira reavaliação, os 14 eventos foram concluídos e quatro mídias ficaram `single_copy_retained`. Os documentos 722/731 ainda não passavam na comparação telefônica direta do echo Meta BSUID-only. O complemento usa uma prova somente leitura do participante já resolvido pelo ID exato da mensagem. Ela pode manter apenas a única cópia canônica existente; não autoriza substituição/purge entre arquivos ou transferência de alias de contato. Exige as duas identidades reconhecidas, direção/tipo/data compatíveis, contato da mensagem comprovado e dono do alias válido ou legado técnico sem telefone. Contato divergente continua em revisão, conforme teste negativo.

O complemento passou novamente na regressão integrada de **461 exemplos sem falhas**, com RuboCop nos cinco arquivos sem infrações. Fontes adicionais versionadas em `r2/` no hostpath; Compose anterior ao complemento salvo em `private/compose.r1.yml`. Quiet das **17:58:18** até a recriação/início dos containers às **17:58:36 de Cuiabá** (18 segundos). Dois workers liberados antes da conferência final; nenhum serviço de dados reiniciado.

## Resultado final na VPS

- **14/14 eventos concluídos como `completed/correlated`**: 335–344, 348, 370, 372 e 373. O reprocessamento usa as provas retidas e não faz novo envio externo.
- **Seis mídias com `unchanged/single_copy_retained`**: 7, 665, 694, 722, 731 e 1421. Mantida a cópia física existente, sem rebaixar sua origem ou criar outro objeto S3.
- Permanecem protegidas: mídia 10, `review/untrusted_mapping`, com conflito histórico de direção; mídias 444/584, `pending/counterpart_pending`, sem contraparte suficiente. Não marcar essas três como resolvidas nem apagar evidências. O job de cinco minutos solicitará nova avaliação quando houver novas provas.
- Comparação exata antes/depois aprovada para os **14 contatos, 86 aliases, 11 conversas, 21 mensagens, nove anexos, nove associações Active Storage e nove blobs** inventariados. Dados dos contatos/aliases e identificadores/conteúdos imutáveis das mensagens intactos. Não houve mesclagem de contatos, mudança de dono de alias, exclusão, purge ou download de nova cópia.
- Cinco hashes de código conferidos nos três containers. Mounts finais: 15 no web e 13 por worker, preservando os mounts anteriores. Ambos os workers ativos com `quiet=false`, sem NameError/SyntaxError/LoadError nos logs conferidos; login HTTP 200. Backup e configurações anteriores preservados. Nenhum rollback necessário.
- Evidências restritas na VPS: `private/inventory.before.json`, `private/inventory.final.json`, `private/verification.final.json`, `private/recheck.final.log` e os logs de conferência dos workers. Sem credenciais nos arquivos versionados.
- Arquivos de transferência da VPS removidos após conferência (**12.545 bytes**); backups, fontes ativas e configurações de rollback preservados. Limpeza do diretório temporário local `C:/Users/caita/AppData/Local/Temp/viperchat-echo-pending-20261019` bloqueada pela ferramenta, sem tentativa alternativa de contornar a restrição. Os arquivos locais permanecem pendentes de remoção. Nenhum cache Docker foi removido.

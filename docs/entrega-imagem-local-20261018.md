# Imagem local para atualização manual no Portainer

Tag gerada e carregada no Docker da VPS: `viperchat:unified-20261018-r1`.

ID da imagem no Docker da VPS: `sha256:040d6040bd4793e5f3afb0a1ace949752d609d097fc8d224e649c50d2c9a7843` (linux/amd64).

Verificação concluída: as 13 camadas de filesystem são iguais às da imagem local; dependências Ruby satisfeitas e manifesto do frontend presente na VPS. Localmente, 32 arquivos alterados conferidos por SHA-256 e 248 entradas do manifesto sem arquivos faltantes. Essas verificações validam o artefato, não substituem o aceite funcional após a atualização.

Após o carregamento, web e os dois workers continuavam com os mesmos IDs de container e com a imagem anterior `viperchat:unified-b829f34ee`. Nenhuma migração ou atualização de serviço foi executada.

Código: HEAD `e30d619f1ccd80e7c2c463f5bf41e909e43d9aae`, incluindo as alterações locais de etiquetas e OpenRouter ainda não commitadas. Não representa uma release publicada no registry.

Fingerprint do contexto de origem: `68df7a828b6da70def4e0777e57e0806aa774f501c1f513776df22c68169528f`.

## Antes de atualizar a stack

1. Salvar o compose atual e fazer backup do PostgreSQL antes das migrações. A entrega da imagem não modifica o banco nem substitui esse backup.
2. Trocar a imagem nos serviços web e em todos os workers; usar a mesma tag também no serviço temporário de migração, se houver.
3. Não habilitar pull/re-pull da imagem no Portainer: a tag é local e deve estar carregada no Docker da VPS.
4. Remover do compose somente as sobreposições antigas de código e frontend indicadas abaixo. Preservar configurações, redes, variáveis e volumes persistentes de dados, anexos e bancos.
5. Com a nova imagem e o ambiente da aplicação, executar `bundle exec rails db:chatwoot_prepare` antes de liberar web/workers. Esse comando aplica migrações pendentes e carrega as configurações da aplicação; não foi executado na produção nesta entrega.
6. Atualizar a stack e conferir logs, saúde da aplicação e envio/recebimento pelos dois transportes.

As quatro migrações adicionais em relação à imagem `unified-b829f34ee` são `20261017000001` a `20261017000004`: eventos de gerenciamento Meta, solicitações SMB, política opcional das primeiras mensagens e solicitações de templates.

## Sobreposições antigas encontradas nos containers ativos

Os seguintes destinos estavam montados por bind em web e worker. Remover essas entradas antigas para usar os arquivos da nova imagem:

```text
/app/app/services/whatsapp/unified_outbound_wait_service.rb
/app/app/services/whatsapp/send_on_whatsapp_service.rb
/app/app/services/whatsapp/message_identity_correlation_service.rb
/app/app/services/whatsapp/message_identity_participant_service.rb
/app/app/services/whatsapp/unified_media_reconciliation_service.rb
/app/app/services/whatsapp/unified_transport_service.rb
/app/app/services/whatsapp/unified_message_alias_service.rb
/app/app/services/whatsapp/providers/whatsapp_cloud_service.rb
/app/app/services/whatsapp/incoming_message_base_service.rb
/app/app/services/whatsapp/message_identity_observation_service.rb
/app/app/services/whatsapp/unified_message_ingestion_service.rb
/app/app/services/whatsapp/unified_delivery_attempt_service.rb
/app/public/vite
```

As origens dessas entradas estão em `/var/snap/docker/common/viperchat-hostpaths/`. Não é necessário apagar esses diretórios: preservá-los ajuda na recuperação da versão anterior. O compose salvo no Portainer pode ser diferente do compose que gerou os containers ativos; conferir o conteúdo antes de atualizar.

## Escopo desta entrega

Correção posterior, somente em dev: o botão geral "Atualizar" passou a salvar também as preferências alteradas do vínculo, incluindo a prioridade inicial da Meta. A tag `unified-20261018-r1` descrita neste documento foi gerada antes dessa correção e não a inclui; será necessário gerar outra imagem para publicá-la.

Apenas build, validação da imagem e carregamento no Docker da VPS. Sem reinício de serviços, alteração da stack, execução de migrações ou mudança dos vínculos das caixas.

A imagem anterior é preservada. Depois de migrar o banco, não basta voltar a tag para garantir rollback: avaliar a compatibilidade do esquema ou restaurar o backup seguindo um procedimento separado.

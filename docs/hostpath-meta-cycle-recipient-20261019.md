# Hotfix programado: ciclo Meta e destinatário/BSUID

Solicitação do administrador: aplicar **19/10/2026 às 12:00 em America/Cuiaba (16:00 UTC)**, por SSH na VPS `192.168.0.50`, via hostpath Docker. Não aplicar antecipadamente. Este documento é preparação, não confirmação de implantação.

## Código autorizado

Usar os arquivos do commit deste hotfix na branch `feat/whatsapp-unified-inbox-dev`, não copiar todo o checkout sujo:

- `app/services/whatsapp/initial_meta_messages_service.rb`
- `app/services/whatsapp/unified_transport_service.rb`
- `app/services/whatsapp/outbound_recipient_service.rb` (arquivo novo, necessário no web e nos workers)
- `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- Aviso da configuração: somente `WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.HELP` das traduções `en/whatsappUnified.json` e `pt_BR/whatsappUnified.json`. Recompilar sobre as fontes da imagem efetivamente ativa, sem levar outras alterações locais de frontend. Não montar JSON-fonte esperando mudar os bundles em produção.

Validação anterior: 270 testes Ruby, 34 testes frontend, RuboCop dos arquivos de produção sem infrações. O endereço de telefone recebido pela Meta mantém seu formato original; BSUID sem telefone é enviado em `recipient`, nunca em `to`. A regra N aguarda resposta Meta válida no ciclo atual e, fora dela, direciona mensagens humanas sem template à Uno antes de qualquer tentativa, sem consumir posição. Não rerotear tentativas já realizadas.

## Aplicação segura

1. Conferir horário e inventariar containers, imagem/digest, mounts efetivos do web e de todos os workers, stack/Compose do Portainer e saúde atual. Não presumir equivalência de imagens apenas pela tag. Preservar todos os hostpaths existentes que não conflitem com estes quatro arquivos e com os assets correspondentes.
2. Criar diretório dedicado sob `/var/snap/docker/common/viperchat-hostpaths/` para este hotfix. Fazer backup restrito do PostgreSQL e validar seu catálogo com `pg_restore --list`; isso não equivale a ensaio de restauração. Guardar configurações/Compose anteriores e fontes/assets atuais em área `private/` restrita ao root, pois podem conter segredos. Não imprimir credenciais ou configurações completas no chat.
3. Transferir somente os arquivos aprovados e conferir SHA-256. Os quatro arquivos Ruby são binds somente leitura no web e em todos os workers. Para frontend, construir isoladamente a partir da versão ativa e das duas alterações de aviso. Preservar assets com hash antigo para abas já abertas e o manifest anterior para rollback.
4. Preservar a estrutura `x-base: &base` e a imagem única compartilhada da stack; não duplicar a configuração nem trocar a imagem dos serviços. Incorporar os binds necessários sem substituir volumes, redes, envs, banco, Redis ou armazenamento. O Compose salvo no Portainer deve ficar coerente com o efetivamente aplicado, para uma reimplantação posterior não remover o hotfix. Antes de sobrescrever qualquer arquivo de stack, validar o destino exato e guardar a cópia anterior.
5. Validar a configuração resolvida com `docker compose config --quiet`. Fazer quiet/drain seguro dos workers, aguardar zero trabalhos ativos e então recriar apenas web/workers necessários, sem perder quantidade de réplicas ou interromper banco/Redis/ViperConnect. Não usar restart de containers como substituto para ativar um novo mount.
6. Conferir binds e hashes dentro de cada processo/container, carregamento da classe nova, HTTP/login e assets. Comparar antes/depois, em consulta somente leitura, os IDs e aliases do contato `53314`, mensagens/anexos/blobs relacionados e configuração do vínculo. Não editar contatos, mensagens, mídias, posições consumidas ou preferências reais para testar. Não disparar mensagens de teste reais sem nova autorização específica; observar apenas tráfego legítimo posterior.
7. Em falha, rollback somente dos arquivos/mounts e configuração anteriores, sem restaurar automaticamente o banco. Não apagar mensagens duplicadas, anexos ou blobs. Relatar qualquer bloqueio de acesso/permissão em vez de contorná-lo.
8. Registrar neste documento a execução efetiva, horário Cuiabá/UTC, commit aplicado, backup, mounts, hashes, validações e rollback. Distinguir aplicado, carregado e validado com tráfego real. Limpar intermediários comprovadamente descartáveis; preservar backup necessário e pacote ainda pendente de uso. Não limpar cache Docker compartilhado.

Sem migração de schema, alteração de IDs, mesclagem de contatos ou exclusão de mensagens/mídias. Credenciais autorizadas permanecem apenas no contexto da conversa ou nos mecanismos de acesso já configurados, nunca neste documento ou no prompt do agendamento.

# Hotfix programado: ciclo Meta e destinatário/BSUID

Solicitação do administrador: aplicar **19/10/2026 às 12:00 em America/Cuiaba (16:00 UTC)**, por SSH na VPS `192.168.0.50`, via hostpath Docker. Não aplicar antecipadamente. Este documento é preparação, não confirmação de implantação.

## Código autorizado

Usar os arquivos do commit deste hotfix na branch `feat/whatsapp-unified-inbox-dev`, não copiar todo o checkout sujo:

- `app/services/whatsapp/initial_meta_messages_service.rb`
- `app/services/whatsapp/unified_transport_service.rb`
- `app/services/whatsapp/outbound_recipient_service.rb` (arquivo novo, necessário no web e nos workers)
- `app/services/whatsapp/providers/whatsapp_cloud_service.rb`
- `app/services/whatsapp/canonical_contact_service.rb`
- `app/services/whatsapp/contact_reconciliation_service.rb`
- `app/services/whatsapp/unified_message_ingestion_service.rb`
- `app/services/whatsapp/incoming_message_whatsapp_cloud_service.rb`
- Executor administrativo, somente web: `script/validation/reconcile_bsuid_contacts_20261019.rb`.
- Aviso da configuração: somente `WHATSAPP_UNIFIED.META_INITIAL_MESSAGES.HELP` das traduções `en/whatsappUnified.json` e `pt_BR/whatsappUnified.json`. Recompilar sobre as fontes da imagem efetivamente ativa, sem levar outras alterações locais de frontend. Não montar JSON-fonte esperando mudar os bundles em produção.

Validação anterior: 270 testes Ruby, 34 testes frontend, RuboCop dos arquivos de produção sem infrações. Validação adicional de contato canônico/reconciliação: **320 exemplos Ruby sem falhas** na rodada integrada (há sobreposição com a rodada anterior), quatro arquivos de produção sem infrações no RuboCop e executor com sintaxe Ruby válida. O endereço de telefone recebido pela Meta mantém seu formato original; BSUID sem telefone é enviado em `recipient`, nunca em `to`. A regra N aguarda resposta Meta válida no ciclo atual e, fora dela, direciona mensagens humanas sem template à Uno antes de qualquer tentativa, sem consumir posição. Não rerotear tentativas já realizadas.

## Aplicação segura

1. Conferir horário e inventariar containers, imagem/digest, mounts efetivos do web e de todos os workers, stack/Compose do Portainer e saúde atual. Não presumir equivalência de imagens apenas pela tag. Preservar todos os hostpaths existentes que não conflitem com estes oito arquivos e com os assets correspondentes.
2. Criar diretório dedicado sob `/var/snap/docker/common/viperchat-hostpaths/` para este hotfix. Fazer backup restrito do PostgreSQL e validar seu catálogo com `pg_restore --list`; isso não equivale a ensaio de restauração. Guardar configurações/Compose anteriores e fontes/assets atuais em área `private/` restrita ao root, pois podem conter segredos. Não imprimir credenciais ou configurações completas no chat.
3. Transferir somente os arquivos aprovados e conferir SHA-256. Os oito arquivos Ruby são binds somente leitura no web e em todos os workers. O executor de manutenção é disponibilizado somente ao web. Para frontend, construir isoladamente a partir da versão ativa e das duas alterações de aviso. Preservar assets com hash antigo para abas já abertas e o manifest anterior para rollback.
4. Preservar a estrutura `x-base: &base` e a imagem única compartilhada da stack; não duplicar a configuração nem trocar a imagem dos serviços. Incorporar os binds necessários sem substituir volumes, redes, envs, banco, Redis ou armazenamento. O Compose salvo no Portainer deve ficar coerente com o efetivamente aplicado, para uma reimplantação posterior não remover o hotfix. Antes de sobrescrever qualquer arquivo de stack, validar o destino exato e guardar a cópia anterior.
5. Validar a configuração resolvida com `docker compose config --quiet`. Fazer quiet/drain seguro dos workers, aguardar zero trabalhos ativos e então recriar apenas web/workers necessários, sem perder quantidade de réplicas ou interromper banco/Redis/ViperConnect. Não usar restart de containers como substituto para ativar um novo mount.
6. Conferir binds e hashes dentro de cada processo/container, carregamento da classe nova, HTTP/login e assets. Comparar antes/depois, em consulta somente leitura, os IDs e aliases do contato `53314`, mensagens/anexos/blobs relacionados e configuração do vínculo. Não editar contatos, mensagens, mídias, posições consumidas ou preferências reais para testar. Não disparar mensagens de teste reais sem nova autorização específica; observar apenas tráfego legítimo posterior.
7. Em falha, rollback somente dos arquivos/mounts e configuração anteriores, sem restaurar automaticamente o banco. Não apagar mensagens duplicadas, anexos ou blobs. Relatar qualquer bloqueio de acesso/permissão em vez de contorná-lo.
8. Registrar neste documento a execução efetiva, horário Cuiabá/UTC, commit aplicado, backup, mounts, hashes, validações e rollback. Distinguir aplicado, carregado e validado com tráfego real. Limpar intermediários comprovadamente descartáveis; preservar backup necessário e pacote ainda pendente de uso. Não limpar cache Docker compartilhado.

## Reconciliação adicional autorizada pelo administrador

O usuário autorizou incluir os seis pares de `docs/previa-reconciliacao-bsuid-20261019.md` nessa mesma janela. Depois do backup e carregamento do código, gerar uma prévia atualizada com o executor. Se os pares/provas continuarem os mesmos e não houver bloqueios, usar o fingerprint dessa prévia para aplicar. Uma mudança apenas de quantidade de mensagens exige registrar a nova prévia e os IDs correspondentes; não autoriza trocar pessoas ou ignorar dependências. Em caso de bloqueio, aplicar somente as correções de código validadas e informar por que a reconciliação ficou pendente.

Essa autorização permite atualizar somente os donos dos aliases/conversas e remetentes Contact desses seis legados para os contatos antigos indicados. Preservar ambos os contatos, não mudar `source_id`, não mover mensagens entre conversas e não apagar ou purgar nada. Conferir o inventário antes/depois, os contatos antigos intactos, zero associações remanescentes nos legados e as mesmas mensagens/anexos/blobs. Não corrigir outras pessoas automaticamente, não renumerar conversas e não executar `ContactMergeAction`.

Sem migração de schema, alteração de IDs ou exclusão de contatos/mensagens/mídias. Credenciais autorizadas permanecem apenas no contexto da conversa ou nos mecanismos de acesso já configurados, nunca neste documento ou no prompt do agendamento.

## Execução efetiva — 19/10/2026

- Início às **12:00 de Cuiabá (16:00 UTC)**, por SSH. Aplicados os arquivos aprovados dos commits `832d0e25d4bab0599a9b4921083e346dae2b6fdd` e `0fd68bd31268d52e68971ac161f071243833aaa0`. Nenhuma outra alteração do checkout foi incluída.
- Pacote ativo: `/var/snap/docker/common/viperchat-hostpaths/meta-cycle-canonical-20261019/`. Backup PostgreSQL em `private/database.dump`, **249.296.465 bytes**, `pg_dump` e leitura do catálogo com `pg_restore --list` concluídos com saída zero. Não houve ensaio de restauração. Compose, inspeção dos containers, fontes e assets anteriores preservados na área restrita `private/`.
- Runtime anterior: sem binds externos e sem diferenças de código nas camadas graváveis. Mantidos `x-base: &base`, imagem `viperchat:unified-20261018-r2` (ID `sha256:23980e11bf28cb1f65b277f9edf38a6e35de0af7bcac47029f73c65d0067425e`) e duas réplicas dos workers. Compose salvo no volume do Portainer atualizado; validação `docker compose config --quiet` aprovada. Sem migração de schema ou reinício de PostgreSQL, Redis e ViperConnect.
- Oito binds Ruby somente leitura conferidos por SHA-256 em web e ambos os workers; web com executor e assets adicionais, totalizando dez mounts. Classes novas carregadas. Frontend recompilado isoladamente com fontes da produção e somente as duas mudanças de HELP; lock de dependências idêntico ao runtime de build. Assets antigos mantidos para abas abertas.
- Workers receberam quiet, ambos confirmaram zero trabalhos ativos e foram drenados antes da recriação. A reconciliação terminou com saída zero; o inventário posterior foi capturado e os dois workers foram liberados novamente às **12:11 de Cuiabá**, antes da comparação detalhada, a pedido do administrador. Verificação posterior: dois processos Sidekiq ativos com `quiet=false`; login público `/app/login`, com Host correto, respondeu HTTP 200. O endpoint Devise consultado inicialmente por IP retornou erro de redirecionamento por Host divergente; não foi usado como evidência de falha do login público.
- Prévia após drain idêntica ao retrato das 11:29, fingerprint `13f63c2eedf6610885be271eceae834a02030104021264874f1237a0afe092f94`, sem bloqueios. Aplicados exclusivamente os seis pares autorizados: **18 aliases, 12 conversas e 6 remetentes Contact** reatribuídos aos contatos antigos.
- Comparação antes/depois aprovada: **12 contatos com atributos intactos, 12 conversas e 102 mensagens preservadas** (somente `contact_id`/remetente autorizado alterados), **14 anexos, 14 associações Active Storage e 14 blobs idênticos**; IDs e conteúdo mantidos. Zero aliases/conversas dos pares continuam nos legados; contato `53314` e seus quatro aliases intactos. Evidências completas em `private/inventory.before.json`, `private/inventory.after.json`, `private/preview.json`, `private/apply.log` e `private/verification.json` na VPS.
- Não houve exclusão, purge, consolidação de conversas, movimento de mensagens entre conversas ou disparo de teste real. Aceite técnico do patch/reconciliação aprovado; a política N e o endereçamento externo continuam sujeitos à observação do tráfego legítimo posterior, sem afirmar entrega de mensagens que não foram enviadas nesta manutenção. Nenhum rollback foi necessário.

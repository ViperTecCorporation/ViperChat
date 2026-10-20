# Imagem para troca manual no Portainer — r2

Tag: `viperchat:unified-20261018-r2` — Linux/amd64, imagem local do Docker, não publicada em registry.

## Conteúdo

- Alterações atuais da branch `feat/whatsapp-unified-inbox-dev`, HEAD `e30d619f1`, incluindo alterações locais ainda sem commit: etiquetas por agentes, OpenRouter, salvamento da prioridade inicial Meta, reconciliação segura de eventos e pesquisas sem acentos.
- API de replicação de contatos ViperERP do commit `5b87f8dac`, preservada da imagem ativa `viperchat:unified-20261018-r1-contact-sync`: controller, migration e rotas acrescentadas sem remover as rotas de coexistência, templates ou insights.
- A API já está commitada e publicada em `origin/4.16.0`; verificado com fetch e teste de ancestralidade. Não foi criado outro commit nem feito cherry-pick na branch de desenvolvimento. A imagem combina os dois conjuntos explicitamente; builds futuros dessa branch precisam preservar essa integração.
- Dependências Ruby/Node sem alteração em relação à r1. Frontend recompilado em produção em container isolado, usando as dependências existentes somente para leitura. Arquivos `.env`, dados persistentes, backups e artefatos locais foram excluídos do contexto.

Fingerprint dos 8.083 arquivos de origem empacotados: `c39e89aefbe35335f63362faa54ac2295042e31074b9382bc6ec14b78711f6b8`.

Validação local: 8.083 arquivos conferidos por SHA-256; 1.717 arquivos Ruby compilados para verificar sintaxe; dependências Ruby satisfeitas; 249 entradas no manifesto do frontend, sem assets faltantes. Rotas de contatos ViperERP e de coexistência/templates presentes. Isso valida o artefato, não substitui o aceite funcional depois da troca.

Manifesto local: `sha256:0102a8739975efaa9f4bd62572e76f169f2a01dc664f79a335c4a01f24f26319`.
Config da imagem: `sha256:23980e11bf28cb1f65b277f9edf38a6e35de0af7bcac47029f73c65d0067425e`.

## Troca no Portainer

1. Salvar o compose atual e fazer backup do PostgreSQL antes das migrações. Não foi feito backup novo do banco nesta entrega de imagem.
2. Usar `viperchat:unified-20261018-r2` no serviço web e em todos os workers.
3. Não marcar pull/re-pull: a tag já está carregada no Docker da VPS, não existe em registry público.
4. Remover apenas os bind mounts de código/frontend abaixo, se presentes. **Não remover os volumes de armazenamento, anexos, PostgreSQL, Redis, redes ou configurações.**
5. Usando a nova imagem e as variáveis/rede da aplicação, executar `bundle exec rails db:chatwoot_prepare` antes de liberar o novo runtime ao tráfego. Conferir a conclusão sem erro e reiniciar os processos da aplicação após migrar.
6. Validar login, busca de contatos/grupos/mensagens com e sem acentos, salvamento da prioridade Meta, eventos de coexistência e API de contatos ViperERP.

Sobreposições encontradas no web:

```text
/app/public/vite
/app/app/services/whatsapp/unified_event_resolution_service.rb
/app/app/services/whatsapp/unified_event_service.rb
/app/app/services/whatsapp/unified_review_service.rb
```

Nos dois workers estavam presentes somente os três caminhos Ruby da lista. O código novo já os inclui. As origens ficam em `/var/snap/docker/common/viperchat-hostpaths/`; manter esses diretórios para rollback, removendo somente as entradas de montagem no compose.

## Migrações

Nova migration da pesquisa de artigos: `20261018150000_enable_unaccent_for_article_search.rb`. Habilita `unaccent`; o arquivo da extensão foi encontrado no PostgreSQL da VPS. Sem essa migração, a pesquisa de artigos da nova imagem pode falhar.

A migration de índice da API de contatos, `20261017160000_index_contacts_replication_cursor.rb`, também foi preservada da versão ativa. A lista completa de pendências depende do banco instalado; o comando de preparação deve ser executado com o backup disponível. Esta imagem é uma atualização do ambiente existente, não uma validação de instalação do zero.

Nenhuma migration foi executada em produção durante a construção ou transferência da imagem. Contatos, IDs, mensagens, mídias, vínculos e preferências de transporte não foram alterados.

## Transferência e verificação

Concluída por SSH, transmitindo `docker image save` diretamente ao `docker image load`, com compressão em fluxo. Não foi criado um arquivo `.tar` local ou remoto. Foram transmitidos 841.379.773 bytes.

ID confirmado no Docker da VPS: `sha256:23980e11bf28cb1f65b277f9edf38a6e35de0af7bcac47029f73c65d0067425e`. As 18 camadas de filesystem coincidem com a imagem local. Um container descartável, sem rede e sem volumes de produção, confirmou as dependências Ruby e o manifesto com 249 entradas.

Após o carregamento, os serviços mantinham os mesmos IDs e a imagem `viperchat:unified-20261018-r1-contact-sync`:

- Web: `bd48da855eee`.
- Worker 1: `5990b38a0100`.
- Worker 2: `5e6176b151b8`.

Sem alteração da stack, reinício de serviços, migrations ou modificações em dados de produção. A imagem anterior e os hostpaths de rollback foram preservados.

## Contexto da construção

O contexto foi composto a partir dos arquivos versionados do HEAD, substituídos pelas cópias existentes do worktree e acrescidos dos novos arquivos de aplicação/configuração/banco. Os três arquivos da API ViperERP foram acrescentados a partir de `5b87f8dac`, com junção aditiva das rotas. O frontend foi compilado isoladamente; a imagem final reutiliza a base r1, recebe os fontes e substitui integralmente `public/vite`. O estado dos serviços de desenvolvimento não foi alterado.

Não foi realizado novo commit/push: a API pedida já está publicada; as demais alterações locais permanecem no worktree e no artefato, sem serem declaradas como uma release publicada no Git/registry.

## Limpeza pendente

A limpeza dos intermediários foi recusada pela política do ambiente antes de executar. Foram preservados, sem nova tentativa por outro mecanismo:

- Diretório temporário `C:\Users\caita\AppData\Local\Temp\viperchat-image-r2-20261018`: contexto, hashes e bibliotecas temporárias de transferência. Sem credenciais salvas e sem arquivo de imagem `.tar`.
- Container de build `viperchat-image-r2-build`, já parado após a compilação, com o fonte copiado e assets de build. Seus volumes de dependências são compartilhados com o dev e devem ser preservados; não usar remoção de volumes/prune para limpar esse item.

A imagem local r2 e a cópia carregada na VPS são entregáveis e devem ser mantidas. Nenhum cache Docker foi removido.

## Restauração posterior do compose com âncora

A pedido do administrador, foi restaurado o YAML original com `x-base: &base` e `<<: *base` nos serviços web, worker e migrate. A imagem `viperchat:unified-20261018-r2` fica declarada uma única vez no `x-base`. PostgreSQL, Redis e relay mantêm suas imagens específicas.

Arquivo salvo do Portainer, stack 24: `/var/snap/docker/common/var-lib-docker/volumes/portainer_data/_data/compose/24/docker-compose.yml`.

Backup anterior e cópia restaurada, ambos restritos ao root e contendo as variáveis originais da stack: `/var/snap/docker/common/viperchat-hostpaths/compose-xbase-r2-20261018/`. Não copiar esses YAMLs para o Git ou para documentação pública.

A comparação dos objetos YAML confirmou que a restauração alterou somente a imagem dos três serviços e do `x-base`, além da retirada do bind de frontend antigo presente no compose salvo. Não havia os outros três binds Ruby nesse arquivo salvo; eles estavam somente na configuração efetivamente usada pelo patch. A configuração restaurada não contém binds de aplicação. Variáveis, portas, redes, volumes de dados, réplicas e dependências foram preservados.

Validação `docker compose config --quiet --no-interpolate` aprovada. SHA-256 do YAML restaurado: `254b73a5e768913df0a0ae484477f8e2c2e0b744ef9e2008f8c0473bfa7e6cf9`.

Nenhum deploy foi disparado; IDs e imagens dos containers ativos permaneceram iguais. Reabrir o editor da stack no Portainer para carregar o YAML salvo, evitando que um editor antigo ainda aberto sobrescreva a restauração. Antes de atualizar, manter o backup do banco e conferir o serviço de migração. Não solicitar pull da tag local.

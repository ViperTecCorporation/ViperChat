# Edição e exclusão na caixa WhatsApp unificada

21/10/2026 — America/Cuiaba. Implementação e validação somente em dev, na `4.16.0`. Sem acesso/deploy à VPS, publicação de imagem ou alteração da tag `.34b`.

Commit e push desta correção, do seletor de transporte e dos planos autorizados pelo usuário em 21/10/2026. A publicação do código na branch não inclui nova imagem nem deploy.

## Evidência e reprodução

Arquivos privados fornecidos, lidos sem incorporar payloads completos, textos de clientes ou credenciais ao repositório:

- `0x8li8l702tjya1rhr2r7o4ek_logs.txt`: SHA-256 `9368b3f0e2e2d0cf962772fb6ccff12bf478c385a0f878ed64201eca843ea7ec`.
- `nijxmz7qqhipd3488nbx9hmvh_logs.txt`: SHA-256 `79fe4c6bf8c3d9e26208413457d922f30c54ebd2f818fde65e165c529cf1ec13`.

O primeiro registra edição da mensagem 3143 na conversa 77 às 14:24:29 UTC, echo Meta `type: edit` em `smb_message_echoes` às 14:24:30 e posterior acesso à conversa 78. A exclusão da mesma mensagem ocorre às 14:25:23, seguida de `type: revoke` às 14:25:25. Há outra edição recebida em `messages` às 14:26:26 e posterior acesso à conversa 79. Os callbacks Meta desses casos retornam HTTP 200; não são as recusas de autenticação tratadas anteriormente. Os logs não apresentam o INSERT das conversas, portanto a atribuição causal foi confirmada com reprodução em banco de teste, não por consulta ao banco do cliente.

Antes do patch, o teste de edição com original ainda não mapeado reproduziu uma conversa adicional: inventário de conversas passou de um ID para dois, sem nova bolha. O fallback legado procura o ID apenas na caixa recebendo o evento, cria contato/conversa e tenta escolher uma mensagem por janela de 15 minutos. Isso é inadequado para eventos do outro provedor em uma caixa unificada.

O segundo arquivo contém retry de mídia por `MutexApplicationJob::LockAcquisitionError`, independente deste problema. Não foi feita correção desse lock nem reconciliação de mídias/conversas no ambiente do cliente.

## Implementação

- Interceptar mutações do par ativo antes de sincronizar perfis ou executar ingestão normal: Meta `edit`/`revoke`, tanto em `messages` como `message_echoes`, e UnoAPI `message_edit`.
- Resolver somente a mensagem exata na conta e nas caixas autorizadas, por source ID, identidade/alias persistido ou envelope Meta reconhecido ligado ao registro canônico original. Para envelopes, exigir participante e direção coincidentes. Confirmar também participante do evento, contato, direção e ausência de conflitos pelo verificador existente.
- Não usar texto, proximidade de horário ou o primeiro contato encontrado. Referências `edit.original_message_id` e `revoke.original_message_id` são específicas da operação: um contexto de resposta não substitui um alvo Meta ausente.
- Aplicar a edição/legenda ou marcação de exclusão à bolha existente, dentro de lock/transação. Não reatribuir source IDs, contatos, caixas ou conversas; não baixar, apagar ou purgar mídias.
- Guardar eventos sem evidência suficiente em `WhatsappUnifiedEvent`, reutilizando fila persistente, backoff e limite de tentativas existentes. Alvo ausente permanece pendente; referência malformada ou múltiplos alvos exigem revisão. O replay não passa pelos resolvedores de mensagens novas.
- Idempotência pelo registro de evento e ordem das edições por timestamp. Uma exclusão é terminal, inclusive com diferenças de precisão entre timestamps; edição atrasada não restaura conteúdo apagado. A preferência existente `show_deleted_message_content` continua determinando a visibilidade do texto excluído, sem purgar anexos.
- Verificar geração/ativação do vínculo no replay. Não reabrir uma conversa resolvida para aplicar uma mutação.

O tratamento legado de caixas sem vínculo ativo não foi reescrito. Esta implementação não pretende resolver identidade de grupos por telefone/BSUID: uma referência a conversa de grupo não é aceita como alvo individual. As regras de assinatura HMAC/token e de seleção de transporte não foram alteradas.

## Validação e ambiente

Testes entram pelos serviços reais de recebimento, sem stub da ingestão/mutação e com rede externa bloqueada. Reutilizam IDs e formatos de referência dos quatro eventos Meta observados e o formato UnoAPI, com conteúdo e credenciais sintéticos; não são reenvios dos payloads privados nem chamadas à produção.

- Matriz: Meta/UnoAPI, entrada/echo, edição/exclusão e principal Meta/UnoAPI; repetição de eventos sem duplicação.
- Alvo ausente seguido de evidência tardia e replay; referência ambígua/malformada; direção/contato incompatível; alvo privado/grupo; vínculo desativado; edição atrasada após exclusão; legenda com anexo; recibo UnoAPI `status: deleted`; conversa resolvida.
- Inventários conferem IDs e dados de contatos, caixas e estados das conversas, IDs/source IDs/caixas/conversas/datas originais das mensagens e IDs/chaves/checksums/tamanhos dos anexos/blobs. Não são removidas bolhas históricas nem conversas vazias preexistentes.
- Reprodução inicial: um exemplo, uma falha por criação de conversa extra. Regressão nova: 31 exemplos, zero falhas. Rodada ampliada: 646 exemplos, zero falhas, quatro pendências preexistentes de captura privada ausente; não é a suíte inteira do projeto. Após o endurecimento da referência específica de cada operação, rodada final com a regressão nova e os serviços Cloud, UnoAPI e replay: 172 exemplos, zero falhas. RuboCop nos seis arquivos Ruby e `git diff --check` aprovados.

Executado no container já existente `viperchat-replica-web-1`, em exportação temporária de código, banco `viperchat_voip_test` e Redis 15. Nenhum container/volume foi criado ou serviço reiniciado. O backend ativo em `/app`, o dev VoIP em uso, as versões nativas e a VPS não foram substituídos. Sem migração nova.

Temporários descartáveis removidos após concluir os testes: `/tmp/viperchat-mutations.BgIMlE` no container, `viperchat-mutations-20261021.tar` e `run-viperchat-mutations-20261021.rb` no Temp Windows. São intermediários regeneráveis; fontes, logs originais, dependências compartilhadas e dados persistentes foram preservados.

## Próximo aceite

Após autorização de publicação/deploy, confirmar com tráfego legítimo que edição e exclusão de uma mensagem existente mantêm o mesmo ID de bolha e conversa. Sem disparos reais nesta tarefa. Eventuais conversas vazias antigas exigem inventário e autorização próprios; este patch não apaga nem mescla registros históricos.

# Bolha unificada de chamada — 23/10/2026

Implementação em dev na `feat/agent-voip-webphone`, sem commit/push ou VPS.

## Comportamento

- A bolha privada da chamada reúne estado, ramal, duração, um player de áudio e as seções Resumo e Transcrição.
- Resumo e Transcrição começam recolhidos, expandem independentemente e limitam a altura do texto com rolagem. O texto do provedor é interpolado como texto, nunca executado como HTML.
- O player é o mesmo usado nas mensagens; sua transcrição automática fica desabilitada nessa bolha para não repetir a seção Transcrição.
- O recebimento de áudio/IA atualiza a mensagem da chamada, sem criar uma segunda nota. Retentativas mantêm a deduplicação do blob e da mensagem.
- Atualizações de estado preservam a análise já publicada. Um registro antigo de artefato que anteceda a bolha pode ser promovido à própria bolha conservando ID, source_id e anexos; seu conteúdo original é preservado em `voip_legacy_content`.
- Caso já existam bolha e nota separadas, a nota não é apagada: mantém ID, texto, anexos e vínculos, e recebe `voip_call_consolidated_into` com o ID da bolha. Apenas essa nota privada explicitamente vinculada deixa de ser repetida na renderização da conversa.
- `VoipCallArtifact#public_payload.message_id` aponta para a bolha canônica quando ela existe, permitindo abrir a mensagem visível pela central de chamadas. O `message_id` persistido do artefato antigo é preservado.
- Sem uma bolha, permanece a compatibilidade com a publicação antiga de uma única nota. A associação continua exigindo evidência de telefone/caixa, sem associação por semelhança de texto ou nome.

Não há alteração em abertura/reabertura de atendimento, permissões de caixas, envio ao WhatsApp, contrato de autenticação ou retenção de gravações.

## Validação

- Backend: **122 exemplos, zero falhas**, serviços VoIP e API de chamadas. Inclui atualizações tardias, ausência de note_target quando já há vínculo comprovado, repetição, deduplicação de áudio, preservação da nota legada, promoção sem novo ID, ciclo da chamada, caixa parceira e ponteiro público para a bolha.
- Frontend: **22 testes, zero falhas**, componentes Message e VoipCall. Inclui estados, ausência de ações antigas Voice, renderização segura de texto, análise reativa, áudio único, seções recolhidas, orientação por direção e ocultação somente da nota privada explicitamente consolidada.
- RuboCop: cinco arquivos, zero infrações. ESLint: zero erros; avisos de chaves dinâmicas de tradução/componentes de fixture.
- Playwright na conversa real 13954: uma bolha 2429135, um player, duas seções recolhidas, nota 2429136 ausente da renderização. IDs, texto original, blob e vínculos conferidos no banco.
- Desktop 1366 e mobile 320/360/390/412/430: ambas as seções abrem e fecham; nenhum overflow medido na mensagem. Capturas desktop e mobile inspecionadas. Evidências em `output/playwright/unified-call-*.png`.

## Réplica e preservação

Atualizados somente o publicador de artefatos, o publicador de bolhas, o payload do artefato e os dois componentes Vue no volume existente. Nenhum container criado.

Apenas o exemplo real da chamada externa 27 foi consolidado em dev. Antes da alteração de metadados foi salvo backup restrito em `/app/tmp/unified-call-bubble-20261023/external-27-20261023T175119977649.json`. A mensagem da chamada 2429135, a nota 2429136, a conversa e o contato conservaram seus IDs. A nota original e o blob não foram excluídos. Não houve migração em massa das chamadas antigas.

Rollback do exemplo: restaurar os atributos da bolha/nota e os campos do artefato a partir desse backup, em transação e com conferência de IDs. Não remover mensagens ou blobs. O código anterior pode ser recuperado pelo diff; as alterações anteriores do usuário na branch devem ser mantidas.

## Nativos

Bundles Android e iOS regenerados com os comandos `native:sync`, em cópia isolada, com heap Node limitado a 3 GB. APK Debug compilado em staging Windows com um worker e heap Gradle de 1 GB; assinatura verificada. Artefato local, fora do Git: `output/validation/unified-call-bubble-20261023/viperchat-unified-call-dev.apk`.

Nenhum Android conectado no `adb devices`: sem instalação ou aceite em aparelho. O Mac de desenvolvimento recusou a conexão SSH configurada: sem build/Archive ou aceite iOS. Bundle sincronizado não equivale a validação nativa completa; não houve publicação de apps.

Resultados e logs de build ficam em `output/validation/unified-call-bubble-20261023`. A cópia isolada de fontes/build no container e o runner temporário foram removidos após a conferência; preservados o APK, capturas, fontes, testes, resultados e o backup de rollback. A proteção do ambiente bloqueou a limpeza do staging Windows `C:/Users/caita/AppData/Local/Temp/unified-call-native-20261023`; ele permanece pendente, sem tentar outro método. Esse diretório contém uma junction node_modules para dependências compartilhadas, que não devem ser apagadas junto com o staging. A sessão Playwright desta tarefa foi encerrada.

## Ajuste de tema e orientação

Por solicitação do usuário, somente as bolhas VoIP deixam de usar o fundo âmbar de nota: o fundo, a borda e o ícone usam a cor primária vigente do tema. A indicação de falha/perdida mantém o destaque vermelho. A mensagem continua privada, sem envio ao WhatsApp.

Chamadas efetuadas ficam à direita e recebidas à esquerda, pela direção canônica da chamada, mesmo quando o remetente persistido é o contato. Notas privadas comuns e chamadas do canal Voice não são alteradas. Em telas menores que 480 px o player usa seu modo compacto para impedir corte dos controles.

Validação final combinada da árvore preparada para commit: **289 exemplos backend, 108 testes frontend e 24 verificações sintéticas do relatório de caixas parceiras aprovados**. A migração de vínculo da chamada com a bolha acompanha o schema regenerado do banco de testes, evitando pendência em CI após db:schema:load. A execução completa anterior com falhas não relacionadas não foi substituída por uma alegação de suíte completa verde.

Capturas verificadas para entrada/saída em desktop e 320/360/390/412/430 px, sem overflow após ativar o player compacto. A troca transitória da variável de cor primária no navegador alterou o fundo da bolha sem salvar configuração. O código correspondente já está no volume da réplica dev; sem VPS ou containers novos.

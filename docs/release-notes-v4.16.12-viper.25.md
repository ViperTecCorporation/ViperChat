# ViperChat v4.16.12-viper.25

Alterações desde `v4.16.12-viper.24`.

## UnoAPI: avisos de envio na bolha

- Suporte aos avisos recebidos em `statuses[].warnings`, incluindo `REPLY_SENT_WITHOUT_QUOTE`.
- Indicador **Aviso de envio** junto à mensagem, com detalhes ao tocar e tooltip no desktop.
- Quando a resposta foi enviada sem citação no WhatsApp, a referência interna recebe o rótulo **Referência não enviada**.
- Preservação dos indicadores de enviado, entregue e lido: aviso não é falha e não gera reenvio automático nem botão de tentar novamente.
- Avisos persistidos e deduplicados por código; callbacks repetidos não duplicam atualizações, e eventos posteriores não apagam os avisos anteriores.
- Retentativa do webhook quando o aviso chega antes da associação do ID externo, com correlação limitada à caixa de entrada.
- Textos de avisos tratados como texto, sem execução de HTML; códigos novos não interrompem o processamento.
- Tratamento exclusivo da UnoAPI, sem alterar o comportamento do canal oficial da Meta.

## PDF no cabeçalho de pedidos

- Suporte a documentos no cabeçalho de mensagens interativas `order_details`, tanto no recebimento quanto no eco do envio.
- PDF baixado pela URL assinada completa e armazenado no próprio ViperChat, sem depender permanentemente da URL temporária.
- Exibição do documento no cartão do pedido, preservando texto, boleto, PIX, botões e ID da mensagem.
- Reprocessamento sem duplicar mensagem ou anexo; falha no download não descarta o pedido.

## Fotos de grupos

- Correção adicional do caso em que grupos sem foto herdavam a imagem de um participante: o identificador da foto individual deixa de ser usado como foto do grupo.
- Jobs antigos com identificadores individuais destinados a grupos são ignorados, sem apagar fotos existentes.
- Sincronização usa o identificador do próprio grupo quando necessário para buscar a imagem pela rota autenticada, inclusive quando a URL retornada aponta para um bucket indisponível.
- Exibição prioriza fotos legítimas armazenadas localmente e preserva uploads manuais.
- Ferramenta de reparo conservador com simulação, seleção explícita dos grupos e backup reversível dos vínculos; não apaga arquivos de imagem e não é executada automaticamente ao atualizar.

## Contatos e histórico de conversas

- Migrations para consolidar contatos duplicados dentro da mesma conta, mantendo o cadastro de menor ID e registrando auditoria dos dados anteriores.
- Limpeza de e-mails legados contendo `@lid`, preservando os identificadores válidos da integração.
- Reparo de vínculos duplicados de contato/caixa e inscrições de notificação compatíveis, com reconstrução dos três índices únicos envolvidos.
- Consolidação de históricos respeita a configuração **Conversa única** da caixa. Caixas com a opção desligada mantêm suas conversas separadas.
- Com conversa única ativada, prevalece a conversa mais nova e suas configurações atuais; mensagens e referências do histórico são transferidas sem herdar indevidamente participantes, etiquetas ou preferências de arquivamento/fixação antigas.
- Conflitos de SLA ou avaliação CSAT impedem a consolidação para preservar o contexto. No recebimento normal, o merge é desfeito sem impedir a chegada da nova mensagem.
- Mesma rotina de preservação de vínculos aplicada ao recebimento WhatsApp e à sincronização UnoAPI.

## Concorrência e transcrição

- Reforço dos locks de processamento WhatsApp: cada execução libera somente o próprio lock, com liberação também em rollback e retentativa quando há processamento concorrente.
- Nova consulta à mensagem persistida após adquirir o lock, reduzindo duplicações por concorrência e reaproveitamento de consultas antigas.
- A transcrição nativa passa a processar somente áudios públicos recebidos. Áudios enviados pelo agente e notas privadas não entram nesse processamento, inclusive jobs já enfileirados.

## Interface e qualidade

- Correção da tradução com `Alt + @` que impedia a renderização das configurações de atalhos.
- Personalização dos atalhos também disponível na modal **Atalhos do teclado**, com layout adaptado a telas menores.
- Ajuste do CI para instalar `libvips`, necessário aos testes de conversão de figurinhas.
- Ampliação dos testes de avisos, pedidos com PDF, fotos de grupos, concorrência e consolidação de dados.

## Atenção antes de atualizar

- **Faça backup testado e reserve uma janela de manutenção.** Esta versão contém as migrations `20260919010000` e `20260919020000`, que alteram dados e podem bloquear gravações. Suspenda web, workers e demais escritores durante a execução. Consulte [o procedimento de reparo](contact-identity-repair.md).
- As migrations mantêm auditoria, mas não possuem reversão automática após commit. Conflitos abortam a operação; não devem ser ignorados para marcar a migration como concluída.
- Atualize web e todos os workers de forma coordenada para não misturar as versões antiga e nova dos locks. **Não é necessário limpar o Redis.**
- Os avisos da UnoAPI dependem de `sendUpdateMessages=true` na configuração da integração.
- Estas melhorias não corrigem a causa de corrupção física de índices do PostgreSQL nem duplicações originadas de transcrições com UUIDs diferentes na UnoAPI. Não foi adicionado `REINDEX` periódico.

Imagem prevista após conclusão do workflow: `ghcr.io/viperteccorporation/chatwoot:v4.16.12-viper.25-ce`.

**Comparação:** https://github.com/ViperTecCorporation/ViperChat/compare/v4.16.12-viper.24...v4.16.12-viper.25

# Prévia: seis contatos legados BSUID

Consulta executada em transação PostgreSQL **READ ONLY** na VPS, em **19/10/2026 às 11:29 de Cuiabá (15:29 UTC)**. Nenhuma reconciliação ou implantação foi feita nessa consulta. O administrador autorizou depois incluir a reconciliação no hotfix das 12h, com backup prévio e validação.

| Contato BR legado, mantido | Contato antigo canônico, preservado | Nome do contato antigo | Conversas preservadas (IDs internos) | Mensagens preservadas | Anexos preservados |
| --- | --- | --- | --- | --- | --- |
| 107089 | 15753 | Guilherme Bellana Sinop | 41367, 41644 | 17 | 2 |
| 107090 | 4540 | Petscaria | 41368, 41645 | 17 | 2 |
| 107092 | 9560 | Jonas Navarro | 41370, 41646 | 17 | 3 |
| 107095 | 13 | Flavio Padaria Claudia | 41373, 41647 | 18 | 3 |
| 107096 | 35 | Anderson Ortiz | 41374, 41649 | 16 | 2 |
| 107097 | 3477 | Silvana Formigoni Mae Do Alex | 41375, 41650 | 17 | 2 |

## O que a operação faz

- Reatribui **18 aliases**, **12 conversas** e **6 referências de remetente Contact** aos seis contatos antigos. Não sobrescreve os nomes, telefones, LIDs, campos personalizados ou demais dados dos contatos antigos.
- Preserva os dois contatos de cada par: não chama `ContactMergeAction`, não exclui o registro `BR.…` e não mescla dados humanos. O contato técnico retido deixa de possuir as associações reconciliadas.
- Preserva as **102 mensagens** (incluindo atividades) e **14 anexos** nessas conversas, com todos os IDs, conteúdos, datas, estados, referências, arquivos e blobs. Não move mensagens entre conversas. As conversas históricas continuam com seus próprios IDs, agora apontando para o contato correto; isto **não** consolida múltiplas conversas numa única conversa nem resolve conversas automaticamente.
- Deduplicação por mensagem continua separada: nas 36 mensagens públicas recentes amostradas, cada ID original tinha Meta e Uno correlacionados, sem segunda cópia física pelos IDs públicos dos provedores. Não deduplicar por texto ou proximidade de horário.

## Provas e proteções

- Em cada par existe alias telefônico Meta que corresponde ao telefone do contato antigo após normalização brasileira apenas para comparação. O canônico é anterior ao contato BR e pertence à mesma conta e ao par autorizado. Contatos com telefone ambíguo ou identidades contraditórias não são escolhidos automaticamente.
- A prévia não encontrou grupos, associações fora do par nem dependências diretas bloqueantes (como agendamento, notas ou convites Web) nesses seis contatos. O executor deve refazer essa checagem na janela de implantação, não presumir que este retrato continua válido.
- Fingerprint desse retrato: `13f63c2eedf6610885be271eceae834a02030104021264874f1237a0afe092f94`. É evidência da consulta, não autorização para ignorar mudanças posteriores.
- `Whatsapp::ContactReconciliationService` aplica somente com fingerprint de prévia atual, dentro de transação e locks de conta/caixas/contatos. Mudanças de IDs, de escopo ou dependências entre prévia e aplicação bloqueiam a operação. Nenhum `DELETE` ou purge é executado.
- Executor específico: `script/validation/reconcile_bsuid_contacts_20261019.rb`. Modo padrão é somente prévia; aplicação exige `APPLY_RECONCILIATION=yes` e `RECONCILIATION_FINGERPRINT` explícito, conta 1, vínculo 1, caixas 1/65 e horário autorizado de 19/10/2026 a partir de 12h em America/Cuiaba.
- Antes de aplicar, guardar em `private/` o backup e o inventário completo original (IDs e donos dos aliases/conversas/remetentes, hashes dos atributos das mensagens e IDs/blobs de anexos). Depois, conferir os donos esperados, os seis contatos antigos intactos, os seis contatos técnicos ainda presentes, zero associações restantes nos legados e os mesmos IDs/arquivos. Não restaurar banco inteiro automaticamente em caso de falha.

## Limites do pacote

A correção de **novas ingestões** escolhe o contato antigo por evidência telefônica do próprio evento Meta, no par ativo, sem transferir alias legado durante o webhook. A reconciliação administrativa deste documento é uma ação distinta, autorizada exclusivamente para os seis pares listados. Alterações extras de dados ou outras pessoas ficam fora desse agendamento.

## Resultado da execução autorizada

Aplicada na janela das 12h de 19/10/2026, depois do backup e do drain dos workers. A nova prévia manteve exatamente o fingerprint acima, sem bloqueios. O executor terminou com saída zero e a comparação antes/depois confirmou os 12 contatos intactos, 12 conversas e 102 mensagens com IDs/conteúdos preservados, 14 anexos e 14 blobs idênticos. Alteradas somente as associações autorizadas; nenhum alias/conversa dos pares permaneceu sob os legados. Os dois workers foram liberados novamente e confirmados com `quiet=false`. Detalhes e caminhos das evidências restritas no [runbook de execução](hostpath-meta-cycle-recipient-20261019.md).

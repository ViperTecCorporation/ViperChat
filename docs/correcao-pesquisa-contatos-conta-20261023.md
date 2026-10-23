# Pesquisa de contatos por conta — 23/10/2026

Branch: `feat/agent-voip-webphone`. Correção somente em dev, sem commit/push ou VPS.

## Regra

O cadastro de contatos pertence à conta, não à caixa em que houve atendimento. Um agente com acesso ao diretório pode pesquisar e abrir contatos da mesma conta, mesmo sem acesso à caixa de origem ou com restrições de atribuição de conversas.

A opção explícita `hide_contacts_for_agent` continua ocultando o diretório dos agentes. A visibilidade das conversas, mensagens e caixas permanece independente. Nenhum acesso entre contas é liberado.

## Alterações

- `Search::ConversationVisibilityService#contacts`: mantém o escopo de contatos recebido da conta, sem intersectar com as conversas visíveis; preserva a ocultação explícita do diretório.
- `ContactPolicy#show?`: permite abrir o cadastro da mesma conta quando o diretório é permitido. Preserva a verificação de conta e as regras anteriores para acesso contextual quando o diretório está oculto.
- Nenhuma alteração em políticas de conversa/caixa, envio de mensagens, frontend, estrutura do banco ou dados dos contatos.

## Regressão e validação

- Novos casos reproduziram o bloqueio antes da alteração: 39 exemplos, cinco falhas esperadas nos casos adicionados.
- Execução final: **199 exemplos, zero falhas, zero pendentes**, incluindo busca global, diretório de contatos, políticas de contato/conversa/caixa, compatibilidade Enterprise e endpoints VoIP.
- RuboCop nos cinco arquivos de código/testes alterados: zero infrações.
- Cobertura com/sem restrições de atribuição, busca global e busca específica de contatos; contato recebido em caixa sem vínculo do agente; isolamento entre contas; ocultação explícita do diretório.
- Endpoints de conversa, mensagens e caixa sem permissão continuam recusando acesso com o status 401 já usado pela aplicação. O histórico de conversas do contato é filtrado e não permite criar atendimento pela caixa restrita.

Os testes foram executados em cópia isolada das fontes dentro do container existente, usando apenas o banco `viperchat_voip_test` e Redis de teste. A preparação de schema foi feita exclusivamente nesse banco de teste.

Na réplica dev foram atualizados apenas os dois arquivos de backend da correção. Conferência em transação READ ONLY, conta 1/agente 3:

- Contato 3679, anteriormente ausente da busca global: encontrado e cadastro permitido.
- Uma conversa inacessível ao mesmo agente: acesso continua negado pela política de conversa e pela política da caixa; excluída do histórico visível.
- Nenhum registro de negócio foi alterado pela conferência.

As permissões negativas na conferência de runtime usam uma conversa restrita existente, independente do contato 3679; a combinação completa contato/caixa restrita é coberta pelos testes HTTP sintéticos.

Evidências: `output/validation/contact-directory-fix-20261023/rspec-results.json`, `regression-before-fix.json` e runners sem credenciais. A cópia temporária das fontes e o script temporário no container são descartáveis e removidos após validar.

Não houve build Web/Android/iOS, pois não há alteração de frontend ou código nativo. Os 199 testes são a validação direcionada desta correção; não substituem nem tornam verde a execução completa anterior, cujas falhas não relacionadas continuam documentadas.

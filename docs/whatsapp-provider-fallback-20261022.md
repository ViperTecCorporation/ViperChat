# Envio alternativo entre caixas parceiras — 22/10/2026

## Escopo autorizado

Implementação em dev a partir da `4.16.0` (`ac141005b`), isolada na branch
`fix/whatsapp-provider-fallback`. Em 22/10/2026, o usuário autorizou commit e push
na `4.16.0` e, em seguida, incorporação na `feat/agent-voip-webphone`. Essa
autorização não inclui release, publicação de imagem ou aplicação na VPS.
A solicitação atual substitui a regra anterior de nunca trocar de provedor depois
de uma tentativa: uma rejeição definitiva permite tentar o parceiro uma vez.

## Evidências e causa no código

- O print mostra falha de sessão 409 na ViperConnect.
- Os dois arquivos de log fornecidos abrangem 11:13–11:19 UTC. Neles existe
  envio UnoAPI aceito (`teste desconect`, mensagem 4140, conversa 77), mas não o
  recibo Meta nem a falha do print das 08:29. Não comprovam uma entrega pela Meta
  para a mensagem do print. Não inferir entrega de um echo ou do texto da mensagem.
- Antes desta mudança, `UnifiedDeliveryAttemptService` bloqueava nova tentativa
  após uma chamada externa e não programava outro provedor após rejeição segura.
  `IncomingMessageBaseService` também dava precedência global a qualquer `failed`,
  mesmo diante de recibos positivos no parceiro. A interface exibia somente
  `external_error`, sem histórico de resultado por provedor.

## Contrato implementado

1. Seleção do operador e caixa principal continuam registradas. O envio efetivo
   pode mudar para o parceiro após rejeição HTTP 4xx, exceto 408, ou recibo `failed`
   com erro explícito. Timeout, exceção de transporte e HTTP 5xx são incertos:
   exigem revisão e não disparam envio alternativo.
2. Somente vínculo ativo da mesma conta e mesma ativação. Notas privadas e grupos
   não entram neste mecanismo. O parceiro deve suportar a capacidade e ter uma
   identificação segura do destinatário. A Meta continua exigindo modelo aprovado
   fora da janela de resposta; a segurança dos webhooks não foi alterada.
3. Uma tentativa por provedor, com claim persistido antes do HTTP. Nunca alternar
   indefinidamente. A fila normal executa o alternativo; o job de recuperação só
   recupera rejeição definitiva ainda não preparada ou alternativo não iniciado.
   Nunca reapresenta uma tentativa incerta/em andamento.
4. `whatsapp_delivery` guarda os resultados separados. A interface mostra, por
   exemplo, `ViperConnect: Falha no envio` + `Meta: Aceita para envio`, passando a
   `Entregue`/`Lida` somente com recibo. Echo é observação, não confirmação de entrega.
   Se ambos falham, mostrar ambos. Se não puder tentar o parceiro, explicar o motivo.
5. A mesma mensagem/conversa, contato, IDs e anexos são preservados. O `source_id`
   original não é substituído; o novo ID é vinculado por identidade/alias e usado
   nas referências do provedor correto. Não juntar contatos/conversas, não apagar
   bolhas, mensagens, anexos ou blobs, nem correlacionar por semelhança de texto.
6. Confirmação positiva atrasada não é rebaixada por erro antigo. Confirmação que
   chegar antes do claim alternativo cancela a tentativa pendente. Depois que o
   HTTP começou, não é possível prometer cancelamento nem entrega exatamente uma
   vez entre sistemas externos sem idempotência compartilhada pelos provedores.
7. O transporte automático desta mensagem não altera o padrão do vínculo nem a
   escolha persistida do operador para as próximas mensagens.

## Validação e isolamento

- Testes sintéticos, HTTP via WebMock; nenhuma mensagem real de cliente disparada.
- Reutilizado `viperchat-replica-web-1`; fonte exportada para diretório isolado em
  `/tmp`, sem trocar `/app`, imagem, volumes ou containers da réplica VoIP.
- A primeira rodada herdou `DATABASE_URL` do runtime, que prevaleceu sobre
  `POSTGRES_DATABASE`. Foi interrompida e seus resultados foram descartados.
  RSpec usava transações, mas sequências locais podem avançar em rollback.
  Não foi feita restauração automática nem limpeza do banco da réplica.
- Repetição com URL redirecionada explicitamente ao banco novo exclusivo
  `viperchat_fallback_test`, ambiente `test` e Redis 14, conferidos por consulta.
  Carregado schema sem seed de demonstração, pois contatos `jane` interferem em
  testes existentes que pressupõem banco vazio. Credenciais não são impressas.
- Executor reproduzível: `script/validation/whatsapp_fallback_test_env.rb`.
  Exemplo no container local, a partir da cópia isolada:

  ```sh
  RAILS_ENV=test POSTGRES_DATABASE=viperchat_fallback_test \
    ruby script/validation/whatsapp_fallback_test_env.rb bundle exec rspec spec/services/whatsapp
  ```

- Frontend: 54 testes / 8 arquivos aprovados; inclui atualização reativa sem F5,
  ambos os resultados, echo sem falsa entrega, camelCase/snake_case e texto seguro.
- Inspeção visual do componente real em 320, 360, 390, 430, 844 e 1440 px, claro e
  escuro; sem overflow horizontal. Evidências em `output/playwright/fallback-*.png`.
- Bundle compartilhado compilado e sincronizado para Android e iOS; APK Debug
  compilado. O Android USB inicialmente disponível se desconectou antes da
  instalação; sem teste no aparelho. Não compilar/testar iOS no Mac sem resolver
  a recusa de autenticação SSH. Não houve upload a lojas.
- Suíte de serviços WhatsApp: **1.644 exemplos, zero falhas e zero pendências**.
  Após acrescentar o caso de broadcast UnoAPI sem F5 e evitar recarregar o mesmo
  objeto antes de seu callback de atualização, repetidos **81 exemplos focados,
  zero falhas**, cobrindo entrega, avisos, claim e envio unificado.
- RuboCop dos 11 arquivos Ruby alterados/novos e ESLint dos componentes alterados:
  sem erros. Nenhum teste existente foi desativado ou teve expectativa reduzida.
- APK de validação preservado em `output/validation/viperchat-fallback-debug.apk`,
  SHA-256 `dfbc29059767cc9f7ac4b53c7650b8a25ccd216b705f5bc5ba7af6bb276c6ae9`.
- A réplica ativa continua com seu código VoIP anterior. A mudança não foi
  sobreposta a `/app`; somente a exportação isolada foi usada nos testes.

### Temporários e limpeza pendente

A limpeza abaixo foi autorizada pelo usuário, mas **continuou bloqueada pela
política do ambiente**, inclusive após a autorização. Nenhum desses diretórios
foi apagado e não houve tentativa de contornar o bloqueio. Cerca de 170 MB são
regeneráveis no worktree desta tarefa:

- `android/app/build`, `android/build`, `android/.gradle`;
- `dist-mobile`, `android/app/src/main/assets/public`, `ios/App/App/public`;
- `.playwright-cli` (sessão de navegador encerrada).

Também ficaram identificados os intermediários de validação desta tarefa:

- Windows: `C:/Users/caita/AppData/Local/Temp/viperchat-provider-fallback-20261022.tar`
  (107.540.480 bytes, exportação de fontes, não backup de dados);
- container local `viperchat-replica-web-1`:
  `/tmp/viperchat-provider-fallback.eHiLGI` (exportação isolada e relatórios);
- PostgreSQL local: `viperchat_fallback_test`, criado exclusivamente para os
  testes desta tarefa, sem dados de clientes; preservado, não removido;
- `.codex/vitest.fallback.config.ts`, `.codex/vite.fallback-preview.config.ts`,
  `.codex/run-fallback-validation.rb` e `output/playwright/fallback-preview.*`.

Preservar fontes, testes, plano, prints, APK, dependências e caches compartilhados.
Os três arquivos nativos gerados pelo sync foram recolocados com o conteúdo do
HEAD; `git diff --exit-code` confirmou ausência de alteração material neles.
Não houve limpeza de volumes, cache Docker ou dados da réplica. Espaço livre
observado no C: antes da tentativa de limpeza: aproximadamente 112,2 GB; não
atribuir variações do espaço livre a exclusões que não ocorreram.

## Integração Git autorizada e homologação futura

Revisar e publicar somente fontes, testes e este plano. Integrar primeiro na
`4.16.0` e depois aplicar o mesmo commit na `feat/agent-voip-webphone`, preservando
os ajustes VoIP e os arquivos locais gerados pelo sync nativo. Conferir os SHAs
remotos das duas branches após o push. Não incluir APK, prints, caches ou
intermediários no commit. A VPS e a imagem do cliente permanecem inalteradas.
Para homologação externa, obter eventos
do horário exato e validar falha segura → aceite do parceiro → recibo, sem forçar
envio real a clientes. Não restaurar banco automaticamente em rollback de código.

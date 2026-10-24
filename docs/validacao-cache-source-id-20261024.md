# Recibo correto na primeira renderização do cache

24/10/2026 — `feat/agent-voip-webphone`, desenvolvimento.

## Causa e correção

O snapshot persistia `status`, mas omitia `source_id`. A bolha WhatsApp exige
esse ID junto ao status para mostrar os checks. Assim, um registro salvo como
`read` era desenhado com relógio até a resposta HTTP repor seu ID de provedor.
O whitelist de mensagens agora inclui `source_id`, sem fabricar IDs nem mudar
a regra do componente. Escopo por conta/usuário, TTL, permissões e filtros de
credenciais permanecem iguais. Fonte aplicada no volume da réplica existente.

Snapshots antigos sem esse campo precisam de uma consulta online para serem
regravados completos. Não há como recuperar o ID omitido sem o servidor; não
se apaga o cache nem se inventa um ID para esconder o problema.

## Testes

- Regressões primeiro falharam: ID ausente no snapshot e checks ausentes na
  primeira montagem real do `MessageMeta`/`MessageStatus` restaurado.
- Depois: 294 testes aprovados, 17 arquivos. O teste do ícone usa os componentes
  reais de recibo/ícone, não um stub textual do status. Confere check duplo,
  ausência de relógio e cor azul somente para `read`, já na primeira montagem.
- Teste de IndexedDB reabre o cache e exige a preservação exata do `source_id`,
  mantendo as verificações de ausência de credenciais e URLs de mídia.
- Playwright em localhost reteve todas as respostas GET de conversas durante
  a renderização. Para `delivered` e `read`, resultado: `cached=true`,
  `sourceId=synthetic-provider-id`, `clock=false`, zero respostas de consulta
  concluídas. `readColor=false` para entregue e `true` para lida.
- Fixtures, conta e IDs fictícios; escritas interceptadas, zero mensagens reais
  enviadas. Nenhuma alteração no banco do cliente ou VPS.

Evidências em `output/playwright`: `cache-source-icon-20261024.js`,
`cache-source-delivered-before-http.png`, `cache-source-read-before-http.png`.
Playwright foi usado para conferir a renderização real antes do HTTP.

## Pacotes nativos

`native:sync:android` e `native:sync:ios` executados. Bundle compartilhado
`dashboard-CyxWkgri.js`, SHA256
`45eb8ce51762ea591f20d3278aac3ccd76b0f33c8e21e0aae4445f87b7ff0b7d`.
Android Debug compilado com dois workers e assinatura verificada. Nenhum
dispositivo Android conectado; o teste do ícone acima foi no navegador.
No Mac, iOS Debug assinado compilou (`BUILD SUCCEEDED`) e passou na verificação
codesign strict/deep. Instalado por cima do `.voipdev`, sem apagar dados,
alterar identificadores ou permissões, nem relançar o simulador para novo teste
autenticado. O usuário informou lentidão severa por falta de aceleração; não se
declara aqui teste de login ou do ícone dentro do simulador.
Sem alteração de versão, commit, push, publicação ou containers novos.

Temporários desta tarefa removidos: logs/snapshot de trabalho do Playwright,
pacote de transferência Windows (~9,8 MB) e pacote/staging Mac (~41 MB), além
dos assets gerados obsoletos conferidos no sync. Capturas, scripts de evidência,
APK, fontes, dados e caches compartilhados preservados. Temporários são
regeneráveis; nenhum dado de atendimento foi removido.

# Diagnóstico: estado de entrega e cache após F5

24/10/2026, `feat/agent-voip-webphone`, réplica local existente.
Diagnóstico inicial e correção posterior autorizada em desenvolvimento.

## Resultado

Há uma condição de corrida reproduzida no código atual:

1. A consulta de reconciliação das mensagens começa com um estado antigo.
2. O fluxo `updateMessage`, usado pelo evento `message.updated` do socket,
   atualiza a mesma mensagem para `delivered`.
3. A resposta HTTP atrasada termina e a reconciliação substitui o estado por
   `progress` (também reproduzido com `sent`).
4. O cache persistente grava o estado regredido.

Isso foi reproduzido com a store real em Chromium, uma mensagem sintética,
respostas HTTP interceptadas com atraso de 1200 ms e atualização injetada no
mesmo dispatch utilizado pelo socket. Não foi um webhook real de provedor.
Resultado: `socket=delivered`, `afterAPI=progress`, `persisted=progress`,
uma única mensagem, sem duplicação.

Ponto identificado: `syncActiveConversationMessages`, ramo `refresh: true`,
faz merge por ID com `merged.set(message.id, message)` e depois substitui
as mensagens, sem a proteção de avanço de recibos existente em `ADD_MESSAGE`.
É necessário preservar a confirmação mais recente ao reconciliar a resposta.
A reprodução demonstra o defeito, mas não comprova que ele foi a causa do
episódio específico observado pelo usuário.

## Cenários de controle

- 18 testes existentes de cache/reconciliação passaram; não cobrem a corrida.
- F5 sem atualização concorrente: o estado foi reconciliado para `delivered`,
  mantendo um só ID. Com 1200 ms de atraso por consulta, estado de cache em
  `progress` observado aos 3421 ms e estado reconciliado aos 4545 ms do documento.
  São medidas desse ensaio dev, não uma promessa de desempenho.
- Logo após o HTTP: memória `delivered`, IndexedDB `progress`. Após 1700 ms:
  memória e IndexedDB `delivered`. O flush tem debounce de 1200 ms.
- Depois da persistência e de outro F5, o estado permaneceu `delivered`.
- Nenhuma consulta de conversa/mensagem repetida nos cinco segundos estáveis
  medidos após o F5 de controle.

## Escopo e evidências

Sessão isolada `cache-status`, identidade fictícia e API mockada antes de entrar
no dashboard. Rotas de escrita bloqueadas/interceptadas; sem login real,
mensagens reais, alterações no banco da réplica, reenvio, VPS ou containers novos.
Chamadas SIP não iniciadas. Browser encerrado e intermediários removidos.

Scripts reproduzíveis e capturas desktop/390 px em `output/playwright`:

- `cache-status-20261024.js` — preparação das fixtures e interceptações.
- `cache-status-exercise-20261024.js` — F5 com rede rápida/lenta.
- `cache-status-persistence-20261024.js` — memória, IndexedDB e novo F5.
- `cache-status-race-20261024.js` — confirmação concorrente com HTTP antigo.
- `cache-status-delivered-desktop.png` e `cache-status-delivered-390.png`.

Playwright orientou a validação em navegador real. Não houve mudança no frontend
nem em bundles nativos; este ensaio não valida o comportamento em iPhone/iPad.

## Correção posterior em dev

O ramo `refresh: true` agora registra os estados no início da consulta. Durante
o merge por ID, protege um recibo mais avançado confirmado enquanto o HTTP estava
pendente, incluindo seu `source_id`. Estados já validados também não regridem
por uma resposta HTTP atrasada. Não considera um estado vindo apenas do cache
como prova suficiente para sobrescrever o servidor: falhas HTTP continuam sendo
aplicadas e o cache não validado continua sujeito à consulta autoritativa.

- Regressões primeiro falharam no comportamento anterior; depois passaram para
  `delivered` contra `progress`/`sent` e `read` contra os três estados inferiores.
- Proteção negativa: falha real do servidor e correção de um recibo de cache
  não validado continuam atualizando a bolha normalmente.
- 285 testes aprovados, 16 arquivos, incluindo cache, fila offline, store,
  reconexão, busca e estatísticas. Três expectativas antigas da integração do
  cache foram atualizadas para exigir explicitamente os novos marcadores e a
  reconciliação, sem remover verificações.
- Playwright repetiu a corrida: `socket=delivered`, `afterAPI=delivered`,
  `persisted=delivered`, `regressed=false`, uma só mensagem.
- Conferidos persistência e novo F5; capturas em 320/360/390/430/844/1440 px,
  sem overflow horizontal. O debounce de gravação de 1200 ms foi mantido.
- ESLint e verificação de whitespace aprovados. Código aplicado na réplica
  existente, sem banco de clientes, envios, containers novos, commit ou push.
- Bundles Android/iOS regenerados com `native:sync:android` e `native:sync:ios`.
  Bundle `dashboard-B70Hqs-S.js`, SHA256
  `1d517862e2bf01c10c333c3f1547991461a9e12d56d580119e21091fe68a0dc8`.
- Android Debug compilou com dois workers e assinatura conferida; sem dispositivo
  Android conectado. APK SHA256
  `08dc4040a0d7cfa31f33a4fd6407bb5dd4a4b0854b8fd13085471f08e9eb0e67`.
  A validação da corrida foi no browser, não em aparelho Android.
- iOS Debug assinado compilou no Mac existente, `BUILD SUCCEEDED` e codesign
  strict/deep com exit 0. Grupos do Keychain simulados conferidos; instalado por
  cima do `.voipdev`, sem uninstall/reset. Captura confirmou a tela de login.
  Ela ainda aponta para o servidor de produção na configuração preservada;
  nenhuma credencial foi submetida. Teste autenticado da corrida no simulador
  continua pendente de conectar a réplica dev; não foi declarado aprovado.
- Limpeza: removidos logs/snapshots intermediários desta sessão do Playwright,
  pacote temporário de transferência Windows (~9,8 MB), staging/arquivo de
  transferência do Mac e assets gerados obsoletos (~19,6 MB em cada plataforma).
  Fontes, evidências, APK, dados, assinatura e caches compartilhados preservados.

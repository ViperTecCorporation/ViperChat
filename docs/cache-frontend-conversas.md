# Cache local de conversas — dev

Implementado na `feat/agent-voip-webphone`, usando IndexedDB e a réplica existente.
O servidor continua sendo a fonte de autoridade. A evolução de 24/10 adiciona
fila offline apenas de textos/notas, documentada em `docs/fila-offline-texto.md`.

## Funcionamento

- Guarda até 100 conversas recentes e 50 mensagens por conversa; limite de 5 MiB
  por snapshot e validade de 24 horas desde a última leitura válida.
- Separação por instalação/origem, usuário, conta e revisão local de sessão.
- Restaura conversas e metadados básicos antes da rede; sincroniza em segundo plano.
- No app nativo, a identidade da sessão local permite montar a interface antes da
  validação HTTP. Sessão expirada continua exigindo autenticação.
- A última conversa pode ser retomada no início nativo; links explícitos prevalecem.
- Metadados e mensagens têm validações separadas: receber metadados novos não
  libera envio enquanto o histórico ainda é do cache. IDs repetidos são mesclados.
- O aviso grande de reconexão foi substituído por um indicador discreto
  “Atualizando…”; desconexões curtas não geram aviso. Offline mostra “dados salvos”.

## Segurança e limites

O cache contém dados pessoais e texto de conversas autorizadas, incluindo notas
privadas; não é uma nova base criptografada. Depende da proteção do perfil do
navegador/dispositivo. Não armazena credenciais, tokens, configuração de provider,
URLs assinadas nem binários de áudio, vídeo e anexos. Mídias continuam online.

Enquanto houver dados não validados ou sessão nativa pendente, escritas HTTP
ficam bloqueadas; textos/notas podem ser guardados na fila local sem envio.
Logout limpa o cache e a fila e invalida outras abas. Mudanças conhecidas
de conta/permissão e respostas de acesso negado removem dados correspondentes.
Uma revogação remota não pode ser descoberta offline: a cópia local pode continuar
legível até expirar ou o servidor voltar a responder. O backend mantém todas as
validações de acesso. Falha/quota/bloqueio do IndexedDB não impede o fluxo online.

O primeiro acesso precisa carregar dados para aquecer o cache. No navegador web,
este recurso não garante abertura do HTML/JavaScript sem rede; no app empacotado,
esses arquivos fazem parte do aplicativo.

## Validação em 23/10/2026

- 221 testes passaram em 20 arquivos: cache, editor, autenticação, reconexão, conversas e
  fluxos nativos. Incluem isolamento, TTL, logout, negação de acesso, falha de
  armazenamento, mensagens sobrepostas e retomada sem substituir deep link.
- Ensaio no navegador usando a entrada nativa da réplica e dados sintéticos apenas
  no contexto local: API com atraso de 4 s, reabertura offline e retorno da rede.
- Conversa sintética apareceu ainda do cache (~3,2 s no servidor Vite de dev);
  envio offline rejeitado com `ERR_CACHE_READ_ONLY`, zero POSTs de mensagem;
  após reconectar permaneceram dois IDs únicos, com texto atualizado pelo servidor.
- Capturas em 1440, 390 e 320 px em `output/playwright/frontend-cache-*`;
  scripts em `output/validation/frontend-cache-20261023` (artefatos locais).
- Teste de navegador não substitui teste em Android/iOS físico. Plugins nativos
  não implementados no navegador não foram tratados como validação de aparelho.

Sem novos containers, VPS, alterações de histórico no servidor, commit ou push.

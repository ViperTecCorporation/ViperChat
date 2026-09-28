# Ambiente local integrado

Codigo ativo: `C:\Users\caita\.codex\worktrees\viperchat-dev`.
Branch: `codex/local-replica-dev`. Esta pasta consolida as alteracoes pendentes do checkout principal e do worktree de hotpatch, sem sobrescrever nenhum deles.

## Uso

Execute PowerShell nesta pasta:

```powershell
.\.codex\dev.ps1 start
.\.codex\dev.ps1 status
.\.codex\dev.ps1 logs
.\.codex\dev.ps1 test-js app/javascript/dashboard/helper/specs/locationSharing.spec.js --minWorkers=1 --maxWorkers=2
.\.codex\dev.ps1 test-ruby spec/jobs/conversations/resolution_job_reopening_spec.rb
```

Abra http://127.0.0.1:3000/app/login. O dominio `https://viperchatdev.vipertec.net` deve encaminhar para a mesma porta 3000, incluindo WebSocket. Nao e necessario publicar a porta do Vite separadamente. DNS/tunel sao administrados separadamente.

## Alteracoes

- Edite os arquivos **neste worktree ativo**. Outros checkouts nao sao sincronizados automaticamente.
- Vue/JS/CSS: Vite observa os arquivos e atualiza o navegador. A primeira carga faz compilacao sob demanda e pode demorar; cargas seguintes usam cache.
- Traducoes: com `VIPER_DEV_PROXY=true`, o Vite precompila todos os idiomas em um modulo para evitar milhares de requisicoes no login. Alterar arquivos em `dashboard/i18n/` reinicia a precompilacao automaticamente; nao reduz os idiomas e nao muda o build de producao.
- Classes Ruby: Rails recarrega na proxima requisicao. Para garantir novos jobs com o codigo atualizado, use `.\.codex\dev.ps1 restart-worker`.
- Configuracoes/inicializadores/rotas complexas: reinicie web/worker quando necessario; `docker compose -f C:\Users\caita\.codex\runtime\viperchat-replica-20260926\compose.dev.json restart web worker-1`.
- Dependencias JS: atualize lockfile e rode `.\.codex\dev.ps1 install-js`.
- Dependencias Ruby: reconstrua `viperchat-dev-runtime:20260926` com `.codex/Dockerfile.local-dev` e recrie web/worker. A imagem base local importada deve ser preservada.

## Dados e servicos

Um worker Sidekiq (concorrencia 5), web Rails development, Vite, gateway Nginx, PostgreSQL 5432 e Redis 6379. Dependencias, logs, caches e a copia executada do codigo ficam em volumes Linux do Docker. Docker Compose Watch sincroniza as edicoes do worktree Windows automaticamente; isso evita leituras lentas de milhares de arquivos pelo bind mount.

Use `.\.codex\dev.ps1 start` depois de reiniciar o Windows/Docker: alem dos containers, ele inicia o sincronizador em segundo plano. `stop` encerra ambos. Rodar somente `docker compose up` nao inicia o sincronizador. Logs do sincronizador ficam no diretorio privado em `watch.log` e `watch-errors.log`. Nao edite a copia dentro do container; edite o worktree Windows.

Banco clonado: `chatwoot_db`. Bucket: `viperchatdev`, endpoint `https://s3.vipertec.net`. Os anexos antigos so aparecem se existirem neste bucket. Integracoes externas permanecem reais, conforme solicitado; automacoes e envios podem atingir servicos externos. O ambiente de desenvolvimento pode exibir detalhes internos: restrinja o acesso ao dominio dev.

Testes Ruby usam **viperchat_test**, Redis DB 15, armazenamento e entrega de email de teste. Nunca execute RSpec definindo o banco clonado como destino. O script `test-ruby` prepara somente esse banco separado.

Compose privado: `C:\Users\caita\.codex\runtime\viperchat-replica-20260926\compose.dev.json`. Contem credenciais e nao deve entrar no Git. Nao use o docker-compose.yaml legado deste repositorio para iniciar esta replica.

## Preservacao

A VPS nao foi modificada. Os checkouts anteriores e os volumes da stack antiga estao preservados. O snapshot original, inventarios e o compose da replica por imagem permanecem no diretorio privado para recuperacao. Nenhum commit ou push foi feito automaticamente.

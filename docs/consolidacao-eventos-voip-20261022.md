# Consolidação de eventos, histórico e gravação — aceite dev

22/10/2026, America/Cuiaba. Branch ViperChat `feat/agent-voip-webphone`.
Implementação e testes sintéticos nas instalações locais existentes.
Entrega de código, testes e planos nos branches de desenvolvimento; sem VPS,
chamada real ou publicação de imagens. As validações abaixo precedem o commit.

## 1. Recuperação REST automática

Implementada sobre `/v1/console/history?sync=webhook_events`, sem reconstruir
JSON a partir do CDR. O produtor retorna exatamente os envelopes da outbox,
autorizados pela empresa e pelo destino conta/serviço/origem configurados.

- Campo explícito `history_company_id` no serviço ViperChat.
- Preparação canônica, leitura e marca d'água atômicas no produtor; regressão
  com mais de 500 registros e captura concorrente impede salto de eventos.
- Cursor assinado na origem e checkpoint criptografado por serviço no receptor.
- Lease persistido e checagem da configuração antes do commit; HTTP fora do lock.
- Página e inbox gravadas juntas, jobs somente depois do commit.
- Jobs registrados a cada minuto, verificados no Redis após reinício do worker.
- 400/409 pausam; 410 relê somente o histórico retido, sinalizando lacuna;
  autenticação inválida bloqueia; rede/5xx usam backoff.
- Releitura não apaga dados nem dispara ligação/toque antigo.

## 2. Matriz sintética de chamadas

Testados recebida/efetuada, término normal, perdida, falha e cancelamento,
participações de transferência, atendimento por outro ramal e direção interna.
Eventos tardios e duplicados mantêm os mesmos IDs e não ressuscitam chamadas.
Falha/rejeição técnica permanece identificável por estado e `end_reason`.
Sem SIP Call-ID comprovado, não há associação por semelhança de telefone/nome.

Gravação e IA chegam em revisões independentes e atualizam a mesma nota privada.
Conversas resolvidas continuam resolvidas. Ausência/ambiguidade de evidência
continua pendente, sem criar conversa ou escolher a mais recente arbitrariamente.

## 3. Falha e recuperação com infraestrutura local real

RabbitMQ existente: resposta HTTP503 intencional, entrega por fila de retry,
parada/reabertura do consumidor com SQLite persistido e supressão de job
duplicado. Mesmo evento, payload e fingerprint; namespace e DB de teste removidos.

REST real: leitura inicial dos seis envelopes de dois CDRs sintéticos sem
duplicação. Depois foi criada uma revisão sintética (sequência59) atomicamente
retida antes de qualquer envio HTTP. A recuperação incremental trouxe esse
evento ausente e avançou o checkpoint, atualizando a nota existente.

O reenvio posterior pelo webhook retornou duplicata, sem nova bolha ou mídia.
Estado final: sete eventos processados, zero eventos pendentes, recuperação
`caught_up`, checkpoint configurado e nenhuma lacuna detectada neste ensaio.

| Principal | Chamada | Conversa pública | Nota | Anexo | Blob |
| --- | --- | --- | --- | --- | --- |
| ViperConnect | 286 | 17753 | 2429120 | 293638 | 505332 |
| Meta | 287 | 17754 | 2429121 | 293639 | 505333 |

Todos esses IDs permaneceram iguais. Áudio de 4044 bytes com SHA-256
`cafb03e3da085ef2e5d23534db6c42bd2809565b4564267e6dbf586f05651c24`.
O player continua sendo AudioChip das bolhas, com download autenticado.

## 4. Diagnóstico e reprocessamento

ViperChat: Serviços VoIP → Diagnóstico. Contagens e códigos sanitizados de
eventos/artefatos, estado da recuperação e aviso de lacuna. Confirmação antes
de reprocessar registro ou reiniciar leitura incremental. Operador/horário
auditados; oito tentativas automáticas antes de falha definitiva.

Manager: Telefonia → Empresas → Entregas ao ViperChat. Diagnóstico e replay
confirmado de eventos pendentes/dead, com UUID idempotente. Revalida empresa,
ramais e destino original; não muda conteúdo, IDs, fingerprint ou tentativas.

API real testada nas duas pontas: token inválido401, diagnóstico sem conteúdo
ou credenciais, replay aceito, repetição controlada/idempotente, rejeição de
reprocessamento repetido409 no receptor. Jobs consumidos pelo worker existente;
notas, blobs e estados finais conferidos novamente depois.

## Validação e limites

- Backend VoIP ViperChat: 146 exemplos aprovados; RuboCop51 arquivos sem infrações.
- Frontend VoIP ViperChat: 143 testes aprovados em12 arquivos.
- Serviço VoIP: 234 testes, 233 aprovados e um skip por ffmpeg indisponível;
  typecheck e build aprovados.
- Manager: 139 testes aprovados em cinco suítes e build aprovado.
- Documentação: 57 páginas, 146 caminhos e191 operações validados.
- UI: componentes reais conferidos em320/360/390/412/430/1280px e844×390,
  incluindo confirmação de reset; não é aceite em aparelho.
- Assets Android/iOS regenerados. Android assembleDebug aprovado; adb sem
  aparelho. Mac192.168.0.138 recusou SSH por chave; não houve Xcode/build/teste iOS.

São suítes focadas nas integrações alteradas, não toda a suíte do repositório.
O operador ainda fará chamadas reais; homologação de central legada, falhas
prolongadas, PushKit/CallKit e Android Telecom permanecem etapas separadas.

## Runtime e preservação

Somente serviços existentes foram atualizados/reiniciados. Migrações aditivas
190000 e200000 no PostgreSQL dev, e008 no SQLite do serviço. Bancos, Redis,
RabbitMQ, contatos, histórico e mídias existentes preservados.

Backup SQLite pré-consolidação: volume do serviço,
`/home/u/app/data/backups/webhook-dev-20261022/before-consolidation.sqlite`,
integridade verificada. Backup PostgreSQL e configurações restritos da etapa
anterior preservados. Não restaurar banco automaticamente como rollback de código.

Removidos banco/fonte de teste isolados (~116,7MiB) e namespace RabbitMQ/SQLite
exclusivos do ensaio. Helpers reproduzíveis, prints, APK e backups necessários
preservados. Pequenos harnesses frontend tiveram limpeza bloqueada por política;
continuam pendentes, sem contorno. Não houve prune ou remoção de volumes/caches.

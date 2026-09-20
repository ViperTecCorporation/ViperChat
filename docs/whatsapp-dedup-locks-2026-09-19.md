# Proteção de processamento WhatsApp — 19/09/2026

## Alteração

- Mutex Redis usa UUID por aquisição e compare-and-delete existente no Alfred.
  Um processo cujo lock expirou não remove a chave do próximo proprietário.
- MutexApplicationJob libera em ensure, incluindo conflito de lock dentro do bloco.
- MessageDedupLock passa a representar processamento em andamento, com lease de
  cinco minutos, não uma confirmação de processamento por 24 horas.
- A mensagem persistida no PostgreSQL continua sendo a evidência de conclusão.
  Após obter a lease, o serviço repete a consulta sem reutilizar query cache.
- Rollback, retorno antecipado e sucesso liberam somente a lease própria.
- Conflito de processamento gera erro reprocessável: até 40 tentativas, a cada
  10 segundos. Isso cobre expiração da lease após queda abrupta de um worker.
  Esgotamento não deve ser tratado como mensagem concluída: acompanhar falhas na fila.
- Antes de sair da transação de criação, verifica-se propriedade da lease.
  Se ela expirou durante download/processamento, a transação é revertida.
- O envio continua salvando o ID devolvido pelo provider; não dispara exceção de
  conflito após enviar, evitando introduzir um reenvio por esse motivo. Sua lease
  também é liberada após persistência ou erro, sem apagar a de outro worker.

## Limites

Não é garantia de exactly-once: há limites de leases, Redis e concorrência entre
envio e eco; a checagem final de propriedade não é atômica com o commit PostgreSQL.
Não há restrição única nova, upsert genérico ou alteração do esquema.
As regras específicas de catálogo/interativos, edições, revogações e reações
continuam nos serviços próprios. Compartilhamentos de múltiplos contatos continuam
podendo gerar várias mensagens com o mesmo source_id.

Não corrige índice inconsistente, não remove duplicados e não resolve transcrições
vazias com UUIDs distintos produzidas pela UnoAPI.

## Implantação futura

- Nenhum deploy foi executado nesta tarefa.
- Atualizar web e todos os workers juntos, drenando jobs antes da troca. Um worker
  antigo ainda pode executar a liberação incondicional de locks; não anunciar a
  proteção como ativa durante uma implantação mista.
- Chaves legadas de deduplicação podem durar até 24h. Mensagens já persistidas são
  encontradas antes da lease. Chaves órfãs antigas sem mensagem podem esgotar o
  retry novo: inventariar e reprocessar de forma controlada após expirarem.
  Não limpar Redis globalmente nem apagar chaves em uso.
- Acompanhar erros Busy, retries esgotados, tempo de processamento e downloads
  superiores a cinco minutos. Não aumentar TTL silenciosamente para mascarar falhas.
- Rollback exige drenar workers e retornar à imagem anterior, reconhecendo que a
  proteção anterior de 24h não é restaurada retroativamente para eventos novos.
- Mudança somente backend: não requer recompilar APK, AAB ou bundle iOS. As alterações
  pendentes anteriores de atalhos do frontend permanecem separadas.

## Validação

Testes locais com PostgreSQL e Redis exclusivos e sem dados de produção.
Casos adicionados: proprietário antigo, rollback/retry imediato, lease expirada,
segunda consulta após lock, histórico repetido e conflito reencaminhado ao job.
Também executados os serviços WhatsApp/UnoAPI/Meta e consumidores de locks.
Rodada final: 627 exemplos, zero falhas. RuboCop: 13 arquivos, zero infrações.
Não é a suíte completa do projeto. Logs preservados em
`C:/Users/caita/AppData/Local/Temp/viper-dedup-20260919/final.log`.

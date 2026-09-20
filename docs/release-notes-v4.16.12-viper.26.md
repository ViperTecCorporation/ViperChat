# ViperChat v4.16.12-viper.26

Atualização corretiva que substitui a tag retirada `v4.16.12-viper.25`, preservando suas funcionalidades.

## Correções

- Corrigida a migration de consolidação de contatos que podia falhar com violação de unicidade ao atualizar vínculos duplicados. Os três índices envolvidos agora são removidos sob bloqueio e reconstruídos na mesma transação; falhas restauram dados e índices.
- Corrigida a seleção da foto de grupos com múltiplos avatares antigos, evitando exibir uma foto de participante quando existe uma foto identificada do próprio grupo.
- Atualizações de avatares agora serializam a substituição e preservam os vínculos anteriores para recuperação, sem apagar os arquivos.
- Corrigido o upload de avatares UnoAPI dentro da transação, garantindo que o arquivo seja armazenado antes da associação.
- Adicionado reparo controlado dos avatares duplicados, com simulação, escopo por conta, backup dos vínculos e exclusão automática de casos ambíguos do reparo.

## Validação

- 580 testes de regressão focados sem falhas; RuboCop sem infrações nos dez arquivos Ruby envolvidos.
- Migrations exercitadas em uma cópia recente do banco, com verificação de idempotência, integridade dos três índices e preservação das mensagens e dos registros de arquivos.
- Correções aplicadas e verificadas na instalação de validação por host patch, antes da publicação desta versão.

## Atualização

- Fazer backup e suspender web/workers durante o reparo: esta migration adquire locks e não deve ser tratada como manutenção online sem impacto.
- Executar `db:migrate` e exigir sucesso antes de iniciar web/workers. No Docker Compose, usar `depends_on` com `condition: service_completed_successfully` para o serviço de migração.
- Se já houver o host patch de avatares/migration, remover seus seis mounts específicos ao atualizar para esta imagem; manter os demais volumes e a dependência do serviço de migração.
- Fotos históricas são preservadas e consomem armazenamento; não há expurgo automático.
- Alteração somente de backend: não exige reinstalação dos aplicativos Android/iOS.

Imagem prevista após conclusão do workflow: `ghcr.io/viperteccorporation/chatwoot:v4.16.12-viper.26-ce`.

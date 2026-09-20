# Avatares de participantes herdados por grupos

## Causa

O normalizador de webhook usava `contacts[].profile.picture_id` (remetente) como
alternativa a `group_picture_id`. O job baixava a foto individual e a anexava ao
contato do grupo. Não era somente cache do frontend.

O normalizador agora aceita somente o campo explícito de foto do grupo. Jobs
antigos com JID individual (`@lid`, `@s.whatsapp.net`, `@c.us`) destinados a
contatos de grupo são ignorados sem remover qualquer avatar existente.

## Reparo conservador e reversível

`Whatsapp::Unoapi::InheritedGroupAvatarRepair` exige cumulativamente:

- Canal UnoAPI e contato vinculado exclusivamente a identificadores de grupo.
- Metadados de download apontando para um JID individual.
- Todas as conversas do contato são de grupo, sem URL explícita de foto e com
  o mesmo identificador individual de foto.
- Nome do arquivo corresponde exatamente ao prefixo gerado pelo job para esse ID.
- Contato individual na mesma caixa tem uma imagem com o mesmo checksum.

Casos ambíguos, fotos manuais, fotos explícitas e fotos identificadas como grupo
ou por ID opaco não são reparados automaticamente. Campo de foto vazio em um
webhook continua não sendo interpretado como autorização para apagar uma foto.

O vínculo ActiveStorage é renomeado para `unoapi_inherited_avatar_backup`, não
apagado. O blob continua anexado e não fica sujeito à limpeza de blobs órfãos.
Metadados anteriores e vínculo ficam registrados em
`contact.additional_attributes.unoapi_inherited_avatar_backup`. Fotos dos contatos
individuais e arquivos no armazenamento não são alterados.

## Operação

Primeiro execute a simulação por conta:

```sh
ACCOUNT_ID=1 bundle exec rails runner script/repair_inherited_group_avatars.rb
```

Para aplicar, informe somente os IDs internos revisados (não display_id) e um
arquivo de backup novo, em diretório privado fora de public:

```sh
ACCOUNT_ID=1 APPLY_IDS=39258 BACKUP_PATH=/private/avatar-backup.jsonl \
  bundle exec rails runner script/repair_inherited_group_avatars.rb
```

O backup é criado com permissão 0600, sem sobrescrever arquivos. Cada snapshot é
sincronizado em disco antes da alteração transacional. Há timeout de consulta e
lock. Instale a correção do normalizador/job antes de aplicar o reparo e valide
novamente com a simulação após a aplicação.

Para restaurar, revise o backup: somente se não existir avatar mais novo,
renomeie o vínculo arquivado para `avatar` e recoloque os metadados específicos
da foto. Não sobrescreva o JSON completo de contato/conversa após novas edições.
Não use purge nem delete de blobs para este reparo.

## Validação local

531 exemplos de regressão de WhatsApp, avatares e webhooks: zero falhas.
Inclui preservação de foto manual, foto explícita, dados ambíguos, foto do contato,
rollback transacional e execução repetida. RuboCop sem infrações nos arquivos
alterados. Mudança somente de backend, sem alteração de bundles Web/Android/iOS.

## Fotos legítimas com URL de bucket indisponível

Também foi identificado um problema distinto: a API de detalhes devolvia uma URL
assinada cujo bucket respondia 404 NoSuchBucket, embora a rota autenticada de foto
do grupo respondesse corretamente. A sincronização agora usa o JID do próprio
grupo quando o ID de foto está ausente ou é um JID individual. IDs opacos explícitos
continuam aceitos. O hash da URL participa da identificação de alterações quando
a API não fornece hash, evitando downloads repetidos sem bloquear URLs novas.

A exibição prioriza o avatar armazenado do contato de grupo, mas não promove
avatares gerados a partir de JIDs individuais. Uploads manuais são preservados
mesmo quando restaram metadados antigos. Falhas na busca não removem o avatar.

Regressão após esse ajuste: 535 exemplos, zero falhas, lint dos quatro arquivos
alterados sem infrações. A correção é de backend e não exige reinstalar os apps.

## Múltiplos avatares ativos no mesmo grupo

Foram encontrados vários vínculos `avatar` no mesmo contato. A associação
`has_one_attached` não impede esse estado legado: a seleção podia devolver a foto
antiga de um participante mesmo após a sincronização correta do grupo.

`Avatar::GroupAvatarService` seleciona a foto identificada como pertencente ao
grupo e preserva fotos manuais. Atualizações pelo job UnoAPI e pelo job de URL
arquivam os vínculos anteriores em uma transação com bloqueio do contato, usando
o nome `group_avatar_history_<attachment_id>`. Nenhum blob é apagado. No job UnoAPI,
o upload termina antes da associação do blob ao contato. Fotos históricas passam
a consumir armazenamento até uma eventual política de retenção, fora deste reparo.

### Simulação e aplicação controlada

Somente leitura, limitada à conta informada:

```sh
ACCOUNT_ID=1 RAILS_ENV=production bundle exec rails runner script/repair_duplicate_group_avatars.rb
```

O reparo automático exige identidade única de grupo e foto confirmada pelo hash
do JID no nome do arquivo. Casos ambíguos, fotos manuais e downloads por URL sem
essa comprovação são excluídos da aplicação automática.

Exemplo de aplicação, somente após revisar a simulação e autorizar os contatos:

```sh
ACCOUNT_ID=1 APPLY_CONTACT_IDS=4697,51828 BACKUP_PATH=/private/group-avatars.jsonl \
  RAILS_ENV=production bundle exec rails runner script/repair_duplicate_group_avatars.rb
```

O backup é criado exclusivamente, com permissão 0600, e sincronizado em disco
antes da alteração de cada contato. Cada contato tem sua própria transação;
uma falha posterior não desfaz contatos já reparados. Os IDs são validados no
escopo da conta. A aplicação altera apenas os nomes dos vínculos antigos.

Para recuperação, revisar o snapshot e restaurar os nomes dos vínculos somente
após verificar que não houve novas fotos. Não sobrepor atualizações posteriores.
Restaurar os nomes antigos também restaura a duplicidade original.

Validação local: 561 exemplos sem falhas e RuboCop sem infrações nos oito arquivos
Ruby alterados/adicionados. Mudança somente de backend. A simulação em produção
não aplica o reparo nem executa migrations.

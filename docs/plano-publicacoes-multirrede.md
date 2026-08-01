# Plano: Publicacoes multirrede agendadas

## Objetivo

Adicionar ao ViperChat um modulo de publicacoes sociais, independente das
conversas e das mensagens agendadas. O primeiro provedor sera o Instagram,
mas a estrutura deve permitir incluir outras redes sem refazer agenda,
biblioteca, processamento de midia ou permissões.

## Navegacao

Adicionar **Publicacoes** como item proprio na sidebar, ao lado de
**Agendamentos**:

```text
Conversas
Agendamentos  -> mensagens de conversa ja existentes
Publicacoes   -> conteudo social publico e agendado
```

`ScheduledMessage` permanece exclusivo para mensagens de WhatsApp. Ele exige
conversa, contato, agente e regras de entrega que nao devem ser aplicadas a
posts publicos.

## Permissoes

- Administradores da conta podem visualizar, criar, editar, cancelar,
  reagendar, publicar e consultar a biblioteca de publicacoes.
- Usuarios nao administradores nao recebem acesso por padrao.
- O acesso desses usuarios depende de uma permissao personalizada explicita,
  por exemplo `social_publications`.
- A permissao deve cobrir leitura e operacao do modulo. Se surgir necessidade
  real de separar funcoes, ela pode evoluir para `view`, `manage` e `publish`;
  o MVP nao deve antecipar essa fragmentacao.
- A verificacao deve existir no backend e na sidebar/rotas do frontend. Esconder
  o item de menu nao substitui a autorizacao da API.

## Dominio proposto

```text
SocialPublication
|- account
|- created_by
|- caption
|- scheduled_at e timezone
|- recurrence_rule
|- status
|- medias
`- targets

SocialPublicationTarget
|- provider: instagram, facebook, linkedin, ...
|- social_account conectado
|- format: feed, story, reel, carousel
|- status, erro e tentativas
|- provider_container_id
`- provider_media_id, permalink e published_at

SocialPublicationMedia
|- arquivo original
|- arquivo derivado/normalizado para o destino
|- preview/thumbnail
|- posicao
`- dimensoes, tamanho, MIME, duracao e demais metadados
```

Estados principais:

```text
rascunho -> agendado -> processando -> publicando -> publicado
                              |              |
                              `------------> falhou -> reagendado ou cancelado
```

Cada destino tem seu proprio estado. Uma mesma publicacao pode, no futuro,
ser enviada a mais de uma rede e falhar apenas em uma delas.

## Agendamento e recorrencia

Reaproveitar do agendamento atual o uso de timezone da conta, fila
`scheduled_jobs`, execucao por minuto, locks e exibicao operacional.

Uma publicacao deve poder ser:

- unica;
- diaria;
- a cada N dias, por exemplo, a cada 3 dias;
- semanal em dias escolhidos;
- mensal em um dia escolhido;
- limitada por data final ou numero de ocorrencias;
- pausada, retomada, cancelada ou editada somente para as proximas ocorrencias.

Uma recorrencia nao deve sobrescrever seu proprio historico: cada ocorrencia
gera uma entrega publicavel e auditavel, com resultado individual.

## Experiencia da tela Publicacoes

Tres visoes no mesmo modulo:

1. **Calendario**: dia, semana e mes; filtros por conta social, rede, status e
   responsavel.
2. **Fila**: rascunhos, proximas publicacoes, recorrencias, publicacoes em
   processamento e falhas que pedem acao.
3. **Biblioteca**: galeria de midias e publicacoes realizadas, com preview,
   rede, conta, data, legenda, responsavel, status e link/permalink quando a
   rede o disponibilizar.

O compositor deve permitir escolher destinos, formato por destino, legenda,
midias, data/hora/timezone e recorrencia. Deve oferecer as acoes de salvar
rascunho, publicar agora e agendar.

## Midia, resize e preview

No upload, inspecionar MIME, dimensoes, proporcao, tamanho, duracao e codec
quando houver video. Para cada destino, informar claramente:

- **Compativel**;
- **Compativel com ajuste**, explicando crop ou resize;
- **Incompativel**, explicando a restricao.

Quando possivel, oferecer resize preservando proporcao, crop visual com area
segura, otimizacao e preview no formato de destino. O original nunca deve ser
alterado: a publicacao usa uma versao derivada associada ao destino.

O MVP deve cobrir imagens estaticas. Video, Reels e Stories em video entram
depois, pois requerem validacao de codec, duracao, audio e processamento
assincrono adicional.

## Providers

Cada rede deve implementar um contrato isolado, por exemplo:

```text
SocialPublishing::Providers::Instagram
SocialPublishing::Providers::Facebook
SocialPublishing::Providers::Linkedin
```

O provider declara formatos aceitos, requisitos de midia, cria o conteiner ou
upload remoto, consulta o processamento e confirma a publicacao. Calendario,
recorrencia, permissao, biblioteca e status permanecem comuns.

## MVP Instagram

Primeira entrega:

- Feed do Instagram com uma imagem;
- Story do Instagram com uma imagem;
- rascunho, publicacao imediata e agendada;
- recorrencia;
- preview/resize de imagem;
- galeria e permalink do resultado;
- erro detalhado da Meta, retry e reagendamento.

O OAuth da integracao Instagram precisara incluir o escopo de publicacao e a
Meta devera aprovar o uso em producao. A integracao atual, voltada a DMs, nao
e suficiente para publicar conteudo.

## Fases de implementacao

1. Base de dados, autorizacao personalizada, APIs, rota e item Publicacoes na
   sidebar.
2. Tela operacional: calendario, fila, rascunhos, edicao, cancelamento e
   historico.
3. Upload, inspecao de imagem, preview e geracao de derivadas.
4. Provider Instagram para Feed e Story de imagem.
5. Recorrencia e entrega individual por ocorrencia.
6. Carrosseis, video/Reels e Facebook; depois as demais redes conforme suas
   APIs permitirem.
7. App Review da Meta, limites, telemetria, alertas e validacao ponta a ponta
   em ambiente real.

## Decisao registrada

O modelo deve nascer capaz de ter varios destinos por publicacao, mas o MVP
habilita somente Instagram. Isso evita retrabalho quando Facebook, LinkedIn ou
outras redes forem adicionados, sem ampliar a interface inicial alem do
necessario.

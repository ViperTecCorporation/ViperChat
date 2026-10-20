# Plano de caixa unificada: Meta oficial + ViperConnect

## 1. Situação, objetivo e autorização

- Documento de planejamento: 15/10/2026, fuso America/Cuiaba.
- Atualização em 17/10/2026: após a imagem inicial implantada manualmente pelo administrador, as correções `a9eec45e0` foram aplicadas via hostpath no Docker por SSH, com autorização explícita posterior à negativa do Portainer, backup prévio e verificações pós-aplicação (seção 24). IDs, arquivos verificados e vínculo preservados. O arquivo da stack no Portainer ainda exige reconciliação antes de uma futura reimplantação pelo painel.
- Atualização em 16/10/2026: vínculo, ingestão única, BSUID-first, reconciliação de mídias e revisão administrativa implementados e validados em dev (seções 17–19). Interface disponível para aceite manual; não confundir esse avanço com release publicada, aceite nativo completo ou implantação na VPS. Aplicação dessas alterações na VPS continua adiada.
- Atualização em 15/10/2026: P1 implementada e validada em dev; P2 aplicada via hostpath na VPS após autorização explícita do usuário. Evidências e limites estão na seção 5.4.
- ViperConnect: commit `b1668845` (`feat(webhooks): expose original provider message identity`), branch `mobile-primary`. IDs públicos atuais e referências operacionais preservados; Typebot não recebe o novo campo.
- Primeiro incremento P4 validado em dev e aplicado como piloto via hostpath na VPS, com backup prévio e validação de eventos reais (seções 6.0 e 6.0.1): persistência aditiva da identidade do transporte e seus vínculos. Incremento seguinte validado em dev e aplicado na VPS: adaptador automático Meta e consulta de correlação em modo observação (seções 6.1.1 e 6.1.2); aceite com eventos reais/horário de pico ainda pendente. Resolução de pessoas, ativação de vínculo entre caixas e unificação continuam pendentes.
- P3 continua pendente: nenhuma nova imagem/release foi publicada. O hostpath é um piloto temporário, não uma atualização definitiva da imagem.
- A data prevista originalmente não cria execução automática ou agendamento. Novos deploys, migrações em produção, reprocessamentos e envios de teste pelo agente exigem autorização correspondente.

Objetivo: apresentar um único atendimento para um número WhatsApp conectado simultaneamente pela Meta oficial e pela ViperConnect. Preservar histórico e vínculos existentes, escolher explicitamente o transporte de envio e correlacionar mensagens equivalentes sem duplicar bolhas, automações, notificações ou cobranças estimadas.

## 2. Decisões consolidadas

| Tema | Decisão |
| --- | --- |
| Caixa principal | Escolhida pelo administrador: pode ser Meta ou ViperConnect. |
| Caixa parceira | O outro transporte do mesmo número empresarial, na mesma conta. |
| Instalação atual | Candidata a manter ViperConnect como principal devido ao histórico; não é regra fixa do produto. |
| Histórico e operação | A principal organiza conversas, responsável, equipe, status, etiquetas, SLA e automações. |
| Transporte padrão | Configuração independente da escolha da principal. |
| Envio | Uma mensagem é enviada por um único transporte efetivo. A seleção do editor é a preferência; recurso incompatível pode ser roteado previamente ao parceiro compatível, sem alterar essa seleção. |
| Ações sobre mensagens | Resolver o transporte pela capacidade da operação e pelo vínculo da mensagem, independentemente da seleção do editor para novos envios. |
| IDs existentes | UUID da ViperConnect, `wamid` da Meta e ID interno do ViperChat continuam preservados. |
| ID original | Novo metadado de correlação; não substitui IDs públicos nem IDs de citação. |
| Deduplicação | Associação determinística; nunca apenas por conteúdo, nome de arquivo ou horário. |
| Falha de envio | Roteamento prévio por incompatibilidade comprovada não é retry: erro, timeout ou resultado incerto não autorizam reenviar automaticamente pelo parceiro. |
| Histórico anterior | Preservado; sem fusão retroativa automática e sem exclusão em massa. |
| Custos | Estimativa separada da fatura, com regras versionadas e tarifas verificáveis. |
| Arquitetura atual | Manter os canais Meta direto e ViperConnect, vinculados no ViperChat; não migrar agora a integração oficial para a ViperConnect. |
| Gateway futuro | Preparar fronteiras e contratos reutilizáveis, sem implementar gateway completo nem transferir o Embedded Signup nesta entrega. |

### 2.1. Caixa principal nos dois sentidos

Os dois cenários são obrigatórios:

1. ViperConnect principal + Meta parceira.
2. Meta principal + ViperConnect parceira.

O código não pode inferir a principal pelo provedor, pela ordem dos IDs ou por qual webhook chegou primeiro. Uma caixa parceira não pode integrar dois vínculos simultâneos. Trocar a principal depois da ativação exige procedimento próprio, prévia do impacto e reconciliação das conversas; não será um simples toggle na primeira versão.

### 2.2. Separação de responsabilidades para uma evolução futura

Decisão confirmada pelo usuário: seguir o plano de duas caixas técnicas vinculadas no ViperChat, aproveitando a integração Meta que já existe. Não transportar agora toda a lógica oficial, templates, Embedded Signup ou gestão de credenciais para a ViperConnect. O gateway unificado é uma possibilidade futura, não requisito para entregar o atendimento único.

Preparar três fronteiras explícitas na implementação, reutilizando serviços existentes e extraindo interfaces somente nos pontos necessários:

| Camada | Responsabilidade nesta entrega | O que deve permanecer independente |
| --- | --- | --- |
| Atendimento ViperChat | Contato canônico, histórico, conversas, equipe, responsável, permissões, editor, preferência do agente, efeitos únicos e anexo canônico | Não depender de a Meta ser acessada diretamente ou por um gateway futuro |
| Adaptadores de transporte | Envio, recebimento, templates, ações, capacidades e IDs operacionais específicos da Meta/ViperConnect; integração oficial permanece no adaptador Meta atual | Não decidir propriedade do histórico nem recriar regras de fila/contato por provedor |
| Contrato de eventos e operações | Identidade interna e externa, correlação, origem, preferência versus transporte efetivo, status, referências, erros, metadados de cobrança e idempotência | Não usar URL, token, caixa principal ou formato de ID de um único provedor como contrato universal |

Requisitos de preparação:

1. O frontend solicita uma operação com mensagem/contato internos, preferência de transporte e contexto. Não conhece credenciais nem resolve UUID/`wamid` ou endpoints de provider.
2. O resolvedor de capacidades decide o transporte efetivo conforme a seção 9; o adaptador correspondente traduz a operação e resolve seus aliases. Não espalhar condicionais de provider por editores, bolhas e regras de atendimento.
3. Eventos preservam canal de origem, transporte real e identificadores completos. Um gateway futuro não deve apagar a distinção entre envio oficial Meta e envio ViperConnect, necessária para ações, auditoria e custos.
4. Manter `id` público atual, `provider_message_id` aditivo e aliases por transporte como conceitos separados. O endereço do futuro gateway não pode exigir mudança dos IDs internos, públicos ou de citação já persistidos.
5. Normalizar apenas o envelope necessário e preservar metadados específicos úteis, com versão/origem do contrato e extensões definidas. Não perder status, categoria de cobrança, erros, conteúdo de templates ou referências por reduzir tudo a texto genérico.
6. Manter resolução de contatos, deduplicação de mensagem/mídia e contabilização de eventos como componentes com fronteiras claras. Nesta entrega o ViperChat continua responsável pela consolidação; uma mudança futura de proprietário dessas funções exigirá desenho específico para não processá-las duas vezes.
7. Contratos de teste devem validar a operação de domínio e a tradução de cada adaptador separadamente. Fixtures de Meta e ViperConnect passam pelo mesmo núcleo de atendimento sem depender de registro Coex real em dev.
8. Não criar um framework genérico de providers, uma segunda implementação Meta nem um sistema novo de credenciais apenas para antecipar o gateway. Implementar a separação mínima usada pelos fluxos reais deste plano.

### 2.3. O que fica fora do escopo atual e como avaliar o gateway depois

Uma futura ViperConnect como gateway Meta + WhatsApp/Zapo exigirá aprovação de outro plano, incluindo: Embedded Signup e reautorização; armazenamento seguro/isolado de credenciais; assinatura e roteamento de callbacks; templates e suas atualizações; eventos de status/cobrança; capacidades; disponibilidade, filas e recuperação; proteção contra logs de segredos; e migração de instalações com Meta direto.

Não reutilizar sem revisão o fluxo atual de coexistência da ViperConnect: seleção implícita por janela, renovação local de janela por envio e fallback para Web após falha Meta devem ser confrontados com as regras explícitas deste documento. Nenhum resultado incerto pode produzir envio pelo segundo transporte automaticamente.

Para eventual migração futura, exigir prova de equivalência do contrato, reaproveitamento de IDs/aliases e histórico existentes, corte de callbacks sem dupla ingestão/envio, piloto e rollback próprios. A caixa Meta direta deve continuar sendo opção para instalações que não precisem do gateway; não forçar migração de todas as instalações nem reabrir registro Coex como pré-requisito.

O primeiro passo permanece igual nas duas arquiteturas: `provider_message_id` no webhook da ViperConnect, sem alterar IDs atuais. A preparação descrita aqui não muda os gates dev -> aceite -> hostpath na VPS -> release e não autoriza implementar ou publicar o gateway.

## 3. Evidências levantadas e limites

As inspeções anteriores da VPS foram somente leitura. Estes dados são evidência histórica e devem ser reconferidos antes do piloto:

- Caixa ViperConnect `1`, canal `1`, número configurado `+5566996222471`.
- Caixa oficial `65`, canal `43`, número configurado `+556696222471`.
- Ambas pertenciam à conta `1`; a diferença do nono dígito não autoriza vincular automaticamente.
- Os contatos internos analisados tinham identificadores próprios de cada canal associados ao mesmo contato.
- A assinatura Meta inicialmente não incluía `smb_message_echoes`. Depois da ativação pelo usuário, o echo foi recebido e persistido na caixa oficial.
- Foram comparados cinco pares de mensagens. O ID original consultado no Redis da ViperConnect estava presente na representação decodificada do `wamid` equivalente da Meta.
- Foram examinados quatro payloads completos da ViperConnect, incluindo texto e imagem, tanto nos parâmetros HTTP recebidos quanto nos argumentos enfileirados no ViperChat. O ID original não apareceu nesses payloads.

| Mensagem Meta | Mensagem ViperConnect | Resultado da comparação do ID original |
| --- | --- | --- |
| `2480758` | `2480756` | Coincidiu |
| `2480767` | `2480768` | Coincidiu, apesar de representação de conteúdo diferente |
| `2480803` | `2480804` | Coincidiu |
| `2480807` | `2480806` | Coincidiu; par com mídia |
| `2480825` | `2480823` | Coincidiu |

Exemplo confirmado:

```text
Mensagem interna Meta:         2480825
Mensagem interna ViperConnect: 2480823
UUID ViperConnect:             05b35fe0-c84b-11f1-9efc-8bd540ee880d
ID original WhatsApp:          A5E5870B16922B5CA6CA6B6A71721286
```

Isso comprova a correlação nessa amostra, não um contrato universal de decodificação de `wamid`. Não presumir cobertura de todos os dispositivos, tipos de mídia, referências ou futuras versões da Meta.

### 3.1. Nova evidência: contato duplicado por BSUID Meta

Na revisão somente leitura de 15/10/2026, o BSUID `BR.2339818310092335` estava associado ao contato `107078`, criado na caixa Meta `65` em 15/10/2026 às 12:20:16 UTC, sem telefone e com o próprio identificador como nome. Já existia o contato `94129`, criado em agosto, com telefone e LID na ViperConnect `1`. Posteriormente o contato Meta recebeu um alias telefônico sem o nono dígito, mas permaneceu separado e sem telefone no cadastro consultado.

Comprovação de equivalência de mensagem, sem depender de nome/texto/horário:

| Meta | ViperConnect | ID original confirmado |
| --- | --- | --- |
| Mensagem `2481329`, contato `107078`, conversa `41348` | Mensagem `2481328`, contato `94129`, conversa `37692` | `3EB05ABCC1AAB1AEEC52E5` |

O original foi obtido do mapa Redis da ViperConnect e conferido na representação decodificada do `wamid` Meta. O conteúdo armazenado diferia entre as duas mensagens. Esta é evidência de que a associação de mensagens deve funcionar mesmo quando os contatos internos já tenham sido criados separadamente.

Na mesma consulta havia 26 contatos da caixa Meta com BSUID `BR.*` e sem telefone; isso não comprova 26 duplicações. Contatos legitimamente sem telefone não devem ser mesclados nem tratados como erro apenas por essa condição.

O payload e eventual warning de lookup do evento inicial não foram encontrados nos intervalos de logs consultados. Não está comprovado se a Meta deixou de fornecer telefone, se a consulta falhou ou se houve outra condição naquele instante. O runtime consultado usa busca de aliases na própria caixa, lookup opcional no echo e criação por atributos disponíveis; a limitação de resolução de identidade deve ser investigada e testada, não atribuída a uma resposta específica da Meta sem evidência.

### 3.2. Recuperação pontual autorizada e executada em 15/10/2026

Após prévia dos candidatos e autorização explícita do usuário para fazer backup e preservar os antigos, foram mesclados somente os dez pares abaixo, usando a ação de merge do ViperChat, com verificações dentro de uma transação e conferência independente posterior:

```text
Duplicado Meta -> contato antigo preservado
107069 -> 89
107075 -> 3427
107078 -> 94129
107081 -> 3431
107083 -> 17449
107087 -> 70322
107098 -> 72
107109 -> 75
107114 -> 283
107121 -> 107120
```

Nos dez pares foi confirmada a equivalência de pelo menos uma mensagem por ID original WhatsApp, além do candidato telefônico com/sem nono dígito. O lote não incluiu os outros contatos sem prova de duplicação.

Backup restrito na VPS: `/root/viperchat-contact-merge-20261015-oGEE3FHj/`, com diretório privado e arquivos acessíveis apenas ao proprietário. Contém `before-merge.json.gz` (snapshot dos registros envolvidos), `schema.sql.gz` (schema do banco) e `verification.json` (resultado pós-operação). O snapshot é específico do lote, não um backup integral da base nem uma cópia dos arquivos binários S3. Gzip, leitura do JSON e hash foram conferidos; uma restauração completa não foi executada. Dados privados do backup não foram copiados para este repositório.

SHA-256 do snapshot: `e3085cfa5c7dbf3d1903ddaad750eaf70ea9897bea135f999f0776ec5136217b`.

Resultado verificado: os dez IDs antigos, nomes, telefones, LIDs/BSUIDs legados e datas de criação foram preservados; os dez cadastros duplicados foram removidos. Os aliases Meta, inclusive `BR.2339818310092335`, agora apontam para os contatos antigos. Permaneceram os 73 vínculos de caixa, 31 conversas e 106 mensagens examinados, além dos 18 anexos e 73 associações/blobs Active Storage conferidos. A etiqueta, o agendamento e as duas avaliações existentes no conjunto também permaneceram. Não foi executado download/upload, purge de mídia ou envio de mensagem; a cópia intermediária do snapshot no container foi removida após a validação, mantendo o backup privado no host.

Rollback, se necessário, exige revisão e restauração seletiva dos registros originais, preservando eventos que chegaram depois da mesclagem. Não restaurar toda a base nem reaplicar o snapshot por cima de atividade posterior indiscriminadamente. A operação não uniu caixas, não fundiu conversas e não eliminou mensagens equivalentes dos dois transportes.

Esta correção de dados **não implementou a prevenção no código**. As seções 6.2 e 6.3 continuam obrigatórias para tratar novos eventos e evitar recorrência.

## 4. Primeira entrega — ViperConnect: ID original no webhook

### 4.1. Contrato aditivo

Acrescentar `provider_message_id` no objeto da mensagem. O campo `id` permanece exatamente como hoje.

```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "changes": [
        {
          "field": "messages",
          "value": {
            "messages": [
              {
                "id": "05b35fe0-c84b-11f1-9efc-8bd540ee880d",
                "provider_message_id": "A5E5870B16922B5CA6CA6B6A71721286",
                "from": "5566996269251",
                "type": "text",
                "text": { "body": "Exemplo de mensagem" }
              }
            ]
          }
        }
      ]
    }
  ]
}
```

Exemplo reduzido, não uma requisição de teste nem alteração do restante do envelope atual.

Regras:

1. `id` continua sendo o ID público usado por clientes ViperConnect.
2. `provider_message_id` contém o identificador real do transporte subjacente, obtido da mensagem ou da resposta de envio. É uma string opaca e sensível a alterações; não truncar nem normalizar arbitrariamente.
3. Capturar o identificador antes da substituição por UUID e carregá-lo até a publicação do webhook, inclusive pelas filas.
4. Ausência legítima: omitir o campo. Não inventar valor, copiar o UUID ou consultar indefinidamente um cache inexistente.
5. Manter compatibilidade com eventos já enfileirados e consumidores antigos, sem exigir a nova propriedade.
6. A nomenclatura é genérica: no Zapo/WhatsApp o valor observado é o ID de protocolo; em outro provedor pode ter outra representação. Registrar a origem e não presumir que todo valor de qualquer engine seja diretamente comparável.
7. Não alterar status, regras de envio, IDs das APIs, formatos atuais de mídia ou filtros de webhooks nesta primeira entrega.

### 4.2. Cobertura do contrato

| Local | Campo adicional proposto | Significado |
| --- | --- | --- |
| `messages[]` | `provider_message_id` | ID original da mensagem recebida |
| `message_echoes[]` | `provider_message_id` | ID original da mensagem enviada/espelhada |
| `statuses[]` | `provider_message_id` | ID original da mensagem cujo status mudou |
| `context` de uma resposta citada | `provider_message_id` | ID original da mensagem citada; `context.id` atual fica intacto |
| Objeto de reação | `provider_message_id` | ID original da mensagem alvo; referência atual fica intacta |
| Objeto de edição/exclusão | `provider_message_id` no objeto alvo normalizado | ID original da mensagem alvo; não confundir ID do evento com o do alvo |

Para edição/exclusão, congelar o caminho exato após inventariar o contrato atual de cada formato, sem reorganizar o payload existente. Separar sempre o ID próprio do evento do ID da mensagem afetada. A documentação e os testes deverão mostrar ambos quando existirem.

No retorno do envio via API, avaliar expor o mesmo campo opcional em `messages[]` quando o provider já o tiver retornado. Isso permite correlacionar a bolha otimista antes do echo, sem alterar o `id` de resposta. Se a confirmação do provider for posterior, documentar essa condição e entregar o ID pelo webhook correspondente.

### 4.3. Pontos de implementação a revisar

No projeto `unoapi-cloud`:

- `src/services/listener_zapo.ts`: preservar `key.id` antes de normalizar para UUID.
- `src/services/message_id_map.ts`: reutilizar o mapeamento existente, sem trocar a identidade pública.
- `src/jobs/incoming.ts`: preservar o ID retornado pelo provider, echoes e statuses dos envios via API.
- Mapeadores WhatsApp/Cloud, referências e eventos de mídia: verificar se descartam propriedades extras.
- Transporte de filas e histórico de webhook: garantir reentrega do mesmo valor e leitura de eventos antigos.
- Adaptação por destinatário do webhook: assegurar que o campo continua presente no payload específico enviado ao Chatwoot/ViperChat.
- Atualizar documentação do contrato e exemplos OpenAPI/Postman existentes, se aplicáveis.

Não alterar IDs armazenados no Redis, seus TTLs ou a semântica de endpoints existentes para implementar este recurso.

### 4.4. Aceite da primeira entrega

- [x] Mesmo evento conserva o `id` atual e acrescenta apenas metadados previstos.
- [x] Texto, imagem, áudio, vídeo, documento e contato preservam o ID original quando disponível (testes dev; subconjunto real na seção 5.4).
- [x] Mensagem enviada por API, recebida, echo e status têm cobertura própria.
- [x] Citação e eventos sobre outra mensagem preservam seus IDs de referência atuais nos testes dev.
- [x] Payloads sem o campo continuam compatíveis; ausência de identidade não inventa valor.
- [x] Repetições são cobertas pela deduplicação existente, sem novo envio por falha na consulta opcional da referência.
- [ ] Ampliar a comprovação real de concorrência, reinício durante envio e eventos fora de ordem; não considerar a amostra da seção 5.4 prova de todos esses cenários.
- [x] Falta do mapeamento não interrompe a entrega atual.
- [x] ViperChat atual recebe o payload com o campo adicional e mantém seus IDs legados; ainda não o persiste como identidade própria.
- [x] Build, lint dos arquivos de produção alterados e testes focados aprovados em dev. Suíte completa: 3.253 passaram, 12 ignorados. O arquivo de teste `__tests__/services/outgoing_cloud_api.ts` mantém cinco erros de lint preexistentes, conferidos também no HEAD anterior; não declarar lint global limpo.
- [x] Campo removido apenas da cópia destinada a webhook marcado Typebot, inclusive contexto, reação e status; demais destinatários mantêm o campo.
- [x] Usuário aprovou código/evidências em dev e autorizou o piloto na VPS.

## 5. Validação real via hostpath na VPS

### 5.1. Motivo e fronteira de validação

O dev usa outro subdomínio e não reproduz o registro/coexistência real da instalação. Não mudar callbacks, registrar novamente o número ou mover a coexistência para o dev como atalho.

Em dev, testar geração do contrato com fixtures anonimizadas, respostas simuladas e consumidores compatíveis. Só classificar o fluxo como validado ponta a ponta depois de receber os eventos reais na VPS e verificar a persistência esperada.

### 5.2. Preparação do piloto — executar somente depois da aprovação

1. Revalidar host, containers, imagem/tag/digest, comando de inicialização, processos consumidores, caminhos compilados e versão do runtime/dependências.
2. Identificar quais serviços executam o código alterado: entrada web, worker de envio, worker Zapo e/ou broker. Não aplicar apenas ao servidor HTTP se outro processo monta o webhook.
3. Apresentar os serviços afetados, a eventual interrupção necessária, a janela de teste e o procedimento de rollback. Não prometer troca sem restart em um processo que não recarrega o código.
4. Registrar compose/configuração anterior e artefato original. Conferir recuperação dos dados antes de futuras migrações. Não copiar credenciais para o pacote de teste.
5. Compilar no dev um artefato compatível com a imagem base da VPS, preservando layout, sourcemaps necessários e dependências. Se houver divergência de versão ou dependências, interromper e ajustar o pacote antes do mount.
6. Criar diretório de hostpath exclusivo e versionado, com manifesto de arquivos, hashes e commit de origem. Montar somente os arquivos/diretórios necessários, preferencialmente read-only; não sobrepor cegamente `/app`, `node_modules`, dados ou segredos.
7. Validar o compose/overlay antes de recriar apenas os serviços autorizados. Preservar volumes, sessões WhatsApp, filas e rede.
8. Não iniciar consumidores paralelos apontando às mesmas filas como forma de teste. Conferir que jobs já pendentes continuam compatíveis e que todos os executores relevantes usam a versão esperada.

O hostpath é piloto controlado, não publicação definitiva. Não executar comandos de deploy deste documento sem revalidar os nomes e caminhos reais e obter a aprovação correspondente.

### 5.3. Testes reais da primeira entrega

Com números de teste combinados com o usuário:

- Entrada do cliente, envio pelo celular, envio ViperConnect por API e envio pela Meta.
- Texto, mídia, resposta citada e atualizações de entrega/leitura; ampliar para edição/exclusão conforme capacidades.
- Comparar payload efetivamente recebido no ViperChat: UUID inalterado e novo `provider_message_id` presente.
- Comparar o ID com o original do transporte e com a mensagem Meta equivalente, quando houver.
- Confirmar que o ViperChat atual segue exibindo e enviando normalmente, mesmo sem aproveitar o campo novo.
- Verificar erros, retries, filas, latência e ausência de envios duplicados.
- Não criar callbacks de inspeção externos nem registrar conteúdo integral, tokens ou links assinados desnecessários. Evidências devem ser resumidas/anonimizadas.

Critério de parada: duplicidade de envio, perda de eventos, falha de sessão, aumento de erros/retries ou incompatibilidade de contrato. Remover o overlay/restaurar o artefato e recriar somente os serviços afetados, sem limpar Redis, filas ou dados.

Após aprovação: produzir release por imagem versionada, substituir o hostpath e confirmar o runtime definitivo. Remover os intermediários descartáveis após verificar que não são a única cópia necessária de rollback; preservar apenas entregáveis/evidências necessários.

### 5.4. Piloto executado e validação real — 15/10/2026

**Escopo executado:** somente o contrato aditivo P1 na ViperConnect. Aplicação autorizada após validação em dev; testes de mensagens enviados pelo usuário. O agente não disparou mensagens nem reprocessou eventos e não executou escritas manuais no banco.

- Imagem preservada: `ghcr.io/viperteccorporation/viperconnect:4.0.37`; Node da VPS `24.21.0`, Zapo `1.10.0`.
- Serviços recriados: `unoapi`, `unoapi-broker`, `unoapi-video-worker` e `unoapi-worker-zapo`. Nenhuma chamada ativa na verificação imediatamente anterior à aplicação.
- Antes do piloto, os quatro serviços estavam sem mounts e os arquivos originais conferiam com o backup. O módulo existente `message_id_map.js` tinha o mesmo hash do dev. A comparação dos compilados confirmou somente o delta P1 esperado, sem trocar dependências.
- Quatro arquivos montados por serviço, todos read-only: `dist/src/jobs/incoming.js`, `dist/src/services/listener_zapo.js`, `dist/src/services/outgoing_cloud_api.js` e o novo `dist/src/services/messages/provider_message_identity.js`, sob `/home/u/app/`.
- Hashes verificados nos quatro serviços, mesma imagem/digest anterior, processos ativos, sem reinícios inesperados no intervalo inspecionado, sem erros de carregamento de módulo/sintaxe e `/ping` respondendo HTTP 200.
- Sessões e credenciais existentes preservadas. Não houve mudança de callbacks, novo registro de coexistência, limpeza de Redis/filas ou migração de banco.

**Comprovação:** o campo foi lido dos parâmetros HTTP efetivamente recebidos pelo ViperChat. Os UUIDs persistidos na caixa ViperConnect `1` foram comparados com os `source_id` completos da caixa Meta `65`, por consultas PostgreSQL somente leitura. O ID original recebido no webhook coincidiu com o identificador encontrado na representação decodificada do `wamid` correspondente. Não foi deduzido do Redis, de texto ou de horário.

| Caso real | Mensagem ViperConnect no ViperChat | Mensagem Meta no ViperChat | `provider_message_id` recebido e correspondente |
| --- | --- | --- | --- |
| Texto recebido | `2484296` | `2484295` | `3AB89628240F57AC2494` |
| Echo de texto enviado pela API | `2484297` | `2484300` | `3EB050A9FF01A65604D6AE` |
| Imagem recebida | `2484303` | `2484301` | `3A2297B3132107520D5C` |
| Áudio recebido | `2484310` | `2484305` | `3A773877A9B421BAEB41` |
| Texto recebido | `2484311` | `2484304` | `3AC70D0FFABFDEC758B3` |
| Figurinha recebida | `2484307` | `2484308` | `3A86A3AC7C1C7BCE3881` |

Os seis pares coincidiram. Houve também um sétimo registro, `statuses[].status = read`, com o mesmo UUID e ID original do envio `2484297`. Exemplo: a figurinha manteve o UUID público `14a1a6b1-c8ff-11f1-8b89-01afaf97c044`; o campo adicional trouxe `3A86A3AC7C1C7BCE3881`, sem substituir seu `source_id`, o `wamid` ou o ID de mídia.

**Limites do aceite:** vídeo, documento, contato, citações, reações, edição e exclusão têm testes dev conforme o contrato, mas não foram todos exercitados nesse teste real de coexistência. Typebot teve regressão automatizada e validação do compilado dev; não foi enviada mensagem real a bot para testar. A extração interna do `wamid` continua sendo evidência desta amostra, não contrato público da Meta: o adaptador da seção 6.1 ainda exige validação própria e rejeição de casos ambíguos. Não houve unificação nem deduplicação de mídia nesta etapa.

**Recuperação preservada na VPS:**

- Diretório: `/var/snap/docker/common/viperconnect-hotpatch/provider-message-id-20261015-p1/`.
- `private/base.yml`: configuração anterior, com acesso restrito; não copiar segredos para este plano/repositório.
- `private/override.yml`, `private/manifest.json` e `private/original/`: mounts, hashes e compilados originais.
- `private/validation.json`, `private/package.tgz` e `private/pilot.py`: evidências resumidas e pacote do piloto.
- Rollback: executar `rollback.sh` desse diretório em uma janela autorizada; restaura os serviços pela configuração anterior, sem mounts, sem apagar dados ou desfazer mensagens.

O hostpath permanece aplicado. Um redeploy pelo compose original/Portainer pode removê-lo; inversamente, manter o overlay ao atualizar a imagem pode sombrear código novo. Na P3, reconciliar explicitamente os mounts e verificar o runtime definitivo. As cópias locais temporárias de transferência foram removidas; backup e entregáveis necessários de recuperação permanecem na VPS.

## 6. Segunda entrega — ViperChat persiste IDs sem unificar ainda

**Próxima etapa acordada após registrar P1/P2:** começar em dev pela persistência aditiva do ID recebido, sua origem/escopo e vínculo à mensagem existente. Manter o modo observação; não aproveitar este aceite para ativar fusão, mudar roteamento ou migrar o histórico em produção. Publicação definitiva da ViperConnect (P3) e deploy/migração do ViperChat permanecem etapas separadas e autorizadas.

Criar estrutura de identidades de transporte relacionada à mensagem interna. Nomes finais de tabelas/classes serão definidos na implementação; os conceitos e garantias são obrigatórios:

- ID interno da mensagem ViperChat.
- Conta, vínculo das caixas, caixa/canal técnico e provedor.
- ID externo completo daquele transporte: UUID ou `wamid`.
- ID original/canônico e versão do adaptador que o interpretou, quando reconhecido.
- Participantes, direção e número empresarial, sem usar nome de contato como chave.
- Dados de status por transporte e horários originais dos eventos.

Preservar `source_id` e as APIs legadas. Uma mensagem unificada pode possuir vários IDs externos; um campo único não representa todos eles.

Primeiro operar em modo observação: armazenar IDs novos, calcular correspondências e registrar conflitos, sem unir conversas, esconder bolhas ou mudar o envio.

### 6.0. Persistência inicial e validação em dev

**Escopo entregue neste incremento:** guardar os IDs efetivamente recebidos e vinculá-los às mensagens existentes. Não calcular correspondências entre caixas ainda; não confundir esta entrega com todo o gate P4.

- `whatsapp_message_identities`: conta, caixa, canal, provedor, `external_id` público completo, `provider_message_id` opcional e observações JSONB. Índice único por caixa/provedor/ID externo; IDs permanecem strings opacas, sem normalização arbitrária.
- `whatsapp_message_identity_links`: vínculo com uma ou mais mensagens internas. Isso preserva os envios legados de múltiplos contatos que geram várias bolhas com o mesmo `source_id`, sem reduzir suas associações a uma única mensagem.
- Observações restritas a origem `webhook`, versão do contrato, número empresarial, identificadores dos participantes, direção, tipo/evento, horários de origem, status e IDs de contexto/reação/revogação. Não armazenar corpo de mensagem, arquivo, URL de mídia, token ou payload integral nesse registro.
- Entrada UnoAPI e Meta oficial passam pelo observador antes da ingestão existente. Status antecipado pode ficar persistido sem bolha; criação posterior da mensagem ou atribuição de `source_id` após envio pela API vincula o registro pendente. Não reproduzir status, enviar mensagens ou reabrir atendimentos a partir da observação.
- Echo e atualização de status reaproveitam o vínculo por escopo e ID público, sem criar mensagens. A direção acompanha o resolvedor existente também nos echoes que usam `messages[]`, além de `message_echoes[]`.
- Repetições usam restrições únicas e locks da identidade. Um original conflitante não substitui o valor conhecido: é registrado em `observations.conflicting_provider_message_ids` para revisão. Falta do campo em eventos Uno antigos não inventa um ID; pode completar um vínculo pendente já conhecido.
- Contexto/reação preservam o ID do alvo separadamente do ID do evento. Edição não renderizada fica como observação com contexto; não cadastrar seu ID de evento como alias operacional da mensagem editada.
- Nesse primeiro incremento, Meta guarda seu `wamid` completo como `external_id`, sem derivar `provider_message_id` da representação binária. A evolução do adaptador, posterior ao piloto na VPS, está na seção 6.1.1; nenhuma busca por texto/horário/substrings foi introduzida.
- `messages.source_id`, `external_source_ids`, mídias, APIs públicas, notificações, bots e regras de envio não foram substituídos. Não há nova tela, seletor, endpoint ou alteração nos bundles Web/Android/iOS neste incremento backend.

**Validação dev:** base isolada `viperchat_provider_identity_test`, distinta da réplica de desenvolvimento `chatwoot_db`. O ambiente do container contém `DATABASE_URL`; confirmar o nome efetivo na conexão, pois somente mudar `POSTGRES_DATABASE` não garante isolamento. A migração aditiva foi aplicada na réplica dev antes do piloto na VPS descrito abaixo.

- Script reproduzível: `script/validation/whatsapp_provider_identity.rb`; exige `RAILS_ENV=test` e o nome exato da base isolada, bloqueia HTTP real e utiliza factories/test adapter. Executar somente com a base de teste limpa e configurada: cria fixtures e testa reversão/reaplicação das duas tabelas novas nessa base, nunca na réplica em uso ou em produção.
- 36 verificações aprovadas: entrada/repetição, payload legado, status antecipado, `source_id` tardio, echo em ambos os formatos, referências, conflito, múltiplas bolhas por identidade, isolamento, concorrência, `wamid` intacto e migração reversível sem remover mensagens legadas.
- Regressão: 185 exemplos existentes aprovados, cobrindo `Message`, UnoAPI, warnings, visualização única e entrada Meta. RuboCop dos arquivos alterados aprovado. Avisos de depreciação existentes não foram tratados como parte desta mudança.

**Ordem de implantação:** executar a migração `20261016000000_create_whatsapp_message_identities` antes de carregar os novos callbacks nos processos web/worker. Para rollback de código, manter as tabelas/observações; não executar `down` em produção sem decidir como preservar os metadados coletados. A reversão da migração elimina somente as tabelas novas e seus vínculos, não mensagens legadas, mas perde as observações.

**Pendências após esse primeiro incremento P4:** adaptador Meta isolado/testado, consulta de candidatos/correspondências com escopo autorizado e diagnóstico de ambiguidades entre contatos distintos/BSUID-only. A entrega dev posterior do adaptador/consulta está na seção 6.1.1. Nenhuma associação entre pessoas/caixas está ativa neste incremento.

**Integração Git autorizada em 15/10/2026:** após a validação dev da seção 6.1.1, commitar e publicar persistência, correlação diagnóstica e plano na branch `feat/whatsapp-provider-message-identity`, integrando em seguida à `4.16.0`, com preservação dos commits. Remover a branch temporária somente depois de confirmar a integração e o push. A integração Git não altera IDs operacionais, não ativa a unificação das caixas nem autoriza novo deploy em produção.

### 6.0.1. Piloto de persistência na VPS — 15/10/2026

Aplicação autorizada pelo usuário, depois da validação dev, sem alterar IDs atuais nem unificar as caixas. Migração `20261016000000` aplicada antes da recriação do web e dos dois workers. Mantida a imagem `ghcr.io/viperteccorporation/chatwoot:v4.16.12-viper.31-ce`, com seis arquivos Ruby montados como somente leitura em cada processo. O hostpath da ViperConnect e o serviço de push existentes foram preservados. Não houve release de imagem, replay de webhooks ou backfill histórico.

**Backup e rollback:** diretório `/var/snap/docker/common/viperchat-hotpatch/provider-message-id-20261015-persistence/`. O arquivo protegido `private/database-before.dump` contém o backup lógico completo anterior à migração: 245.667.919 bytes, SHA-256 `08e61cd7c0f83eedd293f915323015b5b7db696a11413242b2315bace4093e29`. Checksum e catálogo `pg_restore --list` conferidos; restauração integral não foi ensaiada. Configuração, fontes anteriores, manifesto e evidências estão em `private/`. O `rollback.sh` restaura somente o código/configuração anterior, mantendo tabelas e observações novas; não executar `down` como rollback rotineiro.

**Preservação conferida após o piloto:** 1.000 mensagens antigas mantiveram `id`, `account_id`, `inbox_id`, `conversation_id` e `source_id`; as caixas 1 (UnoAPI) e 65 (Meta) mantiveram seus vínculos de canal. Nenhuma fusão de contatos, conversas ou mídias. A consulta dos vínculos novos encontrou zero divergências de conta, caixa ou ID externo.

**Eventos reais:** após o usuário enviar mensagens de teste e responder pelo ViperChat, foram encontrados sete pares persistidos nas duas caixas durante a janela de validação, incluindo texto de entrada/saída, figurinha, imagem e vídeo. Amostra reproduzível por IDs internos, sem guardar conteúdo:

| Mensagem UnoAPI | Mensagem Meta | `provider_message_id` recebido pela UnoAPI |
| --- | --- | --- |
| 2484365 | 2484367 | `3AAE262499CFA29A56A8` |
| 2484370 | 2484369 | `3AB68FDE53F3F972C59E` |
| 2484374 | 2484372 | `3A3883554A687C9AF8F6` |
| 2484376 | 2484375 | `CEF0C6016F0F3CCA9366` |
| 2484378 | 2484380 | `3EB0E87394970CF0F0B535` |
| 2484383 | 2484382 | `A5D5052B5ACDD7E57BE697FE979E894C` |
| 2484384 | 2484385 | `3EB05699E8130DBDF423EE` |

Os UUIDs da UnoAPI e os `wamid` da Meta continuam intactos como `messages.source_id` e `external_id`. A igualdade acima foi conferida por diagnóstico somente leitura da representação do `wamid`; não é um adaptador automático nem uma nova regra de roteamento. Na persistência Meta, `provider_message_id` continua nulo por projeto, até a etapa 6.1. Status antecipados também foram vinculados à mensagem existente; horários ausentes no webhook Uno permanecem nulos, sem inventar timestamps.

O web e os dois workers permaneceram em execução, com hashes dos arquivos conferidos, HTTP `/api` respondendo 200 e sem os erros de carregamento/FK pesquisados nos logs após a aplicação. Evidência operacional detalhada: `private/validation.json`. Isso valida a persistência inicial, não aprova automaticamente os recursos restantes de P4 ou a unificação.

### 6.1. Adaptador Meta

Isolar a interpretação do `wamid` em adaptador testado com os exemplos reais e casos inválidos. Não usar busca de substring como algoritmo de produção nem afirmar que o formato interno é contrato documentado da Meta. Se não houver extração inequívoca, não correlacionar automaticamente.

O piloto deve provar a correspondência para os tipos/dispositivos suportados. Se o formato não permitir correlação confiável, a unificação fica bloqueada para aquele caso até existir alternativa validada. Não recorrer a texto + horário como chave substituta.

### 6.1.1. Adaptador e consulta de correlação implementados em dev

Incremento desenvolvido e validado na mesma branch `feat/whatsapp-provider-message-identity`, depois integrado à `4.16.0` no commit `a97a695af`. A branch temporária local/remota e o worktree limpo foram removidos após confirmar o push e a preservação dos três commits na `4.16.0`. Durante a validação dev, a VPS ainda usava a seção 6.0.1; a aplicação posterior autorizada está registrada na seção 6.1.2. Não houve backfill ou ativação de unificação.

**Extração automática na ingestão:** `Whatsapp::MetaMessageIdAdapter`, versão `coexistence-envelope-v1`. Reconhece somente o envelope inteiro observado: marcadores fixos, comprimento explícito do participante, participante numérico, marcador de direção conhecido, comprimento explícito do original hexadecimal e terminador exato. Base64 estrito e canônico, com ou sem padding correto; tamanho limitado. Não procura substrings e não trata o formato interno como contrato público da Meta. Casos desconhecidos mantêm o `wamid` e seguem a ingestão normal, com diagnóstico `unrecognized`, sem inventar original.

O observador preenche `provider_message_id` somente quando esse adaptador reconhece o ID Meta. Registra versão, resultado, participante e direção do envelope em `observations.meta_id_adapter`; não confia em um campo original arbitrário enviado no payload Meta. UUID UnoAPI, `wamid`, `source_id`, referências operacionais e canais de envio continuam intactos. ID de citação/reação não se torna ID da mensagem atual.

**Consulta em modo observação:** `Whatsapp::MessageIdentityCorrelationService.new(identity: identidade, partner_inbox: caixa_parceira).perform`. Requer a caixa parceira explícita; não descobre/ativa parceiros por telefone ou ID coincidente. Revalida fonte e configuração persistidas, conta, canal, provedores distintos e número empresarial observado. Busca por igualdade exata do original, usando índice por conta/caixa/original; não usa texto, horários ou igualdade prévia de IDs internos de contato. A consulta não grava pares, aliases, mensagens ou vínculos entre caixas.

Resultados distinguem `matched`, `no_candidate`, `ambiguous`, `invalid_scope`, `original_id_pending`, `business_identity_pending`, `participant_identity_pending`, `conflicting_original_id`, `conflicting_observations` e `incompatible`. Vários candidatos ficam visíveis, sem escolher arbitrariamente o primeiro. Número empresarial divergente, inclusive com/sem nono dígito, exige comprovação posterior do vínculo; não é normalizado por aproximação nesta etapa. Participantes com variante móvel brasileira do nono dígito ficam como evidência pendente, nunca como autorização para mesclar contatos.

**Contato incompleto e evidência da própria mensagem:** um original exato pode localizar a identidade candidata da outra caixa mesmo quando chegou só BSUID/LID ou faltou telefone/nome. Retornar os IDs candidatos com `participant_identity_pending` permite ao futuro resolvedor usar essa evidência para preservar o contato antigo. Não usar o corpo da mensagem nem o ID de mensagem citada para identificar o remetente atual. Nesta etapa, localizar o candidato não associa aliases nem mescla contatos; direção, papel, conta, vínculo autorizado e conflitos ainda devem ser confrontados pelo resolvedor da seção 6.2.

**Conflitos e eventos posteriores:** não apagar valores conhecidos quando campos chegam vazios. Registrar contradições de participantes, direção, tipo/evento e número empresarial em `conflicting_observations`; manter o número empresarial original da observação. A consulta bloqueia contradições de direção/participante com o envelope, `to` versus `recipient_id` e reconfiguração de canal. Status isolado sem destinatário suficiente não confirma participante. Mudanças de dados por outra instância são relidas antes da comparação. Nada disso altera a direção/status da bolha legada ou dispara automações.

**Migração adicional:** `20261016000001_index_whatsapp_message_identity_originals` adiciona somente índice parcial não único, concorrente, para originais não nulos. Não alterar a migração já aplicada na VPS. Índice aplicado em dev; conferência de 1.000 mensagens da réplica preservou IDs atuais. Uma aplicação futura em produção precisa da aprovação correspondente; não remover hostpaths antigos nem aplicar este incremento implicitamente.

**Validação dev:** 91 verificações no script isolado, com HTTP bloqueado: envelopes reais de entrada/saída, comprimentos e codificações inválidos, formatos desconhecidos, duas ordens de chegada, status antecipado, escopo, ambiguidades, BSUID incompleto, nono dígito pendente, contradições, instância desatualizada e ausência de alterações de domínio/IDs. Migração do índice aplicada/revertida/reaplicada na base de teste. Regressão: 185 exemplos existentes aprovados; executar sobre schema limpo, separado das fixtures persistidas pelo runner. RuboCop dos cinco arquivos Ruby deste incremento aprovado. Sem mudanças no frontend ou nos bundles nativos.

Código sincronizado ao volume de fontes dev, web e worker recarregados; `/api` retornou HTTP 200. Versão do adaptador, fixture de extração, classe de correlação e índice confirmados no runtime dev; hashes dos três serviços conferidos com a branch. A base descartável `viperchat_provider_identity_test` foi removida após os testes (fixtures reproduzíveis pelo runner); a réplica `chatwoot_db` e seus dados foram preservados.

**Limite do aceite:** extração automática e comparação diagnóstica por par explícito, não roteamento unificado em produção. Ainda faltam configuração administrativa do vínculo comprovado (incluindo representação empresarial com/sem nono dígito), resolvedor de aliases/contatos e aplicação transacional da correlação à ingestão/efeitos/mídias. O ensaio de coexistência real desta versão do adaptador permanece pendente; fixtures reais capturadas e implantação técnica não equivalem a validar o comportamento em tráfego real/pico.

### 6.1.2. Piloto do adaptador Meta aplicado na VPS — 15/10/2026

Aplicação autorizada pelo usuário para testes na manhã seguinte. Commit `a97a695af6aed8f18b7e12cf2ce324ed89844e0d`, branch `4.16.0`; aplicado às 23:30 (America/Cuiaba), via hostpath, sem nova imagem/release. Mantida `v4.16.12-viper.31-ce`; nove arquivos Ruby somente leitura em cada processo web e nos dois workers. Fontes do piloto anterior, hostpath ViperConnect, configuração de push e compose original do Portainer preservados.

**Pacote e recuperação:** `/var/snap/docker/common/viperchat-hotpatch/provider-message-id-20261015-meta-correlation/`. Backup lógico completo novo em `private/database-before.dump`: 245.710.543 bytes, SHA-256 `bfe689102f5540da80637c1af3cbfa84355d0f1d27ae43ad1b1765014cd130efe`. Checksum e catálogo do arquivo conferidos; restauração completa não ensaiada. `private/` protegido, com manifesto, pacote, driver, compose e evidências. `rollback.sh` retorna ao piloto anterior de persistência (seção 6.0.1), mantendo tabelas, índice e observações coletadas; não executa `down`, não retorna à imagem sem persistência e não elimina dados.

**Alteração no banco:** somente a migração `20261016000001`, índice parcial concorrente e válido; a primeira migração não foi reexecutada. Não houve backfill, replay, mensagens de teste enviadas pelo agente, reatribuição de contatos ou fusão de caixas. Conferência pós-aplicação: os IDs de 1.000 mensagens antigas e os vínculos de canal das duas caixas permaneceram iguais.

**Verificação técnica:** nove hashes conferidos em cada container; web e dois workers em execução, sem reinícios adicionais nem os erros de carregamento, validação, FK e deadlock pesquisados nos logs desde o startup. Dois `wamid` reais previamente capturados foram reconhecidos pelo adaptador no runtime, em transação somente leitura. API interna HTTP 200 e API pública HTTP 200 pela estação local. A requisição pública originada da VPS recebeu 403 do Cloudflare; nenhuma regra de segurança foi alterada. Evidência completa em `private/validation.json`.

**Aceite de tráfego ainda pendente:** na janela da conferência, nenhum evento Meta novo com a versão do adaptador havia sido observado (`awaiting_live_events`). O teste de amanhã deve observar entrada, echo e status reais e a carga de pico, incluindo formatos desconhecidos, participantes incompletos e casos com nono dígito. As caixas 1 e 65 possuem representações empresariais diferentes: `business_identity_pending` continua esperado na comparação diagnóstica até a comprovação do vínculo empresarial. Não interpretar esse resultado como autorização para unificar contatos/caixas nem como falha do parser. O observador registra automaticamente a extração; a consulta de pares continua diagnóstica, com parceira explícita, sem aplicação à ingestão.

As duas cópias locais temporárias de transferência foram removidas; pacote, fontes e backups necessários ao piloto/rollback permanecem na VPS. A implantação não cria monitoramento agendado nem execução automática na manhã seguinte.

### 6.1.3. BSUID no wamid e reutilização preventiva do contato — dev em 16/10/2026

Incremento desenvolvido na mesma branch de trabalho `fix/whatsapp-correlation-br-mobile`, sobre a normalização somente de comparação. Sem deploy desta versão na VPS, migração, backfill ou mesclagem do contato `107150`. Não confundir identificação compartilhada de pessoa com unificação de atendimento.

- `coexistence-envelope-v2`: preserva o envelope telefônico existente e reconhece o envelope inteiro com participante BSUID, comprimento explícito e marcadores observados `15 14 00`, distinguindo namespace e direção. Não transforma BSUID em telefone. Envelopes desconhecidos ou inconsistentes continuam sem original inferido. O `wamid` completo permanece operacional e intacto.
- `Whatsapp::MessageIdentityContactResolver`: executa antes da criação legada do contato no fluxo Cloud, para entrada e echo. Exige BSUID do envelope igual ao identificador do participante no papel correto, original da própria mensagem, direção consistente e um único candidato na caixa parceira. Citações, reações, grupos, eventos não suportados e conflitos não servem como prova de pessoa.
- Ativação administrativa técnica, desligada por padrão: `provider_config.identity_resolution_partner_inbox_id` no canal Meta aponta explicitamente para a caixa ViperConnect da mesma conta. Não descobrir parceiros automaticamente nem configurar números/IDs de uma instalação no código. A comparação verifica os números empresariais normalizados, os provedores e os escopos observados. O campo não ativa caixa principal, roteamento, seletor de transporte ou unificação. Ainda não há uma tela administrativa específica para essa configuração.
- O candidato precisa estar vinculado a mensagens públicas, não de grupo, com escopo e direção coerentes, e apontar para um único contato cujo telefone corrobore o participante ViperConnect. O vínculo novo é um `ContactInbox` para o BSUID na caixa Meta, com proveniência em `additional_attributes.message_identity_resolution`. O ID do contato antigo, nome, telefone, LID/`contacts.bsuid`, dados manuais, UUIDs e `source_id` antigos não são substituídos.
- Concorrência: transação/lock da caixa e índice único existente de caixa/source protegem a criação do alias. Repetições reaproveitam o mesmo vínculo; um alias já pertencente a outro contato resulta em `alias_conflict`, sem reatribuição, exclusão ou merge. O resultado mais recente fica em `observations.contact_resolution`; isso não envia mensagens nem produz uma segunda automação por conta própria.
- Cada caixa continua recebendo sua própria mensagem e usando sua própria conversa, com as regras de status e atendimento existentes. O caminho de contato resolvido não chama a fusão automática de conversas históricas, mesmo em modo de conversa única. Não há deduplicação de bolhas ou mídias entre provedores nesta entrega.
- Se Meta chegar antes de existir a contrapartida comprovada, registrar pendência e manter o fluxo legado. Uma nova execução pode resolver quando a prova surgir e não houver alias conflitante; não foi adicionado replay/job de mesclagem tardia. Duplicados já criados exigem recuperação separada e autorização própria; o `107150` na VPS permanece intocado.

Validação reproduzível na base isolada `viperchat_provider_identity_test`, com HTTP bloqueado: `script/validation/whatsapp_bsuid_contact_identity.rb` cobre envelope real do caso relatado, rejeições de formato, opt-in, direção e namespace, ingestão de entrada/echo, aliases idempotentes/concorrentes, conflito com duplicado existente, escopo entre contas, citação não usada como identidade e preservação dos dados antigos. Executar com schema limpo, separado do runner de persistência e do RSpec. Nenhuma alteração de frontend/bundles nativos neste incremento.

Resultado dev: 35 verificações BSUID, 118 verificações do runner de persistência/correlação e 185 exemplos RSpec aprovados, com sete arquivos Ruby sem infrações RuboCop. Versão v2 e classe do resolvedor conferidas no runtime, API dev HTTP 200. Nenhuma caixa real da réplica foi ativada: opt-in apenas nas fixtures isoladas. Base temporária removida após a validação, preservando a réplica `chatwoot_db` e os fontes/testes para repetição.

### 6.1.4. Identificação pendente persistida — incremento somente dev em 16/10/2026

Continuação autorizada em dev, sem VPS, unificação de caixas ou recuperação histórica. Substitui a limitação de chegada fora de ordem descrita no incremento anterior somente para os eventos BSUID reconhecidos e com opt-in técnico válido. O canal permanece desligado por padrão; nenhuma caixa real da réplica foi ativada por esta etapa.

- Migração aditiva `20261016000002` cria `whatsapp_identity_resolutions`: uma pendência por identidade, parceira explícita, estado, motivo, tentativas, próxima execução, contato técnico de origem e contato sobrevivente. Não altera `messages.source_id`, UUID, `wamid`, ID de conversa ou de contato estabelecido. A referência ao provisório permanece como auditoria/redirecionamento após sua consolidação.
- Estados: `pending`, `resolved`, `conflict`, `review`, `disabled`. Até 12 tentativas automáticas por ciclo de evidência, com intervalo crescente de 60 segundos até uma hora. Esgotamento vai para revisão; nova observação da contraparte ou vínculo da mensagem por original exato pode reativar a pendência. Conflitos não são reativados automaticamente por simples repetição.
- `Whatsapp::ResolvePendingIdentityJob`, fila `low`, processa por ID; varredura a cada minuto recupera até 100 registros vencidos por passagem, inclusive quando o enqueue original se perdeu. Estado e vencimento no PostgreSQL, não a presença na fila, determinam se um job repetido pode trabalhar. Configuração removida/trocada desabilita a pendência sem mover contatos para outra parceira.
- Quando a Meta chega primeiro, o fluxo habilitado cria ou reutiliza um único alias e um cadastro estritamente técnico rastreado, deixando a mensagem acessível na sua própria conversa. Não captura corpo de mensagem, mídia ou credenciais na pendência. Status antes da mensagem ViperConnect aguarda a associação real a um contato, sem adivinhar a pessoa.
- A prova segue sendo o original da própria mensagem, com escopo empresarial/conta/caixas, papel, direção e telefone do candidato corroborados. Um único contato antigo comprovado prevalece com todos os seus campos, inclusive LID e dados manuais, intactos. Não procurar por conteúdo, nome, horário ou mensagem citada.
- Somente o provisório criado por este fluxo, com snapshot ainda intacto, um alias próprio e conversas no mesmo escopo pode ser consolidado automaticamente. Reparação transacional atualiza o contato das conversas existentes e o remetente das mensagens, conserva seus IDs e anexos, mantém a proveniência e remove apenas esse cadastro técnico. Não junta conversas, não move bolhas entre caixas, não reabre resolvidas e não executa callbacks de merge/entrega novamente.
- Nome/atributos alterados manualmente, nota vinculada diretamente ao contato, agendamento, CSAT, grupo, avatar/etiquetas ou outras dependências diretas/polimórficas não tratadas bloqueiam a remoção e deixam o caso para revisão. Não presume que o merge genérico cubra essas dependências. Contatos históricos ou aliases sem a marca de propriedade do fluxo, como o `107150` na VPS, nunca são consolidados por esta etapa.
- Locks de caixa, pendência, alias e contatos serializam concorrência. A ingestão relê o proprietário do alias sob lock antes de escolher a conversa, evitando recriar o provisório depois de uma reparação. Falha intermediária reverte a reparação inteira, registra tentativa/erro por classe, sem payload nos logs, e permite retomada limitada.

Validação: runner `script/validation/whatsapp_pending_identity.rb`, base descartável `viperchat_provider_identity_test` e HTTP bloqueado. Cobre Meta primeiro nos dois sentidos, eventos/jobs repetidos, concorrência, status antes da mensagem, dois eventos pendentes no mesmo alias, falha transacional/retomada, recuperação por varredura, limite de tentativas e configuração desligada; também comprova preservação de mídia, nota privada, agendamento, conversa encerrada e contato antigo. Não confundir fixtures com aceite de tráfego de produção.

Resultado: 151 verificações do fluxo pendente, 120 de persistência/correlação (incluindo rollback/reaplicação das migrações na ordem correta) e 35 de BSUID aprovadas. Regressão de mensagens Uno/Cloud, visualização única, avisos e agendamento: 186 exemplos, zero falhas. Quinze arquivos Ruby aprovados no RuboCop. A entrada cron usa `active_job: true` explicitamente; o teste de duplicidade do YAML foi repetido com finais de linha LF no container. Migração aplicada somente na réplica dev, web/worker locais recarregados, API HTTP 200, zero caixas reais habilitadas. Sem alteração de frontend ou bundles nativos.

Runtime: varredura enfileirada pelo cron e executada com sucesso pelo worker Sidekiq, sem pendências reais. Após a validação, removidos a base descartável e quatro jobs falhos da própria varredura inicial, anteriores ao ajuste ActiveJob; filas alheias, base `chatwoot_db`, uploads e serviços ativos preservados. Observado separadamente erro `jid=` no cron já existente `ScheduledMessages::DeliveryJob`; esse fluxo não foi alterado nesta entrega.

Atualização posterior autorizada, ainda em 16/10: corrigida também em dev a entrada `scheduled_messages_delivery_job` com `active_job: true`, sem alterar regra de entrega, horários ou dados agendados. Oito exemplos focados (configuração, entrega, sequência e status) aprovados; execução real pelo Sidekiq concluída, API HTTP 200 e digest dos registros dev preservado. Removidas dez varreduras inválidas antigas de dev, com classe/args vazios e erro `jid=` exatos; não são mensagens agendadas do banco. Base isolada dessa validação removida. Correção e regressão isoladas na branch `fix/scheduled-delivery-active-job`, sem commit/push.

Produção inspecionada somente para leitura: em 16/10, cerca de 11:58 America/Cuiaba, ambos os workers apresentavam execuções recentes do DeliveryJob bem-sucedidas. Sem esse erro nas tentativas/tarefas mortas pesquisadas; 145 registros enviados, oito futuros, quatro cancelados e zero falhos ou vencidos. Não confundir `cancelled: 4` com `failed: 3`. A versão instalada do sidekiq-cron detecta ActiveJob pela classe mesmo sem flag explícita. Nenhum hostpath, migração, reprocessamento, limpeza de fila ou alteração em produção nesta conferência. BSUID/resolvedor e identificação pendente continuam não aplicados na VPS.

Limites: este incremento não implementa a interface de revisão/indicação de pendência no frontend, nem resolvedor genérico para envelopes desconhecidos/sem original ou todas as formas de enriquecimento por telefone/alias. Esses casos continuam conservadores e não autorizam inferir uma identidade. Mídias duplicadas e envio unificado permanecem somente planejados. Não houve commit/push, release ou aplicação na VPS nesta etapa.

### 6.2. Identidade de contato: dependência obrigatória da unificação

`provider_message_id` resolve a identidade da mensagem, não substitui a resolução da pessoa. Implementar um resolvedor de identidade compartilhado pelos fluxos de entrada e echo antes de criar contato e conversa definitivos na caixa unificada.

Requisitos:

1. Manter aliases de identidade com origem e escopo: conta, vínculo de caixas, canal/provedor e escopo empresarial/aplicativo aplicável. Não interpretar BSUID `BR.*`, LID `@lid` e telefone como o mesmo namespace.
2. Não depender de um único `contacts.bsuid` global para representar simultaneamente LID ViperConnect e BSUID Meta. Preservar o atributo legado por compatibilidade, armazenando os vínculos específicos sem sobrescrever um pelo outro.
3. Reutilizar alias verificado já associado ao contato, tanto para mensagem nova quanto para echo. Não limitar a descoberta apenas aos aliases da caixa que recebeu o evento quando houver um vínculo de caixas explicitamente configurado.
4. Se a mensagem tiver ID original reconhecido e corresponder exatamente a um evento da caixa parceira, usar essa evidência para propor/estabelecer o vínculo do alias ao contato canônico, validando conta, número empresarial, direção, papel do participante e conflitos. Não exigir previamente `contact_id` igual: isso impediria justamente resolver o caso duplicado confirmado.
5. Um ID citado, reação, evento de grupo ou encaminhamento não comprova por si a identidade do remetente atual. Usar o ID da mesma mensagem/evento e identificar corretamente os participantes; rejeitar associações ambíguas.
6. Quando houver telefone confiável no próprio evento ou lookup permitido, procurar o contato existente e seus aliases antes de criar outro. Variação brasileira do nono dígito gera candidato contextual, não fusão automática. Exigir evidência adicional e ausência de candidatos conflitantes quando necessário.
7. Alias existente sem telefone/nome deve poder ser enriquecido posteriormente, sem ignorar os novos atributos só porque o vínculo já foi encontrado. Preservar nome humano, dados manuais, histórico, etiquetas, responsáveis e atributos existentes; o identificador técnico não deve substituir nome conhecido.
8. Lookup externo é auxiliar: sem garantia de retorno do telefone, com limite/timeout observável e sem bloquear ou descartar mensagens. Falha de lookup não autoriza inventar telefone a partir do BSUID nem fazer tentativas ilimitadas.
9. Se não houver evidência suficiente, registrar identidade pendente de forma persistente e auditável. A mensagem deve continuar acessível ao atendimento, com indicação de identificação incompleta, sem associação por aproximação. O desenho deve suportar associação posterior, sem uma segunda automação/conversa definitiva quando a identidade for resolvida.
10. Contato realmente novo e identidade ainda desconhecida são situações distintas. Criação provisória, quando necessária ao modelo atual, deve ser marcada e reconciliável; não prometer ausência absoluta de registros temporários sem ID comum disponível.
11. Impedir que workers simultâneos criem dois aliases/contatos definitivos para a mesma identidade confirmada. Usar restrições únicas no escopo correto, transações e recuperação de conflitos, considerando evento Meta antes/depois do ViperConnect.

Separar dois trabalhos:

- Correção preventiva para entradas/echo novos: faz parte da entrega da unificação e do modo observação de identidade.
- Recuperação dos contatos/conversas já duplicados: relatório de candidatos com evidências, dry-run e aprovação própria. O lote de dez pares, incluindo `107078 -> 94129`, foi posteriormente autorizado e executado conforme seção 3.2; isso não autoriza outros lotes nem reapontamento indiscriminado por SQL.

Para recuperação, tratar notas privadas, permissões, mídias, agenda, etiquetas e responsável antes de consolidar registros. Não apagar aliases válidos. A correlação de mensagens pode produzir a evidência para o relatório, mas não deve disparar uma fusão destrutiva de cadastros antigos silenciosamente.

Observabilidade: origem do evento, campo de identidade recebido, resultado do lookup (sem segredos), candidatos encontrados, evidência utilizada, conflito, identidade provisória e vínculo final. Medir quantos casos são identificados por alias, telefone comprovado e mensagem original equivalente.

### 6.2.1. Identificação pendente e chegada fora de ordem

Fluxo-alvo: a Meta pode chegar antes da ViperConnect, somente com BSUID e sem telefone. O subconjunto BSUID reconhecido já possui reconciliação automática somente em dev, conforme 6.1.4; o restante continua como requisito. Não exigir que a contraparte já exista nem considerar a criação de um cadastro técnico como identificação definitiva.

1. Persistir o evento e a identidade recebida, preservando `source_id`, `wamid`, UUID e valores brutos. Registrar conta, vínculo autorizado, namespace, direção, ID original quando reconhecido, motivo da pendência e referências às mensagens já criadas. Sem vínculo autorizado, não buscar contatos indiscriminadamente em outras caixas.
2. Classificar a resolução como pendente, resolvida ou em conflito. Falta de original/contraparte/evidência mantém pendência; vários candidatos, papéis incompatíveis ou aliases de pessoas estabelecidas diferentes geram conflito explícito. Não identificar por corpo, nome, horário ou mensagem citada.
3. Manter a mensagem acessível ao agente com identificação incompleta. Se for necessário um contato provisório, marcá-lo como técnico e rastreável; não sobrescrever dados do contato antigo nem criar repetidamente novos cadastros para o mesmo alias.
4. A chegada da contraparte com original exato, telefone comprovado ou alias confiável agenda nova resolução restrita ao mesmo escopo. Usar trabalho persistido e idempotente, restrições únicas e locks; registrar tentativas, próxima execução e resultado. Recuperar trabalhos interrompidos, limitar retries e encaminhar pendências sem evidência para revisão, sem descartá-las silenciosamente.
5. Com um único contato antigo comprovado, reutilizá-lo e vincular o alias recebido. Quando já houver provisório, sua consolidação preventiva depende do inventário transacional de dependências da seção 6.3. Dois contatos estabelecidos ou alias conflitante nunca são mesclados automaticamente. Duplicados históricos, incluindo o contato `107150`, exigem prévia, backup e autorização própria.
6. Reprocessar somente a resolução e os vínculos necessários: não reenviar mensagens, repetir bots/saudações/notificações, reabrir atendimentos encerrados ou baixar mídia de novo. Eventos atrasados devem seguir o redirecionamento auditado do provisório para o sobrevivente.

O fluxo diferido da seção 6.1.4 cobre o provisório novo e controlado, não a mesclagem de aliases históricos conflitantes nem o fluxo-alvo inteiro desta seção. A aplicação na VPS permanece adiada; desenvolvimento em dev e atualização do plano não autorizam deploy ou recuperação de dados em produção.

Aceite: testar as duas ordens de chegada, contraparte muito atrasada, eventos repetidos/simultâneos, queda do worker, falta permanente de original e conflito de alias. Preservar o ID/dados manuais do contato antigo, sem segundo/terceiro cadastro definitivo, perda de histórico ou efeitos de atendimento duplicados. Medir pendências por motivo/idade, resoluções e conflitos sem registrar segredos.

### 6.3. Preservar o contato antigo, tratar o nono dígito e reconciliar dados posteriores

Regra explícita do usuário: o contato antigo do ViperChat é preservado como cadastro base quando um novo registro técnico da Meta for comprovadamente a mesma pessoa. Manter seu ID interno, nome humano, histórico, vínculos, etiquetas e dados manuais. No caso já confirmado, `94129` permanece; `107078` é o duplicado a incorporar, nunca o contrário. A escolha não depende de Meta ou ViperConnect ser a caixa principal: preservar o cadastro estabelecido adequado, não privilegiar um provedor.

**Prevenção antes da criação:** normalizar o telefone recebido da Meta para comparação e procurar aliases existentes na conta/escopo autorizado, incluindo a representação brasileira com e sem o nono dígito quando aplicável a celular. Não acrescentar `9` a qualquer telefone brasileiro, a fixos, números internacionais, LIDs ou BSUIDs. Validar estrutura e regra de numeração aplicável; preservar o valor bruto como alias de origem e não sobrescrever o telefone canônico conhecido apenas porque a Meta enviou outra representação. Centralizar o comportamento para entrada comum, echo e eventos posteriores de identidade/status quando contiverem identificadores confiáveis.

**Dados posteriores:** se primeiro chegou apenas BSUID e já existe um contato provisório, a chegada de telefone, alias validado, lookup conclusivo ou mensagem equivalente com ID original deve acionar novamente o resolvedor. Encontrar o alias provisório não encerra a resolução: confrontar os novos dados com os contatos estabelecidos antes de apenas acrescentar o telefone ao cadastro técnico.

Quando houver correspondência inequívoca com um único contato estabelecido e nenhum conflito:

1. Reutilizar o contato antigo como base; não criar um terceiro registro para o telefone recém-chegado.
2. Se ainda não houver cadastro provisório, vincular diretamente o novo alias ao antigo.
3. Se houver provisório criado pelo fluxo, reconciliá-lo automaticamente ao antigo em operação transacional, idempotente e auditada, preservando conversas, remetentes, notas, etiquetas, referências de agendamento, atributos, mídias e aliases válidos. Não presumir que a ação de merge existente já cobre todas essas dependências; inventariar e corrigir o que faltar antes de usá-la.
4. Manter LID ViperConnect e BSUID Meta em seus vínculos próprios; evitar que um `contacts.bsuid` já preenchido impeça a associação do outro namespace.
5. Reprocessar apenas a resolução dos eventos pendentes, sem reenviar mensagens, baixar mídias novamente, criar novas conversas indevidas ou disparar novamente bots/saudações/notificações.
6. Registrar o redirecionamento do ID provisório para o sobrevivente para que eventos, jobs ou referências atrasadas não recriem o contato removido. Resolver novamente concorrência sob lock/restrições apropriadas antes da consolidação.

Sem evidência suficiente, com mais de um candidato ou com dois cadastros estabelecidos conflitantes, não mesclar automaticamente. Manter o caso pendente para revisão; identidade ainda desconhecida não justifica fundir pessoas por nome, texto ou horário. A consolidação automática preventiva dos provisórios futuros não autoriza a limpeza indiscriminada dos duplicados históricos já existentes na VPS, que segue o procedimento separado da seção 6.2.

Aceite adicional: simular BSUID primeiro, telefone sem nono dígito depois e contato antigo com telefone completo; a pessoa deve terminar com um único cadastro canônico, conservando o ID antigo. Repetir os eventos e inverter sua ordem, inclusive simultaneamente: não podem surgir segundo/terceiro cadastros definitivos, perder vínculos ou reaparecer o provisório.

## 7. Modelo de vínculo e atendimento único

### 7.1. Configuração administrativa

Adicionar seção “Caixa unificada / Coexistência” nas configurações de ambos os tipos de caixa:

- Ativar, desligado por padrão.
- Escolher caixa parceira e escolher explicitamente qual será principal.
- Transporte padrão de envio, independente da principal.
- Diagnóstico de número, conta, capacidades e recebimento de eventos.
- Prévia de conflitos de atendimentos ativos e data de corte.
- Confirmação administrativa e auditoria de alterações.

Validar mesma conta, número empresarial comprovado, apenas um vínculo por caixa e permissões nas duas caixas. Normalizar formatos telefônicos para diagnóstico, mas não efetuar fusão por heurística de nono dígito. Credenciais e IDs de contato permanecem próprios de cada transporte.

### 7.2. Conversas

A principal governa responsável, equipe, fila, etiquetas, status, SLA e regras de distribuição. O endpoint técnico da parceira continua recebendo e autenticando seus webhooks normalmente; não trocar os callbacks só para unificar a interface.

Eventos novos, depois do corte, são resolvidos para a conversa principal. Respeitar conversa única ligada/desligada. Status, echoes e eventos atrasados não podem criar um atendimento independente nem reabrir um encerrado indevidamente.

Para conversas ativas já presentes nas duas caixas, produzir prévia e selecionar explicitamente o atendimento canônico. Não sumir com uma conversa que possua responsável, nota ou trabalho pendente. No período de transição, fornecer referência/atalho entre os registros e preservar auditoria.

### 7.3. Histórico

Não fundir automaticamente histórico antigo, notas privadas, responsáveis ou anexos. A caixa principal conserva seus registros; o histórico antigo da parceira permanece consultável e identificado. Migração retroativa será outra operação, com dry-run, autorização e critérios determinísticos.

### 7.4. Desunificação administrativa: reversível para o futuro, sem separar o histórico

A unificação deve poder ser desligada pelo administrador nas configurações de qualquer caixa do par, com autorização nas duas caixas e auditoria. **Reversível significa desativar o vínculo para os próximos atendimentos/envios; não significa desfazer o histórico.** Não há operação de “separação histórica” ou restauração automática de duas cópias das mensagens já unificadas.

Contrato da desativação:

- Desativar (`enabled: false`), sem apagar o vínculo, mensagens, conversas, contatos, aliases, identidades ou anexos/blobs. IDs internos, `source_id`, URLs, notas privadas, responsáveis e histórico permanecem nos registros em que já estavam; a mensagem canônica continua na antiga principal. Repetir a desativação deve ser seguro.
- Novas mensagens compostas depois da desativação usam apenas o canal da própria caixa, sem seletor unificado ou roteamento para a antiga parceira. A antiga conversa canônica continua na sua caixa; não deve ser transferida de volta. Eventos realmente novos e independentes seguem o fluxo legado de cada transporte.
- Envios pendentes com metadados do vínculo antigo devem ser rejeitados para revisão explícita; nunca remover os metadados nem reenviar silenciosamente pela caixa principal/parceira. Reativar o mesmo registro de vínculo não autoriza enviar uma mensagem preparada no ciclo anterior.
- Uma reserva/evento do período unificado ainda sem mensagem canônica exige revisão persistente/quarentena, sem materialização automática pelo caminho legado. Não é evento independente só porque o administrador desligou o vínculo enquanto ele estava na fila. A revisão persistente está implementada no backend; sua exposição ao administrador não é comprovada por estes specs.
- Status e echoes de mensagens já materializadas continuam resolvendo para a canônica existente, mesmo com o vínculo desligado. Aliases conhecidos são preservados; uma contraparte tardia ainda não observada também não pode criar segunda bolha, atendimento ou cópia de mídia. Correlação exige evidência exata do original, participante, direção e escopo autorizado do par histórico; não usar texto/horário nem a ausência de vínculo ativo como autorização para duplicar.
- Reativação passa novamente pela prévia/confirmação aplicável e estabelece nova data de corte. O corte permite unificar eventos novos desse ciclo, mas não autoriza replay, fusão retroativa ou retomada de envios/reservas do ciclo anterior. Reconciliação de status/aliases com uma canônica existente é preservação de identidade, não replay histórico.

**Implementado e validado em dev em 16/10/2026:** o `destroy` administrativo chama `update!(enabled: false)` sob lock da conta e não remove dados; `WhatsappInboxLink.for_inbox` passa a ignorar o par. O envio com `whatsapp_transport` persistido consulta novamente o vínculo ativo e rejeita o envio enquanto ele está desligado. A busca de mensagem por alias em `find_message_by_source_id` não depende de vínculo ativo, permitindo reconciliar status e repetir echoes cujos aliases já existem. O spec de desunificação passou com 32 exemplos, incluindo as duas escolhas de principal.

As lacunas anteriores receberam as seguintes proteções de backend, exercitadas nos testes de desenvolvimento:

1. Os metadados de envio agora incluem `activation_cutoff`, além de `link_id`, provedor e caixa. A validação compara o corte persistido com a ativação atual, impedindo que reativar o mesmo vínculo autorize um envio preparado no ciclo anterior, sem trocar seu transporte.
2. `UnifiedHistoricalEventService` procura a reserva pelo original exato, direção e escopo histórico do par, com validação de participante/tipo, antes de liberar o evento ao caminho legado. A contraparte tardia de mensagem já materializada recebe alias para a canônica existente, sem iniciar nova ingestão. Reservas históricas ainda sem `message_id` são retidas em `review`, sem criar bolha independente.
3. A fila persistente `WhatsappUnifiedEvent`/`UnifiedEventService` compara vínculo/corte e passa eventos invalidados para `review`, com motivo `link_changed` e sem próxima tentativa automática. Um coordenador de ingestão inicializado antes da desativação guarda o corte original e revalida o vínculo em `defer_changed_link?`, retendo o evento em revisão antes de chamar o fluxo legado, inclusive se o mesmo vínculo já foi reativado com outro corte. `ensure_owned!` também confere o vínculo vivo (`enabled` e corte), além da posse da reserva, antes de concluir a transação de materialização.

Regressões com persistência real estão em `spec/services/whatsapp/unified_unlink_spec.rb`: **32 exemplos aprovados em dev**, incluindo preservação de notas/anexos/IDs, envio independente, seleção obsoleta, reativação, status, echoes, contraparte BSUID tardia e coordenador inicializado antes de desligar. A matriz de mídias passou com 37 exemplos na mesma rodada focada. São testes reais, sem exemplos `pending`/xfail; não equivalem ao aceite de carga/piloto na VPS. Ver evidências e limites na seção 18.

## 8. Correlação, concorrência e efeitos únicos

Identidade de correlação deve ser limitada à conta, vínculo das caixas, número empresarial e participantes/direção compatíveis, além do ID original reconhecido. Identidade externa também deve incluir o canal/namespace; IDs iguais em outras contas não são equivalentes. Compatibilidade de participantes deve ser resolvida pelos aliases e evidências da seção 6.2: não exigir contatos internos previamente iguais para reconhecer a mesma mensagem entre cadastros duplicados.

Ao receber o segundo evento equivalente, acrescentar seus aliases/statuses à mensagem canônica sem criar outra bolha ou disparar novamente efeitos de domínio. Usar transações, índices únicos e tratamento explícito de concorrência, não apenas Redis.

Cobrir echo antes da resposta de envio, status antes da mensagem, vários workers, retries, reinício e mensagens fora de ordem. A bolha otimista precisa de reconciliação transacional, sem efeitos permanentes duplicados antes da chegada do ID.

Se não houver ID confiável, registrar o caso como não correlacionado e mantê-lo observável. Não descartar a mensagem nem prometer bolha única nesse caso. Conflitos de dois registros já publicados exigem reconciliação auditável, preservando referências e anexos.

Bots, Capitão, saudações, distribuição, notificações, contadores e webhooks externos devem executar uma vez por evento lógico. Echo de saída não é entrada de cliente. Edições/revogação e reações também precisam de identidade de evento/versão para que uma atualização legítima não seja descartada como repetição.

### 8.1. Mídias: deduplicar antes de baixar e salvar

Requisito obrigatório: para uma mesma mensagem de mídia recebida pelos dois transportes, preservar uma mensagem canônica, um anexo lógico por item/versão e um blob original no Active Storage, com um objeto original correspondente no storage do ViperChat. Não basta remover a segunda bolha depois de ambos os arquivos já terem sido baixados e enviados ao S3.

O código atual usa `Attachment#file` com `has_one_attached :file`; o fluxo WhatsApp baixa o arquivo em `attach_files`. A mudança precisa interceptar a ingestão antes desse download/attach. Igualdade de checksum, por si só, não será tratada como mecanismo automático de deduplicação do Active Storage: haverá controle explícito da aplicação.

Fluxo proposto:

1. Autenticar o webhook e resolver a mensagem canônica por IDs, dentro do escopo do vínculo/conta.
2. Resolver cada item de mídia e sua versão. Um álbum pode representar várias mensagens e uma mensagem pode possuir mais de um anexo; não usar apenas um bloqueio por contato nem presumir um único item.
3. Reservar a ingestão daquele item de forma atômica no PostgreSQL, com restrição única e estado persistido. Redis pode auxiliar, mas não é a única garantia.
4. Se o item já estiver pronto, associar os aliases/referências do segundo transporte ao anexo existente e encerrar sem download, novo blob ou upload.
5. Se estiver em processamento, registrar a referência alternativa e aguardar/reagendar a consulta ao resultado; não iniciar outro upload em paralelo. Se a correlação atrasada ainda assim encontrar duas cópias persistidas, aplicar a reconciliação da seção 8.4.1.
6. Somente o responsável pela ingestão baixa o arquivo, valida tamanho/tipo e calcula hash forte do conteúdo, por exemplo SHA-256. Salvar o blob uma vez e concluir o vínculo ao anexo.
7. Se a primeira origem falhar, permitir recuperar o arquivo pela outra referência da mesma mensagem, sem reenviar mensagem ao WhatsApp e sem criar um segundo anexo lógico.

O modelo deve manter as duas referências externas de mídia, seus respectivos canais/credenciais e validade, em vez de tratar URLs assinadas como identidade permanente.

### 8.2. Identidade de mídia, hash e diferenças entre transportes

- Chave lógica: mensagem canônica + item de mídia + versão/representação. Não utilizar nome do arquivo, URL, ID de mídia da Meta ou UUID ViperConnect isoladamente como identidade compartilhada.
- A correlação da mensagem ocorre antes do download. O hash valida a identidade binária quando necessário; não exigir o download das duas origens só para decidir descartar uma delas.
- Um segundo transporte que confirme a mesma mensagem não exige outra cópia do original. Conservar metadados por origem sem sobrescrever legenda, nome ou MIME indiscriminadamente.
- Se já houver evidência de conteúdos distintos, não declarar igualdade binária nem descartar um arquivo por aproximação. Registrar conflito/representação alternativa e investigar a necessidade de manter ambos.
- Arquivos transcodificados, áudio convertido, imagem editada, thumbnail e original não são necessariamente os mesmos bytes. Representações necessárias podem possuir objetos separados e identificados; isso não deve ser contado como duplicação do original.
- Não deduplicar silenciosamente a mesma mídia enviada intencionalmente em duas mensagens distintas. As mensagens e anexos lógicos permanecem separados, mesmo que uma futura política explícita permita compartilhar um blob de bytes idênticos.
- Não buscar blobs globalmente entre contas por hash: evitar vazamento de existência de arquivos, quebra de retenção e mistura de permissões. Reutilização, se implementada além do mesmo evento canônico, fica limitada à política/conta autorizada.
- Se o ID original não estiver disponível ou não puder ser correlacionado, não há garantia de evitar os dois downloads/objetos. Marcar e medir a limitação; nunca perder mídia para forçar a meta de armazenamento único.

### 8.3. Uploads feitos pelo agente e seus echoes

Se o agente já anexou um arquivo no ViperChat, o envio e os echoes dos dois transportes devem apontar para esse mesmo anexo/blob local. Não baixar novamente do WhatsApp apenas porque a mensagem enviada voltou por outro webhook.

Vincular a mensagem otimista e seus anexos à operação de envio antes do processamento assíncrono. Tratar o echo antes da resposta de API com a mesma reserva/reconciliação descrita acima. Upload incompleto, envio falho e retry devem continuar distinguíveis; não remover o arquivo necessário para uma tentativa legítima.

### 8.4. Concorrência, falhas e ciclo de vida no S3

- Não manter transação de banco aberta durante downloads longos. Usar estados persistidos, proprietário da tentativa e lease com retomada controlada, impedindo que um worker atrasado conclua por cima da tentativa válida.
- PostgreSQL e S3 não compartilham uma transação. Um crash entre upload e confirmação pode deixar objeto/blob órfão; não prometer exatamente uma gravação física em qualquer falha possível.
- Antes de reenviar bytes numa retomada, consultar o blob/objeto da tentativa registrada e validar sua integridade. Não reutilizar chave aleatória de outro anexo nem sobrescrever um objeto referenciado.
- Objetivo do aceite: um original vivo por item canônico e nenhum segundo upload no caminho normal/reentrega concorrente; falhas intermediárias têm recuperação e identificação de órfãos.
- Análise de mídia, thumbnails e transcrição devem aproveitar o anexo canônico. Jobs repetidos não devem gerar novas representações equivalentes ou transcrições duplicadas sem controle.
- Não executar `purge` em um blob ainda usado por outra associação. Antes de excluir, verificar referências e retenção aplicável. Um link técnico removido do canal parceiro não autoriza apagar a mídia canônica.
- Só limpar órfãos comprovadamente criados pelo fluxo, após período de segurança e inventário/dry-run. Nunca fazer limpeza global de Active Storage/S3 ou apagar arquivos legados nesta entrega.
- Autorização de downloads, revogação, notas privadas e visualização única continuam valendo independentemente de quantos transportes apontem para a mídia.

### 8.4.1. Duplicidade já persistida: prioridade da mídia do canal principal

Regra explícita: se a mesma mensagem/item de mídia tiver sido persistida por ambos os transportes antes da correlação, manter como canônica a mídia do **canal principal configurado** e retirar a cópia secundária. Vale tanto para Meta quanto para ViperConnect como principal; ordem dos webhooks e transporte selecionado no editor não alteram essa prioridade. A prevenção antes do download continua sendo a primeira barreira, e esta reconciliação cobre duplicidades que escaparem dela.

1. Confirmar mensagem, item e versão equivalentes por IDs no escopo conta/vínculo. Nome, horário, legenda ou tamanho semelhantes não bastam. Diferenças reais de representação/conteúdo seguem a seção 8.2 e não autorizam descarte por aproximação.
2. Manter a mídia secundária disponível até a principal estar disponível, íntegra e autorizada. Se a origem principal falhar ou expirar, registrar pendência e preservar a secundária; não deixar a conversa sem mídia para cumprir a preferência. Não baixar novamente uma mídia já íntegra apenas para confirmar a duplicidade.
3. Sob controle transacional da mensagem/item, revalidar vínculo, principal vigente e referências; apontar o anexo lógico canônico e referências internas para a mídia principal antes de retirar a associação secundária. Preservar permissões, citações, metadados por origem e histórico, sem reenviar a mensagem nem repetir seus efeitos de domínio.
4. Se ambos já apontarem para o mesmo blob, remover somente a associação redundante. Nunca apagar o arquivo compartilhado por essa razão. Se forem blobs diferentes, só agendar a exclusão do secundário após a troca confirmada e a verificação de todas as referências e retenções aplicáveis; referências legítimas de outras mensagens não devem ser removidas para liberar o blob.
5. Executar a limpeza em segundo plano, de forma idempotente, com estados persistidos, auditoria e nova verificação antes do purge. Proteger a disputa entre reconciliação, novos vínculos e exclusão; falhas entre PostgreSQL e S3 devem permitir retomada sem apagar a mídia principal ou um objeto ainda referenciado. Respeitar o período de segurança e a prévia de órfãos da seção 8.4.
6. Aplicar também quando o webhook principal chegar muito depois do secundário, ou quando uma pendência de identidade for resolvida posteriormente. Mudança administrativa da caixa principal exige política/corte explícitos; não inicia limpeza retroativa de todo o histórico automaticamente.

Aceite: principal antes/depois do secundário, correlação tardia após dois uploads, ambas as escolhas de principal, principal indisponível, blob compartilhado, secundário com outra referência, reinício do worker e repetição do job. Ao concluir, um original canônico vivo por item; nenhuma mídia acessível perdida, nenhuma exclusão entre contas e nenhuma segunda bolha/automação criada pela reconciliação. A limpeza dos duplicados históricos permanece fora da ativação inicial, conforme seção 8.6.

### 8.5. Limite: storage do ViperChat versus cache da ViperConnect

A deduplicação acima elimina a segunda ingestão no Active Storage e no bucket/prefixo do **ViperChat**. A ViperConnect pode manter sua própria cópia/cache para entrega e reenvio de mídias. Esse armazenamento pertence a outro ciclo de vida e não desaparece por unificar caixas.

Não apontar Active Storage diretamente para um objeto temporário/URL assinada do provider como atalho. Eliminar também a cópia entre os dois produtos exigiria outro desenho de propriedade, acesso, retenção e recuperação. Nesta fase, medir esses custos separadamente e não prometer uma única cópia física em toda a infraestrutura.

### 8.6. Histórico e aceite de armazenamento

Mídias antigas duplicadas permanecem preservadas. Uma eventual consolidação retroativa exige auditoria por hash/conta, prévia de referências, plano de retenção e autorização separada; não faz parte da ativação inicial.

O piloto deve comprovar:

- [ ] Mesmo texto com mídia não é critério de identidade; IDs correlacionados governam a ingestão.
- [ ] Dois webhooks equivalentes simultâneos resultam em um anexo lógico, um blob original e um objeto original vivo no storage ViperChat.
- [ ] O segundo evento, após conclusão, não baixa nem envia novamente o arquivo.
- [ ] Se ambos já persistiram a mídia antes da correlação, a cópia principal íntegra prevalece; retirar a secundária somente após atualizar referências e comprovar que seu blob pode ser removido com segurança.
- [ ] Principal atrasada/indisponível mantém a secundária acessível; jobs repetidos, blob compartilhado e falhas de limpeza não causam perda de mídia.
- [ ] Upload do agente mais echo Meta/ViperConnect reaproveita o blob local.
- [ ] Falha da primeira origem permite recuperação pela segunda, sem dois anexos ou perda do arquivo.
- [ ] Crash depois do upload, antes do vínculo e durante a análise tem retomada segura e órfãos identificáveis.
- [ ] Álbuns, vários anexos, edições e representações diferentes não são colapsados incorretamente.
- [ ] Históricos, downloads e permissões seguem funcionando, e nenhuma mídia pré-existente é apagada.
- [ ] Desligar o vínculo não purga objetos nem quebra referências de mensagens preservadas.

## 9. Envio e IDs corretos para cada operação

| Finalidade | Identificador |
| --- | --- |
| Selecionar bolha/citação no frontend | ID interno do ViperChat |
| Correlacionar eventos entre caixas | ID original reconhecido, no escopo correto |
| Enviar uma citação pela ViperConnect | UUID público da mensagem naquele transporte |
| Enviar uma citação pela Meta | `wamid` completo da mensagem naquele transporte |
| Reação/edição/exclusão | ID de operação exigido pelo transporte efetivamente resolvido por capacidade, independentemente da seleção do editor |

**Não enviar `provider_message_id` no lugar do UUID da ViperConnect.** Ele serve à correlação. O frontend informa a mensagem interna e o transporte; o backend resolve o alias certo. Na ausência desse alias, avisar e permitir retirar a citação explicitamente, nunca substituir silenciosamente ou inventar ID.

Resolver e persistir o transporte efetivo antes de enfileirar, preservando separadamente a preferência selecionada no editor e o motivo de eventual roteamento por capacidade. O job deve usar credenciais, identidade do contato, regras de janela e templates do transporte efetivo, não apenas `conversation.inbox.channel`. LID e BSUID não são intercambiáveis. Não trocar de canal silenciosamente em retry; envio com resultado desconhecido exige cuidado antes de uma tentativa alternativa.

Reações, edição e exclusão dependem de capacidade e autoria. Remover a mensagem localmente não garante que o outro canal possa revogá-la no WhatsApp.

### 9.1. Levantamento obrigatório de capacidades antes da implementação

Antes de implementar cada recurso da unificação, levantar o suporte real da Meta e da ViperConnect na versão instalada, considerando a documentação do provider, o código de envio/recepção, a edição do ViperChat e as restrições verificadas em testes. Não assumir que a existência de uma opção no frontend comprova suporte do transporte.

Manter uma matriz versionada por recurso, com suporte a envio, recebimento e ações separados. Para cada item registrar: suportado, não suportado ou ainda não validado; limites; autoria/prazo; ID exigido; pré-condições; evidência e versão/data da validação; transporte alternativo compatível; e eventual diferença de custo/semântica. Estado desconhecido não autoriza roteamento automático por suposição.

O levantamento deve incluir, no mínimo: texto, imagem, áudio, vídeo, documento, contato, localização, resposta citada, reação, edição, exclusão para todos, visualização única, formatos interativos, listas/botões, templates, grupos e chamadas. Cada recurso pode ter restrições próprias de formato, tamanho, destinatário e contexto; a matriz não pode ser apenas um booleano global por canal.

O exemplo “excluir via ViperConnect quando Meta não suportar” é uma regra de resolução, não uma afirmação de que toda mensagem ou autoria permita exclusão pela ViperConnect. A capacidade precisa ser comprovada para aquele alvo e contexto antes de executar.

### 9.2. Roteamento automático por capacidade, sem mudar a seleção do editor

Requisito solicitado pelo usuário: se o recurso não for suportado pelo transporte marcado no editor, mas for suportado pelo parceiro vinculado, autorizado e apto para aquele contexto, a operação deve ser enviada automaticamente pelo provedor compatível. A preferência do editor para os próximos envios permanece intacta. Aplicar nos dois sentidos quando a matriz comprovar suporte alternativo.

Ordem de resolução:

1. Identificar recurso, contexto e, para ações, mensagem alvo. A seleção do editor controla a preferência dos novos envios, não obriga ações sobre mensagens a usar o mesmo canal.
2. Para novo envio, usar a preferência quando compatível; se houver incompatibilidade conhecida, resolver o parceiro compatível antes de qualquer tentativa externa.
3. Para ação sobre mensagem existente, priorizar o transporte apto à ação naquele alvo, com autoria e alias corretos; a seleção do editor não deve impedir a operação disponível no parceiro.
4. Se ambos puderem executar uma ação, preferir a origem de envio/alias válido da mensagem segundo uma regra determinística documentada para o recurso, sem executar nos dois.
5. Validar permissões, vínculo ativo, identificador do destinatário/alvo, capacidade contextual e condições de envio no transporte efetivo.
6. Exibir o transporte efetivo e o motivo do roteamento na prévia/confirmação, quando houver, e nos detalhes da operação. Roteamento é automático, mas não oculto.
7. Persistir preferência solicitada, transporte efetivo, motivo, alias utilizado e chave de idempotência antes de enfileirar. O worker revalida a operação; mudanças de configuração não autorizam reencaminhar silenciosamente jobs pendentes.
8. Se nenhum transporte estiver apto, informar o impedimento e não enviar, degradar o conteúdo ou descartar a ação silenciosamente.

Exemplos de comportamento esperado:

| Situação | Transporte efetivo | Seleção do editor depois |
| --- | --- | --- |
| Meta selecionada; excluir para todos só é válido via ViperConnect para o alvo | ViperConnect, usando UUID e confirmação de exclusão | Continua Meta |
| Meta selecionada; recurso de novo envio só é suportado pela ViperConnect no contexto | ViperConnect, identificado na prévia/ação de envio | Continua Meta |
| ViperConnect selecionada; recurso só é suportado pela Meta no contexto | Meta, após validar suas condições | Continua ViperConnect |
| Ambos suportam o novo envio | Transporte selecionado no editor | Sem alteração |
| Parceiro sem permissão, alias necessário ou suporte validado | Nenhum envio/ação; informar motivo | Sem alteração |

### 9.3. Segurança, confirmação e diferença para fallback após erro

- Incompatibilidade de recurso é distinta de indisponibilidade, falta de permissão, autenticação inválida, restrição de segurança, janela fechada, template inválido, erro de rede ou resposta incerta. Estes casos não devem ser convertidos genericamente em “não suporta” para tentar outro canal.
- A seleção automática não pode contornar políticas do WhatsApp, autorizações do usuário, bloqueio de contato, limitações de autoria ou exigências do transporte efetivo.
- Não converter um template oficial em texto livre nem alterar categoria, destinatário ou conteúdo apenas para caber no parceiro. Roteamento só é automático quando preserva a função e as condições aplicáveis; diferenças de semântica devem ser expostas e aprovadas.
- Exclusão para todos continua com confirmação explícita, identificando o transporte efetivo, por exemplo “Excluir para todos via ViperConnect”. Remoção apenas local é outra operação, não substituto silencioso para revogação remota.
- Se já houve tentativa externa com resultado desconhecido ou possivelmente entregue, não iniciar outra pelo parceiro. Preservar a idempotência e oferecer diagnóstico/repetição controlada.
- Se o recurso previsto como suportado retornar erro, registrar e corrigir a matriz quando confirmado. Não usar o primeiro envio real como teste seguido de envio automático alternativo.
- Rascunho, citação e anexos pertencem à operação: roteá-los não deve mover a seleção de preferência, apagar outro rascunho ou duplicar upload. Cobrança estimada e identificadores precisam refletir o transporte efetivo, não o selecionado originalmente.

## 10. Frontend, Web e aplicativos

- Um atendimento, uma timeline e uma bolha por mensagem correlacionada.
- Seletor visível “Enviar por: ViperConnect / Meta” tanto no editor compacto quanto no editor completo, permitindo ao agente escolher explicitamente o transporte de saída em ambos, independentemente da caixa principal.
- Manter o canal selecionado ao alternar entre editor compacto e completo, nos dois sentidos. Ambos compartilham a mesma seleção por conversa; a troca de editor não restaura o padrão administrativo nem altera o transporte silenciosamente. Atividade recebida também não muda a seleção.
- Nos dois editores, distinguir canal preferido e transporte efetivo do recurso. Quando a matriz exigir o parceiro, indicar “Será enviado via ...: recurso indisponível no canal selecionado”, sem trocar a seleção. Menus de ação, como excluir, mostram o canal executor e não dependem do seletor de novos envios.
- Rascunhos independentes por transporte, preservando texto, anexos e citação. Ao trocar, revalidar capacidades sem perder o rascunho.
- Indicação discreta do transporte de envio, detalhes dos aliases e erros acessíveis.
- Status por transporte preservado; status agregado monotônico e baseado na mesma mensagem. Não converter falha em sucesso por evento não correlacionado.
- Templates somente no contexto compatível; janela e disponibilidade do canal visíveis antes de enviar.
- Notas privadas continuam internas. Não as expor ao outro canal, widget ou destinatário.
- Grupos, chamadas, mídia de visualização única e recursos exclusivos seguem capacidades reais, sem prometer equivalência Meta/ViperConnect.

Não confundir `delivery_destination` existente com a escolha do transporte: destino WhatsApp/Web e transporte ViperConnect/Meta são eixos distintos. Mensagens Web continuam sem passar pelo serviço WhatsApp. Convites e lembretes respeitam transporte, janela e template quando necessário; atividade Web não renova a janela oficial.

Testar desktop e mobile 320, 360, 390, 412/430 px, teclado, orientação pertinente e safe areas. Para mudanças compartilhadas, regenerar bundles Android e iOS e executar a validação nativa prevista no projeto. Registrar claramente indisponibilidade de Mac/device; não chamar validação Web de validação iOS.

## 11. Integrações adjacentes

- Agendamento persiste preferência e transporte efetivo resolvido, com motivo de roteamento por capacidade quando aplicável, e revalida disponibilidade/janela ao executar; não herda silenciosamente um novo padrão administrativo nem passa ao parceiro após falha.
- Campanhas usam transporte explícito e não são automaticamente roteadas como uma resposta manual.
- Permissões consideram principal e parceira; o vínculo não amplia acesso indevidamente a credenciais ou histórico.
- Relatórios contam um atendimento e uma mensagem lógica, permitindo decompor os envios reais por transporte.
- Busca, exportação, mídia, downloads e endpoints legados precisam continuar resolvendo os registros históricos.
- Código Enterprise deve ser revisado onde sobrepõe chamadas, canais e permissões; não oferecer recursos ausentes na edição instalada.

## 12. Simulação de custos e franquia de mensagens

### 12.1. Fontes, divergência e data de validade

Consulta em 15/10/2026:

- A [página pública de preços da Meta](https://whatsappbusiness.com/products/platform-pricing/) informa cobrança por mensagem entregue, dependente de mercado/categoria, e oportunidades de gratuidade. O texto consultado ainda descreve serviço e utilidade em resposta como gratuitos, sem refletir a franquia mencionada abaixo.
- O [comunicado operacional da Gupshup para 01/10/2026](https://support.gupshup.io/hc/en-us/articles/62362400519705-WhatsApp-Service-Messages-Pricing-w-e-f-01-Oct-2026) descreve franquia de 1.000 mensagens de serviço por número/mês, cobrança do excedente e de utilidade dentro da janela; preserva a gratuidade de entrada elegível por 72 horas. É documentação do próprio fornecedor, não confirmação da configuração comercial desta conta Meta direta.
- A [documentação técnica de preços da Meta](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing) retornou HTTP 429 na consulta. Sua regra vigente e rate card precisam ser verificadas antes de apresentar valores reais ou tomar decisão automática.

Conclusão de projeto: suportar o cenário de 1.000 mensagens solicitado pelo usuário, com regras versionadas e parametrizadas. Não fixar como verdade universal uma regra comercial contraditória entre páginas; confrontar eventos `pricing`, tabela vigente, mercado e faturamento da conta. Não reaproveitar a antiga franquia de 1.000 conversas como se fosse a mesma unidade.

### 12.2. Parâmetros do simulador

- Vigência da regra e da tarifa; moeda, país do destinatário e eventual faixa de volume.
- Número empresarial e mês/fuso de faturamento confirmado; caixa principal/parceira não duplicam franquia do mesmo número.
- Franquia de serviço configurável, cenário inicial de simulação `F = 1000`.
- Consumo já realizado no mês, incluindo envios por outros sistemas; quando desconhecido, apresentar intervalo e cobertura parcial.
- Mensagens entregues por categoria: serviço, utilidade, marketing e autenticação; outras categorias não reconhecidas ficam pendentes, não gratuitas por padrão.
- Tratamento de janela de atendimento, entrada gratuita elegível, isenções e exceções verificadas; não conceder gratuidade só porque o usuário respondeu.
- Proporção de envios por transporte; custos fixos/variáveis ViperConnect, infraestrutura e eventual provedor/BSP.
- Bytes de originais e derivados, retenção, PUT/GET, download/egress, processamento/transcrição e custo de storage de cada produto. Não contabilizar como economia a remoção de uma cópia ViperConnect que este plano não elimina.
- Câmbio, tributos e margem em campos separados; não tratar custo estimado em BRL como tarifa oficial.

A franquia, quando confirmada, é de **serviço elegível**, não de qualquer template ou de todas as mensagens recebidas/enviadas. Distinguir número de bolhas, número de envios efetivos e número de mensagens faturáveis por mídia/lote. Echo e status não são um novo envio faturável no simulador.

### 12.3. Cálculo e exemplos simbólicos

Para um cenário homogêneo sem faixa de volume e sem outras exceções:

```text
F_restante       = max(0, F - servico_elegivel_ja_consumido)
servico_pago     = max(0, novo_servico_elegivel_meta - F_restante)
custo_servico    = servico_pago * tarifa_servico
custo_templates = soma(mensagens_entregues_faturaveis_por_categoria * tarifa_aplicavel)
custo_total      = custo_servico + custo_templates + custos_viperconnect
                   + infraestrutura_incremental + taxas_adicionais
```

Calcular por vigência/mercado/número e depois agregar. Aplicar faixas reais quando existirem. Entrada gratuita deve ser classificada antes do cálculo e reconciliada com a regra aplicável, sem descontar a mesma mensagem duas vezes.

Exemplos sem tarifa monetária inventada, com `F = 1000`, mês inicialmente sem consumo, apenas serviço elegível e sem outras isenções:

| Cenário mensal | Entregues pela Meta | Pela ViperConnect | Serviço pago Meta | Parcela de custo Meta |
| --- | ---: | ---: | ---: | --- |
| Baixo volume | 500 | 0 | 0 | `0` |
| Limite da franquia | 1.000 | 0 | 0 | `0` |
| Primeira excedente | 1.001 | 0 | 1 | `1 * tarifa_servico` |
| Tudo oficial | 10.000 | 0 | 9.000 | `9.000 * tarifa_servico` |
| Distribuição hipotética 20%/80% | 2.000 | 8.000 | 1.000 | `1.000 * tarifa_servico` |
| Saldo parcial: 800 já consumidas + 500 novas Meta | 500 novas | 0 | 300 novas | `300 * tarifa_servico` incremental |

No cenário 20%/80%, a diferença bruta da parcela Meta é `8.000 * tarifa_servico` em relação ao cenário de 10.000 oficiais. Isso **não é economia líquida comprovada**: faltam custos/limitações da ViperConnect, mix real, janela, templates e condições comerciais.

Templates faturáveis não consomem automaticamente a franquia de serviço neste cenário; são calculados separadamente. Mensagens recebidas e echoes não entram como respostas oficiais faturáveis. Falha sem entrega não recebe cobrança estimada de entrega Meta, mas taxas de terceiros podem ter regra própria.

### 12.4. Persistência e apresentação

- Preservar os atributos de cobrança recebidos da Meta, como categoria, tipo e modelo, quando presentes. Não depender apenas de um campo legado `billable`, nem inferir custo exclusivamente do texto.
- Reconhecer formatos/categorias novos sem perda do payload de cobrança necessário; tipos desconhecidos geram estado “não classificado”.
- Uma entrega física pode gerar vários statuses: contabilizar uma vez e permitir correção idempotente dos metadados.
- Separar “faturamento observado”, “estimativa calculada” e “cenário simulado”. Webhook pode classificar cobrança sem informar o valor monetário exato; conciliar com rate card/fatura.
- Compartilhar contador entre as caixas vinculadas do mesmo número e sinalizar consumo externo não observado.
- Aguardar confirmação de entrega para consolidar consumo observado. Estimativa antes do envio é provisória; envios concorrentes e externos impedem garantia de franquia restante.
- Primeira versão não troca automaticamente o transporte para aproveitar franquia. Roteamento automático por capacidade segue a seção 9 e contabiliza o transporte efetivo; roteamento financeiro automático seria outro escopo.

## 13. Etapas e critérios de avanço

| Etapa | Entrega | Gate |
| --- | --- | --- |
| P0 | Este plano | Revisado e atualizado com o resultado P1/P2; decisões preservadas |
| P1 | `provider_message_id` aditivo na ViperConnect | Implementado e validado em dev; commit `b1668845`; IDs preservados e Typebot excluído |
| P2 | Piloto hostpath da ViperConnect na VPS | Executado e validado na amostra real da seção 5.4: seis pares e status read; testes reais restantes explicitados |
| P3 | Release definitiva ViperConnect | Pendente: imagem versionada validada e remoção explícita do overlay temporário |
| P4 | ViperChat persiste IDs, observa correlações e resolução de identidade | Parcial: persistência inicial validada na VPS; adaptador Meta e consulta diagnóstica validados em dev e aplicados via hostpath (6.1.2), aceite real/pico pendente; vínculo empresarial/aliases e resolução de pessoas pendentes; sem fusão histórica ou alteração de fila/bolhas/envio |
| P5 | Vínculo, correlação, ingestão única de mídias e envio por transporte | Testes transacionais, concorrência Active Storage/S3 e segurança nos dois sentidos de principal |
| P6 | Frontend, Web/Android/iOS e integrações | Interface responsiva, capacidades e referências corretas |
| P7 | Simulador e reconciliação de custos | Regras comerciais verificadas e cálculo sem duplicidade |
| P8 | Piloto da caixa unificada | Hostpath controlado quando aplicável, ativação manual e rollback pronto |
| P9 | Release definitiva e ampliação | Aceite do usuário e autorização de publicação/deploy separadas |

Não saltar da primeira alteração do webhook para a fusão de históricos. O simulador pode ser desenvolvido em paralelo após estabelecer o modelo de eventos, mas não decide o transporte na primeira versão.

## 14. Matriz mínima de testes da unificação

- Principal Meta e principal ViperConnect, com padrão de envio igual e diferente da principal.
- Contato existente nos dois canais, apenas em um, sem telefone e com múltiplos aliases; conflito entre contas nunca pode unir dados.
- Reproduzir o caso `BR.2339818310092335` com fixtures anonimizadas: contato antigo por telefone/LID, echo Meta só com BSUID, chegada posterior do telefone sem nono dígito e mensagem equivalente com o mesmo original mas `contact_id` diferente. Testar entrada comum e echo, nas duas ordens de chegada e com ambos os tipos de principal.
- Lookup Meta ausente/falho, alias já encontrado sem enriquecimento, dois candidatos telefônicos e concorrência na criação. Nenhum desses casos autoriza adivinhar identidade, perder mensagem ou sobrescrever nome humano.
- Correlacionar mensagem exata entre contatos distintos sem fusão destrutiva automática; gerar diagnóstico e proposta de reconciliação histórica separados.
- Conversa única ligada/desligada, duas conversas abertas legadas, resolução e evento atrasado.
- Texto, áudio, vídeo, imagem, documento, contato, localização e formatos não suportados.
- Mídia equivalente simultânea pelos dois canais: conferir anexo canônico, blob, objeto S3 e número de uploads/downloads. Repetir com arquivo enviado pelo agente, retry, crash, álbum, transcodificação e origem indisponível.
- Envio por ambos os transportes, echo antes/depois da resposta, status atrasado e duplicado, retry e reinício de worker.
- Citação nos dois sentidos: UUID enviado à ViperConnect, `wamid` à Meta; alias ausente com aviso explícito.
- Seletor presente e funcional no editor compacto e no completo: selecionar Meta e ViperConnect em cada editor, alternar entre eles nos dois sentidos e comprovar que a seleção, o rascunho e o transporte efetivamente persistido/enviado permanecem corretos. Executar com principal Meta e principal ViperConnect, em desktop e mobile.
- Edição, reação e exclusão, com verificação de autoria/capacidade e sem reenvio acidental.
- Matriz de capacidades validada por recurso antes da implementação; testar recurso não suportado na Meta roteado à ViperConnect e o inverso, quando aplicável, preservando o seletor e informando o transporte efetivo nos dois editores.
- Exclusão para todos via canal compatível, com alias, autoria e confirmação corretos, mesmo quando o editor aponta ao outro canal; remoção local é independente. Testar ambos compatíveis, nenhum compatível, capacidade desconhecida e parceiro sem autorização/alias.
- Falha/timeout depois de uma tentativa não dispara envio automático pelo parceiro. Verificar chave de idempotência, uma única chamada externa, mídia reaproveitada e custo atribuído ao transporte efetivo.
- Uma saudação/bot/notificação/webhook externo por evento lógico; notas privadas permanecem internas.
- Janela oficial aberta/fechada, template aprovado, canal desconectado e envio com resultado incerto.
- Atendimento Web, convites, lembretes, rascunhos, agendamento e relatórios existentes.
- Custos nos limites 999/1.000/1.001, consumo anterior, dois números, mesmo número em duas caixas, mudança de mês/fuso, duplicidade de statuses e isenções.
- Categorias/tarifas desconhecidas, mudança de vigência, consumo externo e comparação estimativa versus fatura.

## 15. Observabilidade, rollback e segurança

Medir eventos por transporte, presença do novo ID, correspondências, conflitos, duplicidades evitadas, pendências, atraso e falhas de envio. Para mídias: ingestões, downloads/PUTs evitados, bytes originais/derivados, retomadas, conflitos e objetos/blobs órfãos. Registrar identificadores de correlação com retenção/controlos adequados, sem conteúdo pessoal ou segredos desnecessários.

Vínculo desligado não deve apagar aliases nem mensagens. Definir corte de desligamento e destino de eventos pendentes; não redistribuir jobs já enfileirados para outro transporte. Rollback não desfaz envios já realizados e não deve reabrir duas automações para o mesmo atendimento.

Migrações futuras devem ser compatíveis com rollback da aplicação; não remover campos ou dados usados pela versão anterior durante o piloto. Conferir backups recuperáveis antes de qualquer operação de migração/conciliação em produção.

## 16. Checklist de retomada após P1/P2

1. Ler o estado atualizado das seções 1, 4.4 e 5.4; reconferir branches, alterações de outros contextos e o commit ViperConnect `b1668845`. Não refazer P1 nem reprocessar os testes reais já comprovados sem necessidade/autorização.
2. No ViperChat, inventariar a ingestão comum, echoes, status, referências e overlays Enterprise antes de definir a persistência aditiva. Preservar `source_id`, IDs internos, mídias e APIs legadas.
3. Implementar a seção 6 primeiro em dev: campo opcional, identidade/origem/escopo, idempotência, eventos antigos sem o campo e recebimento fora de ordem; registrar conflitos sem fundir ou esconder mensagens. Criar adaptador Meta isolado/testado, sem assumir que qualquer `wamid` é decodificável.
4. Validar isolamento entre contas/caixas, ausência de novos envios/automação duplicada e preservação de UUID/`wamid`. Contatos distintos e BSUID-only continuam requisitos de observação/resolução, não autorização de mescla histórica automática.
5. Apresentar evidências dev antes de qualquer migração/deploy ViperChat na VPS. P3 segue pendente e exige sua própria publicação/deploy e retirada do hostpath.
6. Antes de cada recurso posterior da unificação, completar sua matriz Meta/ViperConnect: IDs, restrições, seleção persistente nos dois editores e roteamento por capacidade sem fallback após falha/timeout. Respeitar a seção 2.2, mantendo Meta direto e sem incluir gateway nesta entrega.

Nenhuma senha, token ou segredo operacional deve ser acrescentado a este documento, scripts, commits ou evidências.

## 17. Incremento de implementação em dev — 16/10/2026

Trabalho em `feat/whatsapp-unified-inbox-dev`, separado da `4.16.0`. Esta seção descreve código e testes locais, **não uma release aprovada nem um deploy na VPS**. Os vínculos das caixas existentes no dev permanecem desligados; nenhum histórico foi mesclado.

### Implementado neste incremento

- Vínculo administrativo explícito, desligado por padrão, com principal Meta ou ViperConnect, transporte padrão independente, corte de ativação, prévia de conflitos e confirmação assinada. Endpoints sob a autorização de gestão de caixas da conta; a permissão na parceira não concede acesso ao histórico da principal.
- Reserva durável PostgreSQL antes da ingestão/download dos eventos elegíveis, aliases por transporte, lease com token de propriedade e recuperação de bolha já persistida. O `provider_message_id` correlaciona; os IDs públicos/operacionais não são substituídos.
- Ingestão única de texto, imagem, áudio e PDF exercitada com fixtures sanitizadas derivadas dos formatos reais coletados. Matriz: ambas as principais, ambas as ordens de chegada, repetições, echoes, status antecipado, oitavo/nono dígito, conflitos e isolamento de conta. Não há chamada externa real nos testes.
- Seletor compartilhado antes da bifurcação compacto/completo, preferência e rascunhos por transporte, destino Web e notas privadas independentes. Seleção enviada explicitamente ao backend e revalidada antes do envio.
- Envio por transporte efetivo e referências com seu alias operacional; roteamento por capacidade antes da tentativa, sem troca automática após erro/timeout. Janela Meta calculada pela evidência de recebimento Meta, não pelo fato de a mensagem ocupar uma caixa principal Meta.
- Configuração de vínculo nas preferências da caixa. Conferência do componente real com APIs simuladas em 320, 360, 390, 412, 430, 844 (paisagem) e 1280 px: sem overflow horizontal dos controles. Isso não substitui a aceitação do editor completo autenticado com teclado/aparelho.

### Evidências e limites do aceite

- Regressão Ruby do incremento inicial: 685 exemplos, zero falhas. A rodada posterior de BSUID-first, mídias e desunificação é descrita na seção 18, com seu próprio resultado; não somar contagens de rodadas sobrepostas.
- Frontend do incremento inicial: 140 testes aprovados em nove arquivos (incluindo PIX e os dois editores), sem tratar teste unitário como envio real. Este segundo incremento é de backend, sem mudança adicional de layout ou bundle nativo.
- Bundles Android/iOS regenerados e Android Debug compilado. Não havia dispositivo ADB conectado; Mac de desenvolvimento indisponível. Não afirmar teste nativo em aparelho, Archive iOS, assinatura de release ou publicação.

### Bloqueios para promover a release/piloto

1. O novo fluxo BSUID-first aguarda em banco sem criar contato/bolha especulativos, resolve o alias pelo original comprovado e preserva o cadastro antigo. A interface administrativa foi concluída em dev na seção 19; falta o aceite manual do administrador. A nova regra não autoriza mescla histórica ou reparo indiscriminado de duplicados antigos.
2. Reconciliação excepcional de mídias já persistidas implementada em dev, com prioridade à principal, referências preservadas e limpeza pós-commit com nova verificação no job de exclusão. Validar no storage e no piloto autorizados; os testes de objetos usam DiskService sintético, não exclusões no S3 real.
3. Echo antecipado e resultado incerto possuem espera/claim persistidos. A concorrência com duas conexões PostgreSQL foi exercitada, mas não substitui teste de carga com processos Sidekiq separados, reinícios e serviços externos reais no piloto.
4. Completar a matriz das demais capacidades/eventos (inclusive contatos múltiplos), aceitação integrada dos dois editores e automações/notificações. Exclusão remota não é anunciada: o endpoint atual é remoção local. O bloqueio inicial do agendamento vinculado foi substituído pela persistência e revalidação descritas na seção 20.
5. Validar a UI autenticada, teclado/áreas seguras, Android/iOS e custos conforme a seção 12 antes de apresentar uma release funcional de produção. Nenhuma economia é prometida a partir dos testes sintéticos.

O avanço continua seguindo este plano; não reduzir silenciosamente os critérios acima para declarar a unificação concluída. Deploy/hostpath na VPS, ativação em conta real, conciliação de contatos e limpeza de mídia persistente exigem a etapa de aprovação correspondente.

## 18. BSUID-first, mídias tardias e echo antecipado — segundo incremento dev

### Comportamento implementado

- `WhatsappUnifiedEvent` guarda o evento ainda não identificável, separado da fila de conversas. Primeiro retry após 15 segundos; novas identidades/aliases compatíveis podem antecipar a tentativa. Sem nova evidência, há backoff e limite de 12 tentativas, depois revisão persistente. Repetição não cria outro contato, bolha, download ou novo job inicial. Payload não é registrado em logs e é limpo da pendência concluída.
- BSUID sem alias/telefone aguarda sem contato provisório. A chegada da contraparte com original exato, empresa, direção e participante compatíveis permite reutilizar o contato antigo e acrescentar o alias BSUID, preservando telefone, nome, LID, IDs internos e IDs públicos anteriores. Conflitos ficam em revisão; nome, conteúdo ou proximidade temporal não identificam uma pessoa.
- Echo durante envio ainda sem resposta aguarda em vez de criar outra bolha. O UUID/`wamid` retornado pela API e seu alias são persistidos na mesma transação. O replay adota a bolha otimista somente pela identidade exata, mesmo com rascunhos/mensagens semelhantes pendentes.
- Claim de envio persistido antes da chamada externa impede que concorrência/retry repita automaticamente um envio de resultado incerto. Preferência e executor permanecem registrados; timeout não autoriza outro transporte. O resultado incerto exige conferência/revisão, não confirmação fictícia de entrega.
- Duas cópias de mídia comprovadas e posteriores ao corte são reconciliadas para o arquivo da principal: imagem, áudio, vídeo, figurinha e documento. Preservam-se `Message.id`, `Attachment.id`, associação AS e IDs públicos; o blob secundário redundante pode ser substituído. Rotas por mensagem/anexo permanecem utilizáveis; URLs temporárias do blob antigo podem precisar de atualização, como em sua expiração normal.
- Exclusão é agendada somente após commit. Referências AS, variantes, figurinhas e anexos de agendamento (inclusive IDs assinados em JSON) são verificadas na reconciliação **e novamente na execução da exclusão**. Blob compartilhado não é apagado. Rollback não agenda purge; retry de purge é idempotente. A bolha existente recebe atualização de mídia, sem novo evento de criação ou reenvio da mensagem.
- Arquivo principal temporariamente indisponível não provoca remoção da secundária; o job tem cinco retentativas adicionais, espaçadas em 30 segundos. Combinação ambígua ou escopo inválido não autoriza limpeza.
- Desunificação segue a seção 7.4: histórico permanece na antiga principal; novos envios seguem cada caixa; status/contrapartes tardias continuam identificando as mensagens antigas; pendências invalidadas ficam em revisão. Reativar não ressuscita envios preparados antes do novo corte.

### Validação executada

- Regressão ampla: **838 exemplos Ruby, zero falhas**. Depois dos últimos ajustes, rodada focada: **69 exemplos, zero falhas** (32 desunificação e 37 mídias). As rodadas se sobrepõem: não somar esses números como testes distintos.
- RuboCop: 46 arquivos da alteração, sem infrações.
- `script/validation/whatsapp_unified_concurrency.rb`: quatro cenários com duas conexões PostgreSQL independentes, principal Meta/ViperConnect e entrada/echo simultâneos. Cada cenário manteve uma mensagem, um contato e dois aliases. Execução protegida por ambiente e nome exato do banco sintético.
- Scripts anteriores de identidade/correlação, BSUID e pendência reexecutados com sucesso em banco isolado, incluindo rollback/reaplicação das tabelas aditivas na ordem das dependências.
- Arquivos utilizados nos testes de reconciliação/exclusão são sintéticos em DiskService temporário; não foram excluídos uploads reais nem objetos do S3. Os cenários de erro de download, referência compartilhada criada depois do enqueue, rollback e retry foram exercitados.

### Limites para release

O código está no dev e permanece opt-in, com as caixas existentes desligadas para este recurso. Ainda faltam a experiência administrativa de revisão/resultado incerto, a matriz restante de capacidades e agendamento vinculado, aceite integrado dos editores/aparelhos e carga/piloto autorizado com serviços reais. Não há novo APK/Archive ou validação nativa neste incremento de backend. Nenhuma alteração foi aplicada à VPS, nenhum contato antigo foi mesclado e nenhuma publicação foi realizada.

## 19. Revisão administrativa e aceite integrado — terceiro incremento dev

### Entrega disponível para testar

Em **Configurações → Caixas de entrada → caixa vinculada → Caixa unificada / Coexistência → Revisão administrativa**, o administrador pode filtrar os casos por identificação/eventos, entrega incerta, mídias e reservas retidas sem mensagem canônica. Há paginação e filtros de aguardando revisão, revisados e todos. O painel existe para vínculos persistidos, inclusive desativados; antes de salvar um vínculo não há casos desse vínculo para revisar.

- **Reavaliar evidências:** agenda apenas o processamento seguro do evento ou a verificação da mídia. Não chama o provedor para reenviar, não inventa um alias e não associa contatos manualmente. Ausência de evidência ou conflito pode manter a pendência. Exige vínculo/corte vigente; reservas sem payload e envios incertos não oferecem essa ação.
- **Marcar revisado:** registra a conferência administrativa, sem concluir a quarentena, liberar o caminho legado ou confirmar entrega. O mesmo envio incerto continua incerto. Evidência alterada depois da conferência faz o caso voltar ao filtro de aguardando revisão.
- A confirmação da ação inclui uma revisão otimista do registro e da ativação. Uma confirmação obsoleta recebe HTTP 409 e a interface atualiza a lista. Duplo clique/repetição da mesma versão não cria outra decisão válida.
- Auditoria persistida separadamente em `WhatsappUnifiedReviewAction`: vínculo, tipo/ID do objeto, versão temporal, ação e autor. Não persistir conteúdo do webhook nessa auditoria.
- A listagem expõe apenas diagnóstico técnico: motivo, estado, IDs, datas, tentativas e referências à conversa. Payload bruto, credenciais e configuração do provedor não são devolvidos. Havendo conversa canônica, o atalho usa o número público da conversa; as políticas normais continuam valendo.
- Restrições na conta, autorização administrativa e permissão de atualizar **ambas** as caixas são verificadas em todos os endpoints. Permissão em apenas um transporte não dá acesso à revisão do par.
- O resultado da verificação de mídias agora fica persistido no ledger para aparecer na revisão. A preferência pela mídia principal e as verificações anteriores de segurança/exclusão permanecem obrigatórias.

Endpoints autenticados, relativos a `/api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_link`:

| Método / rota | Uso |
| --- | --- |
| `GET reviews` | Filtros `kind=event/delivery/media/reservation`, `status=open/acknowledged/all`, `page`. Retorna `items` e `meta`. |
| `POST reviews/:id/recheck` | Corpo `{ "version": "valor recebido na listagem" }`. Somente ações permitidas no registro. |
| `POST reviews/:id/acknowledge` | Mesmo controle de versão; registra conferência, nunca recibo de entrega. |

Os identificadores de revisão têm namespace (`event-…`, `delivery-…`, `media-…`, `reservation-…`). Eles não substituem IDs internos de mensagens nem UUID/`wamid` de operação.

### Evidências desta rodada

- **498 exemplos Ruby, zero falhas e zero pendências**, cobrindo revisão/API, ingestão, mídia, echoes, desunificação e regressões selecionadas. Rodada focada de revisão: 64 exemplos aprovados, sobrepostos à rodada maior; não somar contagens.
- **126 testes de frontend, oito arquivos, aprovados**, incluindo revisão, configuração, seletores, rascunhos e editores compacto/completo. RuboCop dos arquivos de produção deste incremento sem infrações; ESLint sem erros. Avisos de dependências/sourcemap e traduções dinâmicas não foram tratados como teste funcional.
- Migração aditiva `20261016000006`: aplicada no dev; aplicação, rollback e reaplicação exercitados na base descartável, nunca revertida na réplica de trabalho.
- Aceite **autenticado na página real**, com conta e caixas temporárias sem envios externos: reavaliação solicitada pela interface, execução no worker, auditoria de revisão de entrega incerta e conferência independente no PostgreSQL. Nenhum novo envio nem alteração de `source_id`/recibo a partir da revisão.
- Atalho abriu a conversa canônica. Seleção Meta permaneceu ao trocar o editor clássico pelo compacto via configuração da conta; o retorno à ViperConnect recuperou seu rascunho. Janela Meta fechada permaneceu bloqueada, sem troca silenciosa para o parceiro. Não foi realizado envio real a um cliente.
- Página real conferida em **320, 360, 390, 412, 430, 844 (paisagem) e 1280 px**. Corrigido o grid pai das configurações, que alargava a tela mobile apesar de o componente isolado caber. Controles e IDs longos agora ficam dentro do viewport, com rolagem vertical acessível. Emulação não comprova teclado/área segura em aparelho físico.
- Bundles Android/iOS regenerados e sincronizados com o mesmo `index.html` (SHA-256 `aff9d17a5f51fd85b0df364660ba2d1ac2352f68f69d73c6f5e5053cd1be9306`). **Android Debug compilado**, com hash do índice dentro do APK conferido. Nenhum dispositivo em `adb devices`; sem instalação/teste físico. Mac de desenvolvimento indisponível: **sem compilação/Archive/teste iOS**.
- Conta, contatos, caixas, mensagens e usuários sintéticos removidos após o teste; base descartável e relatório temporário removidos. Fontes, specs, runner de aceite e capturas pequenas de evidência preservados. Bundles/APK de validação e intermediários nativos anteriores foram preservados; não houve prune de caches/volumes ou remoção de uploads reais. SSD ao final: aproximadamente 56 GiB livres, sem alegar recuperação líquida de espaço nesta rodada.

### Roteiro do aceite manual e limite da release

1. No dev, abra uma caixa Uno/Meta e configure o par desejado, com principal e padrão explícitos. Gere a prévia, revise conflitos e confirme antes de ativar. As caixas reais não foram ativadas pelo agente.
2. Acesse **Revisão administrativa**. Sem ocorrências, o estado vazio é esperado. O runner `script/validation/whatsapp_unified_admin_dev.rb` documenta fixtures isoladas para repetir o aceite, bloqueando HTTP de provedores durante criação/limpeza; suas contas temporárias não devem virar caixas operacionais.
3. Em uma ocorrência sintética, confira tipo/motivo/IDs, confirme a reavaliação e atualize a lista. Marque revisado, alterne para o filtro Revisados e confirme que isso não muda entrega nem libera uma identidade conflitante.
4. Confira os dois editores, o transporte selecionado e a manutenção dos rascunhos. Não usar envios reais como teste de capacidade seguido de fallback.

A **interface administrativa está pronta para aceite em dev**. Isso não encerra silenciosamente os gates restantes das seções 17–18: matriz completa de capacidades/eventos, envios reais, storage/pico, custos e validação física/nativa ainda têm seus aceites próprios. O agendamento vinculado foi completado posteriormente em dev na seção 20. Não houve commit/push, publicação de imagem/release, mudança na VPS, fusão histórica de contatos ou ativação de caixas reais nesta etapa.

## 20. Agendamento vinculado e compatibilidade nativa — 17/10/2026, somente dev

### Intenção persistida e entrega

- Migração aditiva `20261016000007`: JSONB `whatsapp_transport` no agendamento e em cada item. Não altera IDs, contatos, horários ou caixas existentes. Registros anteriores permanecem com objeto vazio até edição ou processamento; listar não escreve no banco.
- O modal do editor e a agenda exibem o transporte escolhido, independentemente do seletor de novos envios. Abrir o modal copia a escolha do editor; alterar o agendamento não muda o editor. A agenda mostra o solicitado, o executor por item e a origem legada quando aplicável.
- A intenção contém vínculo, geração/corte de ativação, provedor solicitado, caixa e origem da seleção. Cada item captura também seu executor efetivo e capacidade antes do despacho. Mudanças posteriores no padrão da caixa não redirecionam o agendamento.
- Recursos incompatíveis seguem a matriz de capacidades **antes da tentativa**, com executor registrado. Mudança posterior de geração, executor ou autorização interrompe o fluxo para revisão. A janela da Meta é conferida no envio real; agendar não garante que ela estará aberta e não transforma texto em template.
- A conversa de destino pertence à caixa principal, preservando contato e aliases; respeita conversa única e atribui o operador escolhido. Caixas sem vínculo e sem seleção explícita mantêm seu fluxo anterior.
- Captura de registros antigos já vencidos grava somente os metadados internos de transporte antes de alterar estado/abrir conversa, sem esbarrar na validação de data futura da criação. O estado editável é revalidado dentro do lock.
- Evidência de despacho impede substituir itens ou reiniciar parcialmente a sequência. Timeout, resposta sem identificador ou entrega incerta interrompem a sequência, sem reenvio/fallback automático. Falha tardia não rebaixa item já confirmado ou agendamento concluído/cancelado. Os dez segundos entre itens confirmados permanecem.
- Anexos do agendamento são reutilizados pelo MessageBuilder: os testes verificam o mesmo blob, sem segunda gravação do arquivo. A reconciliação de contraparte continua regida pela seção de mídias.

### Apps antigos e API

Clientes novos enviam, dentro de `scheduled_message`, apenas a seleção pública opcional:

```json
{
  "scheduled_message": {
    "whatsapp_transport": "whatsapp_cloud"
  }
}
```

Esse fragmento complementa os demais campos obrigatórios normais. Valores aceitos: `unoapi` e `whatsapp_cloud`. Hashes internos, valor desconhecido, vazio ou nulo explícito recebem 422; não se aceita injetar metadados de vínculo pelo cliente. A resposta expõe o objeto persistido e as opções disponíveis, portanto o formato de resposta não é o formato de escrita.

Apps antigos que omitem o campo continuam agendando. Em caixa vinculada, o backend fixa **o provedor da caixa original** (`legacy_inbox`), não o padrão mutável do vínculo. O mesmo vale para agendamentos anteriores ainda sem captura. Uma edição antiga sem o campo preserva uma seleção já persistida. Essa política é específica do agendamento e não redefine o seletor de mensagens imediatas. Sem vínculo, o campo permanece vazio e o comportamento anterior continua.

Desativar/reativar ou trocar o vínculo invalida snapshots anteriores para revisão; não ressuscita o transporte antigo. Um agendamento ainda não despachado pode ser editado e confirmado explicitamente; parcial ou incerto não pode ser convertido em um novo envio por essa edição.

### Evidências e limites

- Backend: 363 exemplos, zero falhas/pendências; rodada final sobreposta de 72 exemplos após endurecer captura vencida/lock, também aprovada. Frontend: 40 testes focados em quatro arquivos aprovados; a rodada anterior ampliada do frontend teve 63 aprovados. Não somar rodadas sobrepostas.
- Matriz sintética com principal Meta e ViperConnect, ambos os transportes, cliente antigo, agendamento anterior, alteração do padrão, desativação/reativação, permissão revogada, sequência/timeout/recibo incerto, janela Meta fechada e arquivos imagem/áudio/PDF em storage temporário. Sem chamadas externas aos provedores.
- Aceite autenticado em conta descartável: registro legado exibido na agenda e editado para Meta; um novo agendamento futuro foi criado pelo modal do editor com Meta explícita. Banco conferido nos dois casos, inclusive transporte do item. O editor permaneceu em ViperConnect. Agenda e modal sem overflow horizontal em 320/360/390/412/430/844/1280 px. Teclado e áreas seguras ainda exigem aparelho físico. Avisos locais de WebSocket e rota Enterprise de limites 404 não foram tratados como aceite de tempo real.
- Migração revertida/reaplicada somente na base isolada de teste; base dev recebeu apenas aplicação aditiva. Fixtures e base isolada são removidas ao concluir; a caixa Meta de teste solicitada na conta 1 é preservada.
- Bundles Android/iOS regenerados e sincronizados. APK debug Android compilado com sucesso; `index.html` do APK e dos dois projetos tem SHA-256 `07ba22b35171f2a243ef34835991d4988baeb04838ab9057ca338764a6809c70`. Sem Android conectado nesta rodada; Mac indisponível para compilar Archive iOS.
- Para distribuir o seletor e a nova UI aos usuários, serão necessárias novas builds Android/iOS, incremento de versão/build, assinatura e publicação separadas. O APK desta rodada é debug, não release/AAB; o bundle iOS sincronizado não equivale a Archive/TestFlight. Backend compatível com apps antigos não exige bloqueá-los.

Worker dev recarregado após a migração e sincronização do código; API HTTP 200. Fixtures administrativas temporárias removidas, caixa Meta de teste 192 preservada. Nenhuma aplicação na VPS, commit/push, publicação de imagem, loja ou ativação de caixa real foi executada nesta etapa. Persistência local não substitui piloto autorizado em produção nem os demais gates do plano.

### Caixa Meta simulada disponibilizada por solicitação posterior

Na conta **1**, foi criada e preservada para o teste manual a caixa **192 — Meta teste DEV — Viper Tec (sem conexão)**, parceira compatível da **1 — Viper Tec**. Ela representa o mesmo número empresarial `5566996222471`, sem token de API, ID de telefone Meta ou WABA e sem configuração externa de webhook. A criação bloqueou HTTP de provedores e manteve os jobs de callbacks no adaptador de teste, sem despachá-los ao worker. O vínculo não foi ativado. A caixa ViperConnect original não foi editada.

O campo telefônico global é único pela grafia bruta; a caixa simulada usa os mesmos dígitos sem o `+`, já aceitos pelo comparador, enquanto a original conserva seu valor completo. Não houve mudança de índice ou relaxamento da validação do produto. O runner idempotente e restrito ao dev está em `script/validation/create_meta_partner_dev.rb`. Não executar na VPS. Essa caixa permite testar configuração/seleção, **não envios reais pela Meta**.

Quando não há parceira elegível, o dropdown agora mostra **Nenhuma caixa compatível disponível**, fica desabilitado e explica os requisitos de provedor, conta, número, acesso e vínculo. Foram aprovados 13 testes focados de configuração, incluindo presença/ausência do aviso; o estado vazio do componente foi conferido no navegador em 320–430 px, paisagem e desktop. A consulta real do controller, com contexto administrativo da conta 1, retornou a caixa 192 como candidata.

Regressão conjunta de configuração e revisão: **51 testes aprovados**. Bundles Android/iOS novamente sincronizados; Android Debug recompilado com sucesso e índice dentro do APK conferido (SHA-256 `29db24d25887cdd574e2258aade71e08fcc8b392c5b6d732698ac2bb80e36b0a`). Sem dispositivo ADB e sem Mac acessível, não houve teste físico nem compilação iOS. Logs intermediários descartáveis removidos; caixa 192 e evidências/fontes de validação preservadas por serem a entrega solicitada. Aproximadamente 56 GiB livres no SSD. Sem mudança na VPS, ativação do vínculo, commit ou push.

## 21. Preparação de implantação direta pelo Portainer — 17/10/2026

Autorizada a implantação do commit `b829f34ee`, com backup prévio e unificação desligada. **A atualização da stack não foi concluída:** login e leituras no Portainer funcionaram, mas `PUT /api/stacks/24?endpointId=3` respondeu HTTP 403. Não houve nova tentativa ou contorno por Docker Compose/CLI. É necessário esclarecer/liberar a operação no Portainer antes de continuar.

- Imagem compilada do commit, frontend de produção incluído, transferida e carregada diretamente na VPS como `viperchat:unified-b829f34ee`. ID no Docker da VPS: `sha256:3e2feb7c0921fe2a898d45ff2e9ca89df17114745ae6bcfcb23b8d872a0f778e`. Sem workflow, push de Git ou publicação em registry. Esse tag é **local**; não ativar pull forçado enquanto não existir publicação correspondente.
- Conferidos commit embarcado e 248 entradas no manifesto de assets. Pacote de transferência de 713.939.968 bytes validado por SHA-256 `e5b4e43a8fea8d07029df87998181d291e6291abfce3c122c610af0b66f79bdb` antes do carregamento; intermediário removido após a confirmação da imagem.
- Backup privado em `/var/snap/docker/common/viperchat-deploy/unified-b829f34ee-20261017`: `database.dump` de 247.242.102 bytes, índice pg_restore conferido, SHA-256 `9b16bd011ec5132821e7d59a8bfe7e752034ad6fa5e5da471f30f3d013c9ed68`; stack original Portainer, configuração efetiva do piloto, inventário dos containers e cópias/hashes dos nove overlays de código. Diretório 0700, arquivos 0600.
- Configuração proposta mantém ambiente e comando dos serviços reais e dois workers. Modifica somente as imagens do web, worker e serviço de migração. O Portainer original não tinha os overlays; a execução real os recebia pelo compose externo do piloto. A proposta elimina essa sobreposição, mas **não foi aplicada**. ViperConnect, PostgreSQL, Redis e push relay ficam fora da alteração.
- `portainer-stack-rollback.yml` preserva a imagem antiga e recompõe os nove mounts no web/worker. `ROLLBACK.md` separa rollback de imagem de restauração de dados; não restaurar dump nem reverter migrações automaticamente sobre tráfego posterior ao backup.
- Antes da tentativa, os dois workers receberam TSTP; ambos foram conferidos sem jobs ocupados. Depois do 403, foram reiniciados com a imagem/configuração anteriores para restabelecer o consumo. Web e dois workers permanecem em `v4.16.12-viper.31-ce`, com os nove hostpaths originais. API interna e pública HTTP 200.
- Banco permaneceu em `20261016000001`; a tabela de vínculos ainda não existe. Não foram aplicadas as migrações 2–7, criados vínculos, mesclados contatos ou alterados os envios para o transporte unificado. Evidência resumida: `deployment-blocked.json` no diretório privado de recuperação.

A imagem e o pacote de recuperação permanecem disponíveis para retomar após a liberação da operação no Portainer. O frontend novo **ainda não está publicado na instalação**. Esta anotação não equivale a implantação concluída.

## 22. Revisão das primeiras mensagens do vínculo — 17/10/2026

Após a atualização manual pelo administrador, a inspeção **somente leitura** encontrou web e dois workers executando `viperchat:unified-b829f34ee`, com o vínculo 1 ativado. Isso atualiza o estado observado, sem reescrever o histórico da tentativa bloqueada na seção anterior. As correções abaixo são posteriores à imagem e ficam **somente em dev**, sem implantação ou reparo de dados na VPS nesta etapa.

### Evidências e correções

- Imagem original `3AA533555760F1AA23B3`: Meta às 01:14:11 e ViperConnect às 01:14:12 (America/Cuiaba). As duas identidades apontam para uma única mensagem, um Attachment e um blob. A origem real é a Meta; a mensagem canônica está na caixa principal. Não houve segunda transferência/gravação.
- O alerta `principal_unavailable` nesse caso esperava uma segunda cópia que a ingestão única deliberadamente não cria. Com as duas identidades confiáveis e apenas um arquivo canônico acessível, o reconciliador retorna `unchanged / single_copy_retained`. Preserva a origem real, todos os IDs e os bytes existentes. Se duas cópias físicas realmente existirem, continua valendo a preferência pela mídia da principal e a remoção segura da secundária após commit.
- Enquanto existe apenas uma identidade válida, a reconciliação aguarda a contraparte (`counterpart_pending`), sem classificar automaticamente como conflito. Evidências contraditórias continuam exigindo revisão; ausência do arquivo continua pendente, sem fabricar confirmação.
- Áudio original `3A004C30BA8EF3C134BF`: o recibo `delivered` precedeu a mensagem recebida; posteriormente chegou um echo sem tipo/conteúdo e sem destinatário. Esse evento parcial estava sobrescrevendo a direção/remetente da identidade. A observação passa a ignorar mensagens/echoes sem tipo; recibos continuam processados. Um recibo cujo destinatário corresponde ao remetente conhecido da mensagem recebida não muda a direção nem constitui conflito. Divergência real de participante ou echo tipado contraditório continua bloqueada.
- Não se apagam conflitos históricos automaticamente: a identidade já contaminada e os alertas existentes na VPS permanecem intocados. Eventual saneamento exige análise/reprocessamento auditável separado, sem reenviar mensagens.

### Interface

- A revisão agora se apresenta como painel de exceções técnicas, não como aprovação obrigatória de cada mensagem. Motivos e orientações ficam legíveis; identificadores e tentativas ficam em detalhes recolhíveis.
- **Reavaliar evidências** solicita nova análise, sem prometer resolução. **Marcar revisado** apenas registra a análise humana; não confirma entrega, corrige a causa ou aprova um arquivo. Nenhuma das ações reenvia mensagens ou mescla contatos.
- No editor compacto, o agendamento permanece no menu **+**: removido o atalho externo redundante sob o seletor de transporte. O editor completo conserva seu botão, e o atalho de teclado não muda.

### Validação local

- Matriz sintética inicial de ingestão/reconciliação: 99 exemplos aprovados, incluindo imagem/áudio/PDF, principal Meta ou ViperConnect, duas ordens de chegada, recibos antecipados e echo parcial. Confere uma mensagem/arquivo/blob, ausência de purge e preservação dos IDs.
- Painel real com API sintética sem escritas: detalhes fechados/abertos sem overflow em 320/360/390/412/430 px, paisagem 844 px e desktop 1280 px. Essa verificação não comprova teclado ou áreas seguras em aparelho físico.
- Regressão final: **341 exemplos Ruby aprovados**, incluindo correlação, observação, ingestão, mídias, revisão, desvinculação, capacidades e serviços de agendamento. **107 testes frontend aprovados**, incluindo a ausência do botão externo no compacto e sua ação no completo. RuboCop sem infrações nos seis arquivos backend/specs conferidos; ESLint sem erros (12 avisos de chaves de tradução dinâmicas).
- Bundles Android/iOS regenerados e sincronizados. Android Debug compilado; o índice dentro do APK coincide com Android e iOS por SHA-256 `0897dea8363b65b0d1ffd7a90ef223f1c141fc89743128c5218b4478003237b4`. Sem dispositivo ADB e sem Mac acessível, não houve instalação/teste físico nem compilação iOS. APK de validação preservado, sem upload ou publicação.
- Nenhum envio real aos provedores, alteração de IDs, mesclagem de contatos ou aplicação destas correções na VPS. Dados de produção e conflitos históricos permanecem intocados.
- Limpeza: removidos o banco isolado `viperchat_review_fixes_test` (24 MB, sem sessões), relatórios/logs temporários e os artefatos descartáveis desta verificação visual. Banco normal e volumes preservados; APK e assets nativos mantidos como entregáveis. SSD com aproximadamente 49,16 GiB livres; artefatos antigos de origem/remoção previamente bloqueada não foram tocados. Worker dev reiniciado após conferir zero jobs ocupados; API dev HTTP 200 e containers ViperConnect mantidos ativos.

## 23. Correções publicadas no Git e hostpath preparado — 17/10/2026

Commit `a9eec45e014621b374f066084be47aef09aaa658` publicado em `origin/feat/whatsapp-unified-inbox-dev`, incluindo a implementação anterior `b829f34ee`. Não houve integração na branch `4.16.0` nesta etapa.

O usuário solicitou aplicação **via hostpath**, sem trocar a imagem. Pacote e recuperação preparados em `/var/snap/docker/common/viperchat-hostpaths/review-a9eec45e0-20261017`. **Aplicação bloqueada:** `PUT /api/stacks/24?endpointId=3` retornou novamente HTTP 403, apesar do login administrativo e das leituras funcionarem. Não foi tentada implantação alternativa por Compose/CLI.

- Backup PostgreSQL em `database.dump`, com índice pg_restore conferido; SHA-256 `bae81d6abb2e7e0f5b60663632199a6e2859858d88a08736a9c0fcada78db044`. Stack e inventário originais privados preservados. Não houve ensaio de restauração.
- `stack-after.yml` acrescenta somente quatro mounts read-only ao web e serviço de workers: os três serviços Ruby de observação/correlação/reconciliação e `/app/public/vite`. Prévia normalizada conferiu que imagem-base `viperchat:unified-b829f34ee`, ambiente, comandos, réplicas e serviços não relacionados não mudam. Não há migração.
- Frontend de produção compilado em saída isolada: 248 entradas de manifesto, 257 arquivos referenciados, nenhum ausente. `vite/` inclui assets da imagem anterior mais os novos para preservar URLs de páginas abertas. Pacote transferido e conferido por SHA-256 `7e9e70d2e5322b705efd4781ea3122d66a639660f92c5ec2d475dfad8303fdbf` (17.725.319 bytes); arquivos Ruby e manifesto conferidos individualmente.
- Antes da tentativa os dois workers foram pausados com TSTP e conferidos sem jobs ocupados. Após o 403, a retomada é feita apenas reiniciando os dois workers na configuração anterior; isso não instala o hostpath.
- Recuperação conferida: web e dois workers em execução na imagem anterior, **zero mounts**, API HTTP 200. Os três hashes de IDs históricos, mídia e vínculo permaneceram idênticos à prévia. Nenhum dos hostpaths propostos foi ativado.
- IDs históricos, arquivos/IDs das mensagens de imagem/áudio verificadas e configuração do vínculo foram registrados por hashes em `validation-before.json`. Não houve backfill, reprocessamento, purge, mesclagem ou mudança dos volumes Active Storage/S3.

Para prosseguir, liberar/esclarecer a autorização de atualização no Portainer ou aplicar manualmente o `stack-after.yml` pela interface autorizada, sem pull nem prune. `ROLLBACK.md` distingue retirar os mounts de restaurar dados; não restaurar o banco automaticamente sobre tráfego posterior. O código corrigido **ainda não está ativo em produção**.

## 24. Hostpath aplicado no Docker por SSH — 17/10/2026

Depois da negativa descrita na seção 23, o usuário autorizou explicitamente: **“aplica via ssh” / “no docker igual estávamos fazendo antes”**. A execução abaixo corresponde a essa nova autorização, não a uma atualização bem-sucedida pela API do Portainer.

```bash
docker compose -p chatwoot-uno \
  -f /var/snap/docker/common/viperchat-hostpaths/review-a9eec45e0-20261017/stack-after.yml \
  up -d --no-deps --no-build --pull never chatwoot-web chatwoot-worker
```

- Comparação adicional com os containers existentes: ambiente e comandos idênticos; duas réplicas do worker preservadas. Workers pausados e zero jobs ocupados antes da recriação. Somente web e dois workers foram recriados, iniciando por volta de 01:52:56 (America/Cuiaba).
- Os quatro mounts read-only estão ativos nos três containers, preservando a imagem `viperchat:unified-b829f34ee`. Hashes dos três serviços Ruby e do manifesto são iguais ao pacote aprovado em todos os containers. Manifesto SHA-256 `0c0923ce8cd724c8235e6247ac4148450534d79cf62450b7536b37eb3aef4ce2`.
- `validation-after.json`: sucesso, migrações inalteradas (`20261016000007`), hashes dos IDs históricos e das mídias verificadas idênticos, vínculo ativo sem mudança e containers ViperConnect/PostgreSQL/Redis/push relay preservados. Web e dois workers ativos, zero reinícios inesperados e workers fora do modo quiet.
- API interna HTTP 200. Manifesto com 248 entradas e 257 arquivos referenciados, nenhum ausente. JavaScript dashboard/v3app e CSS dashboard servidos com HTTP 200; HTML de login referencia o manifesto novo. O primeiro probe ocorreu durante o boot e recebeu reset de conexão; a conferência foi repetida após inicialização e passou.
- Não houve migração, envio de teste, reprocessamento/backfill, limpeza de conflitos anteriores, alteração de IDs, mesclagem ou escrita/purge de mídia pelo procedimento. Alertas antigos não são apagados automaticamente.
- Backup, stack anterior, stack efetiva, hashes, código montado, assets e rollback permanecem no diretório privado da seção 23. Intermediários de transferência/extração na VPS foram removidos após conferir os hashes; os assets antigos continuam junto dos novos para páginas abertas.

**Atenção operacional:** o Portainer ainda mantém seu arquivo anterior sem os mounts. Antes de uma nova implantação pelo painel, incorporar os mounts do `stack-after.yml` ou substituí-los por uma imagem que contenha as correções. Uma reimplantação sem essa reconciliação pode desfazer o piloto. Para rollback somente de código, `ROLLBACK.md` documenta a aplicação da stack anterior via Docker; não restaurar o banco automaticamente.

## 25. Echo da parceira após envio pela Meta — correção somente em dev, 17/10/2026

### Evidência e causa

Inspeção anterior somente leitura identificou a mensagem Meta `2489761` e o echo ViperConnect `2489762` com o mesmo original `CE550277C18EADC4F0ED`; a consulta diagnóstica retornou `matched`. O alias da resposta da API já apontava à mensagem do operador, porém a ingestão do echo da parceira não o adotava antes de criar uma nova bolha. O texto assinado do echo não é critério de identidade. O caso foi reproduzido com teste sintético que falhou por criar a segunda mensagem antes da correção.

### Comportamento corrigido

- Após a API Meta responder, o adaptador reconhecido registra o original e a evidência de saída com origem `api_response`. Isso ocorre junto do registro do alias, na transação do envio, sem esperar um recibo e sem inventar status de entrega/leitura. Envelope desconhecido não é decodificado por aproximação; evidência conflitante não é sobrescrita.
- O echo tardio procura a identidade exata da parceira e seu alias de envio. A adoção exige comparação `matched`, candidato único, conta/par de caixas válidos, contato compatível, mensagem pública de saída na principal e snapshot do mesmo transporte/geração. Confirma ainda que o ID público coincide com a resposta da API. A reserva canônica é bloqueada antes da adoção e o alias é bloqueado/revalidado.
- A mensagem existente torna-se canônica, preservando ID, `source_id`, autor, conteúdo, citação, Attachment, associação Active Storage e blob. O alias de cada transporte permanece próprio. O echo não gera novo `MESSAGE_CREATED`, nova conversa/contato, chamada de envio, download, upload ou purge. Imagem, áudio e PDF reaproveitam os bytes locais, com origem de transporte preservada.
- Contato divergente, snapshot antigo, mensagem privada ou identidade ambígua ficam em revisão, sem adoção nem nova bolha. Não há comparação por nome, conteúdo assinado ou proximidade de horário.

### Validação e fronteiras

- Matriz nova: **20 cenários positivos** (principal Meta/ViperConnect, recibo Meta antes do echo ou somente depois, texto simples/citado, imagem/áudio/PDF citados), incluindo repetições e reconciliação do arquivo único. **Oito cenários de conflito** não criam bolhas; três testes adicionais verificam evidência da API, envelope desconhecido e original contraditório.
- Regressão ampliada: **473 exemplos Ruby, zero falhas ou pendências**, cobrindo os fluxos unificados, observação/correlação, mídias, revisão, desunificação, agendamento, envio Meta, recebimento Meta/Uno e MessageBuilder. As rodadas focadas sobrepõem esses exemplos; não somar as contagens. RuboCop dos três serviços e do spec de observação sem infrações. O spec integrado conserva avisos de estilo preexistentes em exemplos anteriores; não foram relaxadas regras de produção.
- HTTP externo bloqueado e storage DiskService descartável por cenário. Asserções conferem a preservação dos IDs públicos/internos, um único arquivo e ausência de efeitos de criação/exclusão. Isso não substitui aceite posterior com eventos reais nem teste de carga.
- **Somente dev, sem acesso/modificação na VPS nesta implementação, sem apagar ou mesclar as bolhas existentes, sem commit/push ou novo hostpath.** Não há migração nem mudança de frontend/API pública; os bundles nativos não foram alterados. Não houve teste físico nesta rodada de backend.
- Uma futura aplicação precisa levar os três serviços alterados: `MessageIdentityObservationService`, `UnifiedTransportService` e `UnifiedMessageAliasService`. O hostpath atualmente ativo não inclui os dois últimos; atualizar apenas o observador não entrega a correção completa. O tratamento das duplicadas históricas é uma operação separada e exige aprovação.
- Rodada final focada: 28 cenários positivos/conflitantes aprovados após a conferência do contexto de citação do provider Meta. Banco descartável `viperchat_late_echo_test` (27 MB, sem sessões abertas) e seis relatórios intermediários removidos; storage temporário dos novos testes removido automaticamente. Banco normal, base de teste preexistente e arquivos do usuário preservados. Worker dev reiniciado após verificar zero jobs ocupados; API local HTTP 200. Sem compilação/build adicional, pois os arquivos alterados são exclusivamente backend, testes e esta documentação.

## 26. Correção do echo tardio aplicada via SSH/Docker — 17/10/2026

Após a autorização do usuário para commit/push e hostpath, o commit `a9b8db8722347d8f4c44abdbe5691c58e3dabe71` foi publicado em `origin/feat/whatsapp-unified-inbox-dev`. A aplicação usou diretamente o Docker por SSH, sem alteração da stack armazenada no Portainer.

Diretório privado de aplicação e recuperação: `/var/snap/docker/common/viperchat-hostpaths/late-echo-a9b8db872-20261017`.

- Backup novo `database.dump`, formato custom, índice pg_restore conferido; SHA-256 `aad64f3ea5d39671056636f0cc3f5b667d5e0bd302bcf142ecefa0b981f8adda`. Stack efetiva anterior, inventário, hashes e `ROLLBACK.md` preservados; não houve ensaio de restauração.
- Prévia comparou a proposta com a configuração efetiva dos containers: imagem `viperchat:unified-b829f34ee`, ambiente, comandos, duas réplicas, frontend e mounts anteriores de correlação/mídias permaneceram iguais. Foi substituído o mount de `MessageIdentityObservationService` e acrescentados os de `UnifiedTransportService` e `UnifiedMessageAliasService`: seis mounts read-only em cada container. Os três arquivos passaram em `ruby -c` no runtime da VPS.
- Workers pausados com TSTP e zero jobs ocupados antes da recriação. Somente web e dois workers foram atualizados:

```bash
docker compose -p chatwoot-uno \
  -f /var/snap/docker/common/viperchat-hostpaths/late-echo-a9b8db872-20261017/stack-after.yml \
  up -d --no-deps --no-build --pull never chatwoot-web chatwoot-worker
```

- `validation-after.json` confirmou API HTTP 200, os três containers ativos sem reinícios inesperados, seis mounts read-only e hashes de todos os arquivos corrigidos iguais ao pacote em todos os executores. API pública também HTTP 200. Não houve build nem troca de assets neste incremento exclusivamente backend.
- Conferência final do Sidekiq: dois workers fora de quiet e zero jobs ocupados na amostra. Backup de 247.432.953 bytes. Cópias locais de transferência (26.477 bytes) e temporários usados no container foram removidos; fontes, hostpaths ativos e recuperação na VPS preservados. SSD local com aproximadamente 46,78 GiB livres.
- Banco permaneceu em `20261016000007`. Hashes da amostra de IDs históricos, das mídias verificadas e do vínculo permaneceram idênticos. As mensagens duplicadas `2489761` e `2489762` continuam presentes, com os mesmos IDs, caixas, conversa, `source_id` e conteúdo. ViperConnect, banco, Redis e push relay não foram recriados.
- **Não houve envio de teste, reprocessamento, backfill, mesclagem, purge ou remoção das bolhas duplicadas.** O aceite do novo caminho com respostas reais após a aplicação fica para o usuário; implantação técnica e testes sintéticos não equivalem a esse aceite.
- O rollback de código usa o `stack-before.yml` deste diretório e retorna ao hostpath anterior com quatro mounts; não restaurar o banco automaticamente. Os dois diretórios de hostpath continuam necessários: o frontend e as correções anteriores de mídia/correlação ainda apontam ao diretório `review-a9eec45e0-20261017`.

Antes de qualquer reimplantação pelo Portainer, reconciliar sua stack com este `stack-after.yml` ou incorporar todas as correções em imagem definitiva. O painel continua com seu arquivo anterior e pode desfazer o piloto se reimplantado sem os mounts.

## 27. Cartões compartilhados e recibos telefone/LID — 17/10/2026

Diagnóstico e correção autorizados em dev, seguidos de aplicação por SSH/Docker na VPS. Não houve autorização nova para commit/push nesta etapa; fontes e testes permanecem no worktree da branch `feat/whatsapp-unified-inbox-dev`.

### Casos e regras

- O cartão com original `3A459CC4F21C7DF4E8B4` chegou após a ativação do vínculo e criou mensagens `2489753` e `2489754`, nas caixas 1 e 65. Ambas usam o contato antigo ID 6. A causa era a ausência de `contacts` na lista de ingestão unificada, não a criação de outro cadastro.
- Novos eventos `contacts` passam pela mesma reserva transacional. Um evento com vários cartões cria uma bolha canônica com todos os anexos de contato e nomes próprios. Repetições e o outro transporte reutilizam a bolha; não geram blobs nem uploads. Caixas sem vínculo, vínculo desligado e eventos anteriores à ativação preservam o comportamento legado.
- O `event-5`, original `3EB0F3F5B37D5F6329094B`, tinha conflito em `participants.recipient_id`: telefone do cliente versus `182222711709908@hosted.lid`. A evidência na VPS mostrou que esse LID pertence ao número da empresa, não ao destinatário. **Não são duas formas do telefone do cliente.**
- Recibos posteriores à observação tipada guardam participantes separadamente em `receipt_participants`, sem substituir os participantes da mensagem. Evidências contraditórias anteriores continuam armazenadas.
- A comparação pode reconhecer LID/hosted-LID por aliases já estabelecidos, restritos à conta/caixa; a forma hosted usa o mesmo identificador local do LID. Apenas recibos Uno com telefone de mensagem conhecido podem reconhecer o dispositivo empresarial por esse vínculo comprovado. Não há busca por texto, horário ou nome, nem transformação do LID em número de telefone.
- Alias de outra conta, LID desconhecido, proprietários ambíguos, telefone divergente, direção contraditória ou ausência de recibo não ganham essa exceção. Nenhum contato/ID público é regravado ou mesclado.

### Validação

- Banco isolado `viperchat_contact_lid_test`, conferido na conexão efetiva. Casos reais reproduzidos com conteúdo anonimizado: ambos os canais como principal, ordens de chegada, um/vários cartões, repetições, recuperação da reserva, histórico legado, BSUID Meta e recibo de dispositivo empresarial antes/depois do echo Meta.
- Rodada ampliada: **470 exemplos Ruby, zero falhas**. Rodada final focada: **48 exemplos, zero falhas**, incluindo seis verificações adicionais de isolamento/ambiguidade/ausência de recibo. As rodadas se sobrepõem; não somar os totais.
- Os cinco serviços de produção passaram no RuboCop. As duas suítes novas de integração ainda apresentam avisos de estilo nos exemplos extensos; isso não foi escondido por relaxamento das regras de produção.
- Renderizadores de contatos existentes: três testes Vitest aprovados, incluindo agrupamento, abertura da lista, busca e compatibilidade legada. Não houve alteração Vue/JS, compilação de assets ou nova build nativa; não foi realizado teste físico Android/iOS nesta rodada de backend.

### Aplicação e preservação

- Diretório: `/var/snap/docker/common/viperchat-hostpaths/shared-contacts-lid-20261017`. Backup custom de **247.437.909 bytes**, índice pg_restore conferido, SHA-256 `45a3ac89620aff47408b916dd2e529fd3223262c9b576ad6cf37639655f11d6b6`. Configuração anterior, inventário privado e instrução de rollback preservados. Não houve ensaio de restauração.
- Cinco arquivos aplicados: `IncomingMessageBaseService`, `UnifiedMessageIngestionService`, `MessageIdentityObservationService`, `MessageIdentityCorrelationService` e novo `MessageIdentityParticipantService`. Nove mounts read-only por container, preservando mídia, frontend, alias e transporte dos overlays anteriores; a imagem base não mudou.
- Workers pausados por TSTP e zero jobs ativos antes da recriação. Somente web e duas réplicas de worker foram recriadas. API retornou HTTP 200 após a inicialização; workers voltaram fora de quiet. Hashes dos cinco arquivos conferidos nos três containers.
- A consulta somente leitura do caso `event-5` passou a retornar `matched` com candidato `8356`. O registro de revisão continua intacto: **não foi reprocessado, confirmado nem apagado automaticamente**.
- As amostras de mensagens, IDs públicos/internos, anexos/blobs associados, vínculo e estado do `event-5` permaneceram idênticas aos snapshots anteriores à aplicação. As duplicatas históricas não foram removidas. Não houve envio de mensagem, backfill, mesclagem, purge ou migração.
- Rollback de código usa `private/stack-before.yml` deste diretório, mantendo o banco. O hostpath novo e os anteriores ainda são necessários. A stack armazenada no Portainer não foi alterada: reconciliá-la antes de reimplantar pelo painel.
- Aceite com novos compartilhamentos reais na VPS continua com o usuário; testes sintéticos e consulta de correlação não equivalem a reprocessar ou corrigir visualmente as mensagens antigas.
- Limpeza final: banco sintético de 26.571.235 bytes removido após confirmar zero sessões e ausência de mensagens/anexos/blobs; cópia local de transferência de 4.927 bytes removida. Backups/hostpaths ativos na VPS e fontes/testes preservados. Worker dev reiniciado após verificar zero jobs; ViperConnect local permaneceu ativo. API da VPS novamente HTTP 200, três containers sem reinícios inesperados e nove mounts em cada um.

## 28. Echo Uno sem destinatário após envio Meta — 17/10/2026

Caso real `event-6`: original `CEAE20230B67E95629AF`, público Uno `c1bf97d0-ca1c-11f1-8b89-01afaf97c044`, público Meta `wamid.HBgMNTU2Njk2MjY5MjUxFQIAERgUQ0VBRTIwMjMwQjY3RTk1NjI5QUYA`. O envio citado da Meta já estava na mensagem `2489813`, conversa `18316`, contato antigo `6`; o echo Uno não trouxe `to` nem outro destinatário. Não havia outra bolha com esse UUID.

### Correção e segurança

- O resolvedor encontrava o contato pela única mensagem da Meta com o mesmo original, mas a associação exigia `matched` e recusava `participant_identity_pending`. A reserva `54` ficava sem mensagem e o evento ia diretamente para revisão, com zero tentativas.
- A associação aceita esse estado incompleto **apenas para echo de saída Uno sem `to`, `recipient_id`, `to_user_id` ou `to_parent_user_id`**. Destinatário presente e contraditório não recebe essa exceção.
- Permanecem obrigatórios: candidato único pelo original e escopo empresarial/conta, alias da mensagem enviada, contato comprovado pela identidade Meta, mensagem pública de saída na principal, ID público original do transporte e snapshot exato do vínculo/ativação. Não se usa texto, assinatura do operador ou proximidade de horário para identificar mensagens.
- Na reconciliação de mídias, essa comprovação permite conservar **somente uma cópia canônica já existente**. Se aparecer outro `Message` associado, o caminho incompleto volta para revisão, sem troca de blob/purge. Não é uma autorização para conciliar duas mídias com evidência incompleta.
- `source_id`, IDs internos, dados dos contatos, mensagens citadas e arquivos existentes não são regravados pela identificação. O echo torna-se outro alias da mesma mensagem.

### Testes e aplicação

- Reprodução antes da correção em banco isolado `viperchat_missing_echo_test`: a resposta citada com original do `event-6` manteve a reserva pendente, reproduzindo o bloqueio.
- Matriz focada final: **60 exemplos, zero falhas**, com principal Meta/Uno, destinatário presente/ausente, recibo antes/depois, texto simples/citado e imagem/áudio/PDF citados. Asserções conferem os mesmos IDs, citações, autor, quantidade de mensagens, anexos/blobs e ausência de download/upload/purge adicional. Inclui contato divergente, geração antiga, privado, ambiguidade, outro destinatário explícito e alias de destinatário não comprovado; arquivos únicos são mantidos e uma segunda mensagem associada impede a reconciliação incompleta.
- Dois serviços de produção passam no RuboCop e `ruby -c`. Mudança exclusivamente backend; não houve alteração de frontend, build nativa ou teste físico Android/iOS. A suíte integrada mantém avisos de estilo preexistentes nos exemplos extensos.
- Pacote e recuperação: `/var/snap/docker/common/viperchat-hostpaths/recipientless-echo-20261017`. Backup custom de **247.443.203 bytes**, catálogo pg_restore conferido, SHA-256 `4579a7271e53042655625e0e62b7a916644561b128121c1a88279642521a84a7e`. Não houve ensaio de restauração.
- Stack candidata preserva a imagem e os nove mounts anteriores, substituindo somente `UnifiedMessageAliasService` e `UnifiedMediaReconciliationService`. Rollback de código documentado em `ROLLBACK.md`, usando `private/stack-before.yml`, sem restaurar o banco como rotina. A stack armazenada no Portainer não é atualizada por esse procedimento SSH.
- Regressão ampliada final: **508 exemplos Ruby, zero falhas**. A rodada focada se sobrepõe e não deve ser somada ao total. Não houve migração, envio real de teste ou reprocessamento de pendências antigas. O banco descartável de 26.898.915 bytes foi removido após verificar zero sessões e zero mensagens/anexos/blobs; o worker dev recebeu o código novo após conferir zero jobs ativos.
- Aplicação concluída via Docker/SSH após TSTP e zero jobs ativos: web e dois workers, preservando os nove mounts read-only e a imagem existente. Hashes dos dois serviços conferidos nos três executores. API HTTP 200; dois workers fora de quiet e zero jobs na amostra.
- Validação **somente leitura** sobre o `event-6` real: candidato Meta `8399`, participante resolvido `5566996269251`, `alias_compatible: true`, mensagem original `2489813` e zero bolhas com o UUID do echo. A comparação diagnóstica ainda informa `participant_identity_pending`, pois o payload continua sem destinatário; a associação agora usa a comprovação da mensagem, sem fabricar evidência de telefone no webhook.
- Snapshots antes/depois confirmam preservação dos IDs, mensagens históricas/citadas, anexos/blobs associados, vínculo e estado do `event-6`. A revisão antiga permanece `review/correlation_conflict`, zero tentativas; não foi reprocessada automaticamente. Cópia local de transferência de 4.510 bytes removida; diretório remoto ativo e backup necessário preservados. Código e plano ainda sem novo commit/push nesta etapa.

## 29. Citação legada, preparação do envio e isolamento de echoes — 17/10/2026

### Evidência e regra aprovada

A mensagem `2489911` falhou ao citar `2488821`, recebida anteriormente pela própria ViperConnect, com UUID `43574000-c9ae-11f1-8b89-01afaf97c044`. O log do primeiro `SendReplyJob` (`4a486e1a-6db5-4c03-adc0-e4243f76b7ba`) comprova `ArgumentError: Message reference is not available in the selected provider` durante a construção do payload, antes do HTTP. A tentativa `bc212b33-bb56-4d2f-9ff3-52708b284c40` permaneceu erroneamente incerta, bloqueando echoes de outros contatos. A amostra inicial tinha nove casos `matched`; o volume chegou a 27 pendências antes da correção.

O usuário autorizou corrigir os três pontos, enviar sem citação quando ela não for possível, aplicar via hostpath e concluir as pendências comprovadas. Isso **não autoriza reenviar indiscriminadamente entregas realmente incertas**, apagar bolhas, resolver conversas de clientes ou inventar confirmação de leitura.

### Implementação

- `UnifiedTransportService` usa o ID público legado quando a mensagem antecede a ativação, pertence à própria caixa do transporte selecionado, possui formato compatível e não está marcada como transporte/ingestão unificada. IDs originais de correlação nunca são usados como referência operacional.
- Referência ausente no provedor vira fallback sem citação, no mesmo transporte, antes do envio HTTP. `whatsapp_quote_fallback` registra referência pretendida, provedor, motivo e horário, mantendo o histórico interno. A ausência não provoca um segundo envio HTTP nem troca de canal. Bloqueios de conta, conversa, notas privadas e geração do vínculo permanecem ativos.
- `SendOnWhatsappService` prepara destinatário e referência antes da reserva de envio. `UnifiedDeliveryAttemptService` distingue `preflight_failed` (nenhuma requisição externa) de `attempting/uncertain`. Uma preparação corrigida pode ganhar uma única tentativa; timeout/erro após iniciar a operação continua conservador e não é reenviado automaticamente. Confirmação com ID público encerra o estado de envio e limpa apenas os erros internos dessa preparação.
- `UnifiedOutboundWaitService` isola a espera ao mesmo contato e a tentativas efetivamente iniciadas/incertas. Um alias com resposta pública já conhecida, identificado pelo original exato, não espera outro envio. A ingestão continua responsável por validar contato, escopo e adoção; identificações ambíguas continuam pendentes/revisão.
- Não houve alteração de frontend, migração, build Android/iOS ou teste físico. O incremento é exclusivamente backend e mantém o contrato dos apps existentes.

### Validação e recuperação

- Banco sintético isolado `viperchat_quote_isolation_test`. **525 exemplos Ruby, zero falhas**; seis serviços de produção sem infrações RuboCop. As novas verificações cobrem HTTP efetivo único com/sem citação, UUID legado, envio pelo outro provedor sem alias, preparação corrigida, ausência de vazamento do erro privado, proteção da tentativa realmente incerta, outros contatos não bloqueados e conclusão de um evento pendente quando a mensagem existente é comprovada.
- Banco descartável de 26.153.443 bytes removido após conferir zero sessões e zero mensagens/anexos/blobs. Worker dev atualizado após verificar zero jobs. ViperConnect local permaneceu ativo.
- Recuperação e backup: `/var/snap/docker/common/viperchat-hostpaths/quote-unblock-20261017`. Dump custom de **247.590.904 bytes**, catálogo pg_restore conferido, SHA-256 `802bd80198fe0083e207819900a6a6ed277d67d63a7b91a2cf33e998d4e144ec6`. Prova do erro anterior ao HTTP, stack anterior e inventário preservados em `private/`; não houve ensaio de restauração.
- Hostpath de seis arquivos: transporte, controle de tentativa, ingestão, novo controle de espera, envio WhatsApp e provider Cloud compartilhado pela Uno. Preserva a imagem e todos os overlays anteriores; treze mounts read-only por container. Rollback de código não deve desfazer confirmações reais nem reenviar mensagens já aceitas.
- Aplicação concluída após TSTP e zero jobs ocupados, somente web e dois workers. Os seis hashes conferem nos três executores. Snapshots antes/depois preservam IDs históricos, conteúdo da citação antiga, mídias associadas, vínculo e ID/conteúdo da própria bolha recuperada.
- Prévia da recuperação identificou **23 eventos comprovados**, sem casos ambíguos nesse conjunto. A recuperação autorizada fez uma única tentativa sem citação para `2489911`, guardando a tentativa anterior em `whatsapp_transport.preflight_recovery`; a bolha manteve o ID interno e recebeu o ID público antes ausente `942a69f0-ca2e-11f1-b3c4-63718cf5742f`. O provedor aceitou o envio (`acknowledged`, status `sent`); isso não afirma entrega/leitura pelo cliente. Há uma única bolha com esse ID público na conferência.
- Os 23 eventos da prévia foram rechecados com auditoria e concluídos somente após mapear para a mensagem existente esperada. Os demais vencidos foram concluídos pelo processamento normal após o desbloqueio. A amostra final tinha **66 eventos concluídos, zero pendentes por espera de resposta e duas revisões antigas por conflito**; estas não foram falsamente encerradas. Nenhuma conversa de cliente foi marcada como resolvida por essa operação.
- API pública HTTP 200. Evidências de recuperação, prévia, execução e resultados ficaram em `private/`. Temporários do runner removidos do container após copiar as evidências; cópias locais de transferência de 10.668 bytes e banco sintético removidos. Backups/hostpaths ativos e fontes preservados. Código e plano continuam sem novo commit/push, que não foi solicitado nesta etapa.

## 30. Reavaliação automática das pendências de identificação (2026-10-17)

- O evento `event-6` concluiu a reavaliação na VPS em `2026-10-17T13:58:43.809Z`, associado à mensagem existente `2489813`, sem outra bolha. O estado pendente copiado anteriormente era transitório, com descrição antiga de conflito. A consulta posterior encontrou 67 eventos concluídos e uma revisão antiga restante; esta informação é um retrato, não uma garantia do estado futuro.
- Em dev, `Whatsapp::RecheckUnifiedEventsJob` faz uma varredura a cada **5 minutos**, além da recuperação já existente de eventos pendentes a cada minuto. Retoma eventos em revisão com payload preservado, sem atualização há pelo menos cinco minutos e pertencentes à ativação atual de um vínculo habilitado.
- Cada varredura seleciona até 100 eventos, dos mais antigos para os mais novos. O lock do registro revalida a elegibilidade e impede enfileiramento repetido por varreduras concorrentes; falha em um evento não interrompe os demais. O contador de tentativas é preservado. O processamento normal continua responsável pela correlação, locks, deduplicação e autorização de mídias.
- Reavaliar não significa aceitar o conflito: apenas uma correlação comprovada conclui o evento. Evidência insuficiente ou contraditória continua em revisão para outra avaliação, sem inventar contatos ou aliases. Eventos concluídos, desativados, sem payload ou de ativações anteriores não são reabertos. A periodicidade é da varredura; filas ocupadas e o limite do lote podem atrasar o processamento.
- A rotina reaplica webhooks retidos; **não reenvia mensagens de saída com confirmação incerta**, não resolve conversas, não altera IDs e não autoriza apagar bolhas ou mídias existentes. Não substitui revisão administrativa quando a evidência continuar realmente ambígua.
- Validação final em banco sintético isolado `viperchat_auto_recheck_test`, com destino de conexão confirmado antes da carga do schema: **244 exemplos, zero falhas**, cobrindo reavaliação periódica, execução repetida, payload ausente, falha ao enfileirar, vínculo desativado/reativado, BSUID não resolvido, echoes, citação e mídias. Novo job sem infrações RuboCop.
- Worker de dev reiniciado somente após quiet e zero jobs ocupados. Registro do cron conferido no Redis configurado: `whatsapp_recheck_unified_events_job`, expressão `*/5 * * * *`, habilitado. Mudança apenas backend; nenhuma alteração de frontend ou necessidade de novas builds nativas. **Ainda não aplicada na VPS, nem commitada/publicada nesta etapa.**

## 31. Saúde da conta e insights Meta informativos em dev (2026-10-17)

- Corrigida a fonte do limite: consulta `whatsapp_business_manager_messaging_limit` na WABA configurada, em vez do campo legado `messaging_limit_tier` do número. A resposta mantém a chave antiga com o valor atual para compatibilidade; `TIER_2K` tem tradução em português/inglês. Falha ou ausência do novo campo deixa o limite desconhecido, nunca assume 250 nem força 2.000 pelo print.
- Nova consulta administrativa `GET /api/v1/accounts/:account_id/inboxes/:id/insights?days=7|30|90`, padrão 30 dias. Apenas caixas `whatsapp_cloud`, com autorização da conta/caixa e perfil administrador. Não aceita WABA, token ou número arbitrário do navegador. Dados filtrados pelo número configurado, dias completos em UTC; cache por conta, canal, configuração e período, de 10 minutos. O botão atualizar pode retornar esse cache, identificado pela data original da coleta; não é uma leitura de faturamento em tempo real.
- A aba Saúde da conta agora inclui mensagens, custos aproximados, categorias/tipos de cobrança, volumes gratuitos/regulares e chamadas (quantidade, direções e média ponderada quando há contagens válidas). Entradas são consultadas separadamente das saídas; falha apenas na consulta de recebidas tem estado/motivo próprios e não remove métricas de saída. Dados ausentes, parciais, moeda ausente e indisponibilidade de permissão/versão não viram zero. Custo de ligação não herda a moeda da WABA sem evidência própria; a unidade da duração não é presumida.
- Chamadas de gestão são somente GET, com bearer no header, timeout e erros sanitizados. Consultas das seções independentes usam futures e preservam resultados parciais. A implementação não habilita insights na Meta via escrita, não registra tokens, não muda assinatura de webhook, não promete franquia de 1.000 mensagens nem altera o seletor/transporte, regras de envio, IDs, contatos, deduplicação ou mídias.
- Qualidade atual permanece na saúde; não há reconstrução de série histórica de qualidade de 30 dias nem cálculo de cota restante, economia ou fatura a partir de contagens aproximadas. O limite compartilhado é apresentado separadamente dos relatórios por número.
- **52 exemplos Ruby e 23 testes de interface passaram**, incluindo regressões de cadastro/webhook e permissões, cache, falta de dados, custo/moedas, atraso de resposta, período e erros. RuboCop dos quatro serviços/concern sem infrações; ESLint dos componentes/specs sem erros (seis avisos de chaves i18n dinâmicas). Revisão paralela encontrou a perda do estado de falha somente de entrada; corrigida e coberta por regressão.
- Playwright: componentes reais e estilos do servidor dev, com respostas sintéticas restritas ao navegador, em 320/360/390/412/430 px, paisagem 852×393 e desktop 1440 px. Sem overflow horizontal; inspeção visual dos sete tamanhos, seletor por teclado, troca de período, indisponibilidade, erro e recuperação. HMR local informa erro de websocket na configuração já existente; não houve exceção funcional da tela. Capturas de referência em `output/playwright/account-insights-dev/health-320.png` e `health-1440.png`.
- Nova rota e serviço conferidos no runtime dev. A caixa Meta de teste `192` está sem credencial: corretamente retorna `configuration_missing`, sem fabricar estatísticas. Logo, os testes sintéticos **não comprovam os valores da conta Meta real**, nem a disponibilidade de cada campo na versão/permissão do token de produção. Contratos foram conferidos no SDK oficial da Meta; documentação online retornou 429. Antes da VPS, resta aceite da interface e leitura real autorizada das métricas.
- `pnpm native:sync:android` e `pnpm native:sync:ios` concluídos no ambiente local; bundle Android e iOS sincronizados nos projetos. APK debug Android compilado (`assembleDebug`, 306 tarefas) e hash do dashboard embarcado conferido com o bundle atual; artefato `android/app/build/outputs/apk/debug/app-debug.apk`. Nenhum Android listado por `adb devices`; Mac não acessível por SSH nos endereços conhecidos `.120` e `.132`. Sem instalação/teste físico e sem compilação/Archive iOS; sincronização de assets não comprova esses passos.
- Banco de teste isolado `viperchat_account_insights_test`, sem mensagens/anexos/blobs ao final e sem sessões ativas, removido após a validação (21.967.331 bytes). Intermediário do preview e cinco capturas redundantes removidos; duas capturas de referência, fontes, bundles e APK de entrega preservados. Sem limpeza global de caches/volumes. **Nada aplicado na VPS; sem commit/push ou publicação nesta etapa.**

## 32. Padronização Meta e recebimento de eventos em dev (2026-10-17)

- Graph API padronizada em `v26.0`, com resolução central por `WHATSAPP_API_VERSION`: envio Cloud, gestão, cadastro embarcado e CSAT. O valor instalado em dev foi atualizado de `v22.0` para `v26.0`; reversão de configuração não exige alterar mensagens. A UnoAPI mantém suas versões de contrato próprias. `sessionInfoVersion: 3` é formato do evento do SDK, não a versão da Graph nem promessa de Embedded Signup v4.
- Preservados o fluxo de cadastro comum e de coexistência, tratamento de cancelamento e validação estrita de origem HTTPS do SDK. Eventos `message_echoes` e `smb_message_echoes` entram como ecos de saída; lotes com várias mudanças/mensagens são separados para processamento independente.
- O receptor reconhece os campos dos prints: alertas, revisão/configuração/estado da conta, capacidades, nomes/qualidade do número, segurança, templates, histórico, contatos da coexistência, grupos, flows, handover, pagamentos, rastreamento e preferências. Receber e auditar **não equivale a implementar todas as operações comerciais desses produtos**. Atualizações de templates invalidam o cache e enfileiram a sincronização existente; demais eventos administrativos são informativos. `group_settings_update` também mantém o tratamento de grupo preexistente. Não muda a política de envio nem o transporte selecionado.
- Recebimentos administrativos exigem assinatura Meta, conta ativa e correspondência da WABA/número da URL. Registro idempotente por canal/campo/digest; resumo administrativo não expõe payload bruto, contatos, conteúdo de mensagens ou tokens. Corpos limitados a 256 KiB; excedentes conservam somente metadados de truncamento.
- Assinatura padrão preservada em `messages` e `smb_message_echoes`; `calls` continua condicional. Campos opcionais reconhecidos podem ser configurados em `provider_config.webhook_fields`, preservando a união entre caixas da mesma WABA. Não são todos assinados automaticamente: permissões, disponibilidade e configuração no painel Meta continuam necessárias. Nenhuma assinatura foi alterada no painel nesta etapa.
- Estratégia de histórico alinhada à ViperConnect: `ignore_history_messages: true` por padrão e `history_max_age_days: 7`, configurável de 1 a 3.650 dias em Saúde da conta. O limite determina a idade das mensagens recebidas, **não um prazo para apagar o histórico salvo**. Quando habilitado, apenas mensagens com timestamp válido dentro do período são retidas nos lotes; formato desconhecido fica em revisão sem guardar histórico não filtrado. Nesta entrega, lotes filtrados ficam pendentes para revisão: **não há importação automática em bolhas nem mesclagem de contatos**.
- `smb_app_state_sync` guarda lotes de contatos para revisão independentemente de ignorar histórico. Não cria nem substitui contatos antigos. Payloads brutos expiram após sete dias; tarefa horária limpa somente o corpo desses recebimentos, preservando ID, digest e resumo para idempotência. Não remove mensagens, anexos ou objetos S3.
- Novas interfaces administrativas, restritas à conta/caixa Cloud: `GET /api/v1/accounts/:account_id/inboxes/:id/management_events` (últimos 25 resumos e configuração) e `PATCH /api/v1/accounts/:account_id/inboxes/:id/coexistence_settings` (boolean JSON e limite em dias). Salvar a política local não revalida credenciais nem chama a Meta. Interface responsiva junto a Insights, com estados de carregamento, erro e proteção contra respostas atrasadas.
- Migração aditiva `20261017000001` aplicada somente no dev. Sem atualização de IDs, mesclagem, exclusão de bolhas ou download duplicado de mídia. Aceite real de credenciais/permissões e webhooks da Meta permanece etapa posterior. **Sem VPS, commit/push ou publicação nesta etapa.**
- Validação: 236 exemplos de regressão de versões, cadastro, transporte, CSAT, convites e chamadas passaram; 125 exemplos do receptor, assinatura, isolamento, API administrativa, expiração e pipeline existente passaram após a refatoração; 26 exemplos da assinatura opcional passaram. Saúde/insights passaram em outros 15 exemplos. Houve uma falha transitória no teste de assinatura por segredo do canal em uma execução combinada; o spec isolado (11 exemplos) e a repetição completa dos 125 passaram sem alteração do comportamento de autenticação. Não se atribui causa comprovada à falha transitória.
- Frontend: 64 testes do SDK/utils e 43 testes de saúde/eventos passaram. Preview dos componentes reais com dados sintéticos em celular, paisagem e desktop, sem comprovação de respostas reais da Meta. Bundles Android/iOS regenerados; `assembleDebug` concluído. Nenhum dispositivo em `adb devices`; SSH dos Macs conhecidos indisponível, portanto sem instalação Android, compilação/Archive ou teste físico iOS.
- Rotina `whatsapp_expire_management_payloads_job` conferida habilitada no worker dev (`17 * * * *`). Banco sintético `viperchat_meta_webhooks_test` removido após verificar zero sessões, mensagens, contatos, anexos, blobs e recebimentos; 26.169.827 bytes descartáveis. Fontes, bundles e APK preservados; sem limpeza global de caches/volumes.
- Matriz visual final do preview: 320, 360, 390, 412 e 430 px, paisagem 844×390 e desktop 1280×800, sem overflow horizontal. Referência de 412×915 em `output/playwright/meta-webhooks-dev/health-412.png`; dados simulados, lista expandida e campo de dias visível. Intermediários de preview removidos. Espaço livre final do SSD aproximadamente 41 GiB; isto não representa recuperação de todo esse espaço pela limpeza.

## 33. Importação automática do histórico Meta em dev (2026-10-17)

Esta etapa substitui o comportamento somente para revisão descrito na seção 32 para o campo `history`. Não altera a política de contatos de `smb_app_state_sync`, que continua somente recebida para revisão.

- Ao desmarcar **Ignorar mensagens de histórico**, lotes `history` recebidos e validados são importados automaticamente pela fila. O limite padrão continua sete dias, editável de 1 a 3.650 dias, ancorado ao recebimento; o provedor pode disponibilizar um período menor. Mensagens fora do período, futuras ou sem timestamp válido não são importadas. A configuração não apaga mensagens existentes nem busca retroativamente histórico que a Meta não enviou.
- `Whatsapp::ImportHistoryJob` é enfileirado ao criar o recibo. Uma varredura `*/5 * * * *` retoma pendências em lotes de até 100, rotacionando pela última tentativa para que uma identidade ambígua ou uma falha não bloqueie os demais. Payload expirado não é inventado nem reconstruído. O snapshot do vínculo/ativação impede reaplicar um lote em uma vinculação administrativa diferente.
- Mensagens mantêm o ID público original e a data do provedor, inclusive cartões de contato compartilhado. Duplicação é verificada antes de baixar arquivos. Em caixas vinculadas há reserva PostgreSQL da mensagem lógica, verificação do ID original, direção e participante, adoção de contraparte comprovada e aliases sem substituir IDs atuais. Identidades desconhecidas ou conflitantes ficam pendentes; não há deduplicação por texto, horário ou nome.
- O caminho histórico não cria eventos pendentes destinados ao processador de mensagens ao vivo. Histórico não dispara saudação, bot, automação de mensagem, resposta WhatsApp, preview de link, transcrição automática, nova notificação ou reabertura. Uma atualização de leitura histórica é monotônica e não dispara `message.updated` para bots. Mensagens históricas ficam fora das contagens de novas não lidas; mensagens ao vivo mantêm o comportamento normal.
- Conversa existente mantém estado, responsável, equipe, datas de atividade e marcas de leitura. Sem conversa, cria-se uma conversa resolvida com data histórica e sem atribuição automática. A importação não usa o limite anti-flood de mensagens ao vivo, mas mantém as demais validações de conteúdo/conta.
- Contatos antigos são reutilizados por identidade comprovada e comparação brasileira de oito/nove dígitos, sem reescrever telefones, LIDs ou BSUIDs existentes. Contato com somente BSUID desconhecido fica pendente, sem criar outro registro especulativo. Busca/criação de contatos telefônicos de WhatsApp ao vivo e históricos compartilham advisory lock transacional por conta + telefone normalizado; outros canais não recebem esse lock.
- Mídia sem ID disponível não gera download com ID vazio nem bolha vazia. Falha em um item usa savepoint, preservando os demais e permitindo tentar novamente sem baixar os itens já persistidos. Lotes grandes são subdivididos antes do limite de retenção de 256 KiB por recibo. Item individual excessivo/formato desconhecido permanece explicitamente em revisão; não se promete importar um formato de mídia histórica ainda não comprovado.
- Interface informa importadas, duplicatas evitadas, pendentes e falhas. Ignorar histórico continua ativado por padrão; a ativação é administrativa. `smb_app_state_sync` não foi transformado em sincronização automática da agenda e remoção na agenda nunca autoriza apagar contatos do ViperChat.
- Testes sintéticos derivados dos casos reais cobrem chegada Meta/ViperConnect em ambas as ordens, BSUID, nono dígito, conflitos, leases concorrentes, datas, status, contatos compartilhados e PNG/áudio/PDF com um único blob/anexo e download. O fluxo HTTP assinado → fila → bolhas passou, inclusive lote grande e redelivery. Validação sintética não substitui aceite de payloads reais da conta Meta; documentação Meta retornou HTTP 429. Referência de formato complementar: [360dialog — Coexistence Webhooks](https://docs.360dialog.com/partner/onboarding/whatsapp-coexistence/coexistence-webhooks).
- Implementação e cron somente no dev; sem VPS, exclusão de bolhas/mídias, commit/push ou publicação. Não houve nova migração nesta etapa.

### Evidências de aceite da etapa histórica

- Fluxo HTTP assinado até a persistência, redelivery e lote acima de 256 KiB: três exemplos aprovados. Suíte integrada de histórico/modelos/contagens/assinatura/configuração: 69 exemplos aprovados antes da inclusão do filtro de grupos; os dois cenários adicionais de histórico de grupos também passaram na suíte específica (30 exemplos). Concorrência do lock de contato, builder e resolvedor: 27 exemplos aprovados, com conexões PostgreSQL independentes.
- Regressão de ingestão unificada, pendências, LID/telefone e contatos compartilhados: 228 exemplos aprovados. Uma execução extensa dos modelos encontrou `AssociationTypeMismatch` com duas gerações da classe Account durante alterações concorrentes do código; o exemplo isolado passou. Isso não é contado como aprovação de toda a suíte de modelos.
- Revisão independente encontrou três falhas, corrigidas e cobertas: avanço de status histórico com callback de bot; criação concorrente do mesmo contato entre caixas; timestamp ausente dentro de cartão compartilhado. Atualização de status agora é silenciosa sob lock; criadores compartilham lock PostgreSQL; a data sempre vem do envelope histórico.
- Interface e avisos de grupos: 30 testes frontend aprovados; Playwright em 320/360/390/412/430 px, paisagem e desktop, com dados sintéticos. Bundles Android/iOS regenerados; APK debug compilado e assinatura conferida. Sem Android conectado ou Mac acessível: sem teste físico nem compilação/Archive iOS. Assets obsoletos gerados nesta validação foram removidos, preservando o APK atual e evidências 320/desktop.

## 34. Grupos Meta seguindo a separação de identidades da ViperConnect

- Fonte local conferida na ViperConnect: `MessageFilter` filtra grupos por `ignoreGroupMessages`; transformer mantém `message.group_id` separado de `from`/`from_user_id`, emite recibos com `recipient_type: group` e `recipient_id` do grupo, e entrega `provider_message_id` adicional. Grupo nunca é um telefone de contato individual.
- Configuração administrativa Meta `ignore_group_messages`, independente do histórico e com padrão falso para preservar o comportamento existente. A API local aceita somente boolean JSON; clientes antigos que omitem o campo não sobrescrevem a preferência. Não há exclusão de grupos, membros ou histórico ao ativar o filtro, nem alteração automática das assinaturas Meta.
- Há uma diferença de produto: a [documentação da 360dialog para Groups API](https://docs.360dialog.com/docs/messaging/groups) informa indisponibilidade para números em coexistência/Multi-solution Conversations e elegibilidade OBA. Assinar campos no painel não torna os grupos do aplicativo WhatsApp disponíveis na API oficial. A documentação Meta não pôde ser consultada diretamente por HTTP 429; não é uma validação real de elegibilidade da conta do usuário.
- Em vínculo de coexistência, o recebimento de grupos pela ViperConnect deve continuar operacional, inclusive se a caixa administrativa principal for Meta. O fluxo de grupos não pode aguardar uma contraparte que a Meta talvez nunca envie. A unificação individual e seu seletor de transporte continuam separados desse fluxo.
- Correlação de grupo entre provedores exige ID original comprovado, grupo exato, remetente, direção, tipo e conta/número empresarial compatíveis. Nome do grupo, texto e semelhança de participantes não autorizam deduplicação. Um ID Meta opaco não é convertido em JID por extração de dígitos, nem se presume um formato de wamid de grupos ainda não comprovado.
- O histórico `history` com identidade de grupo não é reinterpretado como conversa direta: quando ignorar grupos estiver ativo é descartado da importação; sem a opção, fica pendente de suporte/evidência de identidade de grupo. Isso não bloqueia mensagens individuais do mesmo lote. O histórico de grupos que chega pela ViperConnect permanece no fluxo existente.
- Em Meta sem vínculo, mensagens de grupo usam conversa estruturada com ID Meta exato e participante real como remetente. A foto do participante não substitui a do grupo. Não se enfileira sincronização de participantes Uno para um canal Meta. Recibos de grupos podem resolver um alias de mensagem, mas somente se o grupo também corresponder; não atualizam uma conversa privada por engano.
- Em Meta vinculada, a cópia de grupo só aponta para uma mensagem Uno existente com evidência exata. Mensagem Meta sem prova fica pendente, em vez de criar outra bolha/arquivo. A ViperConnect mantém sua própria ingestão de grupos sem bloqueio pelo vínculo. **Isso não é uma unificação completa da interface/seleção de transporte para grupos, nem suporte automático a formatos Meta ainda desconhecidos.**
- `group_settings_update` Meta tem aplicação serializada por recibo e estado processado; redelivery não repete atualização/avatar. Os outros eventos administrativos de grupos continuam auditados, sem criação automática de grupos ou gestão integral de membros. O filtro atua antes de identificação, criação de contatos e download, em mensagens, echoes, recibos e eventos de grupo; valores administrativos inesperados não quebram o processamento de eventos individuais.
- Validação de grupos pelo subagente: 140 exemplos aprovados; sete cenários de policy repetidos após ajuste defensivo. Aceite final do pai: 59 exemplos combinados de histórico/grupos/API e 259 exemplos dos modelos existentes aprovados com código congelado. A falha anterior de geração da classe Account não se repetiu. Trinta testes frontend aprovados. Sem VPS, alteração de assinatura Meta ou mudança de IDs/remoção de mídias.

### Catálogo de eventos: tratamento funcional versus recebimento para auditoria

| Campos | Tratamento disponível nesta entrega dev |
| --- | --- |
| `messages` | Mensagens e recibos de status; formatos já existentes. Grupos passam pelo filtro e caminho de identidade de grupo, não pelo resolvedor individual. |
| `smb_message_echoes`, `message_echoes` | Ecos de saída externos, identificação e deduplicação conforme evidências disponíveis. |
| `history` | Importação automática de mensagens individuais dentro do período configurado; erros e identidades incompletas ficam pendentes. Grupos seguem as limitações acima. |
| `message_template_components_update`, `message_template_quality_update`, `message_template_status_update`, `template_correct_category_detection` | Recebimento idempotente, invalidação do cache e sincronização de templates existentes. |
| `group_settings_update` | Auditoria e atualização de grupo existente, sem repetir a aplicação do mesmo recibo. |
| `smb_app_state_sync` | Lote de contatos para revisão; sem sincronização/mesclagem automática. |
| `account_alerts`, `account_review_update`, `account_settings_update`, `account_update`, `automatic_events`, `business_capability_update`, `business_status_update`, `business_username_updates` | Auditoria informativa. Não alteram regras de envio, cota ou transporte automaticamente. |
| `flows`, `group_lifecycle_update`, `group_participants_update`, `group_status_update`, `messaging_handovers`, `partner_solutions`, `payment_configuration_update`, `phone_number_name_update`, `phone_number_quality_update`, `security`, `standby`, `tracking_events`, `user_preferences` | Recebimento/auditoria; não equivale à implementação completa das operações de cada produto. |
| `calls` | Campo reconhecido e assinatura condicional à configuração; recebimento funcional ponta a ponta não foi comprovado nesta cadeia de webhooks. Chamadas não são habilitadas por esta entrega. |

Assinatura padrão continua `messages` + `smb_message_echoes`; campos opcionais dependem de configuração/permissões e assinatura no painel Meta. O catálogo de suporte não é a lista de assinaturas efetivamente ativas na conta do usuário.

### Fechamento do aceite dev

- Repetição final com código congelado: **259 exemplos** dos modelos existentes e **228 exemplos** de ingestão unificada/pendências/LID/contatos compartilhados aprovados. Suíte combinada de histórico/grupos/API: **59 exemplos** aprovados. Grupos também tiveram a validação específica de 140 exemplos relatada acima; contagens não devem ser somadas como casos únicos, pois há sobreposição.
- Hashes dos arquivos de histórico, grupo, Message e configuração administrativa conferidos entre checkout e `/app`. Worker dev recarregado após quiet e zero jobs ocupados; cron histórico habilitado em `*/5 * * * *`, Graph v26.0 e policy de grupos carregados. Sem recibos históricos reais pendentes no runtime dev ao conferir.
- Banco descartável `viperchat_meta_history_test` removido depois de conferir zero sessões e zero mensagens/contatos/anexos/blobs/recibos (28.045.795 bytes). Fontes, testes, APK e capturas de referência preservados; assets obsoletos próprios removidos. Sem limpeza global de cache ou volumes. Espaço livre do SSD ao fechar: cerca de 44 GiB; não é uma alegação de recuperação de todo esse espaço.
- Nada aplicado na VPS ou no painel Meta. Sem commit/push, imagem publicada, Archive iOS ou instalação em aparelho nesta etapa.

## 35. Compatibilidade Embedded, formatos oficiais e replay controlado (2026-10-17)

### Limites do aceite e login real

- Graph/SDK `v26.0`, configuração do Embedded Signup, `sessionInfoVersion` e versões dos campos de webhook são contratos distintos. Preservado `sessionInfoVersion: '3'`; não houve alteração de assinaturas/configuração no painel Meta.
- A conta 1 de dev tem App ID, configuração e segredo presentes, mas a flag de criação Embedded está desativada. Nenhum segredo foi impresso ou copiado para evidências.
- O usuário dispõe somente do número de produção. **Não concluir seu Embedded em dev**: o cadastro/reauthorização pode trocar o callback do número e afetar a VPS sem um deploy. O login real exige outro número WhatsApp Business e ativos de homologação, permissões Meta apropriadas e domínio dev autorizado. O usuário entra na própria conta Facebook, autoriza os ativos de teste e executa o pareamento; senha, código SMS e tokens não devem ser enviados ao chat.
- Teste no navegador dev usa módulos reais e fronteira SDK simulada, bloqueando o envio de autorização. Isso verifica o processamento local, não a elegibilidade Meta, o popup real, as permissões nem o recebimento de webhooks reais na URL dev.

### Discrepâncias confirmadas e corrigidas em dev

- O retorno `FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING` documentado pode trazer somente `waba_id`. `business_id`, não utilizado na troca/consulta, deixou de ser obrigatório nas três camadas. Sem `phone_number_id`, somente uma opção inequívoca na resposta da WABA permite continuar. Número solicitado ausente, várias opções ou paginação ambígua interrompem o fluxo; nunca escolhem silenciosamente outro telefone.
- `ERROR` maiúsculo e diagnóstico em `data.error_message` são tratados, incluindo `CANCEL` com erro explícito, preservando os formatos anteriores e o cancelamento comum.
- `history` também aceita o envelope documentado de mídia posterior em `value.messages[]`, com o mesmo corte de idade, conta, canal e ativação do vínculo. Um contexto retido do mesmo ID pode provar destinatário/direção; sem prova suficiente o item permanece pendente. Lotes grandes são particionados antes da retenção.
- Status históricos `SENT`, `DELIVERED`, `READ`, `PLAYED`, `PENDING` e `ERROR` têm mapeamento explícito. `PLAYED` corresponde a lida; confirmação não regride para status anterior/erro e não produz eventos de envio de bot.
- A recusa de compartilhamento `2593109` é recebida como controle registrado/desabilitado, não como lote malformado a retentar. Contagem de contatos do `smb_app_state_sync` lê `state_sync[]`; o evento continua sem importação/mesclagem automática da agenda.
- **A chamada inicial de sincronização `smb_app_data` ainda não está implementada.** Importar automaticamente lotes recebidos não equivale a solicitar o compartilhamento inicial à Meta; essa etapa continua condição explícita para afirmar onboarding com sincronização completa. Não foram adicionadas escritas Graph automáticas durante este aceite.

### Coleta real e isolamento da reprodução

- Acesso SSH autorizado somente para leitura. Coleta limitada de logs de 24 horas, mais consultas delimitadas em transação PostgreSQL `READ ONLY` com timeout. Sem troca de callbacks, assinaturas, hostpaths, imagem, status de atendimento, contatos ou dados da VPS.
- Da caixa em coexistência foram coletados **32 webhooks**, com 18 envelopes de mensagem representando **nove mensagens distintas**, cada uma observada nos dois provedores; três echoes por provedor e recibos restantes. A amostra não é apresentada como dez conversas.
- Para a carga de dez conversas, selecionados eventos ViperConnect reais da mesma conta, conferindo os IDs de conversa e contato no banco: **dez conversas e dez contatos distintos**, sete áudios e três textos. Remetentes diferentes que já pertenciam ao mesmo contato/conversa não contam como dois casos.
- Nessa carga, o envelope Uno e seus IDs são reais; a contraparte Meta é construída sinteticamente a partir da identidade original. Os bytes de mídia são arquivos mínimos de teste: não foram baixados arquivos dos clientes nem acessado o S3 de produção. O replay separado dos 32 eventos usa envelopes reais dos dois provedores.
- Replays usam bancos e filas de teste isolados, HTTP interno assinado e execução restrita aos jobs de entrada. Rede externa, envio WhatsApp, bots, notificações e storage real ficam bloqueados; nenhum payload é enviado ao endpoint ativo do dev. O teste alterna principal, ordem de chegada e reentregas, com conferência dos IDs e da quantidade de bolhas/anexos/blobs.
- Capturas privadas ficam fora do Git e serão descartadas após o aceite. As regressões sintéticas permanecem no repositório; fixtures reais não devem acompanhar commits ou CI.

### Username: contrato separado de identidade

- A documentação Meta acrescenta `contacts[].profile.username`, `country_code`, `user_id`, `from_user_id`, `to_user_id` e `recipient_user_id`; telefone e `wa_id` podem vir vazios. Na amostra de 32 eventos não apareceu `profile.username`; sua validação é baseada no contrato oficial, não em uma ocorrência real dessa amostra.
- Username é dado mutável de perfil, nunca credencial, telefone, ID de mensagem, chave de correlação ou justificativa isolada para mesclar contatos. O ID opaco `user.*` também não é convertido em telefone. WAMIDs desconhecidos não ganham um decodificador especulativo; seguem a política de evidência pendente.
- `business_username_updates` permanece informativo/auditado; isso não habilita gestão ou reserva de usernames empresariais pela interface.

Referências oficiais consultadas pelo mecanismo de pesquisa de documentação Meta: [Embedded Signup](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/implementation/), [coexistência e histórico](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/), [BSUID e usernames](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids). O acesso HTTP direto às páginas retornou 429; a consulta não representa validação contra uma conta Meta real.

### Resultado do replay e correção decorrente

- O primeiro replay estrito dos 32 eventos falhou. A coleta inicial não continha as provas do contato/dispositivo empresarial para recibos com LID hospedado. Essas provas foram consultadas somente para leitura e acrescentadas ao banco sintético, sem afrouxar a comparação de identidade nem mudar o decodificador de IDs.
- Com as provas completas, bolhas e aliases estavam corretos, mas um recibo Uno somente de status ainda criava outro contato. **Corrigido no código:** em caixas vinculadas, a lista `contacts` de um recibo não é importação de agenda. O status continua aplicado à mensagem comprovada; a caixa Uno sem vínculo conserva seu fluxo anterior. Regressão sintética permanente cobre o problema com ambos os principais.
- Reteste estrito: **4/4 exemplos passaram, 384 requisições HTTP internas**, alternando principal e ordem e repetindo os eventos. Cada execução preservou nove bolhas, ambos os aliases por mensagem e os 15 contatos pré-carregados como evidência; nenhum contato adicional, download ou I/O de mídia. Os IDs canônicos ficaram estáveis nas reentregas.
- A carga de dez conversas teve **20 exemplos aprovados**: casos totalmente sintéticos e casos Uno reais com contraparte Meta/bytes de mídia simulados, incluindo defaults, ordens, repetição, assinatura e caixas sem vínculo. Por cenário real pareado: dez conversas, dez mensagens, vinte identidades e sete downloads/blobs simulados.

### Fechamento de username e regressões

- Perfis Meta em mensagens, echoes e recibos atualizam username somente após comprovar mensagem, destinatário, conta e vínculo; a deduplicação não impede atualização legítima do perfil. Omissão do campo não apaga o cadastro; reutilização do mesmo username por BSUIDs diferentes não mescla pessoas. Formato existente com `@` é preservado no campo canônico; os espelhos sociais mantêm a normalização anterior.
- Acrescentado o formato documentado `user.<64 caracteres hexadecimais>` às identidades WhatsApp, sem normalizar seu valor, tratá-lo como telefone ou presumir suporte novo no transporte Twilio. Os campos `recipient_user_id` e `recipient_parent_user_id` são evidências aditivas separadas no registro de observação, não IDs substitutos.
- Avatar de destinatário comprovado continua sincronizando com os metadados existentes. Recibo Meta de mensagem desconhecida não cria um contato nem dispara download de foto. O tratamento Uno fora de caixas vinculadas não foi removido.
- Aceite do principal: **95 exemplos** de regex/username/serviços Cloud e Uno e **270 exemplos** de unificação, pendências, observação, grupos, LID e contatos compartilhados, todos aprovados. Histórico após reorganização dos filtros: **73 exemplos** aprovados; Embedded/autorizações e entrada histórica/administrativa: **124 exemplos** aprovados. Há sobreposição entre suítes; não somar como casos únicos. Frontend do Embedded: **73 testes** aprovados e teste no navegador com SDK simulado. Arquivos de produção revisados com RuboCop sem infrações.
- Bundles Android/iOS regenerados, 196 arquivos idênticos por hash; `assembleDebug` aprovado e APK anterior preservado. Sem aparelho Android conectado; Mac sem SSH disponível. Não houve teste em aparelho nem compilação/Archive iOS.
- Sem commit/push, publicação, implantação ou alteração de dados/configuração Meta/VPS. Login real continua bloqueado por ausência de um número de homologação; solicitação inicial `smb_app_data` continua pendente, conforme acima. Isso não é aceite irrestrito para subir a versão.

### Temporários e bloqueio de limpeza

- Bancos e Redis descartáveis dos subagentes de carga/replay foram removidos após conferir ausência de registros/sessões. Quatro snapshots/logs descartáveis do navegador desta rodada foram removidos; arquivos anteriores do usuário e evidências úteis foram preservados.
- A ferramenta bloqueou a limpeza do container `viperchat-history-compat-20261017` e de `C:\Users\caita\AppData\Local\Temp\viperchat-history-lint-20261017` **mesmo após autorização expressa do usuário**. A verificação anterior mostrou somente `sleep 3600` e uma cópia de lint de 2.019.523 bytes. Não houve tentativa de contornar a política; os dois itens permanecem pendentes.
- Também permanecem, até concluir a limpeza por um mecanismo autorizado, o Redis local exclusivo `viperchat-meta-final-redis`, o banco isolado `viperchat_meta_embed_validation` e as capturas privadas em `C:\Users\caita\AppData\Local\Temp\viperchat-meta-replay-20261017` e nos dois JSONs `/tmp/viperchat-production-*.json` do container dev. Não são fixtures de Git nem envios pendentes. Não remover volumes/bancos ativos, caches compartilhados, APKs ou backups como substituição para essa limpeza.
- Espaço livre do SSD na conferência final: aproximadamente 43,5 GiB. Containers normais ViperChat e ViperConnect continuaram ativos.

## 36. Solicitação inicial `smb_app_data` em dev (2026-10-17)

Esta etapa implementa a pendência de solicitação inicial registrada na seção 35. O recebimento e o importador automático existentes continuam sendo usados; não é um segundo importador ou uma migração dos IDs atuais.

### Disparo e permissões

- Ao concluir o Embedded (cadastro ou reautorização), enfileirar a verificação da sincronização. Salvar a configuração existente com **ignorar histórico desmarcado** também enfileira a verificação, usando os dias configurados. Salvar com histórico ignorado não solicita nada.
- A execução exige `WHATSAPP_SMB_SYNC_ENABLED=true`, conta ativa, canal `whatsapp_cloud`, autorização válida e importação habilitada na caixa. A variável é uma liberação operacional explícita, desligada por padrão e **mantida desligada nos containers dev**, que contêm credenciais de produção. Nos testes isolados ela é habilitada com Meta simulada; não habilitar globalmente na réplica com números de clientes.
- Consultar `is_on_biz_app` e `platform_type` do número antes dos POSTs. Exigir coexistência confirmada (`true` e `CLOUD_API`), sem transformar números Cloud comuns em coexistência.
- Preparar primeiro as assinaturas `history`, `smb_app_state_sync` e `smb_message_echoes`, preservando os campos adicionais configurados e as regras já existentes para outros números da mesma WABA. Se essa preparação falhar, não solicitar sincronização.
- A configuração continua restrita ao administrador e à conta da caixa. O acréscimo `initial_history_sync` nas respostas administrativas expõe somente o estado e IDs técnicos das solicitações daquela caixa, nunca tokens ou payloads de mensagens. Não foi adicionada uma nova tela nesta etapa.

### Contrato de solicitação

Enviar sequencialmente para `POST /<versão Graph>/<phone_number_id>/smb_app_data`, com Bearer token e JSON:

```json
{"messaging_product":"whatsapp","sync_type":"smb_app_state_sync"}
```

Somente após confirmação dessa primeira solicitação, enviar:

```json
{"messaging_product":"whatsapp","sync_type":"history"}
```

- Guardar os `request_id` confirmados. Aceitação do pedido **não significa** consentimento concedido, lotes recebidos ou importação concluída. Os recibos e contagens da seção de eventos continuam sendo a evidência de importação.
- O endpoint não documenta parâmetro de quantidade de dias. Não enviar um campo inventado: aplicar `history_max_age_days` na filtragem dos webhooks e novamente no importador existente, antes de criar mensagens ou baixar arquivos. Alterar os dias não repete uma solicitação já enviada e não recupera lotes antigos já descartados.
- A Meta permite solicitar cada sincronização uma vez por onboarding, dentro de 24 horas de sua conclusão. **A janela de uma instalação legada não é presumida nem renovada pela data de criação da caixa ou por reautorização.** A elegibilidade temporal é validada pela Meta; o serviço não inventa uma data de onboarding, não faz offboarding e não tenta contornar recusa, expiração ou ausência de consentimento. Um novo onboarding real ainda exige fluxo controlado separado; não limpar o diário para forçar reenvio.

### Diário durável e segurança

- Nova tabela aditiva `whatsapp_smb_sync_requests`, com conta, canal, WABA, número empresarial, tipo, dias, instante de despacho, estado e `request_id`. Índice único por `phone_number_id` e tipo, reserva transacional PostgreSQL **antes do HTTP** e conferência da conta/canal/WABA impedem envio simultâneo repetido ou reaproveitamento entre contas.
- Estados: `prepared` (ainda não enviado), `dispatched` (reservado antes da chamada), `accepted` (resposta válida com `request_id`), `rejected` (falha local confirmada antes do HTTP) e `uncertain` (envio sem confirmação segura). Um processo que cair depois da reserva não provoca outro POST na execução seguinte.
- Timeout, resposta inválida ou erro HTTP depois de despachar são conservadoramente incertos, inclusive quando a Meta puder ter processado o pedido. **Não repetir automaticamente** essas chamadas de uso único. Falhas preparatórias têm até cinco tentativas com espera de aproximadamente cinco minutos; não são reenvios de pedidos já despachados.
- Falha no pedido de contatos impede o pedido de histórico; falha no histórico preserva a confirmação do primeiro. Reautorização, jobs repetidos e novos saves não apagam o diário.
- O cliente HTTP congela a configuração usada para o pedido, valida destino e tipo, limita o tempo de espera, não segue redirects nem faz retries internos. Se a identidade empresarial mudar ou o administrador desativar a importação durante a preparação, parar antes de solicitar a próxima etapa.
- Erros não expõem resposta bruta, segredo, cabeçalho de autorização ou URL assinada nos avisos/logs do fluxo novo. Os IDs atuais, contatos antigos, mensagens e mídias não são regravados por esta etapa.

### Importação e limites do aceite

- Os lotes `history` continuam sendo importados automaticamente pelo fluxo existente, com preservação de contatos, datas, IDs, notas privadas e isolamento entre contas. Reentregas e contraparte da caixa vinculada passam pela deduplicação existente antes de um segundo download/attachment/blob.
- Solicitar `smb_app_state_sync` é a primeira etapa oficial de sincronização, não autorização para mesclar/importar a agenda inteira. Seus recibos mantêm o tratamento documentado anteriormente; o importador de histórico resolve os contatos das mensagens de forma comprovada.
- Migração aplicada apenas ao banco local de desenvolvimento e ao banco isolado de testes. Nenhuma alteração de fonte compartilhada do frontend, bundle nativo, login real, assinatura/callback Meta ou VPS nesta etapa.
- Referência oficial do contrato, ordem e janela: [onboarding de usuários do WhatsApp Business App](https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users/). Testes usam HTTP simulado; não comprovam elegibilidade ou consentimento do número de produção.

### Validação desta etapa

- Rodada final congelada: **394 exemplos, zero falhas**, em 18 arquivos de specs, abrangendo cliente/serviço/job SMB, configuração administrativa, Embedded/autorizações/seleção de número, preparação de webhooks, histórico, identificação de contatos e ingestão vinculada. São casos de regressão e HTTP simulado, não 394 conversas reais.
- Teste integrado novo percorre a configuração autenticada, job inicial, consulta de coexistência, assinatura, os dois POSTs e webhook de histórico assinado. Ao repetir a configuração e o lote, ficam um contato antigo preservado, duas mensagens públicas dentro de dois dias e somente um attachment/blob/download; a mensagem de quatro dias não é importada. Não há envio WhatsApp, bot ou nota pública criada pelo importador.
- Cobertos também reserva antes do HTTP/execução concorrente simulada, queda após despacho, timeout e resposta inválida, credenciais renovadas, outra conta com ID empresarial repetido, mudança do número durante a preparação e desativação da importação durante o pedido de contatos. A revisão adicional identificou e corrigiu a troca de número/WABA durante a consulta à Meta: revalidar a identidade sob lock e usar uma instância separada com configuração comprovada antes de preparar os webhooks, sem retargeting para outro número. A suíte existente de histórico mantém as coberturas de imagem, áudio, vídeo e documento e da contraparte recebida depois pelo canal parceiro.
- RuboCop dos oito arquivos de produção/migração desta etapa sem infrações; `git diff --check` sem erro. Permanecem avisos preexistentes de depreciação Rails e de CRLF em executáveis da réplica; não são resultados omitidos de uma suíte falhando.
- Migração local `20261017000002` aprovada, sem alterações nas tabelas de contatos/mensagens/anexos. Worker dev recarregado após observar zero jobs ocupados; job e tabela reconhecidos, `WHATSAPP_SMB_SYNC_ENABLED` desligado e diário dev vazio. Nenhum POST real `smb_app_data`, alteração Meta/VPS, commit, push ou nova imagem nesta etapa.
- Reutilizados o banco e Redis de testes já existentes, sem criar novos containers, pacotes, dumps ou cópias de frontend. Os temporários anteriormente bloqueados pela ferramenta continuam com a limitação de limpeza registrada na seção 35; não houve tentativa de contornar o bloqueio. Espaço livre do SSD ao validar: aproximadamente 43,5 GiB.

## 37. Regra opcional de mensagens iniciais pela Meta — por ciclo de atendimento (dev)

### Regra aprovada e configuração

- Em **Preferências do canal → Caixa unificada / Coexistência**, acrescentar **Mensagens iniciais pela Meta**. A regra é do vínculo, não de um agente individual, e funciona com qualquer uma das caixas como principal.
- `meta_initial_messages_enabled`: desligado por padrão, inclusive nos vínculos existentes. `meta_initial_messages_limit`: padrão **5**, configurável como inteiro de **0 a 1000**; **zero desativa**, mesmo com a opção marcada. Clientes antigos que omitem esses campos preservam a configuração existente.
- Quando habilitada, reservar as primeiras N mensagens públicas elegíveis de operadores para envio pela Meta, independentemente da seleção no editor ou do transporte padrão. Depois do limite, respeitar novamente a seleção normal. Se o operador escolher Meta, isso também ocupa uma posição enquanto houver cota da regra; esgotar a regra não impede novos envios explicitamente selecionados para Meta.
- Cada mensagem sai **uma vez por um único transporte**, sem espelhamento. O seletor e os rascunhos dos editores compacto/completo não são alterados. Guardar separadamente o transporte solicitado e o efetivo; motivo do override: `initial_meta_messages`.

### Ciclo e mensagens elegíveis

- Contagem por **conversa + ciclo de atendimento + geração do vínculo**, usando o ciclo persistente já incrementado na transição de resolvida para reaberta. A caixa de conversa única mantém sua contagem até a resolução e inicia outra cota quando reabre. Sem conversa única, uma nova conversa tem sua própria cota; reabrir a mesma conversa após resolução inicia outro ciclo.
- Reabertura administrativa não dispara mensagem sozinha: apenas prepara um novo ciclo para futuros envios humanos. Mensagens enfileiradas com um ciclo anterior não são transferidas para a cota nova.
- Aplicar a mensagens de saída com remetente operador `User`, inclusive API/apps antigos e mensagens de agendamento do operador. Não aplicar a notas privadas, destino Web, grupos, echoes já persistidos, importação histórica, bots, regras automáticas, campanhas ou lembretes automáticos de ausência Web.
- Exigir recurso suportado, identidade de destinatário utilizável, canal Meta sem reautorização pendente e **janela de resposta Meta aberta por evidência daquele transporte**. Uma mensagem recebida somente pela ViperConnect não abre essa janela. Esta regra não converte texto em template nem cria templates automaticamente.
- Ajuste de 19/10/2026: a política aguarda uma resposta real do cliente **no ciclo atual**, confirmada pelo transporte Meta. Antes dessa resposta (primeiro contato ou reabertura administrativa) e após 24 horas sem resposta, mensagens humanas sem template saem pela ViperConnect, mesmo com Meta selecionada, sem consumir posição. A mensagem do cliente que reabre automaticamente a conversa já pode habilitar a regra. Usar limite de ID do ciclo e data original da evidência; histórico importado, echo, nota, Web e recebimento só pela Uno não habilitam a contagem. A expiração da janela pausa a cota restante, sem zerar posições já consumidas no mesmo ciclo; nova resposta válida permite continuar.
- Templates explicitamente selecionados mantêm seu fluxo e não consomem esta cota de respostas. Demais inelegibilidades preservam as regras de transporte/capacidade existentes. Não tentar Meta para depois cair na ViperConnect após erro: roteamento acontece antes da chamada externa; mensagens com tentativa, ID público ou decisão persistida não são reenviadas nem reroteadas.

### Reserva, concorrência e agendamento

Validação do ajuste de 19/10/2026 em dev: **174 exemplos Ruby aprovados** (política, transporte e serviços de agendamento), **34 testes frontend aprovados**, dois serviços sem infrações no RuboCop. Casos incluem Meta explicitamente selecionada com janela vencida, primeiro contato, reabertura administrativa sem resposta, mensagem recebida que reabre automaticamente, timestamp original de alias Meta, histórico importado excluído, templates explícitos, mídias/citações e repetição sem novo envio. Bundles Android/iOS regenerados e sincronizados; sem dispositivo Android conectado e Mac de validação indisponível. Não equivale a build/Archive ou teste físico. A conferência visual autenticada do aviso permanece pendente: a sessão de navegador separada abriu no login do dev. Sem aplicação na VPS, migração de dados, alteração de IDs ou limpeza de mensagens/mídias.

- Nova tabela aditiva `whatsapp_meta_cycle_slots`: conta, vínculo, conversa, ciclo, geração, posição e mensagem. Índices únicos por mensagem e por posição do ciclo; locks de mensagem/conversa serializam a reserva antes do HTTP. Nenhum telefone, ID público, mensagem histórica ou associação de mídia é substituído.
- A contagem é de **mensagens reservadas para a regra**, não uma promessa de N entregas confirmadas. Timeout ou resposta incerta mantém a posição consumida e impede fallback/reenvio automático; o provedor pode ter aceitado a mensagem. Uma exclusão local da bolha não repõe a posição: a referência opcional é anulada, preservando a reserva do ciclo.
- A intenção é capturada no backend ao preparar a mensagem nova, fora do snapshot de transporte usado para validar agendamentos. Desativar/reduzir o limite antes do despacho é respeitado; aumentar o limite não amplia retroativamente a intenção de mensagens já preparadas. Não rerotear mensagens que já têm tentativa de entrega.
- No agendamento, preservar a seleção original e atualizar o executor efetivo do item quando a regra escolher Meta. A seleção de novos envios do editor e a intenção do agendamento não são trocadas. A validação de vínculo, geração e permissões existente continua em vigor.
- A configuração entra na impressão digital da prévia e na auditoria administrativa. A regra apenas direciona tráfego: **não garante aumento de limite, franquia, gratuidade ou redução de custo**.

### Aceite em desenvolvimento

- Migração `20261017000003` aplicada somente no banco dev e nos bancos isolados de validação. Configuração não ativada em nenhuma caixa operacional; a única ativação de UI ocorreu na conta sintética 422, removida após o teste. Nada aplicado na VPS e nenhum envio real a Meta/ViperConnect.
- Onze hashes de produção conferidos entre checkout e runtime dev; worker recarregado após quiet e zero jobs ocupados. Classe da política e tabela reconhecidas no worker, zero vínculos operacionais com a opção ativa e aplicação local respondendo HTTP 200.
- Regressão ampliada: **404 exemplos Ruby aprovados**. Após acrescentar mídia/citação e excluir explicitamente campanhas/lembretes, rodada focada de **109 exemplos aprovados**, incluindo 75 casos da política, agendamento e transporte de saída. As rodadas se sobrepõem; não somar os números como casos únicos.
- Coberturas: principal Meta ou ViperConnect; primeiras duas mensagens Meta/terceira Uno; zero/desligado; alteração de limite; resolução/reabertura; conversas distintas; mídia PNG/MP3/MP4/PDF sem recriar attachment/blob; citação usando o alias público Meta, preservando o ID original; janela fechada; LID sem destinatário comprovado; reautorização; exclusões; retry/resultado incerto; remoção local sem repor a posição; parâmetros e confirmação administrativa.
- Concorrência real PostgreSQL: runner `script/validation/whatsapp_initial_meta_concurrency.rb`, protegido por nome exato de banco e ambiente. Com **quatro conexões independentes**, nos dois sentidos da principal, quatro mensagens reservaram exatamente duas posições Meta e mantiveram duas Uno; repetir o processamento não criou outras reservas. Banco temporário exclusivo removido após conferir zero sessões: **22.450.659 bytes**, reproduzível pelo runner e schema.
- Frontend: **25 testes aprovados**; ESLint sem erros, com dois avisos de formatação preexistente em `<pre>`. Oito arquivos de produção/migração conferidos com RuboCop sem infrações. `git diff --check` sem erros.
- Aceite autenticado da página real em conta sintética: ativar regra, manter quantidade cinco, gerar prévia, confirmar/salvar e conferir no PostgreSQL que o padrão permanece Uno. Novos controles sem overflow horizontal em 320/360/390/412/430/844/1280 px; retrato e paisagem, captura desktop/mobile e controle acessível após fechar o menu lateral. Avisos preexistentes de WebSocket e endpoint Enterprise de limites 404 não foram considerados aceite de tempo real.
- Bundles Android/iOS regenerados via runtime Node/pnpm compatível no Docker; **196 arquivos idênticos** entre os dois bundles novos. Android `assembleDebug --offline` aprovado, APK em `android/app/build/outputs/apk/debug/app-debug.apk`. Nenhum aparelho listado pelo `adb`; Mac `192.168.0.120:22` indisponível. Não houve instalação/teste físico nem compilação/Archive iOS. Não é uma publicação de release.

### Preservação e temporários

- Conta sintética, seus contatos/conversas/mensagens e credenciais efêmeras removidos após o aceite; navegador de teste fechado. Nenhum cadastro ou arquivo real foi apagado. Capturas pequenas de aceite e APK de validação preservados como entregáveis.
- A ferramenta **bloqueou** a remoção de 29 assets compilados obsoletos em cada pasta `android/app/src/main/assets/public` e `ios/App/App/public`, identificados por comparação com o bundle novo e ausência no Git: **38.759.408 bytes** no total. Nenhum desses arquivos foi removido e não houve tentativa de outro mecanismo para contornar o bloqueio. Permanecem como arquivos gerados antigos, sem impedir o bundle novo; fontes, versões de APK preservadas e demais artefatos do usuário não foram incluídos na limpeza.
- Sem novos containers, dumps ou pacotes de transferência. Os temporários anteriormente bloqueados da seção 35 continuam com sua restrição própria. Espaço livre do SSD na conferência final: aproximadamente **43,42 GiB**. Sem commit, push, imagem publicada ou alteração na VPS nesta etapa.

### Pendência: validar gratuidade e contagem para otimização

- **Pendente de validação:** verificar nas regras oficiais vigentes se a hipótese de mil mensagens gratuitas pela Meta se aplica a esta instalação. Não tratar essa franquia como existente ou disponível antes da comprovação.
- Confirmar unidade de cobrança (mensagem ou conversa), categorias e janelas gratuitas, escopo (número, WABA ou portfólio), período e reinício da eventual franquia. O limite de clientes em 24 horas não deve ser confundido com gratuidade financeira.
- Definir a contagem com base nos eventos efetivos e conciliar com insights e informações de cobrança da Meta, sem contar novamente echoes, reprocessamentos ou mensagens duplicadas; distinguir tentativas, falhas, entregas e mensagens recebidas.
- Após essa validação, simular a otimização da regra das primeiras mensagens via Meta em relação ao transporte padrão, identificando valores estimados ou indisponíveis. Não apresentar economia sem tarifas e regras verificadas.
- Esta pendência não altera a política inicial por ciclo já implementada nem ativa roteamento por custo. Implementação, aceite e eventual aplicação na VPS serão etapas separadas.

## 38. Criação de modelos oficiais pelo ViperChat — desenvolvimento

### Entrega

- Em **Configurações → Caixas de entrada → caixa oficial Meta → Modelos da Meta**, administradores podem consultar o cache, sincronizar e submeter um novo modelo à análise. O recurso funciona independentemente de a caixa estar vinculada e não muda o transporte do editor.
- Primeira versão: categorias Marketing e Utilidade; português do Brasil, inglês dos EUA e espanhol no formulário; corpo de até 1.024 caracteres; variáveis posicionais `{{1}}`, `{{2}}` em sequência com exemplos; cabeçalho e rodapé de texto até 60 caracteres; até três respostas rápidas OU dois botões de URL HTTPS estática. Prévia escapada, sem executar HTML, e envio apenas por ação explícita.
- Modelos NAMED já existentes continuam disponíveis no cache e no fluxo de envio anterior. Esta versão do formulário não cria modelos com variáveis nomeadas, mídia no cabeçalho, autenticação, carrosséis ou demais formatos avançados; o gerenciador da Meta continua disponível para esses casos. Não há edição/exclusão de modelos nesta entrega.
- Criar um modelo não envia mensagens aos contatos nem garante aprovação. O retorno mantém ID, categoria e situação informados pela Meta; quando a criação não informa situação, o cache assume somente `PENDING`, nunca aprovação presumida. Sincronizar atualiza as situações reais.

### API e segurança

- Rotas autenticadas e restritas a administradores, com isolamento por conta/caixa e somente `whatsapp_cloud`:
  - `GET /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_templates`: cache local e data da última sincronização.
  - `POST /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_templates`: criação com objeto `template` contendo `name`, `category`, `language`, `body`, `header`, `footer`, `examples` e `buttons`.
  - `POST /api/v1/accounts/:account_id/inboxes/:inbox_id/whatsapp_templates/sync`: atualização síncrona com retorno de sucesso ou erro na mesma requisição.
- Graph utiliza a versão centralizada e credencial já configurada na caixa, enviada no cabeçalho, sem alterar Embedded, configuração de login, permissões ou coexistência. Não seguir URLs de paginação fornecidas pela Meta: reconstruir o endpoint fixo com cursor e limite de páginas. Falha de sincronização preserva o cache anterior; lista vazia válida limpa o cache.
- Erros de permissão da Meta, credencial inválida, validação, rejeição e resultado incerto são diferenciados. Código técnico e mensagem de erro destinada ao usuário, quando fornecida pela Meta, aparecem escapados; tokens são removidos da mensagem. Não devolver nem registrar erros brutos/credenciais.
- Migração `20261017000004` adiciona `whatsapp_template_requests`: reserva durável antes do POST, identidade única por conta/WABA/nome/idioma e impressão digital da definição. Repetição aceita retorna o resultado anterior; conteúdo diferente para a mesma criação aceita gera conflito. Rejeição definitiva permite nova tentativa explícita.
- Timeout, interrupção ou resposta ambígua não repetem automaticamente o POST. Sincronização pode recuperar o resultado pelo mesmo nome, idioma e componentes, sem correlacionar só por texto. Uma criação aceita concorrente à sincronização não é perdida do cache. Nenhum ID atual de contato, mensagem ou provedor é alterado e nenhuma mídia é recriada.

### Aceite e pendências

- Migração aplicada somente na réplica dev e banco isolado `viperchat_meta_embed_validation`. **197 exemplos Ruby e 56 testes de frontend aprovados**, cobrindo também regressão de Embedded/autorização, CSAT, templates existentes, isolamento, respostas da Meta simuladas, replay, timeout, paginação e preservação do cache. Sete arquivos de produção/migração sem infrações RuboCop; ESLint sem erros, com avisos de estilo/i18n.
- Playwright na página autenticada com conta sintética: prévia, falta de permissão com mensagem/código e rascunho preservado, sucesso `PENDING`, 320/360/390/412/430 px, paisagem 844×390 e desktop 1280×900. Corrigido o banner de migração adjacente que causava overflow horizontal no mobile; capturas pequenas preservadas em `output/playwright/meta-template-*.png`.
- Bundles Android/iOS regenerados, idênticos no runtime, e APK Android debug compilado offline. `adb` sem aparelho; Mac de desenvolvimento sem acesso à porta 22. Sem teste físico Android/iOS, Archive iOS, nova versão de release ou publicação.
- **Pendente:** confirmar `whatsapp_business_management` e acesso à WABA no token real; fazer criação, aprovação/rejeição e sincronização reais em ação controlada. Não solicitada permissão nova, não reconectado o número e não criado template real durante os testes de submissão, que usaram respostas simuladas.
- Sem commit, push ou aplicação na VPS nesta etapa. A pendência de gratuidade/custos da seção 37 permanece independente.
- Limpeza: conta sintética 423 e seus registros removidos após o aceite, navegador fechado e cinco snapshots/logs intermediários descartados (**85.004 bytes**, regeneráveis). Banco isolado sem contas ou solicitações de templates residuais; banco dev sem solicitações reais de criação. APK e três capturas de aceite preservados. Sem novos containers, dumps ou pacotes de transferência; restrições anteriores de limpeza de assets permanecem respeitadas. SSD com aproximadamente **43,35 GiB** livres ao concluir.

## 39. Nova mensagem e encaminhamento na caixa unificada — desenvolvimento

### Consolidação no repositório — 17/10/2026

- Autorizada a consolidação das correções, testes e planejamento desta sequência na branch `feat/whatsapp-unified-inbox-dev`, com commit e push. Os registros abaixo de “sem commit/push nesta etapa” descrevem o estado ao concluir cada aceite local, antes desta consolidação.
- Capturas, logs temporários, credenciais e artefatos gerados de build não integram o commit. A publicação no Git não aplica migrações, imagem ou hostpaths na VPS nem publica os apps nativos.
- Permanecem pendentes os aceites reais explicitados nas respectivas etapas, incluindo permissões da Meta, aparelhos físicos e validação da eventual franquia de mil mensagens; não alterar as regras de custos por suposição.

### Experiência operacional

- Os seletores de **Nova mensagem** e **Encaminhar mensagens** mostram uma opção por vínculo ativo, com nome e ID da principal. A API de caixas contatáveis também retorna a principal uma única vez, usando seu alias existente quando disponível. A coleção administrativa continua expondo as duas caixas físicas, com metadados operacionais adicionais filtrados pela autorização da principal.
- A escolha independente **Enviar por: Meta / ViperConnect** inicia no transporte padrão. O modo do editor, os templates e o ID físico usado para consultar o catálogo seguem o transporte selecionado, não o provedor da principal. Alternar preserva texto/anexos; a nova mensagem persiste o transporte tanto em JSON quanto em FormData, inclusive Uno com somente anexos.
- A Meta continua exigindo template no atalho de nova conversa, de maneira conservadora. Encaminhamento livre pela Meta verifica a janela do destino antes de salvar mensagens/anexos; janela fechada retorna erro, sem tentativa automática pelo parceiro. Regras de capacidade e primeiras mensagens do ciclo continuam no fluxo compartilhado de saída.
- Grupos permanecem nos destinos físicos atuais, sem aplicar o agrupamento de atendimentos individuais. Não declarar unificação de grupos por conta desta entrega.

### Backend, identidade e preservação

- Solicitações antigas que apontem para a secundária são resolvidas na principal antes da criação, respeitando a autorização dessa principal. Ter acesso apenas à secundária não concede acesso à principal. Contatos e mensagens de outras contas, fontes de outras conversas, notas privadas, mensagens de atividade ou excluídas não são encaminhados como conteúdo externo.
- Criação e encaminhamento reutilizam o atendimento individual ativo da principal, preservando responsável/equipe e situações pendente/adiada. Com conversa única, resolver/reabrir mantém o ID e inicia novo ciclo; sem conversa única, um atendimento resolvido permanece no histórico e um novo é criado. Lock da associação contato/caixa serializa criações concorrentes. Conversas legadas da secundária não são movidas nem apagadas.
- Comparação de destinatário brasileiro aceita os aliases móveis equivalentes com oito/nove dígitos usando o normalizador já adotado no vínculo. Não regravar números antigos, IDs, nomes ou mesclar contatos; evidência ambígua continua sendo recusada.
- Para contato existente conhecido apenas por LID no Uno, com principal Meta, uma nova associação interna pode usar `unified-contact:<contact_id>` e marcador de identidade pendente. A validação aceita essa associação somente na principal Meta vinculada, com associação Uno preexistente do mesmo contato. Ela não é um destinatário Meta válido: o transporte Uno usa seu próprio alias, enquanto enviar pela Meta permanece bloqueado antes da chamada externa até existir identidade válida. O alias antigo não é alterado.
- Encaminhar cria uma nova mensagem intencional, com autor atual, destino canal e metadados próprios de transporte. Não herdar aliases, chaves de entrega/idempotência, citação, template ou metadados de Web/bot da origem; manter apenas os atributos de conteúdo permitidos e IDs internos de proveniência.
- Imagem, áudio e PDF reutilizam **o mesmo blob** na mesma conta, criando somente a associação/anexo da mensagem encaminhada. Não baixar o arquivo nem gerar novo objeto S3. Preservar também os campos dos anexos sem arquivo, como contato e localização.

### Aceite em dev

- **395 exemplos Ruby aprovados**, incluindo 134 casos dos fluxos novos/encaminhamento e regressões de conversas, contatos, identidade direta, modelos, envio e política inicial Meta. **78 testes de frontend aprovados na rodada integrada do agente principal**; a rodada do subagente cobriu 96 casos em nove arquivos, com sobreposição — não somar como casos únicos. RuboCop nos oito arquivos de produção sem infrações, ESLint sem problemas e `git diff --check` sem erros.
- Runner reproduzível `script/validation/whatsapp_unified_compose_concurrency.rb`: banco temporário exclusivo, dez contatos sintéticos, quatro conexões PostgreSQL independentes por contato e 40 mensagens intencionais; um atendimento por contato durante a disputa, ambos os sentidos da principal, conversa única ligada/desligada e IDs históricos preservados. Banco temporário de **24.453.647 bytes** removido após conferir zero sessões; nenhum dump ou container adicional.
- Playwright: seletores reais com uma opção principal, alternância de transporte com rascunho preservado, 320/360/390/412/430 px, paisagem 844×390 e desktop 1280×900. Capturas em `output/playwright/unified-compose-*.png` e `unified-forward-*.png`. Nenhum envio real foi solicitado aos provedores.
- Bundles Android/iOS regenerados e idênticos no runtime; APK Android debug compilado offline. `adb` sem dispositivo e Mac de desenvolvimento indisponível: não houve teste físico nem Archive iOS. Apps antigos se beneficiam da resolução no backend e da lista contatável, mas o novo seletor e a mudança de modo do editor exigem o bundle atualizado.
- Sem alteração de IDs existentes, remoção de mensagens/mídias reais, commit, push ou aplicação na VPS. Aceite com provedores reais, aparelhos e publicação continuam etapas separadas; testes sintéticos não são garantia de todo comportamento externo em produção.
- Conferência final: dez hashes de backend/views coincidem entre checkout e runtime dev; aplicação local responde HTTP 200. Após preservar explicitamente o comportamento de caixas sem vínculo na lista contatável, 74 casos focados de contatos/metadados foram reexecutados (sobreposição com a regressão ampliada). Removido o log de depuração do objeto completo da caixa no editor novo, que poderia expor configuração sensível no console de dev.
- Limpeza: conta sintética 424 e registros próprios removidos, navegador fechado e nove snapshots/logs intermediários descartados (**33.489 bytes**, regeneráveis). Capturas pequenas de aceite e APK preservados. Nenhum container, dump ou pacote de transferência novo; não tentada novamente a limpeza de assets anteriormente bloqueada na seção 37.

## 40. Complementos da release — etiquetas e OpenRouter em dev

- Administradores podem habilitar `allow_agents_to_create_labels` nas configurações da conta. O padrão é desativado. A autorização de criação é verificada no backend; editar e excluir continuam restritos ao administrador. A interface libera o cadastro nas etiquetas da conversa, dos contatos e do agendamento, sem ampliar o acesso às configurações administrativas.
- Super Admin → Captain apresenta o catálogo dinâmico da OpenRouter, com seletores independentes de conversa e transcrição, quando o endpoint oficial da OpenRouter está configurado. O catálogo é público, não recebe credenciais e tem cache de uma hora; falhas preservam a seleção salva. A transcrição lista apenas modelos com entrada de áudio e saída de transcrição. O catálogo de conversa não garante suporte a ferramentas/JSON de todos os modelos; essa variação é avisada na tela.
- IDs de modelos com prefixo de provedor passam pelo SDK sem depender do registro estático. Configurações OpenAI existentes, escolhas por conta, embeddings e a hierarquia das permissões são preservados. Endereços com `/v1` não recebem a versão em duplicidade. O modelo de áudio tem configuração própria; a transcrição usa a API de áudio da OpenRouter, preserva metadados do anexo, aceita aliases MPEG/MP3 e remove o arquivo intermediário inclusive em erro. Não há retry automático de chamada paga nem fallback silencioso para outro provedor.
- **Aceite:** 111 testes Ruby e sete testes de frontend aprovados; RuboCop nos nove arquivos de produção avaliados e ESLint dos componentes/helpers novos sem infrações. Banco isolado confirmado antes de executar a suíte, com configuração temporária em transação e rollback. Não confundir testes de contratos com validação individual de cada modelo disponível.
- Na rodada de chamadas reais mínimas, o catálogo retornou 471 modelos de conversa e 26 de transcrição. Foram aprovados texto, resposta estruturada pelo SDK do Captain e três segundos de áudio sintético. A chave foi lida da VPS por SSH autorizado, apenas para essa validação; nenhuma configuração, mensagem, mídia ou deploy foi alterado em produção. Não foi realizado disparo pago contra cada item do catálogo.
- Playwright: configuração da conta e seletores do Super Admin sem overflow horizontal em 320/360/390/412/430 px e desktop de 1280 px; seleção antiga preservada e separação dos catálogos conferida. O cadastro de etiquetas tem cobertura de permissão, busca/prefill e preservação da atribuição normal. Bundles Android/iOS regenerados no runtime dev; não houve nova publicação dos apps nem aceite em aparelhos físicos nesta etapa.
- **Limpeza:** conta sintética 569, seus usuários e Super Admin 265 removidos e contagens residuais iguais a zero; banco de teste sem contas/usuários residuais; navegador fechado e perfil temporário removido. O snapshot contendo um campo secreto foi removido manualmente pelo usuário e sua ausência foi conferida. Oito outros snapshots/logs próprios foram descartados (**12.466 bytes**, regeneráveis), sem apagar evidências de outras tarefas. Captura pequena de aceite preservada; nenhuma credencial adicionada às fontes. Sem commit, push ou aplicação na VPS nesta etapa.

## 41. Endereçamento Meta: telefone divulgado e BSUID — correção em dev (19/10/2026)

- Inspeção SSH/PostgreSQL somente leitura na VPS: contato `53314`, telefone canônico `+5565996598456`, LID Uno `30984414191647@lid`. Na caixa Meta `65`, o alias `214135` (`BR.1316081087211411`) foi criado antes do alias de telefone `214136` (`556596598456`). O recebimento Meta da mensagem `2493867` correlaciona explicitamente esse telefone sem nono dígito com esse BSUID. Não reescrever nenhum desses registros.
- O resolvedor anterior escolhia o primeiro alias válido pela ordem de criação: portanto selecionava o BSUID mesmo após a Meta informar um telefone. O adaptador oficial colocava indistintamente o resultado em `to`. O defeito de contrato foi reproduzido com quatro testes inicialmente falhando: duas ordens de principal/parceira e endereçamento por telefone/BSUID. As requisições foram interceptadas pelo WebMock, sem enviar mensagens reais.
- Novo `Whatsapp::OutboundRecipientService`: para Meta, preferir o alias de telefone da própria caixa, exatamente como recebido (inclusive móvel brasileiro sem nono dígito). Se houver apenas BSUID, preservar seu valor completo e usar `recipient` no payload, removendo `to`; nunca transformar BSUID em telefone ou misturar LID Uno com destinatário Meta. O telefone canônico continua sendo o fallback existente quando não houver alias Meta utilizável. Para ViperConnect e grupos, preservar o endereçamento atual.
- A preferência de endereço de saída não muda a estratégia BSUID-first de identificação/correlação do contato. Não há migração, mesclagem, substituição de `source_id`, alteração do identificador original de correlação, renumeração de mensagens nem recriação de anexos/blobs. O adaptador comum trata as chaves de payload de texto e mídia, preserva citação e template e não é aplicado ao override de identidade da Uno.
- O `131026` observado nas tentativas seguintes significa falha genérica de entrega; não prova ausência de template nem, isoladamente, que este defeito foi a única causa. Nos registros consultados, as duas saudações já estavam com transporte Uno, enquanto envios seguintes reservaram as posições Meta e falharam. Não inferir o transporte da primeira tentativa apenas pelo estado final após retry manual. Não adicionar fallback/reenvio automático após uma tentativa externa a partir desse código genérico.
- Referência de contrato consultada: [guia do SDK Cloud API — BSUID recipient support](https://github.com/netflie/whatsapp-cloud-api/blob/main/UPGRADE.md#bsuid-recipient-support). A referência direta da Meta retornou HTTP 429 na consulta. O aceite aqui é sintético de contrato; validação externa controlada é uma etapa posterior, somente após autorização de publicação.
- Aceite em banco isolado `viperchat_meta_embed_validation`: **270 exemplos Ruby aprovados**, cobrindo resolvedor, despacho unificado nos dois sentidos de principal, providers Meta/Uno, política inicial Meta e serviços de agendamento. Inclui citação com ID preservado, mídia com attachment/blob preservados, template, aliases de outra caixa não reutilizados e repetição sem nova requisição. Quatro arquivos avaliados pelo RuboCop sem infrações e `git diff --check` sem problemas. Mudança exclusivamente backend; sem alteração adicional de frontend ou necessidade de novo bundle por esta correção. Sem commit, push, build de imagem ou aplicação na VPS nesta etapa. Sessão SSH encerrada; nenhum dump, container ou pacote temporário adicional criado.

## 42. Contato canônico e reconciliação administrativa dos seis legados (19/10/2026)

- O diagnóstico somente leitura encontrou mensagens distribuídas entre o contato antigo com telefone e um contato legado identificado apenas pelo BSUID. Nos 36 registros públicos recentes inspecionados, cada mensagem tinha correlação entre os dois provedores, sem repetição física pelo mesmo ID original. Portanto, não apagar bolhas por semelhança de texto ou horário: o problema nesses casos é a escolha do contato, não uma autorização para excluir mensagens.
- Na ingestão nova, a Meta pode selecionar o contato antigo com telefone brasileiro equivalente com oito/nove dígitos, associado ao mesmo par de caixas e comprovado pela correlação segura da mensagem. A seleção exige um único candidato mais antigo, BSUID legado sem telefone e vínculo ativo; ambiguidades não são resolvidas por adivinhação. Não reescrever telefones, aliases ou histórico durante o webhook. Grupos e caixas sem vínculo mantêm o fluxo anterior.
- Os seis casos reais possuem cobertura sintética nas duas ordens de chegada, nos dois sentidos de principal e nas direções entrada/echo: **48 exemplos de ingestão aprovados**. A manutenção tem seis exemplos adicionais para prévia, aplicação preservando IDs/blobs, bloqueio de prévia desatualizada, telefone conflitante, grupos e referências de agendamento. A regressão integrada terminou com **320 exemplos sem falhas**, incluindo ingestão, reconciliação de mídias, telefone/LID e política inicial Meta. RuboCop dos quatro arquivos de produção sem infrações; executor com sintaxe válida. Nenhum envio externo real foi feito nesses testes.
- Prévia somente leitura feita às 11:29 de Cuiabá: **18 aliases, 12 conversas e 6 referências de remetente**, envolvendo **102 mensagens e 14 anexos**. Nenhum bloqueio encontrado naquele instante. Mapeamentos e fingerprint em [prévia da reconciliação](previa-reconciliacao-bsuid-20261019.md). Não tratar essas quantidades como estáticas: gerar nova prévia após backup e drain dos workers.
- O administrador autorizou reconciliar apenas esses seis pares durante a atualização das **12:00 de Cuiabá**, junto das regras N e destinatário/BSUID. O executor é prévia por padrão, exige fingerprint para escrita e recusa aplicação fora da data/janela autorizada. Alterar somente o dono dos aliases/conversas e o remetente Contact correspondente; preservar ambos os contatos, seus dados antigos, IDs, situações, mensagens, anexos e blobs. Não juntar conversas nem mover mensagens entre elas.
- Após aplicar, comparar o inventário de IDs, aliases, mensagens, anexos e blobs, confirmar os donos esperados e zero referências operacionais remanescentes nos legados. Dependências inesperadas ou divergência da prévia bloqueiam a manutenção; não ampliar para outros contatos. Não usar `ContactMergeAction`, exclusão ou restauração automática do banco como atalho. **Aplicado e conferido na VPS em 19/10/2026, janela das 12h**, com backup: 18 aliases, 12 conversas e seis remetentes reconciliados; 12 contatos, 102 mensagens, 14 anexos e 14 blobs preservados. Dois workers liberados, `quiet=false`, login e assets HTTP 200. Não houve disparo real de teste; observar o tráfego legítimo para aceite externo da regra N e do destinatário. Detalhes no [runbook](hostpath-meta-cycle-recipient-20261019.md).

## 43. Echoes retidos e mídias reavaliadas (19/10/2026)

- Concluir correlação por ID exato da mensagem é separado de transferir o dono de um alias de contato. Echo Meta BSUID-only pode adotar a mensagem comprovada do contato antigo sem mover o alias técnico legado, sob as provas restritas do [hotfix](hotfix-echo-pending-20261019.md). Contatos humanos conflitantes continuam bloqueados.
- Suportado o echo Meta exato de envio Uno já reconhecido, inclusive retorno WAMID seguido de echo Uno sem destinatário, preservando o transporte registrado e o `source_id`. Ciclo, conta, contato, provedor, caixa e direção continuam verificados. Um recibo Uno vazio, não vinculado e sem evidências de mensagem não conta como segunda mensagem candidata; o registro é mantido no banco. Não selecionar uma mensagem entre candidatos com contradições reais.
- Reavaliação periódica de mídias pendentes/em revisão pelo job de cinco minutos, em lote limitado. Provas BSUID incompletas permitem somente reter uma cópia canônica comprovada, não substituir/purgar múltiplos arquivos. Falta de contraparte e conflitos de direção não são convertidos artificialmente em sucesso.
- **461 testes aprovados** na regressão final e RuboCop dos cinco arquivos sem infrações. Aplicado via hostpath na VPS com backup, preservando a imagem/x-base/mounts anteriores. Dois ciclos curtos de quiet/recriação: 34 e 18 segundos até containers iniciados; validações e reprocessamento feitos com os workers liberados.
- Aceite real: **14 eventos concluídos e seis mídias retidas sem alterações de arquivo**. Comparação aprovada dos 14 contatos, 86 aliases, 11 conversas, 21 mensagens, nove anexos e nove blobs inventariados. Permanecem três mídias protegidas: 10 por conflito de direção, 444/584 por ausência de contraparte. Não foram criados envios de teste, novos contatos ou cópias de mídia para a validação.

## 44. Cadastro do mesmo telefone e pré-requisito da ViperConnect (20/10/2026, dev)

- A restrição global de `channel_whatsapp.phone_number` bloqueia a segunda caixa quando Meta e ViperConnect usam exatamente a mesma representação do número. Não orientar a remoção do nono dígito como solução para contornar essa restrição.
- A correção em dev permite somente o par Meta/ViperConnect na mesma conta. Continua proibida uma segunda caixa do mesmo transporte, outro canal oficial concorrente ou a apropriação do número por outra conta. A comparação reconhece as representações móveis brasileiras com/sem nono dígito; telefones e IDs persistidos não são reescritos.
- A migração troca exclusivamente índices, sem apagar canais, contatos, mensagens, anexos ou blobs. As verificações de propriedade são serializadas por identidade telefônica durante a transação de gravação. Reverter a migração exige resolver administrativamente os pares criados: não apagar dados para forçar o índice global antigo.
- O webhook da ViperConnect já envia seu token configurado no cabeçalho `Authorization`; essa prova permite selecionar a caixa correta mesmo com URL/telefone iguais. Meta continua usando seu `phone_number_id` e a política de assinatura existente. Evidências internas de roteamento são adicionadas pelo servidor, descartando indicações externas forjadas, e preservadas na separação dos lotes. Não escolher o primeiro canal arbitrariamente.
- Criação manual e Embedded Signup precisam respeitar a mesma regra. O cadastro do par não ativa o vínculo automaticamente nem altera a seleção de transporte.
- **Dependência de distribuição confirmada:** `v4.0.37` da ViperConnect aponta para `7577731d8fff8d7ca0e11f643df59876e5d276ed`. O campo `provider_message_id` foi acrescentado depois, em `b1668845`, e aplicado por hostpath somente no piloto descrito na seção 5.4. Em 20/10/2026, a última release publicada consultada ainda era `v4.0.37`.
- A consulta ao GHCR confirmou também a imagem real `ghcr.io/viperteccorporation/viperconnect:4.0.37`: os rótulos OCI de AMD64 e ARM64 ainda apontam para `7577731d8fff8d7ca0e11f643df59876e5d276ed`. Não foi apenas uma conclusão pelo número exibido no aplicativo ou pela tag local.
- Portanto, instalar a imagem original `4.0.37` em outro cliente não leva automaticamente esse campo. Antes de habilitar a ingestão única, conferir um webhook real e publicar uma nova versão da ViperConnect contendo o contrato aditivo. Não reutilizar/reescrever a tag antiga para ocultar essa diferença.
- Doze casos sintéticos de ponta a ponta aprovados: ambas as caixas principais, ambas as ordens de chegada e número exato ou variante sem nono dígito. Com o ID original, uma mensagem/conversa principal; omitindo o campo na ViperConnect legada, duas mensagens, sem inventar correlação por texto/telefone.
- Validação em banco PostgreSQL e runtime de teste isolados: regressão de **261 exemplos sem falhas**, incluindo correlação e ingestão de mídias; rodada final de **143 exemplos sem falhas**, incluindo os ajustes de autenticação, lotes e eventos administrativos Meta no telefone compartilhado. As rodadas se sobrepõem e não devem ser somadas como casos distintos. RuboCop dos 12 arquivos Ruby sem infrações.
- Esses testes sustentam a hipótese para o cliente, mas não substituem a inspeção de seu payload. Não foi acessado ou alterado o ambiente do cliente nem a VPS. A correção de cadastro ainda não integra a tag ViperChat `.33`, já publicada separadamente para o editor de mídia.
- Publicação autorizada na `4.16.0` para a release de servidor `v4.16.12-viper.34`, incluindo a migração `20261020160000`. Somente imagem Docker nesta etapa: os aplicativos Android/iOS permanecem na `.33`. A publicação não executa migrações nem altera a VPS. Instruções de atualização e restrição de rollback nas [notas da release .34](releases/v4.16.12-viper.34.md).

## 45. Troca de telefone da mesma pessoa e aposentadoria de LID (20/10/2026)

- Regra geral: uma troca real de telefone limpa a identidade de envio antiga e retira os aliases anteriores do uso ativo. O mesmo contato continua dono de todo o histórico; não criar outra pessoa, mover mensagens, reatribuir conversas nem excluir aliases, IDs ou mídias.
- Variação brasileira com/sem nono dígito e correção legada comprovada de nono dígito indevido em fixo não representam uma troca de pessoa/número. Preservar a identidade nesses casos.
- Novos envios usam o telefone novo sem o `user_id`/username anterior; uma identidade confirmada pela ViperConnect pode enriquecer o cadastro existente. Webhooks atrasados e sincronização de diretório não podem restaurar o LID retirado.
- Contato 231 confirmado pelo administrador como a mesma pessoa, número anterior cancelado. A correção retroativa é limitada à conta 1/contato 231/evento 486, com backup, prévia e fingerprint; não generalizar reparação de legados sem revisão.
- Evento 486 contém destinatários realmente divergentes. Arquivar o conflito revisado como `disabled / retired_recipient_after_phone_change`, sem inventar deduplicação, reescrever o payload ou alterar as identidades capturadas. Uma mensagem histórica enviada com identificação errada não comprova entrega ao número novo.
- Aceite dev: 600 exemplos Ruby sem falhas nos fluxos relacionados, mais um teste específico do executor com conversa, mensagem e mídia preservadas. RuboCop dos 18 arquivos de aplicação/spec sem infrações. Sem alteração de frontend ou necessidade de novos pacotes móveis neste hotfix.
- Implantação autorizada via hostpath depois do aceite; status operacional, backup e limitações em [runbook da troca de telefone](hostpath-contact-phone-change-20261020.md). Não confundir patch em runtime com nova imagem ou commit publicado.

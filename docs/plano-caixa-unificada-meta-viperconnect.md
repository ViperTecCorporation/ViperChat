# Plano de caixa unificada: Meta oficial + ViperConnect

## 1. Situação, objetivo e autorização

- Documento de planejamento: 15/10/2026, fuso America/Cuiaba.
- Atualização em 15/10/2026: P1 implementada e validada em dev; P2 aplicada via hostpath na VPS após autorização explícita do usuário. Evidências e limites estão na seção 5.4.
- ViperConnect: commit `b1668845` (`feat(webhooks): expose original provider message identity`), branch `mobile-primary`. IDs públicos atuais e referências operacionais preservados; Typebot não recebe o novo campo.
- Primeiro incremento P4 validado em dev e aplicado como piloto via hostpath na VPS, com backup prévio e validação de eventos reais (seções 6.0 e 6.0.1): persistência aditiva da identidade do transporte e seus vínculos. Correlação automática Meta, resolução de pessoas e unificação continuam pendentes.
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
- Meta guarda seu `wamid` completo como `external_id`, ainda sem derivar `provider_message_id` da representação binária. O adaptador da seção 6.1 é pendência explícita; nenhuma busca por texto/horário/substrings foi introduzida.
- `messages.source_id`, `external_source_ids`, mídias, APIs públicas, notificações, bots e regras de envio não foram substituídos. Não há nova tela, seletor, endpoint ou alteração nos bundles Web/Android/iOS neste incremento backend.

**Validação dev:** base isolada `viperchat_provider_identity_test`, distinta da réplica de desenvolvimento `chatwoot_db`. O ambiente do container contém `DATABASE_URL`; confirmar o nome efetivo na conexão, pois somente mudar `POSTGRES_DATABASE` não garante isolamento. A migração aditiva foi aplicada na réplica dev antes do piloto na VPS descrito abaixo.

- Script reproduzível: `script/validation/whatsapp_provider_identity.rb`; exige `RAILS_ENV=test` e o nome exato da base isolada, bloqueia HTTP real e utiliza factories/test adapter. Executar somente com a base de teste limpa e configurada: cria fixtures e testa reversão/reaplicação das duas tabelas novas nessa base, nunca na réplica em uso ou em produção.
- 36 verificações aprovadas: entrada/repetição, payload legado, status antecipado, `source_id` tardio, echo em ambos os formatos, referências, conflito, múltiplas bolhas por identidade, isolamento, concorrência, `wamid` intacto e migração reversível sem remover mensagens legadas.
- Regressão: 185 exemplos existentes aprovados, cobrindo `Message`, UnoAPI, warnings, visualização única e entrada Meta. RuboCop dos arquivos alterados aprovado. Avisos de depreciação existentes não foram tratados como parte desta mudança.

**Ordem de implantação:** executar a migração `20261016000000_create_whatsapp_message_identities` antes de carregar os novos callbacks nos processos web/worker. Para rollback de código, manter as tabelas/observações; não executar `down` em produção sem decidir como preservar os metadados coletados. A reversão da migração elimina somente as tabelas novas e seus vínculos, não mensagens legadas, mas perde as observações.

**Próximas pendências P4:** adaptador Meta isolado/testado, consulta de candidatos/correspondências com escopo autorizado e diagnóstico de ambiguidades entre contatos distintos/BSUID-only. Nenhuma associação entre pessoas/caixas está ativa neste incremento.

**Integração Git acordada:** persistência e plano ficam na branch `feat/whatsapp-provider-message-identity`. Prosseguir com a correlação automática Meta nesta mesma branch, validar em dev e então integrar à branch principal de trabalho `4.16.0`, evitando branches adicionais para cada subetapa. A integração Git não ativa a unificação das caixas nem autoriza novo deploy em produção. Remover a branch temporária somente depois de confirmar a integração e o push, preservando os commits.

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
5. Se estiver em processamento, registrar a referência alternativa e aguardar/reagendar a consulta ao resultado; não iniciar outro upload em paralelo.
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

### 8.5. Limite: storage do ViperChat versus cache da ViperConnect

A deduplicação acima elimina a segunda ingestão no Active Storage e no bucket/prefixo do **ViperChat**. A ViperConnect pode manter sua própria cópia/cache para entrega e reenvio de mídias. Esse armazenamento pertence a outro ciclo de vida e não desaparece por unificar caixas.

Não apontar Active Storage diretamente para um objeto temporário/URL assinada do provider como atalho. Eliminar também a cópia entre os dois produtos exigiria outro desenho de propriedade, acesso, retenção e recuperação. Nesta fase, medir esses custos separadamente e não prometer uma única cópia física em toda a infraestrutura.

### 8.6. Histórico e aceite de armazenamento

Mídias antigas duplicadas permanecem preservadas. Uma eventual consolidação retroativa exige auditoria por hash/conta, prévia de referências, plano de retenção e autorização separada; não faz parte da ativação inicial.

O piloto deve comprovar:

- [ ] Mesmo texto com mídia não é critério de identidade; IDs correlacionados governam a ingestão.
- [ ] Dois webhooks equivalentes simultâneos resultam em um anexo lógico, um blob original e um objeto original vivo no storage ViperChat.
- [ ] O segundo evento, após conclusão, não baixa nem envia novamente o arquivo.
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
| P4 | ViperChat persiste IDs, observa correlações e resolução de identidade | Parcial: persistência inicial validada em dev e no piloto hostpath da VPS (seções 6.0 e 6.0.1); adaptador Meta, observação entre caixas e resolução de identidade pendentes; sem fusão histórica ou alteração de fila/bolhas/envio |
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

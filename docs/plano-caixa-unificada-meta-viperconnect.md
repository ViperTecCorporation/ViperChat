# Plano de caixa unificada: Meta oficial + ViperConnect

## 1. Situação, objetivo e autorização

- Documento de planejamento: 15/10/2026, fuso America/Cuiaba.
- Próxima etapa prevista: 16/10/2026, começar pelo projeto ViperConnect para acrescentar `provider_message_id` ao webhook.
- Hoje: somente documentação. Não implementar, publicar, alterar a VPS, configurar mounts, reprocessar eventos ou enviar mensagens.
- A data prevista não cria execução automática ou agendamento. A implementação será retomada mediante solicitação do usuário.
- Aplicação e testes reais na VPS serão etapas posteriores, com escopo aprovado, depois da aprovação do código e dos testes em dev.

Objetivo: apresentar um único atendimento para um número WhatsApp conectado simultaneamente pela Meta oficial e pela ViperConnect. Preservar histórico e vínculos existentes, escolher explicitamente o transporte de envio e correlacionar mensagens equivalentes sem duplicar bolhas, automações, notificações ou cobranças estimadas.

## 2. Decisões consolidadas

| Tema | Decisão |
| --- | --- |
| Caixa principal | Escolhida pelo administrador: pode ser Meta ou ViperConnect. |
| Caixa parceira | O outro transporte do mesmo número empresarial, na mesma conta. |
| Instalação atual | Candidata a manter ViperConnect como principal devido ao histórico; não é regra fixa do produto. |
| Histórico e operação | A principal organiza conversas, responsável, equipe, status, etiquetas, SLA e automações. |
| Transporte padrão | Configuração independente da escolha da principal. |
| Envio | Uma mensagem é enviada por um transporte escolhido, nunca automaticamente pelos dois. |
| IDs existentes | UUID da ViperConnect, `wamid` da Meta e ID interno do ViperChat continuam preservados. |
| ID original | Novo metadado de correlação; não substitui IDs públicos nem IDs de citação. |
| Deduplicação | Associação determinística; nunca apenas por conteúdo, nome de arquivo ou horário. |
| Falha de envio | Não mudar de transporte silenciosamente nem reenviar automaticamente pelo parceiro. |
| Histórico anterior | Preservado; sem fusão retroativa automática e sem exclusão em massa. |
| Custos | Estimativa separada da fatura, com regras versionadas e tarifas verificáveis. |

### 2.1. Caixa principal nos dois sentidos

Os dois cenários são obrigatórios:

1. ViperConnect principal + Meta parceira.
2. Meta principal + ViperConnect parceira.

O código não pode inferir a principal pelo provedor, pela ordem dos IDs ou por qual webhook chegou primeiro. Uma caixa parceira não pode integrar dois vínculos simultâneos. Trocar a principal depois da ativação exige procedimento próprio, prévia do impacto e reconciliação das conversas; não será um simples toggle na primeira versão.

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

- [ ] Mesmo evento conserva o `id` atual e acrescenta apenas metadados previstos.
- [ ] Texto, imagem, áudio, vídeo, documento e contato preservam o ID original quando disponível.
- [ ] Mensagem enviada por API, recebida, echo e status têm cobertura própria.
- [ ] Citação e eventos sobre outra mensagem preservam seus IDs de referência atuais.
- [ ] Filas antigas sem o campo continuam funcionando.
- [ ] Repetição e concorrência não mudam o ID original nem geram novo envio.
- [ ] Falta do mapeamento não interrompe a entrega atual.
- [ ] Webhook antigo continua aceito pelo ViperChat ainda não atualizado.
- [ ] Build, lint e testes focados aprovados em dev.
- [ ] Usuário aprova o código/evidências em dev antes do piloto na VPS.

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

## 6. Segunda entrega — ViperChat persiste IDs sem unificar ainda

Criar estrutura de identidades de transporte relacionada à mensagem interna. Nomes finais de tabelas/classes serão definidos na implementação; os conceitos e garantias são obrigatórios:

- ID interno da mensagem ViperChat.
- Conta, vínculo das caixas, caixa/canal técnico e provedor.
- ID externo completo daquele transporte: UUID ou `wamid`.
- ID original/canônico e versão do adaptador que o interpretou, quando reconhecido.
- Participantes, direção e número empresarial, sem usar nome de contato como chave.
- Dados de status por transporte e horários originais dos eventos.

Preservar `source_id` e as APIs legadas. Uma mensagem unificada pode possuir vários IDs externos; um campo único não representa todos eles.

Primeiro operar em modo observação: armazenar IDs novos, calcular correspondências e registrar conflitos, sem unir conversas, esconder bolhas ou mudar o envio.

### 6.1. Adaptador Meta

Isolar a interpretação do `wamid` em adaptador testado com os exemplos reais e casos inválidos. Não usar busca de substring como algoritmo de produção nem afirmar que o formato interno é contrato documentado da Meta. Se não houver extração inequívoca, não correlacionar automaticamente.

O piloto deve provar a correspondência para os tipos/dispositivos suportados. Se o formato não permitir correlação confiável, a unificação fica bloqueada para aquele caso até existir alternativa validada. Não recorrer a texto + horário como chave substituta.

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

Identidade de correlação deve ser limitada à conta, vínculo das caixas, número empresarial e participantes/direção compatíveis, além do ID original reconhecido. Identidade externa também deve incluir o canal/namespace; IDs iguais em outras contas não são equivalentes.

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
| Reação/edição/exclusão | ID de operação exigido pelo transporte escolhido e sua capacidade |

**Não enviar `provider_message_id` no lugar do UUID da ViperConnect.** Ele serve à correlação. O frontend informa a mensagem interna e o transporte; o backend resolve o alias certo. Na ausência desse alias, avisar e permitir retirar a citação explicitamente, nunca substituir silenciosamente ou inventar ID.

Persistir a escolha de transporte antes de enfileirar. O job deve usar credenciais, identidade do contato, regras de janela e templates do transporte escolhido, não apenas `conversation.inbox.channel`. LID e BSUID não são intercambiáveis. Não trocar de canal silenciosamente em retry; envio com resultado desconhecido exige cuidado antes de uma tentativa alternativa.

Reações, edição e exclusão dependem de capacidade e autoria. Remover a mensagem localmente não garante que o outro canal possa revogá-la no WhatsApp.

## 10. Frontend, Web e aplicativos

- Um atendimento, uma timeline e uma bolha por mensagem correlacionada.
- Seletor visível “Enviar por: ViperConnect / Meta” tanto no editor compacto quanto no editor completo, permitindo ao agente escolher explicitamente o transporte de saída em ambos, independentemente da caixa principal.
- Manter o canal selecionado ao alternar entre editor compacto e completo, nos dois sentidos. Ambos compartilham a mesma seleção por conversa; a troca de editor não restaura o padrão administrativo nem altera o transporte silenciosamente. Atividade recebida também não muda a seleção.
- Rascunhos independentes por transporte, preservando texto, anexos e citação. Ao trocar, revalidar capacidades sem perder o rascunho.
- Indicação discreta do transporte de envio, detalhes dos aliases e erros acessíveis.
- Status por transporte preservado; status agregado monotônico e baseado na mesma mensagem. Não converter falha em sucesso por evento não correlacionado.
- Templates somente no contexto compatível; janela e disponibilidade do canal visíveis antes de enviar.
- Notas privadas continuam internas. Não as expor ao outro canal, widget ou destinatário.
- Grupos, chamadas, mídia de visualização única e recursos exclusivos seguem capacidades reais, sem prometer equivalência Meta/ViperConnect.

Não confundir `delivery_destination` existente com a escolha do transporte: destino WhatsApp/Web e transporte ViperConnect/Meta são eixos distintos. Mensagens Web continuam sem passar pelo serviço WhatsApp. Convites e lembretes respeitam transporte, janela e template quando necessário; atividade Web não renova a janela oficial.

Testar desktop e mobile 320, 360, 390, 412/430 px, teclado, orientação pertinente e safe areas. Para mudanças compartilhadas, regenerar bundles Android e iOS e executar a validação nativa prevista no projeto. Registrar claramente indisponibilidade de Mac/device; não chamar validação Web de validação iOS.

## 11. Integrações adjacentes

- Agendamento persiste o transporte escolhido e revalida disponibilidade/janela ao executar; não herda silenciosamente um novo padrão administrativo.
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
- Primeira versão não troca automaticamente o transporte para aproveitar franquia. Decisão continua explícita; roteamento financeiro automático seria outro escopo.

## 13. Etapas e critérios de avanço

| Etapa | Entrega | Gate |
| --- | --- | --- |
| P0 | Este plano | Revisão pelo usuário; nenhuma implementação hoje |
| P1 | `provider_message_id` aditivo na ViperConnect | Código, contrato, testes e build aprovados em dev |
| P2 | Piloto hostpath da ViperConnect na VPS | Aprovação operacional e comprovação no webhook real, sem regressão |
| P3 | Release definitiva ViperConnect | Imagem versionada validada; remover overlay temporário |
| P4 | ViperChat persiste IDs e observa correlações | Evidência real, sem alterar fila/bolhas/envio |
| P5 | Vínculo, correlação, ingestão única de mídias e envio por transporte | Testes transacionais, concorrência Active Storage/S3 e segurança nos dois sentidos de principal |
| P6 | Frontend, Web/Android/iOS e integrações | Interface responsiva, capacidades e referências corretas |
| P7 | Simulador e reconciliação de custos | Regras comerciais verificadas e cálculo sem duplicidade |
| P8 | Piloto da caixa unificada | Hostpath controlado quando aplicável, ativação manual e rollback pronto |
| P9 | Release definitiva e ampliação | Aceite do usuário e autorização de publicação/deploy separadas |

Não saltar da primeira alteração do webhook para a fusão de históricos. O simulador pode ser desenvolvido em paralelo após estabelecer o modelo de eventos, mas não decide o transporte na primeira versão.

## 14. Matriz mínima de testes da unificação

- Principal Meta e principal ViperConnect, com padrão de envio igual e diferente da principal.
- Contato existente nos dois canais, apenas em um, sem telefone e com múltiplos aliases; conflito entre contas nunca pode unir dados.
- Conversa única ligada/desligada, duas conversas abertas legadas, resolução e evento atrasado.
- Texto, áudio, vídeo, imagem, documento, contato, localização e formatos não suportados.
- Mídia equivalente simultânea pelos dois canais: conferir anexo canônico, blob, objeto S3 e número de uploads/downloads. Repetir com arquivo enviado pelo agente, retry, crash, álbum, transcodificação e origem indisponível.
- Envio por ambos os transportes, echo antes/depois da resposta, status atrasado e duplicado, retry e reinício de worker.
- Citação nos dois sentidos: UUID enviado à ViperConnect, `wamid` à Meta; alias ausente com aviso explícito.
- Seletor presente e funcional no editor compacto e no completo: selecionar Meta e ViperConnect em cada editor, alternar entre eles nos dois sentidos e comprovar que a seleção, o rascunho e o transporte efetivamente persistido/enviado permanecem corretos. Executar com principal Meta e principal ViperConnect, em desktop e mobile.
- Edição, reação e exclusão, com verificação de autoria/capacidade e sem reenvio acidental.
- Uma saudação/bot/notificação/webhook externo por evento lógico; notas privadas permanecem internas.
- Janela oficial aberta/fechada, template aprovado, canal desconectado e envio com resultado incerto.
- Atendimento Web, convites, lembretes, rascunhos, agendamento e relatórios existentes.
- Custos nos limites 999/1.000/1.001, consumo anterior, dois números, mesmo número em duas caixas, mudança de mês/fuso, duplicidade de statuses e isenções.
- Categorias/tarifas desconhecidas, mudança de vigência, consumo externo e comparação estimativa versus fatura.

## 15. Observabilidade, rollback e segurança

Medir eventos por transporte, presença do novo ID, correspondências, conflitos, duplicidades evitadas, pendências, atraso e falhas de envio. Para mídias: ingestões, downloads/PUTs evitados, bytes originais/derivados, retomadas, conflitos e objetos/blobs órfãos. Registrar identificadores de correlação com retenção/controlos adequados, sem conteúdo pessoal ou segredos desnecessários.

Vínculo desligado não deve apagar aliases nem mensagens. Definir corte de desligamento e destino de eventos pendentes; não redistribuir jobs já enfileirados para outro transporte. Rollback não desfaz envios já realizados e não deve reabrir duas automações para o mesmo atendimento.

Migrações futuras devem ser compatíveis com rollback da aplicação; não remover campos ou dados usados pela versão anterior durante o piloto. Conferir backups recuperáveis antes de qualquer operação de migração/conciliação em produção.

## 16. Checklist de retomada em 16/10/2026

1. Ler este documento e as instruções do projeto ViperConnect; reconferir branch, alterações de outros contextos e versão de runtime.
2. Inventariar exatamente os caminhos de montagem dos webhooks e referências no código atual.
3. Fechar o contrato aditivo e os exemplos de `provider_message_id`, preservando todos os IDs atuais.
4. Implementar somente P1, com testes focados e revisão de compatibilidade; não iniciar a unificação ainda.
5. Apresentar o resultado de dev e obter aceite antes de preparar/aplicar o hostpath na VPS.
6. Executar P2 apenas no escopo autorizado e com rollback pronto; registrar a comprovação de recebimento real.

Nenhuma senha, token ou segredo operacional deve ser acrescentado a este documento, scripts, commits ou evidências.

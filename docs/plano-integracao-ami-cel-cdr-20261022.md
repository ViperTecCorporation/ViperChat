# Integração direta ViperChat ↔ central: AMI e CEL/CDR

> **Direção substituída em 22/10/2026, após nova orientação do usuário:** o ViperChat receberá webhooks padronizados; o responsável pela central produz os eventos a partir de AMI/CEL/CDR. Não implementar conexão direta AMI nem emulação AMI no nosso serviço como requisito desta etapa. Reaproveitar REST incremental e cliente HTTP já iniciados. Ver o [contrato webhook-first vigente](contrato-webhooks-voip-v1-20261022.md). O restante deste documento registra a proposta anterior e seu código parcial; formulário/configuração AMI não são a entrega final.

22/10/2026 — America/Cuiaba. Estado: arquitetura definida e início de implementação autorizado em dev. A seção 9 distingue o primeiro bloco de código dos recursos ainda planejados. Sem publicação, novas conexões a centrais de clientes ou alteração de runtime/VPS nesta rodada.

Decisão vigente do usuário: o backend do ViperChat conecta diretamente às centrais via AMI e constrói o histórico no próprio ViperChat. Nosso serviço VoIP oferecerá compatibilidade AMI, incluindo eventos CEL/Cdr. **Não acessar bancos de centrais legadas, instalar conector ou acoplar a schemas externos.** Este documento substitui webhook-first e a proposta anterior de consulta SQL. Habilitar funcionalidades nativas já presentes, quando necessário, exige ação autorizada do administrador; não instalar módulos adicionais como requisito implícito.

## 1. Fluxo e responsabilidades

```text
Backend ViperChat
  ├── cliente AMI ────────── Asterisk / FreePBX / Issabel
  │   eventos normais + CEL/Cdr quando habilitados → histórico no ViperChat
  │
  └── mesmo cliente AMI ─── nosso serviço VoIP: servidor AMI compatível
      eventos normais + CEL/Cdr → histórico no ViperChat
      recuperação opcional própria ─ REST incremental persistido

Ambas as origens → inbox durável → reconciliador → histórico/participações
                                             → eventos autorizados para web/apps
                                             → notificações nativas futuras

SIP/WebRTC continua separado: registro, ligação e áudio.
```

- O browser e os apps não recebem credenciais AMI ou REST administrativo. Não há credencial nem conexão de banco legado. A observação é do backend e continua com os clientes fechados.
- Não centralizar a observação das PBXs no nosso serviço VoIP: ele é uma das centrais compatíveis, não o gateway obrigatório das demais.
- Não mudar o caminho do áudio, instalar Asterisk no nosso serviço nem substituir a bridge Zapo. O servidor AMI traduz estados reais já existentes; não simula chamadas.
- Webhooks deixam de ser requisito/caminho principal desta etapa. Os requisitos de persistência, retomada, isolamento e reconciliação permanecem; AMI por si só não os garante.

## 2. Eventos em tempo real via AMI

O ViperChat manterá uma conexão autenticada por integração, com lease para impedir consumidores concorrentes acidentais, reconexão com backoff e saúde visível. O processo persistente de leitura não ocupará indefinidamente um job comum; o desenho de execução será definido na implementação usando a infraestrutura existente.

Conjunto inicial a homologar: `Newchannel`, `Newstate`, `DialBegin`, `DialEnd`, `BridgeEnter`, `BridgeLeave`, `Hangup`, `BlindTransfer` e `AttendedTransfer`; eventos de filas como `AgentCalled`/`AgentConnect` quando suportados. Suporte depende da versão e configuração, não apenas da marca da PBX.

**CEL e Cdr usam a mesma sessão AMI**, não duas conexões/protocolos adicionais. `Event: CEL` descreve um acontecimento do canal; `Event: Cdr` entrega um resumo quando o CDR é gerado/finalizado (uma ligação pode gerar mais de um). O backend armazena ambos, além dos eventos normais, na própria base. Não pressupor que todo CEL precede todo CDR: há filas de entrega e diferenças entre produtores.

Consultar canais/bridges atuais ao reconectar, com as ações permitidas (`CoreShowChannels`, `BridgeList`/`BridgeInfo`, conforme perfil homologado). Assinar eventos antes do snapshot, persistir o fluxo e reconciliar a corrida; um snapshot não reconstitui chamadas encerradas durante a desconexão.

- Correlacionar por integração/instância da central, `Uniqueid`, `Linkedid`, bridge e identificadores SIP por leg. Nome/número/horário isolados não provam equivalência.
- `Linkedid` é evidência de relação, não licença para fundir cegamente tudo. Preservar legs e relações explícitas de transferência.
- Atendimento de URA/fila não significa atendimento pelo agente. Separar atendimento do canal de entrada e início efetivo da participação do operador.
- `Hangup` encerra um canal/participação; não necessariamente toda a ligação transferida.
- Não assumir que `Uniqueid` é ID único de evento. Deduplicar pelos registros duráveis quando disponíveis e por transições idempotentes; preservar a ocorrência observada sem descartar eventos legítimos por igualdade de texto.

## 3. CEL/CDR legado por AMI, sem acesso ao banco

CEL/CDR são tipos de registro. Recebê-los ao vivo pela AMI não é consultar registros antigos no banco. O ViperChat começa a formar seu histórico a partir da captura; não importa automaticamente chamadas anteriores ao início da integração.

### Pré-requisitos reais, não presumidos

- CEL: mecanismo de CEL ativo, eventos relevantes selecionados em `cel.conf`, backend nativo `cel_manager` disponível/carregado e seção `[manager]` com `enabled=yes`. A amostra oficial não habilita tudo automaticamente.
- Cdr: backend nativo `cdr_manager` carregado/registrado e habilitado em `cdr_manager.conf`; eventos dependem da configuração do motor CDR, inclusive registros de chamadas não atendidas.
- Usuário AMI com permissões/filtros adequados. No Asterisk 20 inspecionado, CEL usa classe `call` e Cdr usa `cdr`; não inventar uma permissão `cel` nem conceder `read=all,write=all` como atalho. Outras consultas podem exigir permissões adicionais mínimas, homologadas por ação.
- Ausência de CEL/Cdr não significa ausência de eventos normais. Oferecer perfil básico e indicar capacidade não verificada/indisponível; a falta de eventos durante o silêncio não prova que um backend está desabilitado.
- O botão Testar conexão valida login, ações de leitura e capacidades verificáveis sem originar chamada. Confirmar emissão efetiva CEL/Cdr requer tráfego legítimo correlacionado ou chamada controlada autorizada; não declarar cobertura completa apenas com `Login`/`Ping` bem-sucedidos.

### Reconexão: o que chega e o que não chega

1. Marcar a interrupção na base ViperChat e manter os registros existentes; não classificar chamadas pendentes automaticamente como perdidas/atendidas.
2. Reautenticar e restabelecer assinatura/filtros. Persistir os eventos novos e solicitar canais/bridges ativos para reconciliar o estado atual.
3. Um CEL/Cdr gerado após reconectar pode chegar normalmente, inclusive de uma chamada iniciada antes da queda. Isso não é reenvio garantido dos eventos emitidos enquanto o consumidor estava fora.
4. O perfil AMI padrão estudado não oferece cursor durável, confirmação por evento ou comando genérico de replay de CEL/CDR. Filas temporárias de sessão/HTTP não serão tratadas como journal histórico entre novas sessões ou reinícios. O perfil planejado ainda exige homologação prática.
5. Chamada que começou e acabou inteiramente durante a queda pode não aparecer; chamada conhecida sem desfecho permanece com confirmação pendente. Mostrar intervalo sem cobertura e não fabricar duração/participação.
6. Recuperação automática adicional só existirá quando houver API histórica existente e homologada, como capacidade opcional futura, ou REST próprio do nosso serviço. Sem API, aceitar explicitamente o limite AMI-only; não recorrer a banco, SSH, scraping ou instalação de conector como fallback.

**Browser/app fechado ≠ backend desconectado:** com backend conectado, a captura continua e os clientes encontram o histórico ao reabrir. Se o backend/conexão com a central caiu, AMI-only não garante recuperar tudo. Alta disponibilidade reduz a janela, mas não cria replay ausente no produtor.

### Evidência por produto e limites de compatibilidade

| Origem oficial consultada em 22/10/2026 | Evidência | Consequência para o plano |
| --- | --- | --- |
| Asterisk 20: eventos CEL/Cdr, código e amostras de configuração | Backends próprios emitem os registros na AMI; dependem de habilitação e permissões. As páginas dos eventos os documentam desde 13.2.0. | Baseline de fixtures será Asterisk 20; versões efetivas antigas exigem matriz própria. Não anunciar todas as versões compatíveis. |
| FreePBX/Sangoma: Asterisk Managers User Guide e configuração AMI da versão 16 | Cadastro de usuários/permissões/ACL; documento da versão 16 descreve bind padrão localhost. | Pode exigir liberar acesso remoto protegido pelo administrador. A documentação não comprova CEL/Cdr ativos nem replay histórico universal. |
| IssabelFoundation: cliente AMI oficial `asteriskmanager.php` e uso de AMI no callcenter | Há integração com AMI Asterisk e tratamento de reconexão; fontes de versões históricas, não inspeção de instalação atual. | Basear compatibilidade na versão do Asterisk/configuração da instalação. Não extrapolar habilitação de CEL/Cdr ou API histórica por ser Issabel. |

Não foi acessada central FreePBX/Issabel real nesta pesquisa. Documentação e código oficiais embasam o desenho, não substituem homologação com chamadas, transferências e quedas reais em versões identificadas.

### Limites e requisitos de rede

Sem conector não significa sem configuração: AMI precisa estar habilitada/autorizada e alcançável. Usar rede privada/VPN existente ou transporte protegido e ACLs; não abrir AMI irrestritamente na internet. Se a central estiver inacessível atrás de NAT, a implantação fica pendente de conectividade autorizada, não se resolve com a senha SIP.

Não ativar CEL/Cdr, carregar módulos, criar usuários ou alterar a PBX automaticamente. Configuração dos recursos nativos já presentes será apresentada ao administrador; se não estiverem disponíveis, não instalar componentes sem nova decisão. Não solicitar host, usuário, senha ou schema de banco legado.

### Cadastro do serviço no ViperChat

- Telefonia SIP/WebRTC mantém WSS, domínio, STUN/TURN e ramal por agente.
- Integração de eventos acrescenta host/porta AMI, transporte, usuário/segredo dedicado, filtros/escopo e estado de conexão. Credenciais protegidas e validação de destinos para evitar acesso arbitrário a redes internas pelo cadastro (SSRF).
- Histórico padrão: `viperchat_from_ami`, sem formulário de banco. Capacidades exibem eventos normais, CEL, Cdr e último intervalo sem cobertura separadamente.
- Nosso serviço pode habilitar recuperação `service_rest` por **endereço HTTPS base da central/API e token REST**, configurados ao adicionar/editar o serviço. São distintos de host/porta/usuário/segredo AMI e das credenciais SIP do agente. Segredos ficam criptografados no backend; retornar somente flags de configuração, preservar valor se omitido e permitir limpeza explícita. É extensão adicional de recuperação, não parte da AMI padrão nem requisito para conectar uma PBX legada.
- Persistir em UTC, preservar horário original/proveniência quando presente e distinguir timestamp do evento de horário de recepção. AMI normal pode não fornecer horário de ocorrência exato.

## 4. Compatibilidade oferecida pelo nosso serviço VoIP

- Implementar servidor AMI em transporte próprio protegido, com framing e correlação `ActionID` compatíveis, login, permissões e filtros. Credencial da integração é distinta da senha SIP do ramal e do token administrativo atual.
- Publicar um perfil mínimo de compatibilidade, não anunciar suporte integral a Asterisk. Inicialmente observar eventos e consultar estado: `Login`, `Logoff`, `Ping`, `Events`, `CoreShowChannels`, `BridgeList`/`BridgeInfo`, e descoberta de ações suportadas quando prevista pelo perfil. Ações não suportadas retornam erro explícito, nunca sucesso fictício.
- Não oferecer `Originate`, `Redirect`, `Hangup` administrativo ou execução de comandos na primeira etapa. SIP.js continua executando as ações do usuário; observação/replay não emite segundo INVITE/BYE/REFER.
- Gerar `Uniqueid` estável por leg, `Linkedid` e bridge IDs coerentes; manter mapeamento persistido para IDs atuais do serviço, worker e SIP, com namespace por instância.
- Emitir `Event: CEL` e `Event: Cdr` na mesma sessão autenticada AMI, respeitando classes `call`/`cdr`, filtros e semântica documentada do Asterisk 20. Compatibilizar nomes/capitalização por mensagem: por exemplo `Uniqueid`/`Linkedid` em eventos normais e `UniqueID`/`LinkedID` em CEL. Não exigir `LinkedID` no Cdr padrão; correlacionar pelos canais/UniqueID e referências já persistidas. Campos extras próprios serão opcionais e não necessários ao parser básico.
- Não usar `BillableSeconds` do Cdr como duração de fala do agente sem confirmar participação: atendimento de URA pode ser anterior. Não anunciar módulos Asterisk instalados no nosso serviço; compatibilidade é do protocolo/comportamento oferecido.
- Registrar CEL e CDR normalizados a partir das transições reais na mesma transação do estado/journal quando no mesmo banco. Preservar IDs, histórico, gravações e referências existentes; não substituir o armazenamento atual por registros fictícios de Asterisk.
- **Reaproveitar as rotas REST existentes**, sem criar API paralela: acrescentar `GET /v1/console/history?sync=changes&limit=100&cursor=<opcional>` ao histórico existente. A consulta sem `sync` conserva paginação/filtros anteriores; gravações continuam em `/v1/console/history-records/:recordId/recording`. O feed de alterações de registros CDR existentes não equivale, sozinho, ao journal completo de CEL/participações ainda a implementar. Não expor SQLite nem exigir SQL externo.
- Contrato incremental versão 1: primeira leitura por chave estável dos registros retidos (`phase=snapshot`), guardando marca d'água; depois `phase=changes` entrega alterações em sequência global persistida, incluindo término e metadados tardios. Resposta `items[{sequence,record}]`, `nextCursor` e `hasMore`; consumir até `hasMore=false`, persistindo cada página antes de salvar cursor. Comparar sequência por registro para snapshot/replay não aplicarem revisão antiga sobre nova.
- Cursor opaco assinado, ligado à instância e ao escopo autenticado de empresas/linhas; erro 400 para cursor inválido, 409 para escopo alterado, 410 quando a retenção perdeu a posição. Em 409/410 reiniciar snapshot e reconciliar sem apagar histórico local. Nunca avançar cursor REST por receber evento AMI isolado. O bootstrap captura mudanças durante paginação, não depende da data de início da ligação.
- Persistir alteração do CDR e entrada do journal na mesma transação SQLite; preservar snapshots do journal mesmo quando o limite antigo de CDR faz prune. Retenção inicial do journal é 10.000 alterações, separada da retenção de CDR; filas/volumes precisam dimensionamento antes do aceite produtivo. Snapshot inclui todos os registros ainda retidos, não só os presentes no journal. Backend JSON/file retorna 501 para sync incremental, sem fingir durabilidade equivalente.
- AMI transmite ao vivo; journal/REST recuperam lacunas após reinício. Retenção não pode apagar mudanças ainda necessárias sem indicar expiração do cursor e recuperação exigida.
- A bridge worker→serviço continua sendo uma origem independente de lacunas: persistência no serviço não recupera acontecimentos que nunca chegaram. Fechar/restringir essa garantia antes do aceite completo.

## 5. Reconciliação, histórico e notificações

1. Persistir cada observação AMI ou registro de histórico numa inbox durável, isolada por conta/integração. Recuperar pendências após crash, inclusive entre commit e enfileiramento.
2. Um reconciliador aplica participantes, direção, tempos e resultado sem duplicar chamadas. Eventos fora de ordem não fazem chamada encerrada voltar a tocar.
3. Acrescentar identidade autoritativa e participações sem apagar/recriar os `VoipCall` e IDs atuais. Chamadas anteriores à atribuição de agente exigem entidade de ligação independente de binding; não inventar agente para satisfazer o modelo atual.
4. Relacionar as observações SIP.js ao registro autoritativo somente por evidência técnica exata. Conservar pendências quando o vínculo não estiver provado.
5. Publicar atualização autorizada ao frontend após persistência. Aplicar acesso por conta, serviço e agente; AMI pode revelar tráfego de toda a central e exige escopo confiável no cadastro da integração, não IDs de conta arbitrários do evento.
6. Registrar quedas e intervalos sem cobertura. Ao reconectar, combinar estado atual e participações pendentes; replay somente se houver capacidade adicional comprovada, como REST próprio. Distinguir confirmado de desconhecido.
7. Backfill atualiza o histórico e pode consolidar perdida conforme política de deduplicação, mas nunca dispara alerta de chamada recebida já encerrada. Notificação de chamada ao vivo exige oferta atual válida.

Campos internos mínimos: versão, origem/proveniência, integração/instância, IDs externos, ID da observação/registro e revisão quando disponível, tempos ocorrido/recebido, ligação, legs/participações, ramal, identidade remota, estados/motivos brutos e normalizados, qualidade da evidência e referência segura de gravação. AMI legado não fornece um `event_id` ou revisão universal; não inventar garantia de sequência do produtor.

## 6. Web e apps nativos: alcance da solução

Sim: com o backend conectado e a central acessível, os eventos alimentam o histórico e notificações autorizadas mesmo sem navegador aberto. Apps e web consomem o mesmo domínio persistido; a AMI não depende da WebView.

Não: isso sozinho não mantém o SIP registrado num aplicativo suspenso, não fornece áudio e não garante que uma chamada aguarde o celular despertar.

- Próxima etapa nativa: push seguro, CallKit no iOS e Telecom/ConnectionService no Android, UUID/oferta estável, expiração e cancelamento por atendimento em outro dispositivo.
- Nosso serviço precisará manter/encaminhar a oferta até o dispositivo estar apto, sem segunda chamada indevida. Centrais legadas exigem homologação do mecanismo de entrega após despertar; AMI não substitui suporte de roteamento/SIP push.
- No iOS, tratar o push VoIP conforme o ciclo exigido pela Apple, reportando a chamada ao CallKit prontamente; não aguardar uma consulta REST antes de reportar. Recuperação de histórico nunca gera push VoIP de chamada antiga.
- Expor capacidades separadas: eventos ao vivo, histórico recuperável, participações/transferência, gravações e recebimento nativo em segundo plano. Não declarar o último pronto por os demais funcionarem.

## 7. Sequência futura e aceite

1. Fechar o perfil AMI mínimo e fixtures representativas; inventariar versões, acesso AMI e emissão CEL/Cdr de uma central piloto, somente com autorização, sem consultar banco. Definir limites de garantia por fonte.
2. ViperChat: cadastro administrativo AMI sem campos de banco, inbox/histórico próprios, reconciliação, saúde e atualização autorizada da UI, usando testes sintéticos primeiro.
3. Nosso serviço: servidor AMI compatível, legs/participações, journal CEL/CDR e REST incremental; validar o mesmo consumidor ViperChat contra ambas as origens.
4. Aceite: mesma sessão com eventos normais/CEL/Cdr, backends presentes/ausentes, permissões/filtros restritos, queda com chamada ativa versus encerrada no intervalo, reinício, duplicação, eventos tardios, browser fechado com backend conectado, retenção REST expirada, ramais paralelos, URA/fila, transferências, isolamento entre contas e preservação de IDs/mídias. Provar ausência de qualquer acesso a banco legado.
5. Somente depois homologar push, despertar, CallKit/Telecom e atendimento real em segundo plano, sem confundir evento recebido com chamada disponível para atender.

O usuário autorizou iniciar a implementação em dev e delegar trabalho entre ViperChat e serviço, usando infraestrutura existente. Isso não autoriza configurar clientes, publicar, criar containers ou aplicar na VPS. Nenhum segredo deve constar nos exemplos ou logs.

## 8. Referências oficiais e relação com o plano

- [AMI v2: eventos, ações e autorização](https://docs.asterisk.org/Configuration/Interfaces/Asterisk-Manager-Interface-AMI/AMI-v2-Specification/).
- [CEL: registros por canal, transferências e backends](https://docs.asterisk.org/Configuration/Reporting/Channel-Event-Logging-CEL/CEL-Specification/).
- [CDR: campos, múltiplos registros e cenários de transferência](https://docs.asterisk.org/Configuration/Reporting/Call-Detail-Records-CDR/CDR-Specification/).
- [Evento CEL AMI, Asterisk 21](https://docs.asterisk.org/Asterisk_21_Documentation/API_Documentation/AMI_Events/CEL/), [evento Cdr AMI, Asterisk 20](https://docs.asterisk.org/Asterisk_20_Documentation/API_Documentation/AMI_Events/Cdr/), [snapshot CoreShowChannels](https://docs.asterisk.org/Asterisk_20_Documentation/API_Documentation/AMI_Actions/CoreShowChannels/).
- [Configuração CEL Asterisk 20](https://github.com/asterisk/asterisk/blob/20/configs/samples/cel.conf.sample), [implementação cel_manager](https://github.com/asterisk/asterisk/blob/20/cel/cel_manager.c), [configuração cdr_manager](https://github.com/asterisk/asterisk/blob/20/configs/samples/cdr_manager.conf.sample), [sessões/eventos AMI](https://github.com/asterisk/asterisk/blob/20/main/manager.c).
- [FreePBX/Sangoma: Asterisk Managers User Guide](https://sangomakb.atlassian.net/wiki/spaces/PG/pages/26771608/PBX%2BGUI%2B-%2BAsterisk%2BManagers%2BUser%2BGuide), [bind AMI na versão 16](https://sangomakb.atlassian.net/wiki/spaces/PG/pages/26706045/PBX%2BGUI%2B-%2BAMI%2BDefault%2BConfiguration%2Bin%2B16).
- [IssabelFoundation: cliente AMI oficial](https://github.com/IssabelFoundation/framework/blob/master/framework/html/pbxapi/models/asteriskmanager.php), [histórico do callcenter/reconexão AMI](https://github.com/IssabelFoundation/callcenter/blob/master/CHANGELOG). Fontes históricas não garantem capacidades em todas as versões atuais.
- [Apple: recebimento de notificações VoIP com PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).
- [Plano principal](plano-webphone-sip-agente-20261020.md); [auditoria histórica do serviço](auditoria-contrato-voip-cdr-20261020.md). A auditoria descreve o código observado anteriormente, não prova implementação desta proposta.

## 9. Primeiro bloco iniciado em dev — 22/10/2026

- Serviço: modo incremental na rota de histórico existente, migration SQLite aditiva para journal/versões/cursor, snapshot inicial, delta transacional e isolamento de escopo. Não modifica motor SIP nem instala servidor AMI por este bloco.
- Validação do serviço nesta rodada: typecheck e build aprovados; suíte completa com 203 testes, 202 aprovados, zero falhas e uma pendência por ffmpeg indisponível. Inclui oito novos testes cobrindo atualização de ligação antiga, paginação concorrente, gravação/IA tardias, reinício, escopo, cursor alterado/expirado, rollback, retenção e compatibilidade HTTP anterior. Dados são sintéticos temporários, não o banco ativo do serviço.
- ViperChat: cadastro admin seguro de AMI e HTTPS/token REST, formulário e cliente REST estão em implementação e terão aceite próprio antes da conclusão desta etapa. Não presumir que salvar configuração ativa observação/sincronização.
- Ainda pendentes: servidor AMI compatível no serviço, consumidor AMI persistente, inbox/reconciliador autoritativo de chamadas/participações no ViperChat, job de recuperação com checkpoint persistido e homologação com centrais reais. O feed REST de CDR não transforma esses itens em concluídos.
- Não houve commit/push, imagem nova, alteração do serviço/container ativo, acesso ao banco legado ou VPS. Os resultados deste bloco não equivalem a aceite de telefonia nativa em segundo plano.

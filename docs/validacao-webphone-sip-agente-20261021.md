# VoIP por agente — validação dev na réplica existente

Data: 21/10/2026, America/Cuiaba. Branch de trabalho: `feat/agent-voip-webphone`, base `e246c357054477f19194adf645c6e9cb61c8b5f9`.

Estado deste registro: primeira entrega implementada e validada funcionalmente na réplica dev existente. Os limites nativos/hardware/transferência real abaixo permanecem explícitos; não equivalem a falha escondida ou a aceite desses cenários. Não é relatório de publicação, autorização de deploy ou comprovação de CDR completo. Complementa o [plano](plano-webphone-sip-agente-20261020.md).

## Escopo e limites operacionais

- Continuar exclusivamente na réplica Docker já existente, acessível em `http://localhost:3000`. Usar `docker exec` para testes, sem `docker compose run`, criação/recriação de containers ou nova cópia da stack.
- Não acessar/alterar VPS, Portainer ou o serviço VoIP de produção. Não efetuar chamadas a clientes. Não iniciar workflows, tag, commit, push ou publicação como efeito desta validação.
- Manter web, worker, Vite, PostgreSQL, Redis e ViperConnect locais ativos. Não executar prune de Docker, limpar caches compartilhados, volumes ativos ou bancos da réplica.
- Dados sintéticos ficam na conta local 654 (`Laboratório VoIP isolado`), sem caixas de entrada/clientes, e no banco de testes `viperchat_voip_test`. Não usar integrações reais das outras contas clonadas para smoke tests.
- A limpeza do volume temporário `viperchat-voip-dev-source` e de `.codex/runtime/voip-vite-cache` ficou pendente por bloqueio do ambiente e instrução explícita do usuário. Não contornar esse bloqueio nem parar a entrega para repeti-la.

## Implementação conferida no código

| Área | Implementação |
| --- | --- |
| Cadastro comum | `VoipService`, múltiplos serviços por conta, disponibilidade/autoconfiguração por agente, WSS/domínio/STUN/TURN/registro e capacidade REFER. Produção requer WSS; WS em loopback só em dev/test. |
| Perfil | `VoipAgentExtension`, seleção de serviço antes de ramal/autenticação; um binding ativo por agente/conta, senha omitida preservada e limpeza explícita. Configurar/testar registro não inicia chamada. |
| Segredos | AES-256-GCM no armazenamento, payloads públicos sem senha; bootstrap autenticado do próprio agente sem cache. Credencial apenas em memória no cliente, sem localStorage. Credenciais WebRTC globais antigas filtradas da serialização do usuário. |
| Sessão | `AgentSipClient` com SIP.js 0.21.2 e store global `agentVoip`: REGISTER, entrada/saída, aceitar/rejeitar/encerrar, mídia, mute, DTMF, REFER/NOTIFY, reconexão de registro sem rediscar e coordenação de abas por Web Locks. |
| Histórico | `VoipCall`, `VoipCallObservation` e `VoipFavorite`; chamadas sem inbox/contato/conversa. Intenção idempotente antes do INVITE, observações autenticadas com sequência, eventos antigos não reabrem terminal. Ramal local e ID do agente são snapshots, não mudam retroativamente ao editar/remover o agente. Remoção do vínculo com a conta desativa e limpa o segredo, sem apagar chamadas. Exclusão intencional da conta limpa seus dados VoIP dentro do contrato de exclusão da conta. |
| Falta de evidência | Chamada sem observação recente fica `awaiting_confirmation`; não inventar atendimento, término ou duração. Pendência de persistência continua visível após fechar a sessão e possui retry em memória. |
| Interface | Chamadas abaixo de Conversas; lista/favoritos/pesquisa server-side/filtros/detalhes/discador e webphone global compacto/completo. Mobile usa `BackButton.vue`, seta à esquerda do título, mesma posição das conversas. Conta alterada limpa dados locais e ignora respostas atrasadas da conta anterior. |
| Legado | Voice/custom passa a orientar Serviços VoIP/perfil; novo auto-register não busca uma inbox arbitrária. Twilio/Meta e histórico legado não foram substituídos em massa. O usuário dispensou importar configuração Voice/custom antiga, nunca usada em produção. |

Migrations aplicadas em dev/test: `20261020230000_create_agent_voip`, `20261020230001_snapshot_agent_voip_extension` e `20261020230002_preserve_voip_history_on_agent_removal`. Não executam merge/migração de contatos, conversas, mensagens, anexos ou tabela legada `Call`. A terceira mantém vínculo órfão opcional e índice de ramal único somente para agentes presentes. Seu `down` é irreversível: restaurar um vínculo removido exigiria inventar propriedade, o que não é permitido.

## Evidências finais verificadas

Os resultados abaixo são execuções focadas desta implementação, não a suíte completa do repositório. Resultados antigos completos citados no plano pertencem a outra etapa.

| Verificação | Evidência disponível | Limite |
| --- | --- | --- |
| Backend | Execução final em banco isolado: 175 exemplos, zero falhas; inclui 26 VoIP, AccountUser, AgentsDestroyJob, perfis OSS/Enterprise, contas/usuários/agentes Enterprise e serviços Voice/Twilio selecionados. | Não equivale à suíte completa CE/Enterprise. |
| Ruby lint | RuboCop com `--force-exclusion`: 22 arquivos verificados, sem infrações. | Usa exclusões existentes do projeto; regras/configuração não foram afrouxadas. |
| Frontend | Revisão final de contatos/ramais/UI: 167 testes em 15 arquivos, zero falhas, cobrindo SIP/store/discador/contatos e regressões adjacentes de autenticação/editor. ESLint `--quiet` aprovado nos arquivos alterados. | Não equivale à suíte frontend completa do repositório. |
| Diretório e identidade | 37 exemplos em banco isolado: 26 da API VoIP e 11 novos de diretório, identidade, avatar existente, privacidade, serviço/conta e paginação de cinco chamadas. Zero falhas; RuboCop final de 13 arquivos, zero infrações. | A execução ampliada de 175 exemplos acima pertence à etapa anterior. |
| Lista/detalhe | Regressões da seta comum e de respostas atrasadas de outra conta aprovadas; retorno à lista clicado no browser e captura escura dos detalhes conferida. | Preservar esse contrato em próximas mudanças de navegação. |
| Responsividade browser | Lista/detalhe e modais de perfil/administração conferidos em 320, 360, 390, 412, 430, paisagem 844 e desktop 1280 px, sem overflow horizontal; temas claro/escuro inspecionados. | Teste browser não substitui teclado/safe areas de cada aparelho físico. |
| Chamada local SIP/WebRTC | Ramais internos de laboratório 1001 → 1002, registros locais 30 (saída) e 31 (entrada), encerrados, atendimento/término persistidos, duração observada de 197 s. | Não é telefonia externa nem CDR autoritativo sincronizado. |
| Áudio | ICE/PeerConnection conectados, RTP de entrada/saída e energia de áudio decodificada positiva nos dois lados, usando fonte sintética. | Não comprova microfone, headset, alto-falante físico ou Bluetooth. |
| Controles | Mute desativou a track local e unmute a reativou; encerramento local refletiu término remoto. DTMF 5 enviado sem erro de API. | Recepção do dígito por IVR remoto não foi confirmada. |
| Rejeição real | Nova chamada interna rejeitada no terminal receptor; registros 175 (saída, SIP 603) e 176 (entrada, rejeição local) conferidos por leitura no banco da réplica, ambos `rejected`. | Não generalizar esse resultado a todas as centrais. |
| Transferência | Comportamento REFER/NOTIFY coberto por testes simulados de sucesso/falha. | Não testada ponta a ponta: laboratório tem dois ramais, falta terceiro destino para aceite real. |
| Sem desfecho | Tentativa sem confirmação de CANCEL ficou aguardando confirmação, sem duração/término fabricados. | Recuperação autoritativa depende da próxima entrega. |

### Isolamento correto da execução Ruby

A execução final substituiu explicitamente o caminho da `DATABASE_URL` herdada por `viperchat_voip_test` e usou Redis 15. Apenas definir `POSTGRES_DATABASE` não bastava: a `DATABASE_URL` herdada tinha precedência. As execuções transacionais anteriores chegaram a usar o banco clonado e suas alterações foram revertidas pelas transações; não houve exclusão de contas reais. A evidência final de 175 exemplos refere-se ao banco de teste isolado e não depende daquela configuração incorreta.

Não registrar a URL completa nem seus segredos. Para reproduzir, capturar a configuração disponível em memória, alterar o nome do banco na URL, confirmar o nome efetivo antes dos exemplos e usar Redis de teste separado.

## Checklist do fechamento

- [x] Reexecutar os conjuntos backend/frontend finais após as últimas alterações: 175 exemplos backend e 91 testes frontend aprovados, nos escopos discriminados acima.
- [x] Reexecutar lint dos arquivos alterados sem mudar regras, desativar testes ou aceitar falhas por conveniência.
- [x] Conferir interação final da lista/detalhe, seta comum na mesma posição das conversas, modal do perfil e configuração administrativa em mobile/desktop.
- [x] Confirmar os hashes normalizados dos 46 arquivos de aplicação/rotas no runtime contra o worktree final, sem divergências. Espelhar somente os arquivos próprios e os hunks VoIP no checkout dev, preservando alterações alheias; não ligar sincronização global de árvore suja.
- [x] Regenerar bundles Android/iOS depois da última alteração compartilhada e compilar os dois. Android sem dispositivo disponível; iOS instalado/iniciado em identificador isolado, sem aceite de chamada nativa.
- [x] Inventariar intermediários: no Mac, remover o DerivedData exclusivo `.voip-build` (1,7 GiB) e os dois pacotes de transferência após build/instalação. No Windows, o ambiente bloqueou a limpeza dos dois diretórios de build Android e dos dois pacotes da tarefa (aproximadamente 96 MiB); ficaram pendentes, sem contornar a proteção. Preservar o APK de Downloads e as evidências, além dos dois resíduos anteriormente adiados pelo usuário.
- [x] Registrar conclusão funcional e limitações sem chamar testes de build de teste real de chamadas nativas.

## Complemento: microfone físico e permissão real no navegador

Validação manual assistida de 21/10/2026, somente na réplica existente e conta de laboratório 654. Sem novos containers, sem VPS e sem gravação de voz. Não houve substituição de `getUserMedia`, dispositivo falso ou fonte de áudio sintética neste complemento; a função nativa foi conferida nas duas janelas e o navegador não tinha flags de captura falsa. Os cliques de negar/liberar foram realizados pelo usuário, não por override de permissão.

- Dispositivo real: grupo de microfones Intel Smart Sound, captura mono a 48 kHz; saída Realtek. Acesso inicial `prompt`, concessão real `granted`; no outro perfil, recusa `denied` e liberação posterior `granted`, com recarga da página feita durante a mudança de permissão.
- Chamadas 209/210: 1001 → 1002, atendidas e encerradas, duração persistida de 177 segundos. Usuário confirmou ouvir o retorno de sua própria voz no 1002. ICE/PeerConnection conectados, microfone físico `live`, RTP de entrada/saída e energia decodificada no receptor positiva (aproximadamente 0,9974 em uma amostra).
- Chamadas 211/212: 1002 → 1001, atendidas e encerradas, duração persistida de 68 segundos. Usuário também confirmou ouvir sua voz no sentido inverso; receptor 1001 apresentou energia decodificada positiva (aproximadamente 0,0044 em uma amostra). Não inferir defeito de áudio a partir de nível instantâneo zero durante silêncio.
- Para evitar realimentação acústica entre duas janelas no mesmo computador, apenas uma saída remota ficou audível por vez; a outra foi silenciada apenas na instrumentação de teste. Ao inverter o teste, a saída audível também foi invertida. Isso não alterou o motor SIP.js nem substituiu o microfone.
- Mute pela interface do webphone tornou a track física `enabled=false`; unmute restaurou `enabled=true`. Ao encerrar, as PeerConnections ficaram `closed`, as tracks retidas ficaram `ended` e nenhum webphone de chamada ativa permaneceu. A instrumentação foi removida por recarga/fechamento das janelas de teste.

**Falha histórica da recusa (corrigida posteriormente em dev, ver complemento abaixo):** na repetição com permissão já bloqueada, entrada 208 ficou `awaiting_confirmation`, sem `end_reason` de microfone; saída 207 recebeu SIP 480 (`unanswered`). Nenhuma ganhou atendimento/duração inventados e a captura foi liberada, mas o erro de permissão não permaneceu visível na interface (`role=alert` ausente). Esta evidência original foi preservada; não houve reescrita dessas chamadas para aparentar sucesso. A recuperação após liberação funcionou.

### Correção de `microphone_denied` ao atender — 21/10/2026

- `AgentSipClient.answer()` classifica a recusa local como `failed / microphone_denied`, preserva o mesmo `client_call_id`/SIP ID e libera sessão/tracks/toque. A notificação de término do SIP aguarda a conclusão de `accept()` para não gravar primeiro um resultado genérico. Não repete `accept()` simultâneo nem redisca automaticamente. Falhas diferentes continuam `answer_failed`.
- A ação do webphone conserva o erro específico do cliente SIP, sem substituí-lo por `action_failed`. O aviso traduzido com ícone e orientação continua visível sem chamada e fora da aba Chamadas, até o usuário fechar ou iniciar outra chamada. Fechar o aviso não remove o histórico nem encerra outra sessão.
- Regressões cobrem os dois ordenamentos (SIP termina antes/depois da rejeição de permissão), uma única observação terminal, limpeza de mídia, ausência de atendimento inventado e nova chamada após recuperação; store, UI desktop/mobile e API idempotente também cobertos.
- Na réplica existente, o cliente SIP real foi acionado por uma Invitation sintética que lança `NotAllowedError`, inclusive após emitir `Terminated`; o botão Atender real e store/API reais gravaram a chamada **219**, conta de laboratório **654**, com `state=failed`, `end_reason=microphone_denied`, `answered_at=null`, `duration=null`. Não foi feita nova negação no painel de permissões do navegador nem uma nova chamada física: o teste de voz/recusa física anterior permanece registrado acima. O erro controlado não modificou permissões do sistema.
- Layout inspecionado nas capturas `output/playwright/voip-microphone-denied-{dark,light}-{320,390,844,1280}.png`; medidas adicionais em 360/412/430 px. Sem overflow horizontal ou ação cortada, fechamento acessível de 44 px e launcher mobile livre. Navegação para Contatos manteve o aviso; fechar removeu apenas o alerta. Fixture removida e ação original restaurada; nenhum áudio ou chamada ficou ativo.
- Testes focados desta correção: **76 testes frontend de VoIP em oito arquivos** e **38 exemplos backend/API/diretório**, sem falhas. ESLint `--quiet`, RuboCop e `git diff --check` aprovados. Banco dos specs confirmado explicitamente como `viperchat_voip_test`, separado do laboratório em dev.
- Rodada ampliada subsequente: **143 testes frontend em 15 arquivos**, todos aprovados, incluindo contatos, autenticação web/nativa e editor de mídia. É uma seleção focada com regressões adjacentes, não a suíte completa do repositório; a contagem histórica de outra seleção não substitui este resultado.
- Nenhum container criado, reiniciado ou removido; nenhum acesso à VPS, deploy, commit ou push. Os registros antigos de chamadas, contatos, mensagens e mídias não foram reconciliados nem alterados.

Pacotes após esta correção: bundles Capacitor Android/iOS regenerados; Android Debug `BUILD SUCCESSFUL`, APK atualizado em `C:/Users/caita/Downloads/ViperChat-VoIP-ui-dev-20261021-debug.apk`, SHA-256 `80423cd9a6f712b802c1376056d296d5a24b143093f788d9f22ade0a436baacc`. `adb devices` não encontrou aparelho/emulador. iOS Debug `BUILD SUCCEEDED`, instalado e iniciado no mesmo simulador isolado `net.vipertec.viperchat.voipdev`; SHA-256 do índice `d1a850f70fe030f16d9984d67049e4beffe869d92c87147aa70ac6180a03ae46`, igual no Windows, fonte Mac e app compilado. Não foi validada nova recusa de microfone no SO/WebView nativo: o laboratório SIP depende de loopback do Windows e de contexto seguro, sem acesso equivalente pelo simulador Mac. Não houve alteração de segurança/rede para contornar isso. Estes hashes substituem os da revisão de UI anterior abaixo; não houve publicação nas lojas.

Inicialização iOS conferida na captura `output/playwright/voip-microphone-ios-startup.png`, na tela de conexão da instalação, sem conectar à produção. Limpeza desta rodada: removidos os dois helpers de QA, o pacote `voip-microphone-assets.tgz` no Windows (9.525.837 bytes) e no Mac, o log/cópia temporária da captura no Mac e o DerivedData exclusivo `.voip-build` (1,8 GiB, regenerável). Preservados APK, app instalado, fontes, capturas finais, caches compartilhados e resíduos antigos já adiados/bloqueados. Espaço livre final observado: Windows 86.594.068.480 bytes; Mac 9,9 GiB. Não atribuir a variação total do SSD somente a esta limpeza. Réplica e ViperConnect mantidos ativos.

Evidências visuais sem áudio: `output/playwright/voip-real-microphone-denied.png` e `output/playwright/voip-real-microphone-after-call.png`. Mantidos todos os registros de teste e os dados anteriores. Este teste não valida hardware mobile, Bluetooth/headset, rede externa ou transferência REFER.

## Android e iOS: não confundir empacotamento com aceite de chamada

O bundle final compilou 5.186 módulos e foi sincronizado para as duas plataformas. Android Debug: build aprovado, 306 tarefas; `adb devices` não apresentou aparelho/emulador disponível. Não houve instalação nem teste de chamada em hardware Android nesta execução.

APK de validação preservado fora do Git: `C:/Users/caita/Downloads/ViperChat-VoIP-dev-20261021-debug.apk`. SHA-256: `030ae4b5468044240372683caf92cb625f5c4dc252cd99dd16fafc4e37e261da`.

No Mac autorizado, Xcode Debug terminou com `BUILD SUCCEEDED`. O app isolado `net.vipertec.viperchat.voipdev` foi instalado e iniciado no simulador iPad Pro 13 (M5), sem sobrescrever o app de produção, seus dados, assinatura ou Archives existentes. Somente a tela inicial foi conferida; não houve exercício nativo do fluxo SIP nem publicação no App Store Connect.

O índice dos assets iOS tem SHA-256 `204d851b3eb48e93de2bea06487c66fc391628c5df41ad4406a65068b977be83`, igual entre o bundle final, `App/public` e o app compilado. Isso comprova inclusão do bundle, não chamada ou rede nativa.

A central de laboratório expõe SIP/WebRTC/RTP em loopback Windows. Isso não é um endpoint acessível do simulador Mac. O aplicativo nativo exige servidor HTTPS; não desativar essa proteção nem alterar binds da central/recriar containers para esconder a limitação. Instalar/abrir o pacote isolado comprova inicialização, não chamada/SIP/áudio nativo. CallKit/PushKit, Android Telecom e chamada em segundo plano não estão implementados. O usuário confirmou integração nativa obrigatória em 21/10/2026; a seção 13 do plano passa a exigir bridge e aceite específicos antes de considerar os apps entregues para telefonia. A conclusão funcional web não encerra esse requisito nativo.

## Aceite reproduzível, sem clientes nem novos containers

1. Confirmar os containers da réplica já ativos e a resposta do gateway local. Não imprimir env completo/Compose com credenciais.
2. Rodar testes Ruby no container web existente usando o banco isolado `viperchat_voip_test` e Redis de teste separado. Usar apenas credenciais configuradas em memória e não incluí-las em comandos/documentos versionados.
3. Rodar os testes JS/Vue focados e regressões adjacentes, depois lint. Registrar arquivo/resultado real da execução, sem reusar o total antigo como resultado da revisão nova.
4. Na conta sintética, administrar dois serviços independentes; confirmar que o agente só recebe os autorizados e configura um binding ativo. Verificar ausência de segredos em listagens/metadados.
5. Testar registro sem INVITE. Para a chamada controlada, usar somente 1001/1002; conferir persistência da intenção antes de discar e observar os dois lados. Fonte de áudio sintética evita captura de áudio privado.
6. Conferir controles e histórico, depois mobile/lista/detalhe com retorno preservado. Trocar rota não termina chamada; logout/troca de conta cancelam conexão antiga, sem reusar credencial em outra conta.
7. Conferir que falha/retry de persistência não produz outro INVITE; chamadas incompletas não ganham resultado/duração inventados.
8. Consolidar evidências, builds e limitações. Esta sequência não autoriza deploy, chamadas a clientes, nova central, alteração do serviço VoIP ou integração de webhook.

## Segunda entrega explicitamente adiada

### Revisão visual posterior: janela global e central responsiva

- Webphone montado no shell global e teleportado para `body`, independente da rota. Desktop permite arrastar pelo cabeçalho e mover pelas setas do teclado, com limites da área visível; navegar não recria a janela nem encerra a sessão.
- Mobile expandido ocupa a tela; recolhido apresenta barra de restaurar/encerrar com espaço reservado ao launcher da sidebar e abaixo da camada do menu. Não aplicar transformações de arraste desktop ao mobile.
- Controles circulares com ícones Lucide, nomes acessíveis e rótulos curtos: microfone, encerrar/atender, teclado, dispositivos e transferência. Central usa ícones distintos de recebida, efetuada, perdida e falha, além de busca, favoritos e ações.
- Ordem final solicitada: favoritos (três cartões circulares por página, avatar/nome e pino discreto no canto superior direito), pesquisa e barra Recentes; nessa barra, filtros e nova chamada são botões com ícones à direita. A remoção do favorito exige confirmação e remove apenas o atalho, nunca contato/histórico. Filtros abrem modal com foco/Escape, corpo rolável, espaçamento interno, datas empilhadas no mobile e rodapé fixo; preservam seleções e exibem contador ativo. Histórico usa páginas de cinco chamadas, anterior/próxima, substituindo a página sem acumular registros. Configuração de ramal fica após a lista no mobile.
- Cabeçalho mobile compacto, status truncável e sem aviso de histórico parcial na interface, conforme pedido do usuário. Isso não resolve nem cancela a pendência de CDR/webhooks/REST: o histórico completo continua sendo requisito antes da produção definitiva.
- Responsividade conferida em 320, 360, 390, 412, 430, paisagem 844 e desktop 1280 px; modal também conferida em paisagem, sem sair da área visível. Busca com espaço para ícone, temas claro/escuro e barra recolhida sem sobrepor o botão de menu. Fixture de chamada usada somente para layout, removida ao terminar, sem INVITE, registro no histórico ou captura de áudio adicional.
- Regressões adicionadas para navegação global, limites de arraste/teclado, mudança desktop/mobile, recolher/restaurar, ícones, modal/filtros ativos, paginação de favoritos/histórico e ordem dos elementos. Testes são focados, não a suíte completa do repositório.

Capturas finais inspecionadas em `output/playwright/`: `voip-final-central-dark.png`, `voip-final-central-light.png`, `voip-final-filter-320.png`, `voip-final-filter-844.png`, `voip-final-filter-light.png`, `voip-final-confirm-remove-mobile.png`, `voip-final-dialer-contact-ready.png`, `voip-final-dialer-extension-mobile.png`, `voip-final-contact-shortcut-desktop.png`, `voip-final-contact-details-call-mobile.png`, `voip-final-incoming-agent-mobile.png` e `voip-final-draggable-agent-desktop.png`. O tema claro foi aplicado pelo helper real, incluindo `color-scheme`, e aguardado carregamento das fotos/transições. Capturas intermediárias não representam o aceite final.

### Contatos, ramais e discador global

`GET /voip/directory` pesquisa contatos ou ramais (15 resultados/página); `GET /voip/identity` resolve identidade. Ambos exigem serviço autorizado da conta. Ramais são exatos e restritos ao mesmo serviço, com nome/avatar do agente; contatos usam telefone normalizado completo e só um resultado seguro, respeitando as políticas de visibilidade. Ambiguidade, LID/BSUID e grupos não viram telefones. Não inferir identidade por nomes, sufixos ou `auth_username`.

Chamadas e favoritos recebem `remote_identity` para apresentação com nome/avatar existentes. Não há migração de contatos, mudança de IDs, cópia de foto ou alteração dos snapshots/endereço do histórico; nome/foto não vazam de uma chamada/conta anterior. Busca do histórico também encontra o nome atual identificado, antes de contar/paginar.

`AgentDialer` é global, com Contatos, Ramais e Discagem manual. Escolher uma entrada ou clicar em atalho não disca: é necessário confirmar Ligar. Outro serviço exige ativação explícita de binding configurado. Atalhos foram conferidos na lista de contatos e nos detalhes; sidebar da conversa coberta por regressão, sem criar conversa real. A API/ações Voice anteriores permanecem separadas.

O laboratório 654 recebeu seis contatos fictícios e favoritos/chamadas sintéticos identificados, com avatar do fixture local. Apenas esses dados de teste foram criados, sem clientes ou envio real. Na validação visual de recebida/ativa, o estado da UI recebeu a identidade real do diretório de teste (ramal 1002), sem INVITE/captura de áudio; fixture removida ao terminar. O aceite físico de voz anterior continua registrado em seção própria e não foi repetido enquanto o usuário dormia.

### Pacotes da revisão final de UI/identidade

Android Debug recompilado, sem aparelho/emulador disponível. APK atual da tarefa: `C:/Users/caita/Downloads/ViperChat-VoIP-ui-dev-20261021-debug.apk`, SHA-256 `d3bf7e74f067fe71ee84f07edd5d8bba9bb830574267ffaefab183de4db2c14a`. O APK antigo sem `ui` no nome é de uma etapa anterior e foi preservado.

iOS Debug recompilado com sucesso, instalado/iniciado no simulador iPad Pro 13 (M5), identificador isolado `net.vipertec.viperchat.voipdev`. O índice final tem SHA-256 `985555d5fd32a4ae1862f0f9c7221ba018c1703c0b4ce7152385c41579fb1936`, igual no Windows, fonte Mac e app compilado. Isso comprova inclusão dos assets/inicialização, não aceite SIP/áudio/CallKit nativo. Não houve Archive, publicação ou VPS.

Limpeza posterior: removidos os dois pacotes de transferência desta revisão no Windows (19.041.669 bytes), seus correspondentes no Mac e o DerivedData exclusivo `.voip-build` (aproximadamente 1,8 GiB). São intermediários regeneráveis, sem exclusão do APK, app instalado, fontes, capturas ou caches compartilhados. Removidos também os cinco helpers de QA criados nesta revisão. Os resíduos antigos adiados/bloqueados continuam pendentes; não houve tentativa de contornar a proteção. A réplica/ViperConnect permaneceram ativos, sem novos containers, reinício ou VPS.

Não implementados/ativados aqui: outbox durável do serviço, entrega por webhook com assinatura/retentativas/quarentena, inbox durável ViperChat, reconciliador de CDR autoritativo, feed REST incremental/cursor/backfill e recuperação worker→serviço. A auditoria e o plano mantêm esses contratos.

Histórico atual tem origem `client_observed`. O backend persiste as observações recebidas, mas a fila de retry do navegador é em memória: fechar o browser pode perder observações ainda não confirmadas. Não há garantia de recebidas/perdidas quando o navegador está fechado, de resultado final após desconexão ou de participações completas em transferências. Webhooks/REST futuros não poderão rediscar nem deduplicar por simples nome/telefone/horário; devem correlacionar identificadores exatos, preservando IDs e evidências existentes.

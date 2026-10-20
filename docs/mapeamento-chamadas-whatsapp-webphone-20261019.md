# Chamadas: WhatsApp Windows e base do webphone ViperChat

Levantamento estático em 19/10/2026. Etapa de análise, não de implementação.

Atualização de escopo em 20/10/2026: o [plano consolidado de webphone SIP por agente](plano-webphone-sip-agente-20261020.md) substitui a proposta preliminar das seções 4 e 5. O serviço VoIP já trata a Meta; o novo recurso usa SIP/WebRTC, sem caixa Voice obrigatória, com múltiplos serviços administrativos e ramal configurado no perfil após escolher o serviço. Os prints da lista e detalhes já foram recebidos e estão mapeados no plano consolidado; mobile usará lista e detalhe com Voltar. As evidências estáticas abaixo permanecem como snapshot do levantamento original.

## Escopo e limites

- Inspecionar o pacote instalado do WhatsApp, seus XAML, SVG e metadados .NET, sem executar as DLLs.
- Confrontar os controles com o código atual do ViperChat para preparar uma aba Chamadas integrada ao SIP.
- Não iniciar chamadas, não enviar mensagens, não consultar dados privados do perfil do WhatsApp e não alterar a VPS.
- Prints ainda são necessários para confirmar a aba de histórico, composição visível, espaçamento efetivo e menus desta instalação. Os XAML contêm variantes controladas por estado e flags: estar no pacote não prova estar habilitado na interface.
- Não foi recuperado o código-fonte completo do WhatsApp nem validado áudio/sinalização. Metadados/CIL não equivalem a decompilação C# nem a observação de execução.

## 1. Identidade e evidências

Pacote: `5319275A.WhatsAppDesktop`, versão `2.2640.100.0`, x64.

Raiz inspecionada:

`C:/Program Files/WindowsApps/5319275A.WhatsAppDesktop_2.2640.100.0_x64__cv1g1gvanyjgm`

Os caminhos do WhatsApp abaixo são relativos a essa raiz. Não foram copiados os binários, fontes, sons ou ícones proprietários para o repositório.

REA CLI existente, versão fixada `6.7.0`, operações `inspect-managed-artifact` e `inspect-managed-members`. Inspeção sem carregar ou executar assemblies; nenhuma instalação adicional.

| Evidência REA | Objeto e alcance |
| --- | --- |
| `ev_2d8a2477a2da5931af046e3b78cebcbe33e7655a2811b56daef02207c844e666` | Identidade/classificação de `WhatsApp.VoIP.dll`: CIL, .NET 8, x64. |
| `ev_2a429729fa66055934742fa2d59f70610130e9fa8a347035f27280ba4319fdbf` | Membros/metadados do módulo VoIP; inclui controle de dispositivos. |
| `ev_7273c94d5a92e9718c46e1ff38d728665e69d440c38ab6d12caea5d5df727080` | Membros de `WhatsApp.Root.dll`: tipos de ponte VoIP/WinRT e janela `WhatsApp.CallPopoutWindow`. Não prova o fluxo completo da ponte. |
| `ev_3b6a455954118e15650a5e76131f50de12c340d4c89ed2aed207b4fba45e57af` | Seleção de `AudioCallView`, `CallControlsView`, `ICallControlsVm`, `ExtendedCallState`; nenhum tipo solicitado ausente. |
| `ev_116d81fc14844fc95e443a2bf3fdf5e6c41ca8bc1149246ed5beefb3a7cfa6c4` | Membros/arestas CIL de `CallControlsView` e contrato `ICallControlsVm`; callbacks, propriedades e métodos de controle. |

As consultas de membros acima reportaram cobertura completa nos metadados selecionados. Isso não estabelece cobertura funcional completa do aplicativo. Tokens são coordenadas locais desta build, não IDs estáveis entre versões. O relatório registra os IDs retornados; não depende de um ledger MCP persistente entre processos CLI.

Identidades SHA-256:

| Artefato | SHA-256 |
| --- | --- |
| `WhatsApp.VoIP.dll` | `7f7a50a9227bc90270eb1d15797e5e0261b3a0492ae73b9fbd0289c6afaa384b` |
| `WhatsApp.Root.dll` | `150a692e7498c046ebf6cef39f9994bdeec2772c53172399d0f827e420579d17` |
| `WhatsApp.Design.dll` | `4acbeb858b4c0a939514aabe381de3446098cbf94297514923835c7dba2dd09f` |

`WhatsApp.Design.dll` tem MVID `bdac7b30-3ea0-4065-b87f-bcc36a4e5401`.

## 2. Estrutura de interface encontrada no pacote

Há XAML textual legível, além do XBF compilado. Não é necessário extrair o aplicativo inteiro para estudar esses componentes.

```text
WhatsApp.Design/
  Voip/
    VoipView.xaml                 -> alternância áudio/vídeo por estado/tipo
    AudioCallView.xaml            -> cabeçalho, chamada, participantes e controles
    VideoCallView.xaml            -> variante de vídeo
    CallViewHeader.xaml           -> identificação, participante, informação E2EE
    CallControlsView.xaml         -> barra de ações e variantes compactas
    VoipDevicesFlyout.xaml        -> contêiner de menu de dispositivos
    CallingErrorsView.xaml        -> apresentação de erros
    CallOfferFailedControlsView.xaml -> mensagem, tentar de novo, fechar
    CallEndRatingView.xaml        -> avaliação após término
    AddCallParticipantsView.xaml  -> participantes
    VoipResources.xaml            -> cores, brushes e estilo-base
  Assets/
    Glyph.cs                      -> nomes e códigos dos ícones de fonte
    *.svg                         -> ícones de controles
```

Em `VoipView.xaml:23`, áudio e vídeo usam `x:Load` com funções diferentes e VMs próprios. O comentário do próprio XAML os descreve como mutuamente exclusivos. Em `AudioCallView.xaml:103`, há cabeçalho; em `:148`, o painel depende de estado/grupo/participantes; em `:441`, entra a barra normal; em `:455`, existe controle compacto. Não se deve confundir essa janela de chamada com a aba de histórico.

### Controles e estados comprovados nas declarações

| Controle declarado | Evento/contrato observado | Tratamento proposto no ViperChat |
| --- | --- | --- |
| `NewMicMuteButton` | `MicMuteButton_Click`, VM `IsMuted`/`TrySetMuteAsync` | Mute local de áudio, via adaptador do transporte. |
| `NewMicDevicesButton` | `NewMicDevicesButton_Click`, `AudioSettingsA11y` | Menu de microfone/saída; implementar e validar seleção real, não só o ícone. |
| `NewEndCallButton` | `EndCallButton_Click`, `A11yVoipEndCall` | Encerrar sessão do provedor correto; idempotente. |
| Botão de entrar | `JoinButton_Click`; contrato `AnswerCallAsync`/`JoinCallLinkAsync` | Aceitar chamada recebida; não implementar link de chamada por analogia. |
| `NewMessageButton` | `NewMessageButton_Click`; leitura de `PeerOrGroupJid`, conversão `ToProtocolString` e callback `Action.Invoke` nas arestas CIL | Abrir conversa do contato sem encerrar chamada. |
| `NewParticipantSideBarTriggerButton` | `ParticipantSideBarTriggerButton_Click`, `IsSidebarOpen` | Só apresentar se o backend suportar participantes/conferência. |
| `NewVideoMuteButton` | `VideoMuteButton_OnClick`, `IsVideoMuted` | Fora do MVP SIP de áudio; o cliente atual pede `video: false`. |
| Compartilhar tela, reação, levantar mão | Eventos próprios, flags de disponibilidade e estado | Não habilitar apenas porque há asset no WhatsApp. |
| Falha na oferta | `MessageButton_Click`, `CallAgainButton_Click`, `CloseButton_Click` | Ações explícitas, sem rediscagem automática. |

O clique de dispositivos contém uma chamada de telemetria `ReportTapAudioDevices`; essa aresta isolada não demonstra a abertura do menu. Os handlers assíncronos de mute/encerrar possuem state machines: não inferimos o corpo completo a partir do nome do callback.

### Estilo e responsividade declarados

Valores do pacote, não medições da tela atual:

- `VoipResources.xaml:28`: fundo `#0A1014`; `:32`: conteúdo `#12181C`.
- `VoipResources.xaml:60`: encerrar `#D5382F`; `:63`: aceitar `#24CB63`.
- `CallControlsView.xaml`: fundo normal de controle `#20272B`, texto branco, estado mutado com fundo branco e texto escuro.
- Estilo-base de botão: `40 × 40`, raio `20`; variantes centrais: `48 × 48`, raio `12` (`:52` e `:61`).
- Estados `NewSmallestCompactView` (`:727`) e `NewCompactView` (`:772`): controles de `32 × 32`, raio `16`, ocultação de opções secundárias e setas de dispositivos. Os breakpoints efetivos não foram estabelecidos.
- `AudioCallView.xaml`: colunas laterais de participantes com limite declarado de `300`; cabeçalho, conteúdo expansível e rodapé separados. Não transportar esse limite fixo para o celular.

Para ViperChat, usar os tokens Tailwind e ícones já existentes, com identidade visual própria; esses valores são referência de composição, não CSS pronto para colar. Manter alvos de toque acessíveis no mobile, mesmo onde a referência desktop reduz os controles.

### Assets localizados

`WhatsApp.Design/Assets` contém 23 SVGs no inventário recursivo. Entre eles:

- `call_end_filled.svg`, `ic_calls~filled.svg`, `ic_calls~filled_white.svg`;
- `mic_filled.svg`, `mic_off_filled.svg`, `mic_off_filled_white.svg`;
- `videocam_filled.svg`, `videocam_off_filled.svg`, `videocam_filled_black.svg`;
- `message_icon.svg`, `screen_share.svg`, `stop_screen_share.svg`, `ic_person_add.svg`, `ic_members.svg`, `hand_raise.svg`, `grid_view.svg`, `speaker_view.svg`.

`Assets/Glyph.cs` declara, entre outros: `Phone` U+E717, `Microphone` U+E720, `Mute` U+E74F, `Dialpad` U+E75F, `IncomingCall` U+E741, `OutgoingCall` U+E742 e `EndCall` U+E65A. `GlyphExtensions.cs` constrói `FontIcon`, sem depender de imagem PNG para esses ícones.

Sons encontrados, apenas inventariados: `Sounds/whatsapp_windows_ringtone_02.m4a`, `whatsapp_windows_hangup_01_705kbps.wav` e alertas. Não foram reproduzidos nem incorporados.

Não foi encontrada, no inventário selecionado de HTML/JS/CSS/XAML do pacote, uma página textual inequívoca da aba completa de histórico Chamadas. A aplicação tem WebView2 e ponte nativa, mas não foi coletado o frontend remoto/cache do perfil. A lista, filtros, abas e detalhes precisam dos prints e de observação futura. Não afirmar que o XAML da janela ativa representa essa aba.

## 3. Base do ViperChat encontrada

Snapshot de análise: branch `feat/whatsapp-unified-inbox-dev`, HEAD `b39ba86d24e25b0841211fa06e74fbc4ec40219f`, com alterações locais preexistentes. Não são necessariamente os mesmos arquivos da imagem/VPS.

| Camada | Código existente | Evidência e limite |
| --- | --- | --- |
| SIP no navegador | `package.json:116`, `app/javascript/dashboard/api/channel/voice/customVoiceClient.js` | `sip.js` 0.21.2; UserAgent, Registerer, Inviter, WSS, ICE e áudio. |
| Cliente custom | `customVoiceClient.js:125`, `:147`, `:177`, `:267`, `:281`, `:714`, `:796` | Registro, saída, REFER, DTMF, aceitar/rejeitar presentes no código; não testados numa chamada. |
| Configuração SIP | `enterprise/app/services/voice/provider/custom/token_service.rb`, `enterprise/app/models/channel/voice.rb` | WS URL, domínio, credenciais por agente, ICE, opções REFER/ARI. Nenhum segredo foi consultado. |
| Sessão compartilhada | `app/javascript/dashboard/composables/useCallSession.js` | Estado de chamada, aceitar, encerrar, dispensar e duração. |
| Store | `app/javascript/dashboard/stores/calls.js` | Lista de chamadas em memória, uma ativa, descarte por `callSid`. Não substitui histórico persistido. |
| UI efetivamente importada | `app/javascript/dashboard/routes/dashboard/Dashboard.vue:19` | Importa `components/widgets/FloatingCallWidget.vue`; não o homônimo `components-next/call/`. |
| Nova variante de UI | `app/javascript/dashboard/components-next/call/CallCard.vue`, `FloatingCallWidget.vue` | Cartão com estados, nome, duração e mute; não presumir que esteja montado na raiz. |
| Histórico backend | `enterprise/app/models/call.rb`, `enterprise/app/finders/call_finder.rb` | Modelo Call, direção, estado, duração, agente, gravação; finder com filtros e 25 itens/página. |
| Endpoint de histórico | `config/routes.rb:310`, `enterprise/app/controllers/api/v1/accounts/calls_controller.rb` | GET de calls por conta; visibilidade restrita pelo finder. |

### PJSIP: separação de responsabilidades

Não foi encontrado PJSIP como dependência do frontend pesquisado. O código existente fala SIP pelo SIP.js. Se a central usar Asterisk/PJSIP, o desenho de integração é navegador/SIP.js → SIP sobre WebSocket/WebRTC → central. A existência dos campos no ViperChat não comprova que a central, codecs, certificados WSS, ICE/TURN e roteamento estejam configurados ou funcionando. Não houve conexão à central nesta análise.

### Lacunas concretas antes de chamar isso de webphone funcional

1. `getVoiceCallProvider` em `dashboard/helper/inbox.js:42` reconhece somente Twilio com voz habilitada, e a constante `VOICE_CALL_PROVIDERS` desse arquivo contém somente `TWILIO`. Outros componentes/composables referenciam `VOICE_CALL_PROVIDERS.WHATSAPP`, ausente nesse contrato. Há código de sessão Meta separado, mas não se deve presumir sua integração correta no seletor atual. `useCallSession.js` inicializa Twilio no caminho não WhatsApp e não escolhe o `CustomVoiceClient` para registro/entrada. Conferir esse contrato antes de acrescentar SIP/custom sem regredir Meta.
2. `ConferenceController#token/#create/#destroy` chama serviços Twilio; não há ações `transfer`, `incoming`, `status` nesse controller, apesar das rotas e do `VoiceAPIClient` que as referenciam. O controller de saída de contatos seleciona `Channel::TwilioSms` com voz habilitada.
3. `Call` enumera somente `twilio` e `whatsapp`; `Voice::OutboundCallBuilder` grava `provider: :twilio`. É necessário representar SIP/custom sem reclassificar nem alterar IDs das chamadas antigas.
4. O widget montado desestrutura `transferCall` e `sendDtmf`, mas `useCallSession` não os retorna. O clique de DTMF usa essa função ausente. Há métodos nos clientes, não uma ligação ponta a ponta válida. Os botões de transferência e chamada interna estão comentados no template principal.
5. Não foi localizada uma rota de frontend dedicada à nova central/aba Chamadas na busca direcionada. Existe base para histórico no backend, não uma tela operacional equivalente já validada.
6. Mute, seleção de entrada/saída, permissões, fila de chamadas e reconexão precisam de contrato consistente por transporte. Não presumir que os controles do cartão novo funcionem com SIP/custom.
7. A assinatura `VoiceAPI.leaveConference(inboxId, conversationId)` diverge do objeto passado por `useCallSession`. Incluir esse contrato nos testes antes de reaproveitar o fluxo.

Esses pontos são observações estáticas do checkout atual, não diagnóstico confirmado da produção. Nenhuma correção funcional foi aplicada nesta etapa.

## 4. Proposta preliminar (substituída pelo plano de 20/10/2026)

Separar quatro peças, preservando a experiência existente de Meta/Twilio:

1. **Página Chamadas**: lista pesquisável/paginada, filtros por direção/estado/caixa/agente e painel de detalhes. Em celular, alternar lista e detalhe, sem colunas fixas.
2. **Discador**: contato ou número, caixa/linha elegível, indicação de conexão e ação explícita de ligar. Sem discagem ao selecionar um item do histórico.
3. **Sessão global única**: chamada continua ao mudar de rota; cartão compacto e visão completa compartilham estado. Atender, rejeitar, encerrar, mute, duração, DTMF e retorno à conversa.
4. **Adaptadores de transporte**: SIP/custom, Meta e Twilio selecionados por capacidade. Transferência, vídeo, conferência ou compartilhamento só aparecem se houver suporte real. Não trocar automaticamente o transporte de uma chamada em andamento.

Antes de desenvolver a aparência final: fechar os contratos SIP/controller/modelo, cobrir estados e erros com testes sintéticos, então conectar o layout. A aparência do WhatsApp não exige reutilizar código/ícones proprietários.

Aceite futuro: chamadas recebidas/saída, aceitar em apenas um agente, ocupado, não atendida, rejeitada, falha, término remoto, reconexão, permissões negadas, DTMF/REFER, microfone/saída, histórico e continuidade de navegação. Validar web e os apps nativos; não declarar suporte móvel em background apenas com teste de navegador.

## 5. Prints solicitados no levantamento original

Status em 20/10/2026: aba completa e detalhes de não atendida/duração recebidos; descritos no plano consolidado. Continuam úteis discador, menus, janela ativa e variantes estreitas, sem iniciar ligações só para produzi-los. A lista original solicitada era:

- Aba Chamadas inteira, com histórico e navegação lateral.
- Um item selecionado, mostrando o painel de detalhes.
- Menu de opções do item e filtros existentes.
- Discador/nova chamada aberto, sem apertar ligar.
- Se já houver captura anterior, janela ativa e seletor de áudio.
- Janela estreita para entender a adaptação do layout.

Cada print complementará este mapa: observado no print, declarado no código, hipótese de comportamento ou proposta ViperChat.

## 6. Integridade e validação desta etapa

Os três XAML de controles/áudio/falha foram lidos com parser XML; bindings e callbacks foram inventariados. REA confirmou metadados e tipos selecionados sem executar código do alvo. Nenhuma chamada real, teste de rede SIP, alteração de frontend/backend, commit, push ou deploy foi executado. Este documento é o entregável; não foram criadas cópias temporárias dos assemblies nem extrações volumosas.

Hashes dos recursos textuais lidos (PowerShell `Get-FileHash`, evidência de shell, não Evidence REA):

```text
WhatsApp.Design/Voip/CallControlsView.xaml 83851eb62dff0ca913351d34efd4de92edd5217b2965e5b889e162414c03a2f2
WhatsApp.Design/Voip/AudioCallView.xaml c8655c68297633166d89ccd4e05735f9c8bce793d553b42aa9b1fce47c60b138
WhatsApp.Design/Voip/VoipView.xaml 16a0a6d8610a9be50bde5e691822d2cb444fbfb37318290c59e64d7d30eb3976
WhatsApp.Design/Voip/VoipResources.xaml 23ab20f1c50a621383b990dece9c5081e6b1d910dce30ccdc7d7680f16c5c5e1
WhatsApp.Design/Voip/CallOfferFailedControlsView.xaml ed42f30ced9ca281d695f1ec13315c02f78240c5c328ed15670c02daa91de9b3
WhatsApp.Design/Assets/Glyph.cs 18f85043bc329085e53e3e288b2744e810bb272938e8f9d5e3a076ca6d4b855a
```

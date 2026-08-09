# Viper Chat Native — análise de implementação

## Decisão de arquitetura

O ViperChat é uma aplicação Rails com Vue 3 compilado por Vite através de `vite-plugin-ruby`. O aplicativo das lojas usará um bundle Vue local separado (`dist-mobile`) e não uma WebView apontada para um servidor remoto. A UI e as regras de negócio continuam compartilhadas com Web/PWA.

O rollout será Android primeiro. O primeiro artefato é um APK manual com discovery e configuração da instalação; autenticação só será adicionada junto ao storage seguro em Keychain/Keystore.

## Mapa do frontend atual

| Recurso              | Implementação atual                                                                             | Ponto de integração native                                             |
| -------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Entrypoint dashboard | `app/javascript/entrypoints/dashboard.js`                                                       | Extrair bootstrap reutilizável depois da validação do shell mobile     |
| Entrypoint de login  | `app/javascript/entrypoints/v3app.js`                                                           | Reutilizar componentes de login com API base dinâmica                  |
| Router               | `dashboard/routes/index.js` e `v3/views/index.js`, ambos com Vue Router history                 | Usar history no web e hash no bundle local                             |
| Estado               | Vuex em `dashboard/store`; migração incremental para Pinia                                      | Manter stores e desmontá-las ao trocar instalação                      |
| Autenticação         | Devise Token Auth, headers salvos no cookie `cw_d_session_info`                                 | Web mantém cookie; native usará Keychain/Keystore por `installationId` |
| API                  | Axios criado em `dashboard/helper/APIHelper.js`; clientes usam URLs relativas                   | Introduzir base URL da instalação ativa sem mudar o default web        |
| WebSocket            | ActionCable em `dashboard/helper/actionCable.js` e `shared/helpers/BaseActionCableConnector.js` | Resolver `wss://<instalação>/cable` e desconectar na troca             |
| Manifest PWA         | `public/manifest.json`                                                                          | Não é incluído nem alterado pelo bundle Capacitor                      |
| Service Worker       | `public/sw.js`                                                                                  | Nunca registrar no runtime native                                      |
| Web Push             | `dashboard/helper/pushHelper.js`                                                                | Preservar `browser_push`; native terá FCM/APNs independente            |
| Lista de conversas   | `dashboard/components/ConversationList.vue` e `ConversationItem.vue`                            | Reutilizar no futuro `ShareConversationPicker`                         |
| Rota de conversa     | `inbox_conversation`, em `conversation.routes.js`                                               | Resolver por serviço usando `accountId` e `display_id`                 |
| Composer             | `dashboard/components/widgets/conversation/ReplyBox.vue`                                        | Receber pending share sem envio automático                             |
| Upload               | `dashboard/composables/useFileUpload.js`, ActiveStorage DirectUpload                            | Converter URI nativa em `File` e entrar no mesmo pipeline              |
| Gravação de voz      | `WootWriter/AudioRecorder.vue`                                                                  | Solicitar microfone apenas quando o usuário gravar                     |
| Chamadas             | `useWhatsappCallSession.js`, `useCallSession.js`, Twilio Voice                                  | Primeiro validar WebRTC foreground; background exige integração nativa |

## Backend de notificações

`NotificationSubscription` já diferencia `browser_push` e `fcm`. `Notification::PushNotificationService` entrega Web Push via VAPID e FCM diretamente ou pelo Chatwoot Hub. A implementação native deve estender esse núcleo e criar um relay central Viper dedicado, sem substituir `/sw.js`, VAPID ou inscrições de navegador.

## Storage e isolamento

O dashboard usa cookie, localStorage, sessionStorage e IndexedDB no mesmo origin. Como o bundle native terá um origin local único para todos os servidores, a troca de instalação deverá:

1. cancelar requests e ActionCable;
2. desmontar stores;
3. limpar caches, sessionStorage e IndexedDB da instalação anterior;
4. carregar credenciais seguras pelo `installationId`;
5. reinicializar API, autenticação e realtime.

Preferences armazena somente URL, identidade e capacidades públicas. Tokens não podem ser persistidos nela.

## Permissões

O primeiro Android declara Internet, notificações e microfone. Galeria e documentos usam Photo Picker/Storage Access Framework; share recebe permissões temporárias para as URIs. Câmera, localização e Bluetooth serão adicionados somente junto da funcionalidade correspondente.

WebRTC foreground é tecnicamente compatível com a base atual. Chamadas confiáveis em background ou com o app encerrado exigirão Android Telecom/foreground service e iOS CallKit/PushKit; essa fase não deve depender de a WebView permanecer viva.

## Riscos e gates

- O HTML do dashboard hoje é produzido pelo Rails e injeta `window.chatwootConfig` e `window.globalConfig`; o bundle local precisa de bootstrap público próprio antes de montar o dashboard completo.
- Login cross-origin exige CORS para as origens Capacitor e storage seguro antes de persistir headers.
- Arquivos compartilhados grandes não podem passar em base64; o spike Android deve provar URI local para `File`/ActiveStorage ou implementar streaming nativo.
- O mesmo usuário com PWA e APK instalados poderá receber dois pushes até existir deduplicação entre dispositivos; os transportes permanecem independentes.
- Web/PWA, manifest, Service Worker, VAPID, composer, upload e ActionCable formam a suíte obrigatória de regressão.

## Arquivos iniciais

- `app/controllers/native_app_controller.rb` e `config/routes.rb`: discovery público versionado.
- `config/initializers/cors.rb`: origens Capacitor explícitas sem retirar o comportamento existente.
- `vite.mobile.config.ts`, `capacitor.config.ts` e `app/javascript/native/`: shell local Android.
- `android/`: projeto gerado pelo Capacitor, permissões e build APK.

## Estado da implementação incremental

- Etapa 1, fundação Android: shell Vue local, runtime detection, armazenamento de instalações e APK debug concluídos.
- Etapa 2, discovery: endpoint, capabilities e limites implementados; o teste Rails precisa ser executado em um ambiente com o runtime Ruby do projeto.
- Autenticação, dashboard completo, share nativo, registry/relay de push e navegação profunda permanecem desativados até suas respectivas etapas.
- `nativeShare` e `nativePush` não são anunciados como disponíveis antes de existirem ponta a ponta.

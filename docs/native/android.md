# Android

## Permissões

Declaradas explicitamente:

- `INTERNET`, necessária para validar e acessar a instalação;
- `POST_NOTIFICATIONS`, preparada para a etapa de push nativo;
- `RECORD_AUDIO`, necessária para notas de voz e para o futuro WebRTC.
- `CAMERA`, solicitada pelo Android somente quando o usuário abre captura de foto/vídeo;
- `ACCESS_COARSE_LOCATION` e `ACCESS_FINE_LOCATION`, solicitadas somente quando uma ação de localização for usada.

O plugin de push acrescenta permissões técnicas de rede, wake lock e recebimento FCM. O app não pede câmera, microfone, localização ou notificações no primeiro lançamento: cada prompt nasce da ação correspondente. Galeria e arquivos usam os pickers do Android e não exigem leitura ampla do armazenamento.

## Sessão

O plugin local `SecureStorage` usa uma chave AES-256 gerada dentro do Android Keystore e AES-GCM para criptografar os headers de autenticação antes de gravá-los. O backup do aplicativo está desabilitado para impedir a restauração de dados criptografados sem a chave correspondente.

As sessões usam o namespace `viper:{installationId}:auth`. Senha, histórico de conversa e corpo de mensagens não são gravados nesse storage.

Galeria e documentos usam o seletor do WebView/Photo Picker e o Storage Access Framework. O Android concede acesso temporário apenas aos itens selecionados ou compartilhados. Bluetooth será adicionado junto da integração Android Telecom para chamadas em segundo plano, evitando uma permissão sem uso nesta versão.

## Compartilhar para o ViperChat

O aplicativo aparece no Share Sheet para texto, um arquivo ou até 10 arquivos. O conteúdo é copiado para cache privado sem Base64, permanece pendente enquanto o usuário escolhe uma conversa e entra no compositor somente após confirmação. Nada é enviado automaticamente.

## Push

O pedido de permissão aparece dentro do dashboard apenas quando o servidor anuncia `nativePush`. Depois da autorização, o token FCM é registrado como `viper_native`, isolado do `browser_push` usado pelo Web/PWA. O toque abre diretamente a conversa indicada no payload.

Para uma APK realmente receber push, adicione o `google-services.json` do projeto Firebase Android em `android/app/google-services.json` antes do build. Esse arquivo contém configuração de ambiente e não deve ser versionado.

## Instalação manual

1. Copie o APK debug para o aparelho.
2. Autorize a instalação por essa fonte quando o Android solicitar.
3. Instale e abra o ViperChat.
4. Informe uma instalação que já publique o endpoint de discovery.

Uma conta Google Play não é necessária para esse fluxo. A atualização de um APK debug exige que o novo arquivo use a mesma chave debug; builds de release/Play Store usarão outra chave e devem ser tratados como canal separado.

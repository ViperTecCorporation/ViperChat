# Android

## Permissões da primeira entrega

Declaradas explicitamente:

- `INTERNET`, necessária para validar e acessar a instalação;
- `POST_NOTIFICATIONS`, preparada para a etapa de push nativo;
- `RECORD_AUDIO`, necessária para notas de voz e para o futuro WebRTC.

O plugin de push acrescenta permissões técnicas de rede, wake lock e recebimento FCM. Câmera, localização e leitura ampla do armazenamento não são declaradas nesta fase.

## Sessão

O plugin local `SecureStorage` usa uma chave AES-256 gerada dentro do Android Keystore e AES-GCM para criptografar os headers de autenticação antes de gravá-los. O backup do aplicativo está desabilitado para impedir a restauração de dados criptografados sem a chave correspondente.

As sessões usam o namespace `viper:{installationId}:auth`. Senha, histórico de conversa e corpo de mensagens não são gravados nesse storage.

Galeria e documentos deverão usar Photo Picker e Storage Access Framework. O Android concede acesso temporário apenas aos itens selecionados ou compartilhados. Câmera, localização e Bluetooth serão adicionados junto das respectivas funcionalidades e solicitados no contexto de uso.

## Instalação manual

1. Copie o APK debug para o aparelho.
2. Autorize a instalação por essa fonte quando o Android solicitar.
3. Instale e abra o ViperChat.
4. Informe uma instalação que já publique o endpoint de discovery.

Uma conta Google Play não é necessária para esse fluxo. A atualização de um APK debug exige que o novo arquivo use a mesma chave debug; builds de release/Play Store usarão outra chave e devem ser tratados como canal separado.

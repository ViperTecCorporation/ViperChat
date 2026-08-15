# iOS

O aplicativo iOS reutiliza o mesmo bundle Vue local, autenticação, dashboard, conversas, contatos, traduções e upload usados pelo Android. O projeto nativo fica em `ios/App` e usa Swift Package Manager, sem CocoaPods.

## Ambiente

- macOS Sequoia 15.6 ou superior;
- Xcode 26.0 ou superior compatível com a versão do macOS;
- Node.js 22 ou superior;
- pnpm 10.2.0.

No iMac de homologação com macOS 15.7, use Xcode 26.0 até 26.3. Versões 26.4 ou posteriores exigem macOS Tahoe 26.2.

## Gerar e abrir

```bash
pnpm install --frozen-lockfile
pnpm native:sync:ios
pnpm native:open:ios
```

O bundle ID é `net.vipertec.viperchat` e o deployment target inicial é iOS 15. O ícone e a tela de abertura usam a identidade ViperChat.

Para testar login e persistência de sessão no simulador, execute o aplicativo pelo Xcode ou gere o build com assinatura local (`Sign to Run Locally`). `CODE_SIGNING_ALLOWED=NO` deve ser usado somente para validar a compilação, pois um aplicativo sem `application-identifier` não consegue acessar o Keychain.

## Sessão e permissões

O plugin local `SecureStorage` persiste os headers de autenticação no Keychain com acesso restrito ao aparelho. A senha não é armazenada.

O `Info.plist` declara câmera, microfone, localização durante o uso e biblioteca de fotos. O iOS mostra cada prompt somente quando a funcionalidade correspondente é acionada; o seletor de documentos não exige acesso amplo aos arquivos.

A extensão `ShareExtension` aparece no menu de compartilhamento do Fotos e de outros aplicativos. Ela copia até dez imagens, vídeos ou arquivos para o App Group `group.net.vipertec.viperchat` e entrega o conteúdo ao mesmo seletor de conversa e uploader do aplicativo.

## Dependências externas pendentes

- conta Apple gratuita para executar no iPhone e Apple Developer Program para TestFlight/App Store;
- configuração local `GoogleService-Info.plist` do aplicativo iOS para obter token FCM e entregar push pelo relay central;
- chave ou certificado APNs associado ao projeto Firebase;
- App Group `group.net.vipertec.viperchat` registrado na conta Apple para assinar o app e a Share Extension em aparelhos físicos;
- CallKit e PushKit para chamadas recebidas com o aplicativo suspenso ou encerrado.

O `GoogleService-Info.plist`, certificados e chaves de assinatura não devem ser versionados.

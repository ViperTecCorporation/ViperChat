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

## Sessão e permissões

O plugin local `SecureStorage` persiste os headers de autenticação no Keychain com acesso restrito ao aparelho. A senha não é armazenada.

O `Info.plist` declara câmera, microfone, localização durante o uso e biblioteca de fotos. O iOS mostra cada prompt somente quando a funcionalidade correspondente é acionada; o seletor de documentos não exige acesso amplo aos arquivos.

## Dependências externas pendentes

- conta Apple gratuita para executar no iPhone e Apple Developer Program para TestFlight/App Store;
- aplicativo iOS cadastrado no Firebase e seu `GoogleService-Info.plist` para obter token FCM e entregar push pelo relay central;
- certificados APNs associados ao projeto Firebase;
- App Group e Share Extension para receber texto, imagens e arquivos de outros aplicativos;
- CallKit e PushKit para chamadas recebidas com o aplicativo suspenso ou encerrado.

O `GoogleService-Info.plist`, certificados e chaves de assinatura não devem ser versionados.

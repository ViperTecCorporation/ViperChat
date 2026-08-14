# Viper Chat Native

Os aplicativos Android e iOS usam Capacitor com um bundle Vue local compartilhado. Eles não carregam uma instalação remota dentro de uma WebView e não alteram o entrypoint, manifest, Service Worker ou Web Push da aplicação Web/PWA.

## Estado atual

A terceira entrega permite instalar o APK, validar a instalação, autenticar por e-mail/senha com MFA opcional e abrir o mesmo dashboard Vue usado no Web/PWA. As credenciais de sessão são criptografadas pelo Android Keystore e isoladas por `installationId`; a senha nunca é persistida.

Upload direto aponta para a instalação remota, o Share Sheet anexa texto/arquivos ao compositor após escolha da conversa e o push nativo registra tokens em um canal independente do Web/PWA. Push real exige Firebase no aplicativo e o Viper Push Relay configurado no servidor.

A fundação iOS já contém o projeto Xcode, identidade visual, permissões declaradas e sessão protegida pelo Keychain. Push FCM/APNs, Share Extension, assinatura e publicação nas lojas ainda dependem das credenciais Apple/Firebase e das próximas entregas. WebRTC em primeiro plano pode reutilizar os fluxos já embarcados no dashboard; chamadas em segundo plano exigem Android Telecom/foreground service e, no iOS, CallKit/PushKit.

## Comandos

```bash
pnpm build:native
pnpm native:sync:android
pnpm native:build:android
pnpm native:bundle:android
pnpm native:sync:ios
pnpm native:open:ios
```

O APK debug é gerado em:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

O build Android usa JDK 21, Android SDK 36 e Gradle Wrapper. A assinatura debug serve somente para instalação manual e validação; uma chave de release separada será necessária para distribuição.

## Identidade

- Android application ID: `net.vipertec.viperchat`
- iOS bundle ID: `net.vipertec.viperchat`
- Nome: `ViperChat`
- Versão atual: `4.16.12-viper.10` (`versionCode` 4161210)

Veja também [android.md](android.md), [ios.md](ios.md), [self-hosted.md](self-hosted.md) e
[push-relay.md](push-relay.md).

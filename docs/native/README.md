# Viper Chat Native

O aplicativo Android usa Capacitor com um bundle Vue local. Ele não carrega uma instalação remota dentro de uma WebView e não altera o entrypoint, manifest, Service Worker ou Web Push da aplicação Web/PWA.

## Estado atual

A primeira entrega permite instalar o APK, identificar o runtime, informar uma URL HTTPS, validar `/.well-known/viper-chat` e persistir instalações públicas por `installationId`. Credenciais e tokens ainda não são armazenados; login, share e push nativo serão habilitados incrementalmente.

## Comandos

```bash
pnpm build:native
pnpm native:sync:android
pnpm native:build:android
```

O APK debug é gerado em:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

O build Android usa JDK 21, Android SDK 36 e Gradle Wrapper. A assinatura debug serve somente para instalação manual e validação; uma chave de release separada será necessária para distribuição.

## Identidade

- Android application ID: `net.vipertec.viperchat`
- Nome: `ViperChat`
- Versão inicial: `4.16.11-viper` (`versionCode` 4161100)

Veja também [android.md](android.md) e [self-hosted.md](self-hosted.md).

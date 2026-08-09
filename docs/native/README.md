# Viper Chat Native

O aplicativo Android usa Capacitor com um bundle Vue local. Ele não carrega uma instalação remota dentro de uma WebView e não altera o entrypoint, manifest, Service Worker ou Web Push da aplicação Web/PWA.

## Estado atual

A segunda entrega permite instalar o APK, informar uma URL HTTPS, validar `/.well-known/viper-chat`, autenticar por e-mail e senha e abrir o mesmo dashboard Vue usado no Web/PWA. As credenciais de sessão são criptografadas pelo Android Keystore e isoladas por `installationId`; a senha nunca é persistida.

MFA, login social/SSO, upload direto, share e push nativo continuam desabilitados até suas respectivas etapas.

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
- Versão atual: `4.16.11-viper.2` (`versionCode` 4161101)

Veja também [android.md](android.md) e [self-hosted.md](self-hosted.md).

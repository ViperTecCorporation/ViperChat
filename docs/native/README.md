# Viper Chat Native

O aplicativo Android usa Capacitor com um bundle Vue local. Ele não carrega uma instalação remota dentro de uma WebView e não altera o entrypoint, manifest, Service Worker ou Web Push da aplicação Web/PWA.

## Estado atual

A terceira entrega permite instalar o APK, validar a instalação, autenticar por e-mail/senha com MFA opcional e abrir o mesmo dashboard Vue usado no Web/PWA. As credenciais de sessão são criptografadas pelo Android Keystore e isoladas por `installationId`; a senha nunca é persistida.

Upload direto aponta para a instalação remota, o Share Sheet anexa texto/arquivos ao compositor após escolha da conversa e o push nativo registra tokens em um canal independente do Web/PWA. Push real exige Firebase no aplicativo e o Viper Push Relay configurado no servidor.

SSO/social, recuperação de senha, iOS, publicação nas lojas e chamadas recebidas com o app encerrado ainda dependem das próximas entregas e/ou credenciais externas. WebRTC em primeiro plano pode reutilizar os fluxos já embarcados no dashboard; chamadas em segundo plano exigem Android Telecom/foreground service e, no iOS, CallKit/PushKit.

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
- Versão atual: `4.16.11-viper.4` (`versionCode` 4161103)

Veja também [android.md](android.md) e [self-hosted.md](self-hosted.md).

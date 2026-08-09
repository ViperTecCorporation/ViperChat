# Self-hosted discovery

Cada instalação compatível publica:

```http
GET /.well-known/viper-chat
```

O endpoint é público e retorna somente identidade, versão, capabilities, limites e configurações não sensíveis. O `installationId` vem do identificador estável já mantido pelo Chatwoot.

O aplicativo aceita somente HTTPS fora de desenvolvimento, exige `product: viper-chat` e API nativa versão 1. Ele persiste URL e metadados públicos somente depois dessa validação.

Variáveis previstas para a etapa de push:

- `VIPER_NATIVE_PUSH_ENABLED`
- `VIPER_PUSH_RELAY_URL`
- `VIPER_PUSH_RELAY_TOKEN`

`nativePush` só fica verdadeiro quando as três estão configuradas. O token nunca aparece no discovery. `nativeShare` permanece falso até o fluxo Android estar completo.

# Self-hosted discovery

Cada instalação compatível publica:

```http
GET /.well-known/viper-chat
```

O endpoint é público e retorna somente identidade, versão, capabilities, limites e configurações não sensíveis. O `installationId` vem do identificador estável já mantido pelo Chatwoot.

O aplicativo aceita somente HTTPS fora de desenvolvimento, exige `product: viper-chat` e API nativa versão 1. Ele persiste URL e metadados públicos somente depois dessa validação.

Variáveis do push nativo:

- `VIPER_NATIVE_PUSH_ENABLED`
- `VIPER_PUSH_RELAY_URL`
- `VIPER_PUSH_RELAY_TOKEN`

As imagens oficiais do ViperChat trazem o push nativo habilitado e usam por padrão
`https://relay.vipertec.net/v1/push` com a credencial compartilhada da ViperTec.
Os três valores continuam aceitando sobrescrita no ambiente de execução, inclusive
`VIPER_NATIVE_PUSH_ENABLED=false` para desativar o recurso ou URL/token próprios
para usar um relay privado.

`nativePush` só fica verdadeiro quando as três estão configuradas. O token nunca aparece no discovery. Cada notificação destinada a uma inscrição `viper_native` é enviada ao relay com `Authorization: Bearer`, identidade da instalação, token/dispositivo/plataforma e os campos `title`, `body` e `data`.

Contrato esperado do relay:

```http
POST ${VIPER_PUSH_RELAY_URL}
Authorization: Bearer ${VIPER_PUSH_RELAY_TOKEN}
Content-Type: application/json
```

O relay deve responder com qualquer status 2xx. Web Push e inscrições `browser_push` continuam no fluxo original e não passam por esse endpoint.

Todas as instalações Android do projeto Firebase podem compartilhar um único relay central. O token acima autentica a comunicação servidor-servidor entre cada Chatwoot e o relay; ele não é incluído no APK. Veja o procedimento de publicação em [push-relay.md](push-relay.md).

# Webhooks UnoAPI recusados com 401 após a release .34

21/10/2026 — America/Cuiaba. Correção de backend em dev, branch `4.16.0`; sem deploy, SSH ou alteração de VPS nesta implementação.

## Entrega para homologação

Autorizada a publicação da branch e da nova tag `v4.16.12-viper.34b`, sem alterar a versão interna `4.16.12-viper.34`. O push da tag aciona `publish_foss_docker.yml` para gerar `ghcr.io/viperteccorporation/chatwoot:v4.16.12-viper.34b-ce`, nas arquiteturas AMD64 e ARM64. A disponibilidade da imagem depende da conclusão do workflow; publicar a tag não significa deploy. Sem geração de aplicativos móveis nem alteração de VPS.

## Evidência e causa

Comparação das tags `v4.16.12-viper.33` (`733dec635`) e `v4.16.12-viper.34` (`68f3f9abf`). A .34 passou a selecionar UnoAPI pelo Authorization, mas os candidatos da URL eram pesquisados por igualdade literal. Ao mesmo tempo, o fallback pelo metadata passou a aceitar apenas Cloud. Um canal UnoAPI cadastrado com `+5581988985300` não era encontrado para `/webhooks/whatsapp/5581988985300`, mesmo com token correto: canal não identificado exigia HMAC Meta e retornava 401. A .33 podia reconhecer esse canal pelo metadata, mas não garantia autenticação por token nesse caminho.

Nos arquivos fornecidos, `sb14t4aqv32d8j53jv2kwgh49_logs.txt` tem 147 respostas 401 gerais; 38 requisições estão correlacionadas à URL desse número: 17 status `sent`, sete `delivered`, 13 `smb_message_echoes` e um evento `messages` sem status extraído. Cinco requisições aceitas do número usam o metadata oficial `display_phone_number=558188985300` e `phone_number_id=105303615886039`, na URL com `+`. Não representam prova de aceite da autenticação UnoAPI. O arquivo `4y81p5k6j2lyq9th8pyz39qqb_logs.txt` tem processamento de jobs, sem respostas HTTP 401. O 502 mencionado pertence ao texto de uma mensagem ecoada, não ao erro HTTP comprovado.

Integridade dos arquivos lidos, sem copiar seu conteúdo para o repositório:

- `sb14t4aqv32d8j53jv2kwgh49_logs.txt`: SHA-256 `87b844afebc103a031370584d34ec81aa19f575c2c3851cd57e424a75b3c4a2b`.
- `4y81p5k6j2lyq9th8pyz39qqb_logs.txt`: SHA-256 `e3dbc920149c4365038dae737894a4d4cd32f4e318cde81b1b4c810fa7b2f988`.

O servidor do cliente não está acessível por SSH nesta tarefa. Não foi possível provar se o Authorization histórico chegou ao Rails ou se corresponde ao token configurado. A reprodução comprova o defeito do código nas condições descritas, não uma inspeção do cadastro/runtime do cliente. A produção própria permanece na .33 com hostpaths e não é a origem desses logs; não recebeu esta correção.

## Correção e segurança

- Reutilizar `Whatsapp::ChannelPhoneIdentity.channels` nos candidatos da URL: comparar com/sem `+` e as representações brasileiras válidas com/sem nono dígito, sem regravar o número cadastrado.
- UnoAPI exige correspondência de `Authorization` com `provider_config['webhook_verify_token']`, por comparação constante. Compatível com token direto ou `Bearer `. Apenas uma correspondência autenticada pode determinar o canal. Token ausente, inválido, de outro número ou identidade ambígua não enfileira processamento.
- Encontrar um UnoAPI único pela URL não é mais autenticação. Nem um HMAC global válido substitui o token para um evento identificado como UnoAPI.
- Em URL compartilhada, metadata presente e incompatível não pode cair no primeiro Cloud apenas porque existe um cabeçalho de assinatura. Eventos administrativos sem metadata continuam com seu caminho oficial de assinatura.
- HMAC Meta continua validado sobre o corpo original, com os segredos configurados e as políticas anteriores. Segredo incorreto, assinatura ausente/inválida e corpo adulterado são recusados nos canais oficiais protegidos. Não houve alteração do concern de HMAC nem eliminação das exceções legadas já existentes para 360dialog/Cloud manual sem segredo.
- Hints `whatsapp_provider` e `whatsapp_channel_id` fornecidos pelo remetente continuam descartados. A identificação autenticada UnoAPI segue no job por ID interno; Meta segue pelo fluxo oficial. IDs, contatos, mensagens, mídias e tokens existentes não são alterados.

## Validação

Request specs usam os números/phone IDs e formatos observados nos logs, com mensagens, destinatários e credenciais sintéticos. Não são uma retransmissão integral dos payloads privados, nem validação dos cabeçalhos históricos do cliente. A matriz cobre quatro formas de cadastro por quatro formas de URL, token direto/Bearer válido, ausente/inválido, Meta válido/inválido e separação dos canais coexistentes. Inclui `sent`/`delivered` com telefone normal e `hosted.lid`, echoes UnoAPI e Meta, token de outro número, duplicidade legada, HMAC global incapaz de substituir token UnoAPI e corpo oficial modificado após assinatura.

Antes do patch, um request spec no código .34 reproduziu `sent` UnoAPI com token válido retornando 401. Depois, a rodada focada passou com **175 exemplos, zero falhas**. Os testes de carga antigos foram ajustados para enviar token no UnoAPI e HMAC no Meta; não foram removidas as verificações de IDs, contatos, bolhas, anexos, retries ou dedupe. Foram acrescentadas recusas UnoAPI antes de job/download. O replay privado opt-in recebeu o mesmo contrato de autenticação; continua dependendo de sua captura privada, que não é fornecida por estes logs.

Rodada ampliada final: **236 exemplos, zero falhas e quatro pendências preexistentes** (232 executados), em todos os controllers de webhook e regressões adjacentes de job, identidade telefônica e coexistência. As quatro pendências são exclusivamente o replay privado opt-in, sem `WHATSAPP_REAL_COEX_REPLAY`; nenhum teste foi desativado. RuboCop aprovado nos quatro arquivos Ruby alterados/adicionados; `git diff --check` aprovado. Comando da seleção:

```sh
bundle exec rspec spec/controllers/webhooks \
  spec/jobs/webhooks/whatsapp_events_job_spec.rb \
  spec/jobs/webhooks/whatsapp_events_job_coexistence_spec.rb \
  spec/models/channel/whatsapp_phone_coexistence_spec.rb \
  spec/services/whatsapp/inbox_link_phone_service_spec.rb
```

Execução em exportação temporária da `4.16.0`, no container já existente `viperchat-replica-web-1`, sem copiar o backend inteiro sobre o dev VoIP em uso. Banco confirmado como `viperchat_voip_test`, Redis de teste 15. A migração existente `20261020160000` da própria .34 foi aplicada somente nesse banco de testes para permitir o par de canais. Não foi criada migração nova, container ou volume. Sem mudança de frontend/nativo; não foi necessário recompilar aplicativos.

Limpeza após validação: exportação descartável `/tmp/viperchat-webhook-auth.IaaMPl` (aproximadamente 193 MiB), cópia transitória do novo spec em `/app/spec/controllers/webhooks/whatsapp_webhook_authentication_spec.rb` e pacote `viperchat-webhook-auth-4.16.0-20261021.tar` no Temp Windows (107.458.560 bytes) removidos. São intermediários regeneráveis, não backups/dados de cliente. Preservados fontes/testes finais nesta branch, logs originais enviados, serviços ativos, volumes e caches compartilhados. A medição interna do Docker não comprova redução do VHDX no SSD.

Após publicação futura, o cliente deverá atualizar sua imagem e verificar novos callbacks. Se o token estiver errado ou o proxy remover Authorization, o 401 continuará sendo a resposta correta. Esta correção não recupera callbacks antigos que o provedor não reenviar; não houve reenvio de mensagens ou replay contra produção. O processamento de `hosted.lid` e `MutexApplicationJob::LockAcquisitionError` permanece separado deste ajuste de autenticação.

## Ajuste posterior dos testes de vínculo de caixas

As duas falhas em `whatsapp_links_controller_spec.rb` foram reproduzidas sem o ajuste: **dois exemplos, duas falhas** durante a criação dos canais, antes da requisição HTTP. Os cenários tentavam cadastrar um telefone equivalente em outra conta e um segundo UnoAPI equivalente na mesma conta. A validação de propriedade/unicidade introduzida na .34 recusa corretamente esses cadastros; não são falhas da correção de autenticação da .34b.

Os testes agora criam canais válidos primeiro, confirmam explicitamente a recusa do número conflitante e simulam somente no banco de testes as representações distintas de registros legados por `update_columns`. O primeiro mantém a prova de que candidatos de outra conta não vazam, mesmo com telefone equivalente. O segundo exige o erro específico de vínculo ativo duplicado e confirma que o par original permanece intacto. Nenhuma validação de produção foi alterada, nenhuma expectativa anterior foi removida e nenhum teste foi desativado.

Validação focada na réplica existente: **37 exemplos, zero falhas**, cobrindo controller de vínculos, coexistência telefônica e modelo de vínculo; RuboCop sem infrações. Não foram criados containers nem alterados os fontes ativos em `/app`. Esta entrega posterior altera apenas testes/documentação na branch `4.16.0`; não move a tag `.34b`, não gera outro artefato e não altera VPS.

Rodada ampliada posterior: **325 exemplos, zero falhas, quatro pendências preexistentes** (321 executados), incluindo todos os controllers de configuração de caixas e webhooks, os modelos de coexistência/vínculo, normalização de telefone e os dois specs de jobs WhatsApp. As quatro pendências continuam sendo exclusivamente o replay de captura privada ausente. Não representa execução da suíte inteira do projeto.

Temporários desta rodada, descartáveis após os testes: `/tmp/viperchat-link-specs.OenAHa` dentro do container existente e `viperchat-link-specs-20261021.tar` / `run-viperchat-link-specs-20261021.rb` no Temp Windows. Removidos após concluir a validação, sem apagar dependências compartilhadas, bancos ou volumes.

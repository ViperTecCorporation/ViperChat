# Gmail API e IMAP/SMTP legado

Em **SuperAdmin → Configurações → Google**, a opção **Usar Gmail API por padrão**
seleciona o transporte das caixas Gmail novas ou reconectadas pelo OAuth.

- **Verdadeiro:** Gmail API, com `https://www.googleapis.com/auth/gmail.readonly`
  e `https://www.googleapis.com/auth/gmail.send`, além de `email` e `profile` para
  identificar a conta conectada.
- **Falso** (padrão de compatibilidade): IMAP/SMTP XOAUTH2 com
  `https://mail.google.com/`.

A opção não altera o login social do ViperChat. A seleção é assinada no início
do OAuth e persistida em `provider_config.gmail_transport` no callback. Alterar
o padrão não migra caixas existentes nem muda conexões com OAuth em andamento.
Não há mudança de esquema nem necessidade de migrar mensagens armazenadas.

## Configuração e migração

1. Habilitar a Gmail API no projeto Google que fornece o Client ID da integração.
2. Em ambiente de homologação, configurar os escopos mínimos no consentimento e
   conferir a URI autorizada: `<FRONTEND_URL>/google/callback`.
3. Habilitar a opção no SuperAdmin. Salvar não exige reinício da aplicação;
   a instalação de código novo exige atualizar os processos web e workers.
4. Conectar uma caixa de teste ou reconectar a caixa Gmail desejada. A troca do
   botão sozinha não muda o token nem as permissões de uma caixa existente.
5. Conferir o consentimento expandido. Receber uma mensagem com anexo, responder
   pelo ViperChat e conferir o Gmail e o destinatário. Testar CC e CCO.
6. Somente depois da validação, alinhar código, Console e demonstração enviados
   à revisão do Google. Não retirar escopos usados por outros consumidores do
   mesmo projeto sem inventariá-los. Não liberar escopos não verificados para
   usuários de produção.

Para voltar ao legado, desabilitar a opção e reconectar a caixa. Isso volta a
solicitar o escopo amplo e depende da autorização/política do projeto Google;
não é uma alternativa à exigência de escopos mínimos na revisão.

## Comportamento

- Reutiliza o agendamento existente e o bloqueio por caixa. `imap_enabled`
  continua sendo o interruptor de recebimento, inclusive para o modo API.
- Lê mensagens da INBOX, inclusive já lidas, como o transporte legado. Não
  marca mensagens como lidas, não modifica marcadores e não exclui no Gmail.
- Processa páginas de até 50 mensagens, com janela temporal fixa e checkpoint
  persistente. Falhas não avançam a janela; o próximo ciclo retoma a leitura.
- Reutiliza o processamento MIME, anexos, contatos e agrupamento por referências.
  Deduplica pelo Message-ID e respeita o registro de exclusões locais.
- Mantém a importação opcional de histórico (até 12 meses), cancelamento e
  progresso. Erros de importação aparecem como falha; iniciar novamente é seguro
  quanto às mensagens já importadas.
- Envia MIME pela API, preservando anexos, destinatários, CC/CCO e cabeçalhos de
  resposta. Respostas a mensagens importadas pela API também levam o threadId.
- Renova tokens OAuth e mantém o refresh token quando não há rotação. Erros da
  API não disparam fallback para SMTP; o envio é marcado como falha.

## Testes locais

Executar somente com `RAILS_ENV=test`, PostgreSQL e Redis isolados da réplica e
de produção. Os testes de integração HTTP usam WebMock, não uma conta Google.

```sh
bundle exec rspec spec/services/google/gmail_client_spec.rb \
  spec/requests/google_gmail_api_spec.rb \
  spec/controllers/google/callbacks_controller_spec.rb \
  spec/controllers/api/v1/accounts/google/authorization_controller_spec.rb \
  spec/jobs/inboxes/fetch_imap_emails_job_spec.rb \
  spec/mailers/conversation_reply_mailer_spec.rb \
  spec/services/email/send_on_email_service_spec.rb \
  spec/services/google/refresh_oauth_token_service_spec.rb \
  spec/services/microsoft/refresh_oauth_token_service_spec.rb \
  spec/requests/google_email_history_spec.rb \
  spec/services/imap/google_history_service_spec.rb
```

Uma suíte aprovada não comprova consentimento OAuth real nem entrega externa.
Essa validação exige uma conta de teste e a configuração correspondente no Google.

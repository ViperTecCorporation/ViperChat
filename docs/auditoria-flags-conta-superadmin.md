# Auditoria das flags de conta — Super Admin

Data: 21/09/2026. Checkout local 4.16.0, incluindo alterações ainda não publicadas.

## Correções locais posteriores à auditoria

A matriz abaixo preserva o diagnóstico original, **não o estado final das correções**.

- Busca avançada e indexação respeitam os bits salvos. Permanecem habilitadas por padrão, inclusive se a configuração global antiga não tiver essas entradas. Desmarcações explícitas são preservadas; nenhuma migration reativa indiscriminadamente contas existentes.
- Criação de canais com flag própria passou a ser validada no modelo, incluindo vias alternativas de criação. A restrição do tipo de canal não bloqueia atualizações nem tráfego de caixas existentes. Gestão de caixas é uma permissão separada.
- Escritas de gestão de agentes, times/membros, caixas/membros, etiquetas, atributos, automações, respostas prontas, macros, campanhas e hooks têm guards explícitos. Leituras auxiliares ao atendimento foram preservadas; isso não equivale a desligar automações/integrações existentes.
- Rotas protegidas verificam flags do destino e dos pais. O seletor API e o fallback Community do menu passam a respeitar a flag.
- Políticas de acesso direto às conversas respeitam as restrições de atribuição. Administradores, bots e participação em chat interno mantêm as exceções existentes. Diretório de contatos é bloqueado pela flag; o cartão do contato de atendimento continua disponível. A flag de ocultar o diretório, isoladamente, não é isolamento de todos os dados de contatos.
- Exclusão de mensagens por agentes recebe guarda no servidor. Importação legada também consulta `data_import`. Criação de conversas verifica autorização antes de enviar a mensagem e restringe a resolução de `source_id` às caixas da conta.
- Campanhas UnoAPI verificam a flag de campanha antes de agendar envios.
- Guards Enterprise acrescentados para gestão de SLA, papéis personalizados e notas CSAT; Captain V2 não sobrepõe mais a desativação de ferramentas personalizadas. Runtime Enterprise ainda não validado.

### Pendências — não considerar as 82 flags homologadas

Validação desta etapa: 770 exemplos RSpec e 43 testes Vitest passaram; build web, bundle móvel e APK debug concluídos. Bundle iOS sincronizado, mas Mac inacessível e ADB sem dispositivos; não houve validação nativa em aparelho. O runtime Ruby usado é CE, não Enterprise.

Temporário de build preservado porque a exclusão foi bloqueada pelo ambiente: `C:\Users\caita\AppData\Local\Temp\viper-flags-qa-2c53c256323847d889c76fdbff301b8e`. Contém somente cópia de assets e script Gradle desta validação.

- `api_and_webhooks`: decisão confirmada: bloquear somente novas configurações. Implementado para novas caixas API e webhooks (controller e modelo), preservando acesso por token e entrega/manutenção dos existentes na instalação self-hosted. Não identifica nem bloqueia novos programas externos que reutilizem tokens válidos. Regras comerciais de Chatwoot Cloud não foram alteradas.
- Configurações de resposta por e-mail, resolução automática e atributos obrigatórios ainda precisam de revisão específica dos caminhos de gravação/execução.
- Callbacks e execução de integrações individuais, recursos Enterprise, flags internas, legadas e apenas visuais não estão certificados ponta a ponta. Não prometer que desligar a janela WhatsApp contorne limites da Meta.
- Nenhuma publicação ou mudança de produção foi executada nesta correção.

### Validação complementar — criação de API e webhooks

74 exemplos RSpec e 20 testes Vitest passaram. Confirmados: criação negada por sessão/token/modelo, reativação da flag, leitura/edição/exclusão de webhooks existentes, atualização de caixa API existente e entrega de eventos após desativação. Botão de criação e seletor de caixa API respeitam a flag; o tooltip descreve o alcance.

Build web e APK debug concluídos; bundles Android/iOS sincronizados. ADB sem dispositivo e Mac inacessível; sem teste em aparelho/Xcode. Não houve nova inspeção visual completa de responsividade nesta etapa, que alterou condições de exibição sem alterar o layout.

Temporário adicional de validação preservado, pois a limpeza recursiva foi bloqueada pelo ambiente na etapa anterior: `C:\Users\caita\AppData\Local\Temp\viper-api-creation-qa-cd81f2088ab34029a585dcdedb7c4c12`. Contém apenas assets/recursos copiados para contornar leitura de placeholders Nextcloud e script Gradle.

## Conclusão

**Não: nem todas as 82 flags são respeitadas como restrições operacionais.** Há controles apenas visuais, flags ignoradas e exceções self-hosted/Enterprise. Esta revisão não modificou implementação, banco de produção, VPS, versão, commits ou imagem.

A matriz abaixo é uma revisão estática de todos os nomes de config/features.yml, complementada pelas provas locais indicadas. “Aplicação localizada” significa que existe um consumidor explícito no caminho inspecionado, não uma certificação de todos os endpoints/provedores e combinações de edição. Enterprise foi inspecionado no código; o runtime de teste utilizado é CE.

## Falhas prioritárias

1. **Visibilidade de agentes:** a busca/listagem e o acesso direto têm regras diferentes. Flags de ocultar contatos e conversas não devem ser apresentadas como isolamento de dados enquanto não forem aplicadas nas políticas/escopos de acesso direto.
2. **Criação de canais:** API ignora a flag até no seletor. Outros canais têm controle visual sem guarda equivalente de criação. Preservar o funcionamento de caixas existentes, como solicitado.
3. **Gestão de conta:** rotas têm metadados featureFlag, mas o guard global verifica permissões, não essas flags. Esconder menus não impede acesso por URL/API. usePolicy também retorna true no fallback CE sem marca personalizada.
4. **Busca avançada:** feature_enabled? força advanced_search e advanced_search_indexing para true.
5. **API/webhooks:** api_and_webhooks_enabled? ignora a flag em CE e Enterprise self-hosted.
6. **Controles parciais:** exclusão de mensagem, notas CSAT, atributos obrigatórios, configurações de e-mail e importação legada precisam de cobertura uniforme no servidor.

## Provas e testes locais

- 122 exemplos existentes de flags, políticas, busca, filtros e criação WhatsApp passaram. Esses testes **não cobrem todos os desvios encontrados**.
- Em objetos não persistidos, advanced_search e advanced_search_indexing ficaram com bit false e retorno efetivo true; api_and_webhooks_enabled? retornou true com a flag false.
- Em transação local revertida: POST de caixa API com channel_api=false e inbox_management=false retornou **200**.
- Na mesma transação: GET de contatos por agente com hide_contacts_for_agent=true retornou **200 e o contato de teste**.
- GET direto de conversa de outro agente na mesma caixa retornou **200** com hide_all_chats_for_agent e hide_unassigned_for_agent ativos.
- A tentativa HTTP de exclusão retornou 404, portanto sua exploração não foi confirmada em runtime; a ausência de verificação da flag no destroy foi identificada por inspeção.
- Todos os registros dos experimentos HTTP foram revertidos com ActiveRecord::Rollback. Nenhuma requisição foi enviada à VPS.

## Inventário completo

| Flag | Resultado | Observação | Evidência no projeto |
| --- | --- | --- | --- |
| `inbound_emails` | Aplicação localizada | Consultada na composição de endereços de retorno e no mailer. Não é equivalente ao bloqueio de novas caixas de e-mail. | `app/builders/email/reply_to_builder.rb:19`; `app/mailers/conversation_reply_mailer.rb:200` |
| `channel_email` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `channel_facebook` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `conversation_unread_counts` | Aplicação localizada | Controllers, listener, contador e frontend consultam flags; dependências entre os contadores são explícitas. | `app/controllers/api/v1/accounts/conversations/unread_counts_controller.rb`; `app/services/conversations/unread_counts/` |
| `ip_lookup` | Aplicação localizada | Widget e modelo de contato consultam flag antes de geolocalização. | `app/controllers/widgets_controller.rb:68`; `app/models/contact.rb:212` |
| `disable_branding` | Aplicação localizada | Views do widget e portal consultam flag. É remoção de marca, não permissão de acesso. | `app/views/widgets/show.html.erb:31`; `app/views/layouts/portal.html.erb:12` |
| `email_continuity_on_api_channel` | Aplicação localizada | Serviço de notificação por e-mail consulta flag. | `app/services/messages/send_email_notification_service.rb:35` |
| `help_center` | Parcial | Acesso público do portal consulta flag; gerenciamento via API de portais não apresenta a mesma condição no controller inspecionado. | `app/controllers/public_controller.rb:24`; `app/controllers/api/v1/accounts/portals_controller.rb` |
| `agent_bots` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `macros` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `agent_management` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `team_management` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `inbox_management` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `labels` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `custom_attributes` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `automations` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `canned_responses` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `integrations` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `voice_recorder` | Interface | Consultada pelos dois compositores para exibir o gravador; não deve impedir anexos de áudio comuns. | `app/javascript/dashboard/components/widgets/WootWriter/CompactReplyComposer.vue`; `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue` |
| `report_rollup` | Sem uso localizado | Localizada em ferramenta de manutenção para habilitação, mas não no caminho de leitura dos builders de relatórios pesquisados. Requer confirmar contrato legado antes de remover. | `lib/tasks/reporting_events_rollup.rake:214` |
| `channel_website` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `campaigns` | Parcial | Menu e campanhas do widget consultam flag; não há bloqueio geral equivalente no CRUD de campanhas identificado nesta revisão. | `app/controllers/api/v1/widget/campaigns_controller.rb:6`; `app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js` |
| `reports` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `crm` | Parcial | Metadados de rota/menu consultam a flag; guard global de rota valida permissões, não featureFlag. APIs não têm bloqueio geral equivalente por flag. | `app/javascript/dashboard/helper/routeHelpers.js`; `app/controllers/api/v1/accounts/` |
| `auto_resolve_conversations` | Parcial | Controle localizado na tela de fluxo; settings podem ser atualizadas pelo endpoint da conta sem consulta desta flag. Execução das regras existentes precisa de contrato separado. | `app/javascript/dashboard/routes/dashboard/settings/conversationWorkflow/index.vue`; `app/controllers/api/v1/accounts_controller.rb:59` |
| `custom_reply_email` | Parcial | Campos ocultados conforme flag e inbound_emails; update da conta aceita support_email/domain sem consultar essas flags. | `app/javascript/dashboard/routes/dashboard/settings/account/Index.vue:107`; `app/controllers/api/v1/accounts_controller.rb:59` |
| `custom_reply_domain` | Parcial | Campos ocultados conforme flag e inbound_emails; update da conta aceita support_email/domain sem consultar essas flags. | `app/javascript/dashboard/routes/dashboard/settings/account/Index.vue:107`; `app/controllers/api/v1/accounts_controller.rb:59` |
| `audit_logs` | Aplicação localizada | Controller Enterprise verifica feature ao autorizar acesso. | `enterprise/app/controllers/api/v1/accounts/audit_logs_controller.rb:28` |
| `custom_tools` | Condicional | Endpoint permite custom_tools OU captain_integration_v2. Desativar apenas custom_tools não fecha esse acesso quando V2 está ativo. | `enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb:39` |
| `message_reply_to` | Legada | Declarada deprecated no catálogo; não tratar como controle operacional atual. | `config/features.yml` |
| `branded_email_templates` | Aplicação localizada | Guards em controller, inbox, mailer e resolver de templates. | `app/controllers/api/v1/accounts/branded_email_layouts_controller.rb`; `app/models/concerns/inbox_branded_email_layoutable.rb` |
| `inbox_view` | Sem uso localizado | Constante e rotas existem, mas não foi localizada condição efetiva usando esta flag para liberar a visualização. É flag interna. | `app/javascript/dashboard/routes/dashboard/inbox/routes.js`; `app/javascript/dashboard/components-next/sidebar/Sidebar.vue:993` |
| `sla` | Parcial | Feature em rotas e usos específicos, mas controllers CRUD Enterprise inspecionados não bloqueiam pela flag; EnterpriseAccountsController está vazio. | `enterprise/app/controllers/api/v1/accounts/enterprise_accounts_controller.rb`; `enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb`; `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` |
| `help_center_embedding_search` | Aplicação localizada | Controllers públicos e modelo Article consultam antes de usar busca vetorial. | `enterprise/app/controllers/enterprise/public/api/v1/portals/search_controller.rb` |
| `linear_integration` | Parcial | Disponibilidade da integração consulta flag e credenciais. Não assumir bloqueio de execução/callback apenas por active?; guard genérico de Hook depende de feature_flag configurada no catálogo. | `app/models/integrations/app.rb`; `app/models/integrations/hook.rb:83`; `config/integration/apps.yml` |
| `captain_integration` | Parcial | Consultada no frontend, transcrição e templates CSAT; criação de contas Enterprise self-hosted a habilita explicitamente. Não foi feita validação ponta a ponta de todos os endpoints Captain. | `enterprise/app/services/messages/audio_transcription_service.rb:38`; `enterprise/app/models/enterprise/account.rb:107` |
| `custom_roles` | Parcial | Feature em rotas e usos específicos, mas controllers CRUD Enterprise inspecionados não bloqueiam pela flag; EnterpriseAccountsController está vazio. | `enterprise/app/controllers/api/v1/accounts/enterprise_accounts_controller.rb`; `enterprise/app/controllers/api/v1/accounts/sla_policies_controller.rb`; `enterprise/app/controllers/api/v1/accounts/custom_roles_controller.rb` |
| `chatwoot_v4` | Interface | Referência localizada no SidemenuIcon; não representa desligamento geral do frontend V4. | `app/javascript/dashboard/components/SidemenuIcon.vue:26` |
| `captain_v1_action_classifier` | Aplicação localizada | Job de classificação V1 consulta flag interna. | `enterprise/app/jobs/captain/conversation/v1_action_classifier.rb:5` |
| `contact_chatwoot_support_team` | Interface | Controla a opção de suporte no menu de perfil. | `app/javascript/dashboard/components-next/sidebar/SidebarProfileMenu.vue:43` |
| `shopify_integration` | Parcial | Disponibilidade da integração consulta flag e credenciais. Não assumir bloqueio de execução/callback apenas por active?; guard genérico de Hook depende de feature_flag configurada no catálogo. | `app/models/integrations/app.rb`; `app/models/integrations/hook.rb:83`; `config/integration/apps.yml` |
| `search_with_gin` | Aplicação localizada | Busca consulta flag para selecionar estratégia. | `app/services/search_service.rb:170` |
| `channel_instagram` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `crm_integration` | Aplicação localizada | Consultada na disponibilidade e também no catálogo da integração, usado pelo guard do Hook. | `app/models/integrations/app.rb:64`; `config/integration/apps.yml:258`; `app/models/integrations/hook.rb:83` |
| `hide_all_chats_for_agent` | Parcial | Há filtro em busca/listagem; acesso direto via ConversationPolicy continua baseado em caixa/time. GET de conversa de outro agente da mesma caixa retornou 200 com ambas ativas. | `app/services/search/conversation_visibility_service.rb`; `app/policies/conversation_policy.rb:10` |
| `hide_contacts_for_agent` | Parcial | Busca global e destinatário livre consultam a flag; endpoint geral de contatos não a aplica. GET local retornou contato com a restrição ativa. | `app/services/search/conversation_visibility_service.rb:8`; `app/controllers/api/v1/accounts/contacts_controller.rb:20`; `app/policies/contact_policy.rb` |
| `hide_filters_for_agent` | Interface | Controla visibilidade do filtro; não é barreira de leitura de dados por API. | `app/javascript/dashboard/components/ChatList.vue:180` |
| `send_agent_name_in_whatsapp_message` | Aplicação localizada | Serviço WhatsApp Cloud consulta para compor identificação do agente; comportamento de cada provedor exige testes específicos. | `app/services/whatsapp/providers/whatsapp_cloud_service.rb:280` |
| `read_message` | Aplicação localizada | UpdateLastSeenJob consulta separadamente confirmação de leitura e registro de visualização. | `app/jobs/update_last_seen_job.rb:7` |
| `disable_whatsapp_messaging_window` | Sem uso localizado | Regra atual depende do canal/provedor: UnoAPI sem janela; oficial com 24h. Não foi localizada leitura desta flag no fluxo. Não se deve usá-la para prometer contornar restrições da Meta. | `app/services/conversations/message_window_service.rb:17` |
| `agent_conversation_viewed` | Aplicação localizada | UpdateLastSeenJob consulta separadamente confirmação de leitura e registro de visualização. | `app/jobs/update_last_seen_job.rb:7` |
| `hide_unassigned_for_agent` | Parcial | Há filtro em busca/listagem; acesso direto via ConversationPolicy continua baseado em caixa/time. GET de conversa de outro agente da mesma caixa retornou 200 com ambas ativas. | `app/services/search/conversation_visibility_service.rb`; `app/policies/conversation_policy.rb:10` |
| `hide_delete_message_for_agent` | Parcial | Oculta ação no menu; não há verificação equivalente no destroy inspecionado. Prova HTTP desta ação ficou inconclusiva (404), portanto não foi classificada como exploração reproduzida. | `app/javascript/dashboard/components-next/message/Message.vue:490`; `app/controllers/api/v1/accounts/conversations/messages_controller.rb:34` |
| `channel_whatsapp` | Aplicação localizada | Correções locais anteriores protegem criação/troca de provedor no modelo e seletor. Não desligam caixas existentes. | `app/models/channel/whatsapp.rb:174`; `app/models/channel/twilio_sms.rb:84` |
| `channel_api` | Falha | Seletor aceita API sem consultar channel_api; POST de nova caixa retorna 200 com channel_api e inbox_management desativadas. | `app/javascript/dashboard/components/widgets/ChannelItem.vue:74`; `app/controllers/api/v1/accounts/inboxes_controller.rb:30` |
| `channel_notifica_me` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `channel_voice` | Aplicação localizada | Há guard para criação de canal Voice e habilitação de chamadas WhatsApp, além do frontend. | `enterprise/app/controllers/enterprise/api/v1/accounts/inboxes_controller.rb:95`; `app/models/channel/whatsapp.rb:113` |
| `notion_integration` | Parcial | Disponibilidade da integração consulta flag e credenciais. Não assumir bloqueio de execução/callback apenas por active?; guard genérico de Hook depende de feature_flag configurada no catálogo. | `app/models/integrations/app.rb`; `app/models/integrations/hook.rb:83`; `config/integration/apps.yml` |
| `captain_integration_v2` | Condicional | Altera roteamento/modelo e comportamento do Captain; habilita permissões adicionais e é forçada na criação Enterprise self-hosted. | `lib/llm/feature_router.rb:34`; `enterprise/app/models/enterprise/account.rb:107` |
| `whatsapp_embedded_signup` | Legada | Declarada deprecated no catálogo; não tratar como controle operacional atual. | `config/features.yml` |
| `whatsapp_campaign` | Parcial | Modelo de campanha e serviço oficial consultam flag; serviço UnoAPI não possui a mesma checagem explícita antes do processamento. Validar campanhas já enfileiradas. | `app/models/campaign.rb:71`; `app/services/whatsapp/oneoff_campaign_service.rb:32`; `app/services/whatsapp/oneoff_unoapi_campaign_service.rb:4` |
| `crm_v2` | Aplicação localizada | Flag interna muda seleção de contatos em busca, filtros e exportação. | `app/models/contact.rb:194`; `app/services/contacts/filter_service.rb:33` |
| `assignment_v2` | Condicional | Job e Inbox consultam a flag; setter Enterprise também ajusta advanced_assignment. | `app/jobs/auto_assignment/periodic_assignment_job.rb:7`; `app/models/inbox.rb:227`; `enterprise/app/models/enterprise/account.rb:117` |
| `captain_document_auto_sync` | Aplicação localizada | Agendador de sincronização ignora contas sem flag. | `enterprise/app/jobs/captain/documents/schedule_syncs_job.rb:23` |
| `advanced_search` | Falha | feature_enabled? retorna true explicitamente, mesmo com bit persistido falso. Indexação ainda tem exceção self-hosted adicional. | `app/models/concerns/featurable.rb:98`; `app/models/message.rb:300` |
| `saml` | Aplicação localizada | Autenticação, callback e configurações SAML consultam flag. | `enterprise/app/controllers/api/v1/accounts/saml_settings_controller.rb:53`; `enterprise/app/controllers/enterprise/devise_overrides/omniauth_callbacks_controller.rb:99` |
| `advanced_search_indexing` | Falha | feature_enabled? retorna true explicitamente, mesmo com bit persistido falso. Indexação ainda tem exceção self-hosted adicional. | `app/models/concerns/featurable.rb:98`; `app/models/message.rb:300` |
| `reply_mailer_migration` | Aplicação localizada | Flag interna seleciona novos builders de e-mail. | `app/mailers/conversation_reply_mailer_helper.rb:102` |
| `unread_count_for_filters` | Aplicação localizada | Controllers, listener, contador e frontend consultam flags; dependências entre os contadores são explícitas. | `app/controllers/api/v1/accounts/conversations/unread_counts_controller.rb`; `app/services/conversations/unread_counts/` |
| `companies` | Aplicação localizada | Guard explícito nos controllers de empresas; modelo e parâmetros dependem da flag. | `enterprise/app/controllers/api/v1/accounts/companies_controller.rb:77`; `enterprise/app/controllers/api/v1/accounts/companies/base_controller.rb:8` |
| `channel_tiktok` | Parcial | Seletor consulta a flag; criação/callback correspondente não apresenta bloqueio equivalente por conta. Caixas existentes devem continuar funcionando. | `app/javascript/dashboard/components/widgets/ChannelItem.vue`; `app/models/channel/`; `app/controllers/` |
| `csat_review_notes` | Parcial | Frontend consulta; update Enterprise grava notas sem validar esta flag. | `app/javascript/dashboard/routes/dashboard/settings/reports/components/CsatTable.vue:38`; `enterprise/app/controllers/enterprise/api/v1/accounts/csat_survey_responses_controller.rb` |
| `captain_tasks` | Aplicação localizada | Serviços e jobs consultam flag; modo de resolução automática também depende dela. | `lib/captain/base_task_service.rb:155`; `app/models/concerns/account_captain_auto_resolve.rb:19` |
| `conversation_required_attributes` | Parcial | Exigência localizada no frontend. Sem barreira equivalente identificada no endpoint para impedir resolução direta sem atributos. | `app/javascript/dashboard/composables/useConversationRequiredAttributes.js`; `app/controllers/api/v1/accounts/conversations_controller.rb` |
| `advanced_assignment` | Condicional | Seleção/limites consultam flag; salvar conjunto de flags pode habilitá-la por plano ou desabilitá-la conforme assignment_v2. | `enterprise/app/models/enterprise/account.rb:117`; `enterprise/app/services/enterprise/auto_assignment/assignment_service.rb` |
| `whatsapp_manual_transfer` | Interface | Controla exibição do fluxo de migração manual; não foi localizado guard de servidor específico para a flag. | `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue:403` |
| `data_import` | Aplicação localizada | Novo controller de importações verifica a flag; endpoint legado contacts#import ainda requer revisão equivalente. | `app/controllers/api/v1/accounts/data_imports_controller.rb:85`; `app/controllers/api/v1/accounts/contacts_controller.rb:37` |
| `api_and_webhooks` | Falha | CE retorna true; Enterprise self-hosted também retorna true sem consultar a flag. Não significa que autenticação da API esteja desligada. | `app/models/account.rb:174`; `enterprise/app/models/enterprise/account.rb:76` |
| `whatsapp_reconfigure` | Condicional | Reconfiguração de caixa embedded ativa exige flag. Reautorização necessária e caixas manuais têm exceções explícitas. | `app/controllers/api/v1/accounts/whatsapp/authorizations_controller.rb:36` |
| `whatsapp_embedded_signup_inbox_creation` | Aplicação localizada | Correção local verifica criação no serviço, inclusive self-hosted; reautorização existente permanece separada. | `app/services/whatsapp/embedded_signup_service.rb:13`; `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Whatsapp.vue` |
| `restrict_assignee_filter_for_agent` | Aplicação localizada | Servidor reescreve filtro assignee_id para o próprio agente; não restringe administradores. Não substitui autorização geral de conversas. | `app/services/conversations/filter_service.rb:77` |
| `disable_channel_unoapi` | Aplicação localizada | Correções locais anteriores protegem criação/troca de provedor no modelo e seletor. Não desligam caixas existentes. | `app/models/channel/whatsapp.rb:174`; `app/models/channel/twilio_sms.rb:84` |

## Plano recomendado de correção

1. Centralizar escopo de visibilidade e aplicar em busca, listagem, abertura direta, mensagens, contatos e endpoints auxiliares. Testar agente/administrador, atribuição por time e conta diferente.
2. Guardar criação de canais no servidor, incluindo callbacks OAuth e caminhos alternativos. Não bloquear recebimento/envio das caixas existentes ao desmarcar flag de criação.
3. Unificar metadados de rota com guard de navegação e guards de gestão no backend. Evitar bloquear leitura auxiliar de equipes/caixas necessária para atendimento.
4. Remover hardcodes de flags somente após definir a compatibilidade esperada de busca, indexação e API/webhooks. Desligar acesso à API pode interromper integrações existentes; requer escolha explícita de escopo.
5. Definir flags apenas visuais como tais; retirar do painel opções legadas/sem efeito ou implementar o comportamento prometido. Não reordenar bits nem apagar entradas do catálogo.
6. Adicionar matriz de regressão on/off por flag, vias alternativas e cenários Enterprise/self-hosted. Só depois publicar.

Não aplicar um bloqueio genérico em todos os controllers: isso pode quebrar funções auxiliares, caixas existentes e integrações. As correções de WhatsApp/UnoAPI/Embedded Signup do trabalho anterior continuam locais; esta auditoria não as publicou.

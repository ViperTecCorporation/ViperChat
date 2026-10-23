# Configurações salvas da simulação de caixas parceiras

Implementado em dev na `feat/agent-voip-webphone`, sem commit/push, VPS ou containers novos.

- O botão **Salvar configurações** persiste as tarifas de serviço, utilidade, marketing e autenticação, moeda, fuso e janela de anúncio na conta. Reabrir o relatório recupera esses valores antes do cálculo inicial.
- Os campos continuam editáveis; salvar novamente substitui os valores anteriores. Branco continua significando tarifa desconhecida e zero significa custo zero.
- Período, datas e caixa selecionada não são persistidos. O botão Atualizar relatório continua independente do salvamento.
- GET/PATCH `/api/v2/accounts/:account_id/reports/partner_inboxes/settings`, sob a mesma permissão de relatórios (incluindo a extensão Enterprise existente), sem abrir acesso a agentes não autorizados ou outras contas.
- Persistência em `accounts.settings.partner_inbox_report`, com lock e merge que preserva as demais configurações. Apenas os sete campos permitidos são aceitos; reaproveita a validação do simulador, adicionando moeda BRL/USD. Não altera tarifas reais da Meta nem transporte/envio.
- Falha de leitura é visível e bloqueia salvar valores padrão sobre uma configuração não recuperada. Falha de gravação mantém os valores anteriores e os campos editados na tela.

## Validação

Atualização posterior: padrão **Mês atual**, respeitando a virada de mês no fuso escolhido em dropdown IANA. A opção padrão segue `account.reporting_timezone`, retornado pela API em `account_timezone`; na ausência, usa o fuso do sistema. Uma escolha explícita continua sendo preferência do relatório, sem modificar o fuso da conta. A API do relatório também aplica esse fallback, sem depender do navegador. Passaram 12 testes backend e 9 frontend, incluindo mês atual, seleção alternativa, volta ao fuso da conta e manutenção dos 30 dias móveis. Contadores são consultas ao banco do ViperChat, não totais obtidos da API/painel Meta; a atualização depende dos webhooks/status recebidos. Identificação de anúncio exige `referral.source_type = ad` e `source_id` preenchido. Ausência de referência não comprova origem orgânica; `ctwa_clid` vazio não identifica clique e anúncio identificado não comprova gratuidade.

Dropdown e mês atual conferidos na réplica com Playwright em desktop 1366 px e mobile 390 px, sem overflow; escolha de America/Cuiaba exercitada somente na sessão de teste, sem salvar ou alterar o fuso da conta. Na conta 1, `reporting_timezone` está vazio, portanto a opção automática mostra o padrão do sistema (Etc/UTC). Bundles Android/iOS regenerados novamente após esse ajuste e APK Debug recompilado, assinatura verificada: `output/validation/partner-settings-20261023/viperchat-partner-month-dev.apk`, SHA-256 `681a466f3f09a3b2a0580ffe0d38cc8c635163d21cbb47676be6cb4700026c5b`. Continuam sem dispositivos Android e sem Mac acessível para execução/build iOS. Sessão de navegador encerrada e log intermediário removido; bundle runtime e APK preservados. Sem VPS, novos containers ou commit/push.

- 10 testes backend aprovados: leitura inicial, salvar/carregar/editar/limpar, zero/branco, isolamento de contas, autorização, valores/fuso/janela/moeda inválidos e preservação de outras configurações.
- 7 testes frontend aprovados: valores salvos carregados antes do relatório, edição e novo salvamento, branco/zero, erros de leitura/gravação e filtros anteriores.
- RuboCop sem infrações e ESLint sem erros (avisos de traduções dinâmicas e textos existentes).
- Playwright no localhost: salvar 0,04, recarregar, editar para 0,08, salvar e recarregar confirmou persistência. Valores sintéticos removidos ao concluir, restaurando a ausência anterior de configuração salva, sem alterar os outros settings.
- Capturas desktop 1366 px e mobile 390/320 px, sem overflow horizontal; evidências em `output/playwright/partner-settings-*`.
- Bundles Android/iOS regenerados; Android Debug compilado com um worker e heap Gradle de 1 GB. APK assinado verificado em `output/validation/partner-settings-20261023/viperchat-partner-settings-dev.apk`, SHA-256 `f46719cb7b1201062d0a396eb61bc1ec19d227bb5e6f58283ad4f8b02903f08d`.
- Sem dispositivos Android conectados; sem instalação/smoke em aparelho. Mac configurado recusou conexão: sem build/Archive ou teste de execução iOS. Não houve publicação de apps.

## Limpeza

A cópia Linux isolada de fontes/build e o log intermediário são descartáveis e removidos após validação. Preservados fontes, testes, capturas e APK. O staging Windows reaproveitado de tarefa anterior continua preservado devido ao bloqueio de limpeza já conhecido; não se tentou contornar a proteção. Containers, volumes, dependências compartilhadas e dados da réplica permanecem ativos e preservados.

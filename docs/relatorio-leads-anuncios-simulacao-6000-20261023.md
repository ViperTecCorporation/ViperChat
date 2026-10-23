# Leads de anúncios, comparativo e demonstração de 6.000 mensagens

Implementado em dev na `feat/agent-voip-webphone`, usando a réplica existente. Sem commit/push, VPS, containers novos, envios reais ou inserção do conjunto sintético no histórico.

## Relatórios e escopo

- Caixas parceiras: contador de contatos únicos com referência de anúncio, além da quantidade de entradas. Detalhamento por contato, anúncio, caixa, início/fim estimados, dias previstos/decorridos e entregas Meta isentas no período. Mensagens observadas em caixas parceiras seguem a canonização existente, sem deduplicar por texto ou horário.
- Relatórios → **Leads de anúncios**, `/app/accounts/:account_id/reports/ad_leads`: relatório independente de aquisição em todas as caixas WhatsApp da conta, inclusive sem parceira. Usa metadados `referral` já persistidos nas mensagens; não cria contatos, conversas ou um histórico paralelo.
- Filtros: período, fuso, contato/telefone, ID do anúncio, caixa, provedor e situação da janela; 10 entradas por página. Filtros específicos refinam o conjunto do período já autorizado; limite backend de 100.000 mensagens examinadas, sem truncamento silencioso. Um contato pode ter múltiplas entradas; quantidade de contatos é distinta da quantidade de entradas.
- API de aquisição: `GET /api/v2/accounts/:account_id/reports/partner_ad_leads`, sob `ReportPolicy#view?` e isolamento de conta, como o relatório original. Não libera acesso a conversas ou caixas fora das permissões existentes.
- Gráficos de tentativas diárias por provedor e de custo atual Meta versus cenário hipotético de envios identificados pela Meta. O segundo cenário recalcula franquia e janelas sobre as mesmas entregas, sem simples multiplicação bruta. Custos de ViperConnect, impostos, acréscimos e descontos por volume não entram: o indicador é custo Meta estimado evitado, não economia líquida.

## Regras e conferência

- Padrões sugeridos **Brasil/BRL**, fornecidos pelo operador: serviço, utilidade e autenticação 0,0350; marketing 0,3217. Novas configurações recebem esses valores. Valores salvos (inclusive zero e branco) são preservados; **Usar tabela Brasil** preenche os campos sem salvar automaticamente. Não há conversão para USD.
- Desde 01/10/2026, utilidade dentro das 24 h não recebe a isenção antiga. A franquia mensal de 1.000 é exclusiva de serviço e agrupada por número/mês, no fuso escolhido, sem acúmulo. Períodos anteriores mantêm as isenções anteriores no simulador. Recebidas e tentativas não entregues não geram custo.
- Serviço é saída sem template com evidência de interação do cliente nas 24 h. Template sozinho não abre a janela livre. Uma entrega ViperConnect não prova que Meta autorizaria o mesmo envio hipotético.
- Anúncio exige `referral.source_type == ad` e `source_id` preenchido. `ctwa_clid` vazio não é prova de clique; ausência de referência não prova origem orgânica.
- Janela estimada só abre após resposta Meta entregue em até 24 h da entrada por anúncio. Dentro dela todas as categorias são isentas e **não consomem** a franquia de serviço. Mantidas as opções de 7 dias e 72 h, sem promover cenário escolhido a confirmação de faturamento.
- Atribuição é por número comercial + contato, sem transportar janela entre números distintos. Exibe sem resposta elegível quando não há evidência de abertura; dias decorridos e estados usam o fim do período consultado limitado ao horário atual. As datas exibidas são estimadas e dependem das evidências disponíveis no período; não há busca de faturamento na Meta.
- Conferência em 23/10/2026: a documentação direta da Meta retornou 429; portanto não houve autenticação independente do rate card oficial. As regras de outubro foram corroboradas por [Wati](https://support.wati.io/en/articles/16954666-whatsapp-business-platform-api-pricing-changes-service-messages-and-click-to-message-ads) e [Gupshup](https://support.gupshup.io/hc/en-us/articles/62362400519705-WhatsApp-Service-Messages-Pricing-w-e-f-01-Oct-2026), com diferenças de implantação documentadas sobre 72 h / até 7 dias. Preservada a seleção explícita da janela e o aviso de estimativa.

## Demonstração reproduzível

Gerada com as classes reais de cálculo, sem persistir mensagens e sem fazer requisições aos provedores. Interceptação da API somente na sessão Playwright própria para mostrar o conjunto; retirada antes do encerramento da sessão.

- 6.000 mensagens únicas = 1.200 entradas + 4.800 envios/tentativas; 200 contatos e 60 contatos de anúncios.
- Saídas Meta: 1.718 tentativas / 1.714 entregas. ViperConnect: 3.082 tentativas / 3.076 entregas. As entradas foram observadas nos dois provedores, sem duplicar o total único. Dez tentativas sem entrega não foram tarifadas.
- 40 janelas estimadas abertas / 20 sem resposta elegível comprovada. Nas janelas: 325 entregas Meta isentas, sem consumir franquia. Fora delas: 693 serviços usaram a franquia, saldo de 307 no cenário atual.
- Custo atual estimado Meta: 123,8449 BRL; cenário hipotético: 348,68 BRL; diferença estimada: 224,8351 BRL, 64,48%. Interface/PDF arredondam a exibição monetária, não o cálculo interno.
- PDF em `output/pdf/caixas-parceiras-6000-mensagens-sinteticas.pdf`, 5 páginas renderizadas e conferidas visualmente, com todos os 60 leads e suas janelas/ausência de resposta.
- Dados e scripts em `output/validation/partner-6000-demo-20261023/`: `report.json`, `messages.json`, `generate_demo.rb`, `export_pdf.py`. Nomes, números, IDs e anúncios explicitamente sintéticos. Não substituir dados reais por esses arquivos.

## Validação, nativos e limpeza

28 exemplos backend e 13 testes frontend aprovados. Cobertura: cinco volumes de serviço informados (1.000/5.000/10.000/50.000/100.000), franquia exclusiva de serviço, todas as categorias na janela de anúncio, fim da janela, resposta tardia, corte histórico de outubro, mês/fuso/número, cenários incompletos, relatório independente com caixa não pareada, preservação de dados salvos, filtros, paginação, autorização e isolamento de contas.

RuboCop sem infrações nos arquivos novos/alterados de cálculo e aquisição; ESLint sem erros nos componentes, rotas e sidebar alterados. Playwright em desktop 1366 e mobile 390 px: combinação de filtros anúncio AD-SINT-1 + janela encerrada + Lead sintetico 003 retornou 1 card. Sem overflow horizontal. Capturas em `output/playwright/*6000*`.

Bundles Android/iOS regenerados. APK Android Debug recompilado com um worker e heap Gradle 1 GB, assinatura verificada: `output/validation/partner-6000-demo-20261023/viperchat-ad-leads-dev.apk`; SHA-256 `9d2b2cdb061f53518ced5dad06734996692f7d8649a83f8b68f243037369b233`. Sem dispositivos Android conectados; sem instalação/smoke em aparelho. Mac recusou a conexão configurada; sem build/Archive/execução iOS e sem publicação de apps.

Intermediários removidos após a cópia: runner e JSONs sintéticos em `/app/tmp/partner-6000-demo-20261023`, `/app/tmp/partner-6000-generate-20261023.rb`, log nativo intermediário e PNGs de renderização PDF. Preservados PDF, dados/scripts reprodutíveis, capturas solicitadas e APK. O staging Windows de tarefa anterior continua preservado devido ao bloqueio de limpeza já conhecido; não houve tentativa de contornar a proteção. Fontes, banco, volumes, dependências e containers existentes preservados.

# Plano consolidado - relatórios, gráficos e leads de anúncios

Destino: `feat/agent-voip-webphone`. Publicação do código solicitada em 23/10/2026, sem deploy ou acesso à VPS.

## Concluído em dev

- [x] Salvar/editar tarifas, moeda, fuso e janela por conta, preservando zero, branco e demais settings.
- [x] Padrão de período Mês atual; dropdown IANA com opção de seguir o fuso da conta.
- [x] Padrões Brasil/BRL editáveis e botão explícito para aplicá-los sem sobrescrever valores salvos.
- [x] Contadores provenientes do banco do ViperChat, com canonização/deduplicação das caixas parceiras.
- [x] Gráficos diários por provedor e comparação do custo atual Meta com o cenário hipotético.
- [x] Franquia exclusiva de serviço; corte histórico de 01/10/2026 para utilidade nas 24 h; janela de anúncio isenta sem consumir franquia.
- [x] Detalhamento de contatos/entradas de anúncio e janelas estimadas na caixa parceira.
- [x] Relatório independente de Leads de anúncios, incluindo caixas WhatsApp não pareadas, filtros e paginação.
- [x] Demonstração de 6.000 mensagens sem inserção no histórico real, PDF conferido visualmente e dados/scripts reprodutíveis preservados localmente.
- [x] 28 testes backend e 13 frontend aprovados; testes de autorização, isolamento de conta, filtros, paginação, custos e franquia.
- [x] Bundles Android/iOS regenerados e APK Debug compilado com assinatura verificada.

## Pendências e limites explícitos

- [ ] Aceite em aparelho Android/iOS. Sem dispositivo Android conectado e sem Mac acessível para build/execução iOS na validação registrada.
- [ ] Confirmar regras e rate card efetivos de cada WABA antes de tratar estimativas como base de faturamento. A consulta direta à Meta foi limitada por HTTP 429; mantidas as alternativas de 72 h e 7 dias.
- [ ] Eventual conciliação com evidências de faturamento Meta, descontos por volume e tarifas por país. O comparativo atual não inclui custos ViperConnect, impostos ou acréscimos de provedores e não presume autorização Meta para envios hipotéticos.
- [ ] Implantação na VPS, somente com autorização separada. Commit/push não é deploy.

Detalhes: [relatório de caixas parceiras](relatorio-caixas-parceiras-custos-meta.md), [configurações](partner-inbox-report-settings-20261023.md) e [leads/demonstração](relatorio-leads-anuncios-simulacao-6000-20261023.md).

Bolhas/avatar VoIP, configurações nativas geradas, APKs, PDFs e capturas locais não fazem parte deste commit de relatórios. Alterações locais desses itens são preservadas.

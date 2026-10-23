# Relatório de caixas parceiras e simulação de custos Meta

## Estado em 23/10/2026

Implementação consolidada em `feat/agent-voip-webphone` por solicitação do usuário.
Origem: alterações não commitadas da branch temporária `feat/partner-inbox-cost-report`, baseada na `4.16.0`.
Após a integração, passaram 42 testes frontend combinados (relatórios e configuração VoIP)
e as 24 verificações sintéticas backend. Os 14 arquivos funcionais conferem com a réplica existente.
A referência local `feat/partner-inbox-cost-report` foi removida. A pasta de origem
ficou em detached HEAD, com seus arquivos intactos, inclusive os temporários cuja
limpeza havia sido bloqueada. Não foram removidas outras branches ou worktrees.
Disponível na réplica dev existente, junto do código VoIP que já estava nela:
Relatórios → Caixas parceiras (`/app/accounts/1/reports/partner_inboxes`, substituindo a conta quando necessário).
Foram aplicados somente os trechos novos nos arquivos compartilhados da réplica,
sem substituir sua árvore pela branch 4.16.0. Sem containers novos, commit, push,
publicação, migração de banco ou implantação na VPS nesta tarefa.

## Funcionalidade

Atualização de 23/10: gráficos comparativos, padrões Brasil editáveis, regra de utilidade corrigida para outubro, detalhamento de contatos/anúncios/janelas e relatório independente de Leads de anúncios (inclui caixas sem parceira). Demonstração e validação completas em [Leads e simulação de 6.000 mensagens](relatorio-leads-anuncios-simulacao-6000-20261023.md). Dentro da janela estimada de anúncio, todas as categorias são isentas sem consumir a franquia de 1.000 serviços.

- **Mês atual** inicialmente, do dia 1º até hoje no fuso do relatório; alternativas de 30, 21, 14 e 7 dias ou datas personalizadas.
- Fuso em dropdown de zonas IANA. Padrão **Usar fuso da conta**, derivado de `reporting_timezone` (ou fuso do sistema se não configurado). Escolher outro fuso não modifica a configuração da conta; pode ser salvo como preferência do simulador. Não se utiliza o fuso do navegador.
- Todas as caixas parceiras ou um vínculo específico. Vínculos desativados ficam identificados.
- Mensagens públicas de canal, com recebimentos por Meta/ViperConnect e saídas pelo transporte efetivo registrado.
- Entregas confirmadas separadas das saídas/tentativas. Tentativas sem confirmação não entram na estimativa de cobrança.
- Total de mensagens únicas separado dos recebimentos observados: a mesma entrada pode ter observações dos dois provedores.
- Alias autorizado/canonização existente para deduplicação. Não compara texto, mídia ou proximidade de horário para unir registros.
- Um eco da Meta não comprova que o envio saiu pela Meta. O transporte precisa estar nos metadados ou em uma resposta de API identificada;
  mensagens antigas sem essa evidência aparecem como **não identificado**, inclusive se tiverem um `wamid`.
- Notas privadas, atividades e cards de chamada ficam fora dos contadores. Edições, exclusões e reações que atualizam a bolha existente
  não geram um novo envio. Histórico importado não consome a estimativa de franquia.
- Tarifas manuais não negativas por categoria: serviço, utilidade, marketing e autenticação. Campo vazio é desconhecido;
  zero é um valor informado. Sem preços oficiais fixos, conversão de moeda ou alteração de roteamento. Moeda BRL ou USD dos valores inseridos.
- Tarifas, moeda, fuso e janela de anúncio podem ser salvos pelo botão **Salvar configurações**, no escopo da conta, e continuam editáveis. São preferências do simulador, não configurações reais da caixa ou da WABA. Período e filtro de caixas permanecem parâmetros de cada consulta.
- A página recupera os valores salvos antes do relatório inicial; **Atualizar relatório** não salva configurações implicitamente. Zero e branco continuam distintos. Detalhes e validação: [Configurações salvas](partner-inbox-report-settings-20261023.md).

## Premissas de simulação, não promessa de faturamento

A imagem recebida é uma captura de outra resposta de IA, não documentação oficial.
A documentação técnica de preços da Meta retornou HTTP 429 na consulta desta tarefa.
A [página comercial oficial acessível](https://whatsappbusiness.com/products/platform-pricing/)
ainda descrevia 72 horas de gratuidade para entradas por anúncio/CTA e cobrança por mensagem **entregue**.
Não foi possível confirmar nela a universalidade da nova franquia de 1.000 nem dos sete dias para todas as WABAs.

Por isso, a UI identifica o resultado como simulação e expõe a janela de 7 ou 3 dias.
O padrão de sete dias e a franquia mensal de 1.000 reproduzem o cenário solicitado pelo usuário,
não uma alteração silenciosa de segurança ou uma garantia de preço da Meta.

### Franquia

1. Agrupada pelo número comercial normalizado, não pelo contato ou pelo provedor principal.
2. Renovação simulada no primeiro dia do mês às 00:00 no fuso selecionado para o relatório; sem acumular saldo. Para comparação com faturamento, conferir se corresponde ao fuso efetivo da WABA.
3. Lê desde o começo do primeiro mês do intervalo, mesmo se o relatório começar depois.
4. Cada mês tem sua própria franquia. Mensagens na janela gratuita de anúncio não consomem novamente a franquia de serviço.
5. Sem escolha explícita no relatório, os cálculos seguem o fuso da conta ou o padrão do sistema. Essa preferência não comprova o fuso de faturamento da WABA nem seus preços reais.

### Entrada de anúncio

- Evidência utilizada: `content_attributes.referral.source_type == "ad"` e `source_id` preenchido.
- A presença da chave `ctwa_clid` não basta: o valor pode estar vazio. Ela não é usada como prova de cobrança/gratuidade efetiva.
- Para o cenário estimado, a resposta pela Meta em até 24 horas abre a janela selecionada, contada da resposta.
- Uma entrada normal posterior não reinicia a janela de anúncio. Ao encerrar a janela, volta a classificação normal.
- Utilidade dentro da janela de atendimento de 24 horas aparece separadamente como gratuita na simulação.
- A gratuidade estimada de anúncio **não autoriza mensagens livres depois de 24 horas**: as verificações existentes de template/janela permanecem intactas.

### Limitações explícitas

A simulação usa o horário de criação da mensagem e o estado de entrega disponível, não o horário de faturamento da Meta.
Assim, uma entrega atravessando a virada do mês pode divergir da fatura. Não há conciliação automática de faturamento nesta entrega.
Não altera os webhooks para persistir novos campos de `pricing` e não consulta novamente a Graph API de cada mensagem.

Templates usam a categoria registrada nos parâmetros ou no cache de templates do canal.
Um template sem categoria não é convertido em mensagem de serviço para conceder gratuidade.
Categorias ou transportes desconhecidos não recebem uma cobrança inventada; são evidenciados como lacunas.
O subtotal considera somente categorias com tarifa preenchida. Não é custo total garantido, cobrança real ou economia comprovada.

## Amostra real, somente leitura: empresa 17

Na janela de 30 dias consultada nesta tarefa:

- Uma caixa WhatsApp ViperConnect, inbox 50 / canal 36. Nenhum vínculo de caixas parceiras cadastrado nesta conta.
- 6.510 entradas públicas e 8.502 saídas públicas no canal.
- 508 entradas com objeto `referral`; 507 com `source_type = ad`.
- A chave `ctwa_clid` aparece na estrutura, mas estava nula em parte da amostra. Não confundir chave presente com identificador preenchido.
- Sem `timezone` / `waba_timezone` na configuração do canal consultado.

Esta conta validou o formato dos anúncios, **não** o comparativo de dois transportes nem o faturamento.
Foram consultados apenas campos técnicos e agregados, sem imprimir tokens, nomes de contatos, texto, URLs de mídia ou payloads completos.

## API e autorização

`GET /api/v2/accounts/:account_id/reports/partner_inboxes`

Preferências: `GET` / `PATCH /api/v2/accounts/:account_id/reports/partner_inboxes/settings`, sob a mesma autorização e isolamento de conta. Campos permitidos: `timezone`, `currency` (BRL/USD), `ad_window_days` e as quatro tarifas. Persistência em `accounts.settings.partner_inbox_report`; merge sob lock preserva os demais settings. Entrada inválida retorna 422 sem sobrescrever a configuração anterior.

Parâmetros: `from`, `to` (datas ISO; final inclusivo na UI), `link_id` opcional, `timezone` opcional,
`ad_window_days` (7 ou 3), `service_rate`, `utility_rate`, `marketing_rate`, `authentication_rate` opcionais.

Aplica a mesma `ReportPolicy#view?` dos relatórios existentes: administrador ou permissão Enterprise `report_manage`.
Consultas e vínculos são sempre restritos à conta autorizada. Sem acesso de agente comum ou usuário não autenticado.
Sem tokens, credenciais ou conteúdo das mensagens na resposta.
Limites: período de até 366 dias e até 100.000 mensagens examinadas; exceder exige reduzir o intervalo, sem truncar silenciosamente.

A mensagem do pedido terminou em “só nos”; caso faltasse uma restrição adicional, o padrão acima deve ser confirmado antes da publicação.

## Validação

- `script/validation/partner_inbox_report.rb`: 24 verificações sintéticas na base isolada `viperchat_voip_test`, Redis 15;
  registros revertidos por transação. Inclui mês/fuso, consumo anterior ao filtro, anúncio, tarifas vazias/zero,
  templates, dedup de eco, fallback, falhas, isolamento de conta e autorização HTTP.
- RSpec existente de relatórios, mensagens iniciais Meta e estados de entrega: **129 exemplos, zero falhas**.
- Vitest da nova tela e API de relatórios: **16 testes aprovados**, incluindo os quatro novos casos do componente.
- Playwright com o componente real e resposta sintética de API: **16 verificações** de filtros, tarifas, erro/estado vazio e layouts.
  Capturas em `output/playwright/partner-report-*.png`: 320, 360, 390, 412, 430, 844 e 1280 px; controles sem overflow horizontal.
  Essa validação visual isolada não substitui um aceite autenticado do cliente com dados de caixas parceiras reais.
- RuboCop nos três arquivos Ruby novos: sem infrações. ESLint nos componentes/rotas/API exercitados: sem erros;
  permanecem avisos de chaves dinâmicas i18n e pontuação de template.
- Android: `adb devices` sem aparelho/emulador. `pnpm native:sync:android` falhou no build Vite por heap de 1.536 MB.
- iOS: `pnpm native:sync:ios` falhou pelo mesmo limite, antes da sincronização Capacitor.
  **Nenhum bundle nativo novo, APK, Archive ou teste em dispositivo foi concluído.** Não houve aumento do limite de RAM.

## Pendências para publicação

1. Aceite do relatório na réplica com um vínculo real e confirmação do fuso da WABA.
2. Confirmação documental/contratual das regras de gratuidade aplicáveis à WABA do cliente.
3. Regeneração e validação dos bundles Android/iOS em ambiente com recursos suficientes.
4. Revisão/commit/push e qualquer implantação somente quando solicitados.

## Limpeza bloqueada pelo ambiente

O navegador Playwright próprio foi encerrado e os containers existentes continuam ativos.
As capturas (aproximadamente 1,37 MB) são evidências preservadas, não descartes.
O `dist-mobile` anterior (20/10) não foi removido/substituído pelos builds que falharam.
Nenhum cache compartilhado, imagem, volume, banco ou gravação foi apagado.

As falhas dos builds fizeram o capturador de crashes do WSL gerar quatro dumps.
Foi lido somente o metadado ELF `PRPSINFO`, sem imprimir argumentos completos,
variáveis de ambiente ou conteúdo da memória. Os PIDs/PPIDs confirmam duas árvores
Vite → pnpm desta tarefa: 8432 → 8420 e 8496 → 8484.

Pasta: `C:\Users\caita\AppData\Local\Temp\wsl-crashes`.
Somente os quatro arquivos abaixo foram identificados como descartáveis desta tarefa,
totalizando **8.130.830.336 bytes** (aproximadamente 8,13 GB / 7,57 GiB):

- `wsl-crash-1792741347-8432-_usr_local_bin_node-6.dmp`
- `wsl-crash-1792741365-8420-_usr_local_bin_node-6.dmp`
- `wsl-crash-1792741441-8496-_usr_local_bin_node-6.dmp`
- `wsl-crash-1792741459-8484-_usr_local_bin_node-6.dmp`

A tentativa de remoção destes arquivos por caminho literal, após validar a pasta,
foi **rejeitada pela política do ambiente antes da execução**. Não houve remoção
parcial, contorno por outra ferramenta nem promessa de espaço recuperado.
O espaço livre observado antes dessa tentativa era 99.804.401.664 bytes no disco C:.
Os dumps podem conter memória de processos e devem ser removidos pelo operador,
nunca enviados ao Git ou compartilhados como evidência.

Também permanece pendente a limpeza dos intermediários desta tarefa:

- Worktree: `.codex/runtime-overlay` e `.playwright-cli`.
- Réplica: `/app/public/partner-report-validation.html` e
  `/app/app/javascript/validation/partner-report-validation.js`.

Os dois últimos arquivos são apenas a prévia de validação com dados sintéticos;
não contêm tokens nem dados reais e não são a tela autenticada do relatório.
A limpeza ficou pendente após o bloqueio, sem tentar outra via de exclusão.

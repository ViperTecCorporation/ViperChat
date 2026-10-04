# Atendimento web integrado ao UnoProvider e WhatsApp Cloud API

## Canal oficial da Meta

O mesmo atendimento Web pode ser ativado em caixas `whatsapp_cloud`, sem criar
outra conversa. O convite usa `interactive.type: cta_url`, `action.name: cta_url`
e `action.parameters.display_text/url`. Não inclui os campos WebView do Uno;
a abertura em navegador interno depende do WhatsApp, sem garantia.

No canal oficial, convite manual, saudação com CTA e lembrete de ausência exigem
a janela de resposta de 24 horas aberta por mensagem recebida no WhatsApp.
Atividade Web não renova essa janela. A permissão é verificada também no envio
atrasado e na tentativa manual como texto. Fora da janela, não há conversão
automática em template: o convite é bloqueado, mas o atendimento Web continua.
O texto do convite aceita até 1024 caracteres e o botão até 20, com padrão
"Abrir atendimento". O Uno mantém seu payload e seus limites atuais.

## Contrato aprovado

Uma conversa, contato, caixa, responsável e equipe; destinos WhatsApp/Web explícitos,
rascunhos independentes e nenhuma duplicação de envio. Ativação administrativa por
caixa UnoProvider, inicialmente desligada. Convite manual entre Capitão e Contato.
O editor Web do agente reutiliza o editor compacto com mídias, áudio, contatos,
localização, emojis e respostas rápidas. Templates WhatsApp e chamadas não pertencem
ao canal Web. Visualização única oculta a mídia até abrir e permite rever.

Saudação opcional com CTA personalizado (padrão Continuar atendimento), uma vez por
ciclo, inclusive em conversa única reaberta por mensagem WhatsApp. Reabertura manual
não envia saudação. Falha de CTA permite envio manual como texto, sem envio automático
duplicado. Um convite substituto só invalida o anterior após entrega aceita pelo Uno.

O visitante vê mensagens públicas dos dois destinos apenas do ciclo atual. Sem OTP;
quem tiver o link pode acessar enquanto válido. Tokens aleatórios armazenados como
hash; telefone não autoriza acesso. Resolução, revogação e desativação invalidam
links e sessões. Reabertura exige novo convite. Downloads exigem sessão válida.
Conversas legadas sem início confiável mostram histórico a partir do primeiro convite.

Sem bots ou respostas automáticas na Web. Convites/saudação são enviados no WhatsApp.
Atividade Web não amplia a janela WhatsApp. Além do convite manual, uma nova
resposta Web do agente pode gerar um lembrete WhatsApp após cerca de 15 segundos
de ausência confirmada do cliente. O lembrete usa o convite ativo, não copia a
resposta Web e só é enviado uma vez por episódio de ausência. Voltar e sair
novamente permite outro lembrete, desde que haja nova resposta do agente.
Mensagens já lidas, retorno do cliente, resolução, revogação e desativação
cancelam o lembrete. A permissão de responder pelo WhatsApp é revalidada no envio.
Métricas medem convites, aberturas e mensagens, sem estimar tarifas não verificadas.

## Validação e entrega

Validar isolamento entre contas/ciclos, repetição de eventos, concorrência, revogação
com página aberta, mídias/contatos/localização, destinatários e ausência de chamadas
Uno para mensagens Web. Testar editor e convites em larguras 320–430, desktop,
Android e iOS disponíveis. Aplicação inicial no container dev; caixa de homologação
habilitada pelo usuário. Publicação e produção são etapas separadas.

## Estado

Aplicado no dev em 03/10/2026, com o recurso desligado em todas as caixas existentes.
As três migrações foram aplicadas; web, worker e Vite foram reiniciados. Bancos,
uploads e serviços ViperConnect foram preservados. Login e página visitante HTTP 200;
sessão visitante sem credencial HTTP 410.

Validação: 49 cenários do recurso cobertos (44 passaram na rodada completa e os
cinco corrigidos passaram na repetição); 30 testes de isolamento e 75 de regressão
aprovados. Frontend: 142 testes aprovados; build web de produção e bundles Android/iOS
gerados; assembleDebug Android aprovado. Lint Ruby sem infrações; ESLint sem erros,
com três avisos i18n. Verificação de carregamento Zeitwerk aprovada.

Pendente de homologação humana: CTA no UnoProvider real, navegadores externo/interno
do WhatsApp e ferramentas do editor com clientes reais de teste. ADB sem aparelho;
Mac 192.168.0.132 indisponível por SSH. Não houve execução Android/iOS em aparelho,
Archive iOS, publicação, commit, push nem deploy em produção. Não confundir geração
de bundles com validação nativa completa.

## Homologação no dev

1. Abra Configurações → Caixas de entrada → uma caixa UnoProvider → Preferências do canal.
2. Ative Atendimento web. Opcionalmente habilite a saudação existente e marque
   Incluir convite para atendimento web; personalize o texto do botão.
3. Em uma conversa aberta, use o botão de convite entre Contato e Capitão.
   Confira a prévia e confirme uma única vez. Aguarde a aceitação pelo provedor.
4. Abra o CTA como cliente e teste texto, anexos e áudio. No painel do agente,
   selecione explicitamente WhatsApp ou Web e confirme os rascunhos independentes.
5. Resolva a conversa com a página do cliente aberta: ela deve perder o acesso.
   Reabra e confirme que o link anterior continua inválido. Teste também revogar
   pelo painel e desativar a opção da caixa, sem apagar o histórico.

O visitante usa consultas periódicas autorizadas pela sessão (sem credencial de
pubsub do contato). O convite só é ativado após resposta de envio aceita pelo Uno.
Uma falha permite tentativa manual como texto; não há fallback automático.
O teste automatizado do payload não substitui a validação no UnoProvider real e
nos navegadores externo/interno do WhatsApp. Não habilitar outras caixas por rotina.

## Status, áudio e presença

As mensagens Web usam o status persistido sem exigir ID do provedor WhatsApp:
um tique indica envio aceito, dois indicam entrega ao destinatário e dois azuis
indicam leitura. A busca de histórico confirma entrega somente das mensagens Web
devolvidas; leitura exige a confirmação separada do destinatário. Respostas HTTP
atrasadas não devem fazer um status lido voltar para enviado.

O áudio do visitante tem waveform durante a gravação, cancelamento, prévia e
descarte antes do envio. Após aceitação, a bolha usa o anexo persistido e sua URL
autorizada por sessão, não a URL temporária da gravação.

A presença usa heartbeat da página visível junto às consultas periódicas, não um
socket com acesso amplo ao contato. Cada aba tem um identificador próprio;
qualquer aba/sessão visível e recente mantém o cliente presente. Ocultar ou fechar
a página informa saída; queda abrupta é detectada pela expiração do heartbeat.
Esse heartbeat não marca leitura nem renova a janela WhatsApp. O link continua
secreto e não é enviado em heartbeats ou armazenado em logs.

A caixa UnoProvider permite configurar a mensagem padrão do convite manual em
Preferências do canal → Atendimento web. O texto é persistido por caixa (até
4096 caracteres), preenche a prévia e pode ser editado apenas para aquele envio.
Vazio mantém o padrão traduzido. Não altera a saudação nem o lembrete automático.

## Extensão Cloud no dev — 03/10/2026

Configuração, abas e convite agora aceitam UnoProvider e WhatsApp Cloud API;
demais provedores não foram habilitados. Convites Cloud usam o endpoint v24.0,
sem mudar a versão dos outros envios existentes ou do Uno. Erros de validação
do convite retornam HTTP 422, incluindo janela encerrada e tentativa manual
como texto fora da janela. A caixa oficial existente permaneceu desligada.

Backend: suíte de regressão com 83 exemplos aprovada; os 12 exemplos específicos
Cloud também passaram (nove já incluídos na suíte e três adicionados para
saudação e lembretes), totalizando 86 cenários distintos. RuboCop sem infrações.
Frontend: 53 testes aprovados e ESLint sem erros. Bundles Android e iOS
regenerados e sincronizados. Não houve APK novo: assembleDebug falhou ao
ler um SVG da pasta sincronizada pelo Nextcloud como arquivo regular.
ADB detectou um Android, mas a ausência de compilação impediu instalar e
validar a nova implementação no aparelho. Mac 192.168.0.132 sem acesso SSH;
não houve compilação ou teste iOS. Payload Meta ainda exige homologação real.
Nenhuma mensagem real, commit, push, publicação ou deploy de produção nesta etapa.

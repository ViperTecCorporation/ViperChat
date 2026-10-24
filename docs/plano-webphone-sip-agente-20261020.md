# Plano: webphone SIP/WebRTC por agente e aba Chamadas

## Entrega dev — eventos na conversa e ajustes operacionais (23/10/2026)

- Cards baseados no visual do canal Voice, com ícone, estado, serviço, ramal, duração e o mesmo AudioChip das bolhas. Um card privado por chamada é atualizado pelos eventos, sem enviar mensagem ao WhatsApp. Chamadas internas não criam cards de cliente.
- Identificação por telefone confirmado da linha e do contato; caixas parceiras usam a principal. IDs, notas e mídias já publicados não são movidos. Gravação usa o mesmo blob disponível na nota privada.
- Configuração opcional `reopen_on_incoming`, desligada por padrão, no serviço VoIP do ViperChat. Habilitada: chamada de entrada em andamento reutiliza/reabre conversa única ou cria uma nova conforme regra da caixa. Desabilitada: só registra na conversa existente. Recuperação REST de chamada já terminada não reabre atendimento.
- ViperConnect: filas VoIP outgoing/dead visíveis para inspeção, sem ações destrutivas; tentativas temporizadas permanecem na outbox SQLite. Editor da empresa agrupa transcrição e resumo com os avisos de segredo junto ao campo correto.
- Serviço VoIP: registro SIP/WebRTC tardio recebe INVITE se elegível para a onda atual ainda em toque; chamadas atendidas/encerradas não são convidadas novamente. Retenção encontra gravações mesmo após a saída do CDR do catálogo, preservando IDs/referências e marcando `retention_expired`.
- [Contrato REST completo](voip-rest-consolidacao-20261023.md): rota, autenticação, escopo, cursor, erros, idempotência e gravações. Atualizar receptor/migração antes do produtor com o novo campo opcional `call.business_phone`.

Validação sintética: 118 exemplos backend VoIP/controllers, 57 testes frontend ViperChat, 86 testes selecionados ViperConnect/OpenAPI; serviço VoIP com 247 testes (246 aprovados, um skip por FFmpeg ausente no Windows). Typecheck/build do serviço aprovados; lints sem erros. Playwright com componentes reais em 320/360/390/412/430/844/1280 px, capturas revisadas em `output/playwright/conversation-call-events-*` e `company-ai-layout-*`; sem overflow horizontal. Filas conferidas visualmente com zero botões de purge VoIP. Dados das prévias são sintéticos, não eventos publicados em conversas reais.

Ativação apenas nos containers dev existentes, incluindo migração aditiva na réplica. Serviço VoIP reiniciado e saudável; backup dos quatro JS anteriores em `/tmp/voip-events-registration-retention-before-20261023.tar`. Backup pré-migração da réplica em `/app/tmp/voip-conversation-before-20261023.json` (restrito). Retenção local continua desabilitada (`retentionDays=0`): nenhuma mídia real foi apagada. Sem VPS, novos containers, commit/push ou publicação.

Pendências de aceite: nova chamada real com registro durante o toque e gravação; push/CallKit nativo não faz parte desta entrega. Pacotes Android/iOS não foram gerados nesta rodada: build compartilhado anterior esbarrou no heap de 1536 MB, sem aumentar consumo, e não há aparelho conectado/iOS disponível neste ambiente. Não declarar homologação nativa concluída.

Atualização de 23/10/2026 — cards de ramais: adicionado lápis acessível por nome do agente/ramal, reutilizando AgentVoipCard e o endpoint administrativo existentes. O clique seleciona explicitamente o vínculo do agente e o serviço do card, sem escolher automaticamente outro serviço padrão. Salvar/ativar/desativar atualiza a listagem sem F5; senhas não são pré-carregadas. Regressão de agente/serviço não padrão, preservação de senha e atualização dos cards incluída. Validação: 40 testes frontend em quatro arquivos, ESLint sem erros; Playwright com componentes reais e dados sintéticos em 320/360/390/412/430/844/1280 px, capturas conferidas e sem overflow horizontal. Atualizados os fontes na réplica existente, sem novos containers, gravação de configurações reais ou VPS. Empacotamento nativo pendente: pnpm disponível é 11 versus engine 10; execução direta do build Vite atingiu o limite de heap de 1536 MB, sem aumentar consumo. Nenhum aparelho Android conectado e nenhum novo pacote Android/iOS entregue. Capturas em output/playwright/voip-extension-edit-*.png; temporários de prévia removidos após validação.

Atualização de 23/10/2026: [consolidação de dispositivos, correção de missed e investigação da gravação](correcao-historico-voip-multidispositivo-20261023.md). Validação com a chamada real 288/289, sem exclusão de IDs/histórico; serviço VoIP e réplica atualizados apenas em dev, sem novos containers ou VPS.

> **Última decisão vigente — 22/10/2026:** receber webhooks no ViperChat com `api_access_token` de administrador; o responsável pela central adapta AMI/CEL/CDR ao nosso contrato. Nosso serviço produz o mesmo contrato com outbox SQLite, RabbitMQ e retentativas. Isso substitui a conexão direta AMI, consulta SQL e servidor AMI próprio. Cadastro por empresa, receptor, reconciliador, produtor, recuperação REST periódica com checkpoint criptografado e diagnóstico/reprocessamento administrativo nas duas pontas estão implementados/testados em dev. Ver [contrato webhook-first vigente](contrato-webhooks-voip-v1-20261022.md), especialmente seção 12, que prevalece sobre as seções históricas abaixo. Sem banco legado ou conector instalado pela nossa equipe. Sem VPS, containers adicionais ou publicação. Aceite real e integração nativa em segundo plano permanecem separados.

Plano inicial: 20/10/2026 — America/Cuiaba. Atualização: 21/10/2026. Estado: primeira entrega implementada e validada funcionalmente na réplica dev existente, sem publicação ou implantação na VPS. Limites de aceite nativo, hardware e transferência real estão explícitos no runbook.

**Ampliação autorizada em dev — 22/10:** cadastro do produtor por empresa,
somente ramais vinculados; seletor `artifactsDelivery: legacy|webhook` mantém
compatibilidade sem dois envios simultâneos. `call.artifacts.updated` entrega
gravação/IA ao processador durável do ViperChat, com nota privada única na
conversa comprovada, deduplicação e preservação dos IDs. Central de chamadas
reutiliza o player `AudioChip` da bolha, com download autenticado e transcrição/
resumo. Contrato completo e limites no documento vigente acima; teste sintético
ponta a ponta na réplica, sem chamadas reais ou VPS. Aceite real posterior pelo
usuário não equivale a aceite nativo em segundo plano.

Execução e limites de aceite: [runbook da validação na réplica existente](validacao-webphone-sip-agente-20261021.md). Esta atualização separa recursos implementados de testes ainda pendentes. Os resultados das seções históricas ao final não substituem os testes desta implementação.

Complementa o [levantamento do WhatsApp e do código atual](mapeamento-chamadas-whatsapp-webphone-20261019.md). As decisões abaixo substituem as propostas preliminares desse levantamento quando divergirem.

Contrato do serviço/worker analisado em 20/10/2026: [auditoria de REST, eventos e CDR](auditoria-contrato-voip-cdr-20261020.md). Já existe histórico SQLite/JSON e REST paginado; faltam contrato incremental durável, participações e escopo específico de agente para o aceite completo. Não foi acessada a VPS.

**Decisão histórica substituída — 22/10/2026:** foi considerada conexão direta via AMI. Não implementar esse caminho nem usar os campos anteriores como configuração final; o contrato webhook-first acima é o vigente. As referências Asterisk/FreePBX/Issabel permanecem no [levantamento histórico](plano-integracao-ami-cel-cdr-20261022.md) para os integradores que produzirão eventos. Eventos/histórico não resolvem sozinhos segundo plano nativo.

## 1. Objetivo e decisões confirmadas

- O serviço VoIP do usuário já integra as chamadas da Meta. O novo webphone ViperChat se conecta a esse serviço por **SIP.js / SIP sobre WebSocket seguro / mídia WebRTC**. Não construir outra integração direta Meta para esse recurso.
- Chamadas deixam de depender da criação ou seleção de uma caixa de entrada Voice/custom. Ramal pertence ao vínculo do agente com um serviço VoIP da conta.
- Administrador pode cadastrar **mais de um serviço VoIP na mesma conta**. Na modal do perfil, selecionar o serviço antes de configurar o ramal.
- Acesso **Chamadas** na sidebar imediatamente abaixo de Conversas.
- Estilo do webphone baseado nas referências extraídas do WhatsApp: controles agrupados/arredondados, contraste, estados de áudio, variantes compacta/completa e organização lista/detalhes. Traduzir isso para componentes Vue/Tailwind e identidade ViperChat, sem incorporar binários, fontes, sons ou SVGs proprietários.
- Desktop: lista à esquerda e detalhes à direita. Mobile: lista em tela inteira → detalhes com Voltar, preservando busca, filtros e rolagem.
- Preservar histórico, IDs, contatos, mensagens e mídias. O usuário dispensou preservar/migrar a configuração Voice/custom antiga, que nunca foi usada em produção; a interface antiga agora orienta a configurar Serviços VoIP e ramal no perfil. Essa dispensa não autoriza alterar outros provedores Voice/Twilio/Meta nem apagar dados legados.
- Primeira entrega: áudio. Preparar contratos para integração nativa futura iOS/Android; não incluir vídeo, links, programação de chamadas ou promessa de segundo plano só por existirem no WhatsApp.
- Duas entregas com aceite separado: (1) ViperChat funcional para sessões observadas pelo agente conectado; (2) histórico autoritativo sincronizado entre servidores, inclusive com navegador fechado. A segunda entrega não bloqueia o desenvolvimento da primeira, mas sua ausência deve ser visível e não pode ser declarada como cobertura completa.

## 2. Modelo de organização

```text
Conta
  Serviços VoIP (administrador): Serviço A, Serviço B, ...
  Agente / vínculo com a conta
    Perfil → Configurar VoIP
      Selecionar serviço autorizado
      Configurar ramal e autenticação desse serviço
      Definir conexão ativa
  Chamadas
    Histórico persistido + eventos do serviço
    Sessão SIP/WebRTC global do agente
    Lista / detalhes / discador / webphone compacto e completo
```

**Recorte proposto para a primeira versão:** o agente pode salvar configurações para vários serviços, mas usa uma conexão ativa por vez. A escolha é explícita e persistida por conta/agente; não ativar a primeira central retornada pela API. Receber simultaneamente de várias centrais é uma ampliação posterior, não uma consequência automática do cadastro múltiplo. Essa limitação deve aparecer na interface e no aceite.

## 3. Configuração administrativa: serviços VoIP

Nova seção **Configurações → VoIP → Serviços**, separada de Caixas de entrada, com listagem, criar/editar e ativar/desativar.

| Grupo | Campos planejados |
| --- | --- |
| Identificação | Nome legível, ativo/inativo e serviços disponíveis aos agentes elegíveis. |
| Conexão | URL WSS, domínio SIP, proxy opcional e parâmetros de registro. Não presumir suporte a um campo só porque existe no formulário legado. |
| Autenticação | Modo senha ou token compatível com o serviço. Chave de assinatura fica no servidor. Tokens de sessão curtos quando o serviço os suportar. |
| Mídia | STUN/TURN, credenciais TURN protegidas e capacidades de áudio confirmadas pelo serviço. |
| Roteamento | Regras de discagem da central, transferência REFER ou API de controle e identificadores de origem permitidos. |
| Integração | Autenticação e contrato para eventos/CDR do serviço: identificadores, legs, sequência, timestamps, estados e permissões. |

- Editar o endereço/credenciais não reinicia nem transfere uma chamada em andamento; aplicar nova configuração após seu encerramento.
- Desativar impede novos registros/envios e avisa os agentes afetados; não apagar histórico ou bindings. Definir a transição de sessões ativas antes de executar a desativação.
- Arquivar serviço referenciado, não fazer cascade de chamadas/ramais. Troca para outra central nunca é fallback silencioso.
- Serviços e ramais isolados por conta; uma conta não pode consultar, configurar ou autenticar usando o ID de outra.
- Administrador controla os serviços compartilhados e quais agentes podem configurar o próprio ramal. Agente não edita URLs, chaves do serviço ou credenciais de colegas.
- Agentes autorizados são escolhidos pelo nome no mesmo `TagInput` utilizado ao vincular agentes à caixa de entrada: pesquisa, seleção por clique e remoção individual. A interface envia IDs de usuário (não de membership), aceita nomes repetidos sem confundi-los e preserva vínculos indisponíveis ao editar. Nenhuma seleção mantém a política existente de permitir todos os agentes da conta; administradores conservam seu acesso.

## 4. Perfil do agente: modal Configurar VoIP

Substituir os campos WebRTC soltos no formulário básico por um cartão **VoIP** com serviço/ramal atual, status e botão **Configurar VoIP**. Modal reutilizável quando o administrador gerenciar o agente, com política explícita.

Fluxo:

1. Escolher um serviço VoIP ativo e autorizado. Se não houver, explicar que o administrador precisa cadastrá-lo; não mostrar dropdown vazio sem orientação.
2. Carregar somente a configuração desse serviço para esse agente. Trocar o serviço não copia senha/token/ramal da central anterior.
3. Informar ramal e usuário de autenticação, quando diferentes; selecionar o modo definido pelo serviço e fornecer a credencial necessária. Não usar o email do agente como ramal implícito.
4. Salvar. Campos de segredo omitidos preservam o valor armazenado; limpar/substituir exige ação explícita. Mostrar apenas “credencial configurada”, nunca preencher o input com segredo salvo.
5. **Testar registro** realiza conexão/REGISTER autorizado, sem INVITE, sem tocar ou iniciar chamada. Mostrar resultado após confirmação do estado de registro, não apenas após resolver uma Promise.
6. **Usar este serviço** define a conexão ativa; bloquear troca durante chamada e explicar o motivo. Cancelar modal preserva a configuração ativa.

Exibir estados distintos: não configurado, desconectado, conectando, registrado, reconectando, erro de autenticação e indisponibilidade. Estado de chamada fica separado do estado de registro. “Registrado” não prova que áudio/RTP funciona.

Ramal é identificador da central, não obrigatoriamente telefone E.164. Preservar zeros à esquerda. Normalização brasileira/nono dígito não se aplica a ramais. O mesmo ramal pode existir em serviços diferentes. Na primeira versão, detectar ramal duplicado entre agentes do mesmo serviço em vez de compartilhar a credencial silenciosamente.

### Credenciais e segurança

- Entidades próprias, com segredos criptografados usando o mecanismo suportado pelo projeto; não continuar usando `User.custom_attributes` global para novas credenciais.
- Metadados de perfil/usuário, API de listagem, eventos ActionCable, auditoria e logs não expõem senha/JWT/chaves.
- Para autenticação SIP no navegador, o cliente precisará de material de autenticação. Quando não houver token temporário suportado pela central, a senha SIP só pode ser entregue em endpoint de bootstrap autenticado, ao próprio agente autorizado, por HTTPS, sem cache e mantida apenas em memória. Não prometer que senha nunca chega ao navegador se ela for necessária ao Digest SIP.
- Não gravar material de autenticação em localStorage, URL, relatório, fixture, analytics ou log de erro/SDP. Guardar na preferência apenas IDs de serviço/binding e preferências não sensíveis.
- Logout, remoção do agente da conta e troca de conta encerram a conexão correspondente e limpam credenciais em memória; tratar chamada ativa explicitamente. Revogar sessão/token conforme capacidade real do serviço.

## 5. Histórico e persistência independentes de conversa

Proposta de entidades novas, preservando as tabelas legadas:

| Entidade proposta | Responsabilidade |
| --- | --- |
| `VoipService` | Serviço da conta, parâmetros comuns, capacidades e segredos administrativos. |
| `VoipAgentExtension` | Vínculo conta/AccountUser/serviço, ramal, auth username e credencial. Único por agente/serviço; escolha ativa explícita por conta/agente. |
| `VoipCall` | Tentativa lógica com IDs de correlação, serviço e participantes/legs, direção, origem/destino, timestamps, estado e motivo final. |
| Eventos/participações de chamada | Dedupe, processamento fora de ordem e agentes que tocaram/atenderam/transferiram. Nunca atribuir uma perdida a um agente que não recebeu a oferta. |
| Favorito do agente | Referência a contato/número/ramal por conta/agente, sem copiar contatos. |

- Chamada pode existir sem contato identificado, inbox ou conversa. Guardar número/ramal e nome disponíveis como snapshot. Associar contato/conversa posteriormente apenas com evidência segura e autorização de acesso.
- Não criar conversa nem novo contato automaticamente para cada tentativa/evento. Não mesclar contatos por aproximação; número ambíguo permanece sem vínculo.
- Cada tentativa aparece separadamente na lista, inclusive repetidas para o mesmo contato, conforme os prints. Transferências e múltiplas legs da mesma chamada não viram tentativas duplicadas.
- Usar chave de chamada escopada por conta/serviço/ID do serviço, e chave idempotente de evento. Não usar número, texto ou horário aproximado como dedup de chamada.
- IDs SIP Call-ID, ID lógico do serviço e IDs de legs não são necessariamente iguais; persistir mapeamento explícito validado com o serviço.
- A nova tela pode exibir históricos legados permitidos por projeção de leitura, mantendo origem e ID compostos (`source_type`, `id`). Não copiar registros antigos para a nova tabela nem reclassificar enum de `Call` em massa. Registro legado não vira chamada SIP automaticamente.
- Agente acessa suas participações; administrador acessa a conta conforme política. Rever a regra atual baseada apenas em `accepted_by_agent_id`, insuficiente para perdidas e chamadas compartilhadas.

### Fonte de verdade e estados

O navegador informa intenção e telemetria, mas **eventos autenticados do serviço/CDR** são necessários para histórico confiável quando o app fecha, perde rede ou não está registrado. Um relatório só do SIP.js não fecha esse requisito.

Contrato mínimo: ID de evento/revisão, ID lógico de chamada, recordId, IDs de legs, ramais oferecidos, ramal que atendeu, direção, origem/destino, timestamps de início/atendimento/fim e código/motivo de término. A inspeção local confirmou `GET /v1/console/history` com `id`, `callId`, `direction`, `status`, `extensionId`, tempos, duração e campos de gravação/IA. O contrato atual não expõe feed incremental de alterações nem todas as participações. A auditoria anexa separa cada campo disponível do que precisa ser acrescentado.

Na primeira entrega, o ViperChat opera pelo SIP/WebRTC e persiste no próprio backend os registros das sessões que observou, com origem `client_observed` e confirmação limitada. Não usar localStorage como histórico. A identidade SIP conhecida e os vínculos de serviço/ramal ficam preservados para reconciliação posterior; a falta de um ID lógico do serviço não autoriza deduplicar por telefone/horário aproximado. Associação não comprovada permanece pendente sem apagar registros. O agente só pode registrar observações do seu binding autorizado, não fabricar participações de terceiros.

Sem a segunda entrega, não garantir perdidas com navegador fechado, atendimento em outro dispositivo, resultado final após desconexão ou histórico completo de transferências. Ao reabrir o app, sessão local sem desfecho fica “aguardando confirmação”, sem inventar estado atendida/perdida ou duração. A interface informa que o histórico do serviço ainda não está sincronizado; registros legados disponíveis continuam preservados. Não ativar polling fingindo que o REST paginado atual já oferece cursor incremental.

Na segunda entrega vigente, **AMI direto entrega eventos normais e CEL/Cdr habilitados; o histórico é persistido no ViperChat**. Não consultar banco de centrais legadas. Reconexão recupera estado ativo, não todo o passado; recuperação adicional depende de API comprovada e, no nosso serviço, REST incremental próprio. Persistir observações numa inbox e aplicar transições idempotentes, sem presumir eventId/revisão universal no AMI legado. Paginação REST por início não basta para recuperar alterações tardias. A bridge Zapo privada não é uma assinatura ViperChat e não deve receber um segundo consumidor tomando a sessão. Detalhes e limites na seção 7.1.

Separar navegador fechado de bridge offline: o serviço já registra chamadas sem o browser; o worker atualmente não reenvia de forma durável chamadas encerradas enquanto a bridge estava indisponível. Prever recuperação do produtor, sem prometer cobertura que o código ainda não oferece. O aviso textual de chamada e a fila de notas privadas de gravação não substituem CDR.

A gravação pertence ao serviço local/S3; a aba nova usa referência/stream autenticado e não gera automaticamente outra cópia em Active Storage/S3. Preservar o fluxo de notas privadas existente quando habilitado sem duplicar o áudio pela nova interface.

- Separar `direction` de resultado. Saída não atendida não é a mesma coisa que entrada perdida.
- Estados previstos: iniciando, chamando, atendida/em curso, encerrada, não atendida, perdida, rejeitada, ocupada, cancelada e falha; manter código SIP/motivo original para diagnóstico. Elaborar tabela de tradução com exemplos reais, sem classificar qualquer 487/erro genérico como perdida.
- Duração de conversa começa no atendimento efetivo; tempo tocando pode ser armazenado separadamente. Clique em atender ou criação de INVITE não inicia duração de fala.
- Duplicação de eventos AMI/CEL/Cdr e eventual releitura REST têm aplicação idempotente. Evento antigo não reabre chamada terminal; correção posterior só por evidência autoritativa e regra explícita, preservando auditoria.
- Ao recuperar conexão, consultar estado/CDR antes de finalizar uma chamada como falha. Não retentar uma discagem automaticamente nem criar um segundo INVITE por timeout de HTTP.
- Separar estado global da chamada e resultado por agente: se outro agente atendeu, encerrar toque nos demais sem chamar isso de perdida não atendida por ninguém.

## 6. Interface: referência visual e adaptações

### Evidências visuais fornecidas pelo usuário

Prints de 20/10/2026, já visualizados na conversa:

| Referência | Observado |
| --- | --- |
| `codex-clipboard-1f7d974f-e9ea-4200-aea5-a7c850a5ce7e.png` | Ícone de telefone abaixo de Conversas na faixa lateral. |
| `Captura de tela 2026-10-20 000558.png` | Título Ligações, pesquisa, favoritos, recentes, novo contato/chamada e painel inicial amplo. |
| `codex-clipboard-4cb84fbb-0959-4b75-b820-c35fa60900d4.png` | Seleção destacada na lista, Dados da ligação, fechar painel, avatar/nome, atalhos, data/hora e saída Não atendida. |
| `codex-clipboard-6b9c09fc-3f3f-403d-bcf1-3a3523d2f89f.png` | Detalhe de chamada com duração; tentativas repetidas do mesmo contato aparecem separadamente. |

Não copiar para documentos nomes/números privados visíveis nesses prints; referências de arquivo bastam. As imagens comprovam aparência, não a execução dos botões.

### Sidebar, lista e detalhes

- Item Chamadas após Conversas; funcionar com sidebar expandida/recolhida e menu mobile. Não deslocar os grupos existentes indevidamente.
- Cabeçalho com título, estado do serviço/ramal ativo e nova chamada. Indicar serviço nas linhas/detalhes para não confundir centrais.
- Pesquisa por nome, telefone e ramal, tolerante a acentos e formatação de telefone; filtros por direção, resultado, serviço, agente autorizado e período. Busca paginada no backend, não só nos itens carregados.
- Seções Favoritos e Recentes. Datas localizadas (“Hoje”, “Ontem”, dia/data), timezone do usuário e precisão absoluta nos detalhes. Não repetir inglês residual como “now”.
- Avatar/nome ou número, direção, resultado e data por tentativa; vermelho para perdida e distinção textual/ícone, não apenas cor.
- Detalhes: contato/número, serviço, agente/ramal, data/hora, início/atendimento/fim, duração e motivo de erro humanizado com detalhes técnicos opcionais. Atalhos abrir contato/conversa autorizada e ligar novamente explicitamente.
- Fechar detalhes não remove histórico e nunca encerra uma chamada. Clicar na linha não disca. Não adicionar lixeira para chamadas como consequência da referência visual.
- Badge de novas perdidas, se adotado: ciência por agente, sem alterar o resultado histórico; abrir a lista e ler uma perdida são ações de UI, não atendimento.

### Webphone completo e compacto

Base visual: `WhatsApp.Design/Voip/CallControlsView.xaml`, `AudioCallView.xaml`, `VoipResources.xaml`, ícones e estados descritos no mapa anterior. A implementação usa recursos próprios do ViperChat e bibliotecas de ícones já instaladas, com light/dark.

- Completo: avatar/identificação, serviço/ramal, estado, cronômetro de fala, aceitar/rejeitar, encerrar, mute, teclado DTMF, menu de áudio e acesso à conversa quando houver vínculo.
- Compacto global: estado, identificação, duração e ações essenciais, com expandir. Não desmontar a sessão ao sair da aba ou alternar as duas visões.
- Menu de áudio: microfone/alto-falante de acordo com APIs suportadas, estado de permissão e dispositivo removido. Não exibir seleção de saída funcional onde a plataforma não oferece essa API; informar limitação.
- Mute altera a trilha local de mídia; reconectar a interface não deve abrir o microfone novamente sem respeitar o estado. Desligar encerra sessão correta e libera tracks/áudio.
- DTMF via método suportado/negociado pelo serviço. Transferência REFER só após suporte e resultado confirmados; não tratar apenas envio de REFER como transferência concluída. Hold é evolução condicionada à sinalização suportada, não sinônimo de mute.
- Vídeo, reações, compartilhamento, participantes, links e agendamento ficam fora do MVP salvo novo escopo e capacidades confirmadas. Não copiar a afirmação de criptografia ponta a ponta do WhatsApp.

### Mobile e acessibilidade

- Mesmo padrão da lista de chats: lista em tela inteira; detalhe em rota/tela própria com Voltar, inclusive botão físico/gesto nativo. Preservar filtros, pesquisa, seleção e rolagem ao retornar. A implementação reutiliza `BackButton.vue`: somente a seta, com rótulo acessível, à esquerda do título de detalhes, na mesma posição da navegação de conversas.
- Webphone completo em apresentação adequada ao celular; compacto não cobre enviar, navegação ou outros controles críticos. Reservar safe areas.
- Modal VoIP com rolagem e rodapé acessível quando o teclado abre; seleção de serviço antes dos campos do ramal. Sem overflow horizontal.
- Validar 320, 360, 390, 412/430 px e desktop, retrato/paisagem, labels longas e foco de teclado. Os controles compactos de 32 px do WhatsApp desktop não determinam o alvo de toque mobile.

## 7. Sessão SIP.js e concorrência

- Registro pertence ao binding selecionado, não a `inboxId`. Montar o gerenciador global uma vez após autenticação/conta e mantê-lo entre rotas.
- Estado `Registered` só após retorno real do registro; tratamento distinto de 401/407 de desafio, rejeição final e falha WSS. Não imprimir senha ou cabeçalhos Authorization.
- Uma chamada ativa por agente na primeira versão. Cliques repetidos, eventos duplicados e duas views do mesmo telefonema não abrem duas sessões.
- Coordenar múltiplas abas para não disputar registro nem tocar/atender duplicado. Definir propriedade da sessão e recuperação; navegador não é autoridade suficiente para impedir corrida entre web e app nativo futuro.
- O serviço já suporta múltiplos registros SIP/WebRTC por ramal e `answered_elsewhere`. Preservar telefones/dispositivos existentes: coordenação de abas limita a duplicação do próprio ViperChat, não reduz a central a um único registro total por ramal.
- Quem pode aceitar e quem ganhou a disputa precisa ser confirmado pelo serviço para o mesmo ID de chamada. Os demais terminais encerram alerta. Implementar idempotência de ações e refletir eventos do serviço.
- Uma rotina de reconexão por binding, sem somar os retries de `VoiceAutoRegister` e `customVoiceClient`. Backoff, logout e mudança de conta cancelam tentativas antigas.
- Não oferecer troca de serviço durante ligação nem mudar a central por erro de autenticação/ocupado. Re-registro e recuperação de chamada são operações diferentes.

## 7.1. Integração vigente: AMI direto + histórico próprio e recuperação REST existente

O backend ViperChat será cliente AMI das centrais Asterisk/FreePBX/Issabel e do nosso serviço VoIP, que implementará um servidor com perfil mínimo compatível. Não haverá intermediário obrigatório nem instalação de conector na central. SIP/WebRTC e o caminho do áudio permanecem separados.

Centrais legadas: eventos normais e `Event: CEL`/`Event: Cdr` na mesma sessão AMI, condicionados a backends nativos, configuração e permissões. O ViperChat grava o histórico na própria base, sem consultar banco legado. Reconectar não solicita replay genérico: consultar canais/bridges ativos e registrar o intervalo sem cobertura. Chamadas encerradas inteiramente durante a queda podem não ser recuperáveis. API histórica legada existente é apenas capacidade adicional futura, não requisito nem garantia universal. Nosso serviço terá REST incremental próprio para recuperar seus registros persistidos, sem expor SQLite remoto.

Ambas as fontes passarão por inbox durável e reconciliador único, preservando IDs e participações, com atualização autorizada da web/apps após persistência. A captura continuará sem browser se o backend estiver conectado; não confundir isso com backend/AMI offline. Push e entrega SIP após despertar são requisitos nativos adicionais. Fontes oficiais, cadastro AMI sem campos de banco, capacidades por versão e aceite no [plano AMI/CEL/CDR de 22/10/2026](plano-integracao-ami-cel-cdr-20261022.md).

**Início autorizado em dev:** reaproveitar `/v1/console/history` com `sync=changes`, snapshot/delta e cursor assinado, preservando consulta paginada e rota de gravação existentes. Ao cadastrar/editar nosso serviço no ViperChat, configurar endereço HTTPS base e token REST protegido, separados das credenciais AMI/SIP; centrais legadas não exigem REST nem banco. O primeiro bloco está discriminado na seção 9 do plano complementar; servidor/consumidor AMI e reconciliação completa continuam pendentes. Não confundir configuração salva e cliente HTTP com sincronização ativa. A etapa passou de documentação para implementação autorizada sem novos containers ou VPS.

## 7.2. Arquitetura anterior: webhook durável + REST incremental (histórico)

**Substituída pela decisão de 22/10/2026 da seção 7.1.** Preservada para rastreabilidade, não como trabalho a executar: endpoints de webhook, entregador HTTP e sua matriz de falhas não integram a etapa vigente. Reaproveitar somente garantias de durabilidade, isolamento, retomada e idempotência no novo transporte. Webhook não é requisito para nosso serviço nesta etapa.

Esta seção define o contrato a preparar no ViperChat na primeira entrega e integrar de fato na segunda. As rotas e campos abaixo são propostos, não recursos já implementados no serviço.

### Produção e fila persistente no serviço VoIP

1. Persistir a mudança de CDR/participação e o evento correspondente em outbox na mesma transação quando estiverem no mesmo armazenamento. Não depender de memória, `setTimeout` ou navegador para conservar eventos.
2. Envelope versionado: `event_id` imutável, `event_type`, `schema_version`, `occurred_at`, `service_id`, `record_id`, `call_id`, `revision`, sequência/cursor de alteração e os snapshots/legs necessários. Identidade de conta/serviço é resolvida por configuração confiável; não por IDs arbitrários do payload.
3. Eventos de entrada/toque, atendimento, término/falha e transferência; atualizações de gravação/IA quando existentes. Normalizar eventos internos para o contrato externo, sem confundir `requestId` de comando, SIP Call-ID e sequência de áudio com eventId/revisão do CDR.
4. Entregador HTTP independente da mídia: timeout, tentativas, próxima execução, último resultado e confirmação persistidos por destino. Reinício do worker/serviço preserva itens pendentes. Uma falha não bloqueia chamadas nem filas de outras contas/serviços.
5. Retentativas com backoff exponencial limitado e jitter, parâmetros configuráveis. Reutilizar o mesmo eventId/corpo lógico ao reenviar; registrar nova tentativa, não criar outra ligação/evento. Tratar timeout, falha de rede, 429 e 5xx com retry; respeitar Retry-After quando válido. Erros permanentes de autenticação/schema/versão geram aviso e quarentena/revisão, sem loop agressivo.
6. Após o limite de tentativas, conservar evento em fila de falhas com diagnóstico e reprocessamento controlado; não descartar silenciosamente. Retenção não pode apagar mudanças ainda necessárias a consumidores offline; expor atraso e lacunas.
7. Webhook carrega metadados, nunca áudio, senha SIP, token administrativo, SDP sensível ou credenciais de S3/TURN. Gravação continua referenciada no serviço, sem cópia automática no ViperChat.

### Recepção no backend ViperChat

- Endpoint dedicado de webhook, com HTTPS, segredo por integração, assinatura do corpo e validação de timestamp/rotação. Assinatura por tentativa pode renovar timestamp sem mudar eventId. Nunca publicar segredo de assinatura no frontend.
- Resolver conta/serviço pelo vínculo autorizado do endpoint/credencial. Validar versão, tamanho e identidade antes de aceitar dados; tokens de serviço administrativos não substituem políticas de agente.
- Gravar envelope em inbox persistente com unicidade por integração/eventId e agendar processamento recuperável. Responder sucesso somente após aceitação durável; se a gravação falhar, devolver erro para o produtor retentar. Não depender de um job somente em memória ou de enqueue sem recuperação de pendentes.
- Evento repetido já aceito recebe confirmação idempotente; evento inválido não é marcado como processado. Processamento falho permanece pendente ou em quarentena com motivo, sem bloquear eventos de outras chamadas.
- Aplicar revisão/estado por chamada, armazenar evidências/participações e impedir evento antigo de reabrir chamada encerrada. REST e webhook passam pelo mesmo reconciliador de domínio; fonte autoritativa pode confirmar/corrigir observação local com mapeamento exato, preservando IDs públicos e evidência anterior.
- IDs de transporte/leg ainda desconhecidos ficam pendentes para reconciliação. Não descartar nem unir chamadas de pessoas diferentes usando nome, número ou proximidade temporal como prova.
- O aceite HTTP do webhook não significa que a UI já foi atualizada; expor contadores de recebidos, pendentes, processados, falhas e atraso. Publicar atualização ao frontend somente após persistência autorizada.

### Recuperação REST incremental

- Feed durável de mudanças com cursor estável e ordem total, snapshot/revisão e paginação server-side no escopo autorizado. A API paginada por `startedAt` atual não atende esse contrato. Prever consulta exata por recordId e mapeamento SIP Call-ID/legs.
- Consumidor agendado no backend ViperChat continua funcionando sem browser. Executar periodicamente e ao configurar/reativar serviço, recuperar erro ou reiniciar processo; limite de concorrência por integração evita leituras/checkpoints concorrentes.
- Backfill inicial com marca d'água consistente e retomada incremental sem janela de perda; preservar atualizações ocorridas durante a paginação. Nunca avançar checkpoint de página antes de aplicar ou colocar duravelmente cada mudança na inbox.
- Webhooks podem chegar antes/depois do backfill ou fora de ordem: mesmo evento/revisão usa o mesmo dedup. **Não avançar o cursor REST ao receber um webhook isolado**, pois podem faltar mudanças anteriores. Manter progresso REST e aceitação de webhooks separados.
- Se o cursor expirar ou detectar lacuna de retenção, sinalizar e executar recuperação completa permitida/retomável. Nunca declarar sincronizado com retorno vazio de um escopo incorreto ou feed já podado.
- Não rediscar ou emitir comandos SIP como efeito de replay de histórico. Retry de webhook/REST nunca repete INVITE, transferência ou mensagem.

O outbox HTTP do serviço não recupera sozinho eventos que o worker Zapo nunca entregou à bridge. Manter na segunda entrega o gap separado de persistência/replay worker→serviço, timestamps reais e captura de rejeições por capacidade. Sem fechar esse gap, a limitação deve continuar explícita mesmo com webhooks funcionando.

## 8. Inventário de configuração e lacunas no checkout

Consulta em 20/10/2026 no worktree `viperchat-unified-inbox`, HEAD `b39ba86d2`, com alterações locais preexistentes. Não inspecionado banco de produção.

| Fonte atual | Achado / destino planejado |
| --- | --- |
| `settings/inbox/channels/Voice.vue` e `settingsPage/ConfigurationPage.vue` | Parâmetros comuns WSS/domínio/auth/transferência hoje no Voice/custom → `VoipService`. |
| `enterprise/app/services/voice/provider/custom/token_service.rb` | Prefere credencial de `InboxMember`, depois perfil global; token gerado por serviço é outra alternativa → bootstrap por binding explícito. |
| `app/models/inbox_member.rb`, `inbox_members_controller.rb` | `webrtc_username`, `webrtc_jwt`, `webrtc_password` no vínculo de caixa → candidata a migração para binding de serviço. |
| `settings/profile/UserBasicDetails.vue`, `settings/profile/Index.vue`, `ProfilesController` | Campos WebRTC junto dos dados pessoais e `User.custom_attributes` global → modal e vínculo com conta/serviço. |
| `app/views/api/v1/models/_user.json.jbuilder` | Serializa `custom_attributes` inteiro; revisar exposição das chaves WebRTC ao migrar, não apenas esconder o input da senha. |
| `components/widgets/VoiceAutoRegister.vue` | Itera caixas custom, obtém token e escolhe a primeira válida → substituir por seleção explícita, sem dependência de caixa. |
| `customVoiceClient.js` | Base SIP.js com registro, INVITE, REFER/DTMF e recebimento; contexto interno ainda depende de `inboxId`/conversa. |
| `useCallSession.js`, `helper/inbox.js`, `ConferenceController`, `Call` | Contratos misturados/incompletos entre Twilio, código Meta e custom: detalhes no mapa anterior. Reutilizar por extração controlada, não trocar tudo por find/replace. |
| `components-next/sidebar/Sidebar.vue:368`, `Dashboard.vue` | Menu central e raiz do widget/registro: pontos de entrada para nova aba e sessão global. |

A seleção de serviço resolve um problema concreto do código atual: credenciais globais e “primeira caixa válida” não identificam de maneira segura qual central o agente deseja usar.

Inventário complementar do serviço, agora confirmado no código local: `viperconnect-voip-service` 0.1.67 (`9615a6f78582fb84a9f10647f98744cc41e1befe`) e ViperConnect 4.0.37 (`b1668845d2b24b9b6b8b23a2b19d986d2cd417bf`). Reutilizar `GET /v1/voice/extensions/:extensionId/webrtc-config`, SIP Digest em `/sip/ws`, REST de registros, transferência e histórico. Credencial REST de serviço é administrativa, não token de agente; nunca entregá-la ao frontend. O proxy já possui `GET /admin/voip/console/history`. Endpoints `/v1/voice/config` estão descontinuados (410). Ver detalhes/limites de escopo na auditoria.

## 9. Migração e compatibilidade

O plano inicial previa importar configurações das caixas; essa parte foi dispensada explicitamente pelo usuário antes da implementação, pois Voice/custom nunca foi colocado em produção. Não há importador automático de credenciais antigas nem migração de chamadas legadas para as novas tabelas.

1. As migrations `20261020230000`, `20261020230001` e `20261020230002` criam cinco tabelas VoIP e preservam ramal e ID do agente como snapshots da chamada. Não movem contatos, conversas, mensagens, mídias ou registros da tabela legada `Call`. Remover um agente da conta desativa seu binding, limpa a credencial e preserva o histórico, sem atribuí-lo a outro agente. A reversão da terceira migration é explicitamente irreversível: não fabricar proprietários para preencher vínculos removidos.
2. Serviços e bindings são configurados explicitamente. O novo bootstrap não lê senha/JWT global do perfil nem escolhe a primeira inbox válida. O registro automático Voice/custom antigo foi substituído pelo gerenciador global do agente.
3. A configuração antiga Voice/custom mostra orientação para a nova localização; Twilio e os demais canais mantêm seus fluxos. Os endpoints legados não foram removidos em massa.
4. Listagens de usuário filtram os segredos WebRTC legados. O formulário básico deixa de editar essas credenciais; somente o novo vínculo por conta/serviço recebe credenciais novas.
5. Um binding ativo por agente/conta, protegido também por índice único. Desativar serviço/binding preserva histórico. Troca durante chamada é bloqueada; alteração administrativa de configuração é refletida pelo cliente após encerrar a sessão ativa.
6. Não há migração automática de contas, ativação por ordem da API ou fallback para outra central. Um agente sem binding ativo permanece desconectado.
7. Rollback de código não implica restaurar o banco sobre chamadas novas. Eventual publicação exigirá autorização separada, backup e avaliação das migrations; esta execução permanece exclusivamente em dev.

## 10. Dependências e atualização

`package.json:116` e o importer do `pnpm-lock.yaml` fixam `sip.js: 0.21.2`. Na consulta de 20/10/2026, o [repositório oficial de releases](https://github.com/onsip/SIP.js/releases) também marca 0.21.2 como Latest. **Manter a versão fixada como baseline; não há atualização identificada a executar só pela idade do código.**

O guia oficial de [transferência](https://sipjs.com/guides/transfer/) é referência para a revisão de REFER; a confirmação operacional depende da central. Auditar as chamadas usadas pelo cliente contra a API da versão fixada, em especial DTMF, eventos de registro e gestão de mídia.

Antes de mudar dependências: conferir versão resolvida/instalada e compatibilidade com Vite, Vue e Capacitor; revisar advisories e testes. Não executar upgrade global de pacote/lockfile. Uma atualização realmente necessária entra em mudança isolada, com justificativa e rollback. Preservar dependências de Twilio/Meta enquanto houver uso por fluxos legados; não removê-las pelo novo foco SIP.

## 11. Contratos implementados de API da primeira entrega

Base account-scoped `/api/v1/accounts/:account_id`:

| Recurso | Operação implementada |
| --- | --- |
| `/voip/services` e `/:id` | GET/POST/PATCH/DELETE. Administrador configura serviços; DELETE desativa, não apaga histórico. GET retorna metadados disponíveis ao agente. |
| `/voip/services/agents` | GET administrativo dos agentes elegíveis da conta. |
| `/voip/profile` e `/voip/profile/activate` | GET/PATCH do próprio binding ou gestão administrativa autorizada; POST seleciona explicitamente o binding ativo. |
| `/voip/registration` | POST do próprio agente. Retorna configuração e credencial SIP do binding autorizado, `Cache-Control: no-store, private`; não cria chamada. Não é um token efêmero quando o serviço usa senha Digest. |
| `/voip/calls` e `/:id` | GET com paginação/filtros e detalhe; POST persiste intenção idempotente antes do INVITE do SIP.js. Agente vê suas chamadas; administrador pode consultar a conta. |
| `/voip/calls/:id/observe` | POST autenticado do agente dono do binding. Sequência/evento idempotentes; conserva auditoria e não reabre chamada terminal por evento antigo. Não é webhook do serviço. |
| `/voip/favorites` e `/:id` | GET/POST/DELETE dos favoritos do agente, escopados por serviço. |
| Ingestão de eventos/CDR do serviço | Não implementada nesta entrega. Cliente AMI direto, eventos CEL/Cdr, inbox/histórico próprios e reconciliador pertencem à seção 7.1; recuperação REST própria é adicional. Sem leitor SQL legado; webhook é arquitetura anterior da seção 7.2. |

Mute, atender, encerrar, DTMF e REFER são executados uma vez no cliente SIP.js; não há segundo executor backend dessas ações. O backend persiste as observações sem emitir INVITE/BYE/REFER. As tentativas de salvar observações no navegador são limitadas e em memória: não equivalem a fila durável após fechar o navegador.

## 12. Fases e critérios de saída

| Etapa | Entrega | Critério para avançar |
| --- | --- | --- |
| 1A — ViperChat: contratos e cadastro | Usar o mapeamento existente; modelos, políticas, múltiplos serviços, modal do perfil e prévia de migração. Preparar interfaces futuras com fixtures sintéticas, sem alterar serviço/worker. | Isolamento por conta/serviço, persistência da escolha, credenciais protegidas e conflitos explícitos. |
| 1B — ViperChat: SIP/WebRTC | Registro pelo ramal do agente, áudio, ações, concorrência e reconexão com o serviço já existente. | Testes sintéticos; depois registro/chamadas controladas quando autorizados. Não depender de webhook novo para o fluxo conectado. |
| 1C — ViperChat: aba e histórico observado | Sidebar, lista/favoritos/detalhes/discador, compacto/completo, mobile com Voltar; backend persiste observações SIP com origem e confirmação limitada. | UI responsiva, navegação sem perder sessão, IDs estáveis; falta de sincronização do serviço informada. Não garantir histórico offline. |
| 1D — Aceite ViperChat em dev | Validar SIP, observações, perfis, transporte e regressões com sintéticos e chamadas autorizadas. | Áudio bidirecional e estados do fluxo conectado; lacunas de navegador fechado/replay não escondidas. É aceite funcional parcial, não de CDR completo. |
| 2A — Contrato e acesso sem conector | Fechar perfil AMI mínimo, fixtures, eventos CEL/Cdr e capacidades; inventariar uma central piloto com autorização. | Acesso protegido, emissão/limites de recuperação explícitos; sem consultar banco ou instalar componente na PBX. |
| 2B — ViperChat: integração direta | Cadastro AMI sem campos de banco, consumidor backend, inbox/histórico próprios, snapshot de ativos e reconciliação; recuperação REST própria quando habilitada. | Browser fechado com backend conectado, reconexão sem replay presumido, IDs preservados, isolamento por conta/serviço e lacunas visíveis. |
| 2C — Nosso serviço: compatibilidade | Servidor AMI com subconjunto documentado, CEL/CDR persistidos, participações e REST incremental; tratar gaps worker→serviço da auditoria. | Mesmo consumidor ViperChat funciona nas duas origens; sem mudar áudio/bridge, reproduzir ações SIP ou alegar compatibilidade AMI integral. |
| 2D — Aceite integrado completo | Quedas/replay, recuperação de histórico, chamadas longas, registros tardios, múltiplos dispositivos e transferências nas origens homologadas. | Resultados/durações/participações corretos, mídias e IDs preservados; cobertura comprovada por fonte. Não equivale a aceite nativo em segundo plano. |
| Publicação de cada entrega | Backup, prévia/aprovação, flag, imagem/builds e monitoramento/rollback. | Autorização separada do usuário; primeira entrega, se publicada antes da segunda, mantém aviso de cobertura parcial. Sem deploy automático por concluir o plano. |

**Execução atual:** 1A, 1B e 1C implementadas; 1D validada para o fluxo conectado na réplica dev, com 175 exemplos backend e 91 testes frontend aprovados na rodada histórica, áudio sintético bidirecional e os limites discriminados no runbook. Em 22/10/2026, 2A/2B/2C/2D estão apenas planejadas na nova arquitetura AMI; não declarar novo aceite por atualizar este documento. As pendências são obrigatórias para histórico autoritativo com navegador fechado. Os aceites físicos/REFER posteriores continuam discriminados nas evidências históricas. Nenhuma etapa autoriza mexer na VPS por conta própria.

### Matriz de testes planejada

- Serviços A e B, mesmo número de ramal em ambos, senha/token distintos, agente em duas contas, serviço desativado e tentativa de usar binding de outro agente/conta.
- Salvar/reabrir modal, trocar central sem copiar segredo, senha omitida preservada, limpar explícito, credencial inválida, teste de registro sem qualquer INVITE.
- Entrada, saída, não atendida, perdida, rejeitada, ocupado, cancelada, falha WSS/ICE, atendimento em outro terminal e término remoto. Dados sem contato/conversa são válidos.
- Eventos repetidos, fora de ordem, timeout/reenvio de intenção, múltiplas legs, dois agentes aceitando e reconciliação CDR após navegador fechado.
- Cursor de alterações com chamada longa iniciada fora da janela, áudio/IA tardios, prune do histórico (padrão atual de 1000 registros por empresa), bridge desconectada/replay, chamadas espelhadas e rejeição por capacidade sem duplicar tentativas. Transferência preserva primeiro atendimento e participantes anteriores.
- Mute, DTMF real, REFER/NOTIFY/resultado, dispositivo removido, permissão negada e áudio bloqueado por autoplay; não confundir teste de registro com teste de mídia.
- Dois serviços configurados, um ativo; duas abas, refresh, troca de conta, logout, mudança de rota e alternância compacto/completo.
- Migração sintética com precedências e conflitos; repetir dry-run/aplicação não duplica, histórico/IDs legados permanecem intactos.
- UI mobile/desktop, tema claro/escuro, acentos, fuso, listas grandes, busca server-side e retorno preservando rolagem.
- Segurança: serialização de usuário, bootstrap, logs e eventos; secrets não disponíveis a outro agente/conta nem em armazenamento persistente do browser.
- Primeira entrega: observação local sem confirmação do serviço; refresh/perda de rede não fabrica resultado/duração; fixtures de eventos externos não ativam conexão real nem registram chamada duplicada.
- Segunda entrega vigente: eventos normais/CEL/Cdr na mesma sessão, emissão desabilitada ou bloqueada por filtro/permissão, queda/reconexão AMI, snapshot concorrente, autenticação inválida, crash após persistir inbox e evento tardio. Validar chamada ativa versus encerrada na lacuna, browser fechado com backend conectado e ausência de acesso SQL legado. Na recuperação REST própria, checkpoint não avança por evento AMI isolado e retenção expirada fica explícita. Replay não duplica ligação nem executa SIP. Matriz webhook da seção 7.2 é histórica.

Complemento de aceite em 21/10/2026: áudio físico do navegador confirmado pelo usuário nos dois sentidos (chamadas de laboratório 209/210 e 211/212), mute/unmute e liberação das tracks aprovados. A recusa real revelou falha de persistência/aviso, posteriormente corrigida em dev: `answer()` registra `failed / microphone_denied` antes de liberar a sessão, incluindo a corrida de término do SIP; o aviso específico permanece após o fim da chamada e a navegação, com fechamento explícito. Regressão controlada na réplica gravou a chamada sintética 219 sem atendimento/duração fictícios. A recusa física anterior e esta simulação controlada são evidências diferentes; não houve nova negação manual de permissão nesta rodada. Detalhes e limites nativos no runbook.

## 13. iOS/Android: integração nativa obrigatória

Prioridade vigente de 22/10/2026: primeiro integração direta AMI e histórico próprio da seção 7.1, com limites de recuperação por origem; depois homologação nativa. O backend conectado pode alimentar histórico/notificações sem browser, mas recebimento em segundo plano ainda exige push, CallKit/Telecom e oferta SIP disponível após despertar, conforme o [plano complementar](plano-integracao-ami-cel-cdr-20261022.md#6-web-e-apps-nativos-alcance-da-solução).

Compartilhar agora domínio de chamadas, ações idempotentes, IDs e estados. Separar motor de transporte da UI para um adaptador nativo futuro usar os mesmos registros sem abrir uma segunda ligação.

Requisito confirmado pelo usuário em 21/10/2026: chamadas nos apps devem integrar a telefonia nativa. No iOS, usar CallKit; no Android, Telecom/ConnectionService, equivalente do sistema Android — não existe CallKit Android. O painel em WebView sozinho não atende ao aceite nativo. A fase conectada web validada não significa entrega nativa concluída.

- Criar bridge Capacitor de ações/estados: apresentar recebida, aceitar, rejeitar, iniciar saída, silenciar, encerrar, ativação/interrupção de áudio e finalização por erro. A interface do sistema e o webphone representam a mesma sessão; não discar novamente ao aceitar pelo sistema.
- Correlacionar UUID nativo com a intenção existente e SIP Call-ID/ID autoritativo, mantendo agente/conta/serviço. Eventos repetidos ou atendimento em outro dispositivo não podem criar segunda chamada ou novo registro de histórico.
- No iOS, coordenar sessão de áudio com a ativação/desativação do CallKit e as interrupções do sistema. No Android, integrar conexão e foco/rota de áudio e execução permitida pelo sistema. Não tratar apenas uma notificação comum como chamada nativa.
- Logout/troca de conta, falha de autenticação e término remoto precisam limpar a chamada nativa e revogar sua elegibilidade, sem expor senha SIP em push/logs ou deixá-la em armazenamento público.
- Recebimento com app suspenso/fechado depende também da sinalização e do push do serviço: PushKit/VoIP push no iOS e push/execução de chamada no Android. Isso exige implementação e configuração próprias, além do CallKit/Telecom. Webhooks de CDR não substituem push de chamada recebida.
- O serviço deve coordenar atendimento único entre web e nativo. Manter a parte do serviço/push pendente conforme a restrição atual de não implementar seus eventos; não prometer recebimento em segundo plano antes desse contrato e do aceite em dispositivos reais.

Aceite nativo obrigatório: entrada/saída, tela bloqueada, app em primeiro/segundo plano e encerrado, permissões negadas, atendimento remoto/duplicado, troca de rota de áudio, interrupção por outra chamada, reconexão e término, sem duplicar sessão ou histórico. A bridge nativa e esse aceite ainda não foram implementados; os builds atuais comprovam empacotamento/inicialização apenas.

O frontend final foi sincronizado para Android e iOS e compilado em Debug nos dois. Android sem aparelho/emulador disponível; iOS instalado e iniciado no simulador iPad Pro 13 (M5) com identificador isolado. Somente a inicialização nativa foi verificada no iOS: esses builds não comprovam chamada nativa, áudio de hardware ou segundo plano. A central de laboratório usa sinalização/RTP em loopback Windows, que não é acessível do simulador Mac sem preparação adicional de rede; a instalação nativa exige servidor HTTPS. Não enfraquecer HTTPS/WSS de produção nem conectar produção para simular esse aceite. Artefatos e hashes constam no runbook.

## 14. O que está fechado e o que falta verificar

Refinamento visual solicitado em 21/10/2026: webphone global arrastável no desktop, tela cheia no mobile e barra recolhida reservando o launcher do menu; ações circulares por ícones com acessibilidade. Central compacta com favoritos paginados no topo, pesquisa entre favoritos e Recentes, filtros e nova chamada por ícones à direita de Recentes. Filtros abrem modal, não ocupam permanentemente a lista, e mantêm as seleções/contador. A paginação de histórico continua server-side. O aviso visual de histórico parcial foi removido a pedido; permanece obrigatório resolver a integração autoritativa antes da produção definitiva. Essas alterações não implementam CallKit/Telecom nem eventos do serviço e não autorizam implantação na VPS.

Ampliação implementada em dev: favoritos em três cartões com avatar/nome por página, pino discreto e confirmação de remoção do atalho; Recentes com cinco chamadas por página. Diretório e identificação account-scoped por telefone completo/ramal exato do mesmo serviço, respeitando visibilidade e recusando ambiguidades/LID/grupos. Reutilizar nome/foto de contatos/agentes na lista, favoritos e webphone sem alterar os IDs/snapshots ou copiar mídias. Discador global com abas Contatos/Ramais/Manual, pesquisa/paginação e confirmação explícita; troca de serviço exige ativação pelo usuário. Atalhos na lista/detalhes/sidebar de contatos abrem o discador, não iniciam chamada automaticamente. Validação anterior: 167 testes frontend e 37 exemplos API/diretório, sem falhas. A correção posterior de microfone tem sua própria rodada registrada no runbook. Limitações de CallKit/Telecom e eventos do serviço continuam discriminadas; não chamar isso de aceite de produção concluído.

Implementado em dev: arquitetura sem inbox, ramal por agente/serviço/conta, múltiplos serviços administrativos, modal de seleção/configuração, credenciais criptografadas, sidebar Chamadas, lista/favoritos/detalhes/discador, webphone global compacto/completo e observações autenticadas persistidas. A seta comum das conversas fica na mesma posição do cabeçalho mobile. Não foi necessário atualizar SIP.js além da versão fixada 0.21.2.

Contrato atual de eventos/CDR e REST mapeado localmente na auditoria anexa. Após o mecanismo ViperChat/SIP e a interface dev, a decisão de 22/10/2026 é planejar e integrar AMI direto e consulta CEL/CDR conforme seção 7.1, substituindo a proposta anterior de webhooks. Gaps P0 do serviço permanecem obrigatórios para histórico autoritativo completo; a auditoria anterior não prova compatibilidade AMI nem acesso ao histórico de uma PBX legada. Validar versões, rede, WSS/ICE e autorização antes de testes reais. Uma conexão SIP ativa por agente continua sendo o recorte, preservando múltiplos registros autorizados na central; a observação AMI backend é independente dessa sessão.

Nesta implementação houve alterações de código e migrations aditivas na réplica local, dados sintéticos isolados e chamadas internas controladas. O aceite funcional dev e suas limitações estão no runbook; não houve implantação/acesso à VPS nesta tarefa, publicação de imagem, commit/push ou envio às lojas. As seções abaixo documentam etapas históricas anteriores à implementação VoIP e não representam o aceite atual.

### Consolidação Git autorizada em 20/10/2026

Antes de iniciar a etapa 1A, o administrador autorizou commitar as alterações pendentes do ViperChat, publicar a branch e integrá-la por pull request em `4.16.0`, preservando os commits da API de contatos já presentes no destino. Esta autorização não inclui implantação na VPS nem implementação antecipada do VoIP.

A revalidação focada da consolidação aprovou 156 exemplos backend e 55 testes frontend. São verificações dos recursos existentes (pesquisa, etiquetas, OpenRouter e unificação), não testes do VoIP planejado. Não houve novo teste físico Android/iOS ou Archive nesta consolidação; permanecem as limitações nativas registradas na auditoria de pesquisas. APKs, capturas, snapshots e arquivos temporários locais ficam fora dos commits.

### Correção do CI e validação ampliada em 20/10/2026

Antes da implementação VoIP, foram corrigidas as falhas da consolidação: os mocks do editor incluem suas referências; os testes Meta usam a versão configurada; os casos exclusivos Enterprise ficam na árvore Enterprise; os exemplos e scripts respeitam o lint sem relaxar a configuração global. Os cenários e suas asserções foram preservados. O teste de notificação usa uma instância explícita de mailer para não depender da ordem de carregamento das subclasses.

No código funcional, a filtragem de credenciais também protege os binds SQL de `provider_config`, mesmo quando Active Record é carregado antes do inicializador; o envio MMS mantém os anexos ordenados por ID, com regressão que inverte a associação em memória. Não foram alteradas as regras de transporte/unificação nem implementado o VoIP nesta correção.

Validação local em infraestrutura Docker descartável, com recursos limitados e banco/Redis separados do dev:

- Backend CE completo: 8.204 exemplos, zero falhas; 97 pendências preexistentes do ambiente/suíte. As 27 verificações de migração incluídas nessas pendências foram executadas separadamente no banco mínimo exigido: 27 exemplos, zero falhas. As demais pendências não equivalem a testes aprovados.
- Compatibilidade Enterprise e LLM: 39 exemplos, zero falhas, incluindo ações de chamada versionadas e transcrição de áudio histórico. Isso não representa a suíte Enterprise completa.
- Frontend completo com cobertura: 515 arquivos e 4.855 testes aprovados.
- RuboCop completo: 3.192 arquivos, zero infrações; sem modificar `.rubocop.yml`, `.rubocop_todo.yml`, `.rspec` ou desativar testes.
- ESLint completo de JavaScript/Vue: aprovado, sem alterar suas regras.

Na primeira execução remota do PR de correção, o lint detectou oito comentários redundantes `Rails/Output`. A investigação identificou uma diferença de caminho: o padrão `**/app/**/*.rb` também inclui scripts quando o checkout inteiro está em `/app`, mas não na raiz usada pelo GitHub. A correção remove esses comentários sem mudar o comportamento dos scripts; a revalidação usa uma exportação limpa do commit fora de `/app`, evitando essa divergência entre fonte enviada e runtime de teste.

O reinício local do Docker Desktop foi autorizado após sobrecarga; os serviços dev voltaram e o endpoint `/api` respondeu HTTP 200. Nenhuma VPS foi acessada/alterada. Nesta correção o frontend funcional, as dependências e os bundles nativos não mudaram; não foram gerados APK/Archive nem feitos novos testes em aparelhos. A integração em `4.16.0` depende ainda da confirmação dos checks desta correção no GitHub.

### Retomada da branch VoIP e integração dos hotfixes — 21/10/2026

Retomado o checkout `C:/Users/caita/.codex/worktrees/viperchat-voip`, branch `feat/agent-voip-webphone`. A branch já continha as correções até `e246c3570`. Foram integrados, em ordem e sem conflitos, os três commits restantes da `4.16.0`, preservando autoria e os commits de implementação VoIP:

- `f8b372d80` → `c06fe42eb`: autenticação UnoAPI por token com variações de `+`/nono dígito, preservando assinatura Meta.
- `f30427ccf` → `390943148`: fixtures legadas de vínculos sem relaxar a unicidade de produção.
- `c0d137c5b` → `6b9cd9192`: edição/exclusão na bolha canônica, fila para referências pendentes e seletor de transporte hidratado sem F5, incluindo os dois planos e as regressões.

`git cherry` confirmou equivalência de todos os patches restantes da `4.16.0`. Nenhuma versão/tag foi movida e não houve deploy, restart, sincronização do runtime ativo ou envio de chamadas/mensagens reais.

Validação da combinação nesta branch:

- Frontend: 197 testes, 18 arquivos, zero falhas, incluindo SIP.js, store VoIP, webphone, central de chamadas, configuração, contatos, ReplyBox, seletor e editor compacto.
- Backend: 229 exemplos, zero falhas, incluindo APIs VoIP/diretório, vínculos, autenticação UnoAPI/Meta e mutações da caixa unificada.
- Executado no container já existente, com exportação descartável do código e banco `viperchat_voip_test`/Redis 15, sem criar containers nem substituir `/app`.
- O junction de dependências do worktree exigiu configuração Vitest temporária permitindo apenas o worktree e o diretório de dependências compartilhado, sem desativar testes. O arquivo temporário, a exportação no container e os dois arquivos de transferência no Temp Windows foram removidos ao concluir.

As três alterações locais preexistentes em `android/app/capacitor.build.gradle`, `android/capacitor.settings.gradle` e `ios/App/CapApp-SPM/Package.swift`, além de `.playwright-cli/` e `output/`, foram preservadas e não incluídas na integração. Não foi feita nova tentativa de contornar os bloqueios nativos documentados em `docs/correcao-seletor-transporte-sem-f5-20261021.md`: o aceite físico Android/iOS desta integração continua pendente. Webhooks/CDR do serviço VoIP continuam fora do escopo autorizado da implementação atual.

### Integração das reações nas caixas parceiras — 21/10/2026

O commit `ac141005be8363ae60a6bdae13408219771925f3`, publicado na `4.16.0`, foi incorporado por cherry-pick com referência de origem como `a954ccede`. Inclui serviço, regressões e o complemento do plano em `docs/correcao-edicao-exclusao-caixa-unificada-20261021.md`. Os três arquivos resultantes foram comparados com a origem e são idênticos, sem conflitos ou alterações no VoIP.

Reações recebidas/echo de Meta e ViperConnect no par ativo atualizam somente a bolha original identificada, sem criar conversa ou reabrir atendimento; referências sem evidência ficam pendentes/revisão. IDs, histórico e mídias são preservados. A validação anterior do patch aprovou 376 exemplos backend e RuboCop nos dois arquivos Ruby; não é uma nova execução da suíte VoIP nem a suíte completa. Não houve alteração de frontend compartilhado ou código nativo nesta correção.

Commit/push das duas branches autorizados pelo usuário. Trabalho retomado em `feat/agent-voip-webphone`; alterações nativas locais e arquivos não rastreados preexistentes continuam fora dos commits. Sem atualização do runtime da réplica, containers, imagem/tag ou VPS nesta integração.

### Ajustes de homologação local — conexão, configuração e ramais, 21/10/2026

- Corrigido o registro automático quando um ramal ativo passa a estar disponível depois do carregamento inicial: `refreshConfiguration` conecta mesmo sem runtime anterior; salvar o próprio ramal atualiza a configuração imediatamente. A revisão tentada fica registrada antes do REGISTER, evitando repetição periódica de credenciais recusadas sem mudança de configuração. Mantidos serviço explicitamente ativo, lock entre abas e impedimento de troca durante chamada.
- Serviços VoIP passam a listar os ramais configurados abaixo dos cards, com agente, serviço, extensão e indicação de padrão. Esse indicador não afirma que o SIP esteja registrado. API exclusiva de administrador, com projeção explícita sem usuário de autenticação, senha ou credenciais criptografadas; bindings sem agente não são exibidos.
- A falha do print ao editar é validação HTTP 422: `ws://` em IP LAN não atende à regra de WSS; a exceção WS continua restrita ao loopback em desenvolvimento. A tela agora mostra orientação específica de WSS e os campos inválidos conhecidos, sem relaxar segurança. A regressão confirma edição WSS por administrador, rejeição de WS LAN e preservação de credenciais.
- Preparado consumo do destino completo retornado pelo SIP (`P-Asserted-Identity` ou URI To nas respostas). A discagem original é preservada; o destino confirmado vai nos detalhes de observação e resolve nome/foto com a política de contatos existente. Não há inferência de DDD, união por sufixo, mudança de contato ou migração de histórico.
- **Dependência ainda aberta:** o gateway SIP do serviço VoIP local inspecionado normaliza internamente, mas as respostas examinadas repetem o To recebido e não informam o destino normalizado. O exemplo discado só com nove dígitos não está comprovadamente resolvido no serviço atual. Solicitada autorização específica para acrescentar esse retorno no código dev do serviço/ViperConnect, sem introduzir webhooks/CDR nesta etapa. Não foram corrigidos os registros históricos existentes.
- **LAN:** viável, mas ainda não preparada: exige HTTPS para o app, WSS para SIP, certificado confiável e STUN/TURN/relay publicados no IP LAN. O coturn atual está publicado somente em loopback. Não foram abertos firewall, portas ou confiança de certificados, nem alterada a configuração de rede do serviço.

Validação: 82 testes frontend em sete arquivos e 42 exemplos backend, zero falhas. RuboCop dos sete arquivos Ruby aprovado; ESLint sem erros, com avisos de tradução/separadores visuais registrados. Playwright verificou o componente real com API sintética: lista em 320/360/390/430/1280 px e paisagem 844 px, erro de WSS e acesso ao rodapé da modal em celular, sem overflow horizontal. Capturas em `output/playwright/voip-fixes-*.png`; não são um aceite com chamadas reais.

Bundle compartilhado gerado e sincronizado nos dois projetos Capacitor; Android `assembleDebug` aprovado, APK em `android/app/build/outputs/apk/debug/app-debug.apk`. `adb devices` sem aparelho/emulador conectado. iOS sincronizado, mas sem compilação/assinatura ou teste em aparelho nesta rodada Windows; aceite nativo permanece parcial. Configurações nativas preexistentes foram preservadas. Sem publicação de apps/imagem/tag ou commit/push nesta etapa.

Os onze arquivos funcionais foram atualizados na réplica existente após conferir ausência de chamadas ativas, com backup de código restrito em `/app/tmp/voip-fixes-backup-20261021/source-before.tar.gz`. App responde HTTP 200. Sem migração, novos containers, restart de serviços ou alteração na VPS. O serviço VoIP/ViperConnect e suas configurações não foram alterados. O processo de preview foi encerrado e removidos os seus quatro arquivos, a exportação `/tmp/viperchat-voip-fixes.NFNNoa` e a pasta `viperchat-voip-fixes-20261021` no Temp Windows. São intermediários regeneráveis. Preservados o APK/bundles de validação, as capturas e o backup pequeno para rollback de código; caches compartilhados e arquivos preexistentes não foram apagados.

### Atualização autorizada do container VoIP local — 21/10/2026

Após nova autorização do usuário, o serviço existente `viperconnect-mobile-lab-voip-1` foi atualizado de 0.1.65 para 0.1.67, compilando a tag imutável `v0.1.67` sem alterações no fonte. Imagem local `viperconnect-voip-lab:0.1.67`, digest `sha256:8927497ab1e43f0f95a1463ed11de1c63200c5d217f52f44371bb6b07475bd3a`. Atualizado somente o seletor de imagem no ambiente local externo ao repositório; variáveis funcionais permaneceram iguais. Compose `up --no-deps --force-recreate --pull never voip`, sem instância paralela e sem reiniciar web/worker/ViperChat/coturn.

Sem chamadas ativas antes da troca. Backup consistente SQLite por `node:sqlite.backup`, restrito ao volume existente: `/home/u/app/data/backups/voip-before-0167-20261021`. Verificação posterior: 52 IDs de histórico e 48 IDs de gravações preservados; todos os valores antigos da configuração continuam iguais, admitindo apenas campos novos da versão; bridge reconectada e healthcheck saudável. A imagem antiga `viperconnect-voip-lab:dev` foi preservada para rollback de código. Nenhuma chamada real de teste iniciada, publicação de imagem/tag ou acesso à VPS. Atualizar o serviço não comprova ainda a identificação da discagem curta no webphone; esse aceite continua pendente.

A limpeza da pasta temporária de compilação `C:/Users/caita/AppData/Local/Temp/viperconnect-voip-update-0167-20261021` foi bloqueada pela proteção do ambiente e não foi contornada. O backup SQLite permanece necessário para recuperação; configurações, volumes e arquivos de mídia não foram removidos.

### Sidebar compacta sob demanda — 21/10/2026

Em telas estreitas, o menu inicia totalmente oculto. Clicar no botão flutuante abre a barra de ícones de 56 px; o controle imediatamente acima de Notificações alterna entre ela e o menu expandido de 200 px. Fechar e reabrir retorna à barra compacta. O estado mobile é separado da largura persistida do desktop. O botão flutuante acompanha a largura aberta, sem cobrir os ícones da barra compacta.

Validação: 38 testes em oito arquivos da sidebar aprovados, incluindo abertura, alternância, posição do controle e fechamento em 320/360/390/430 px; ESLint sem erros nos cinco arquivos envolvidos. Playwright com componentes reais e contexto sintético confirmou os três estados, ausência de overflow horizontal, controle acima de Notificações e botão flutuante fora da barra compacta nessas quatro larguras. Capturas preservadas em `output/playwright/sidebar-toggle-*.png` e conferidas visualmente. Não é aceite em aparelho físico.

Bundle mobile recompilado e sincronizado em Android/iOS; Android `assembleDebug` aprovado. `adb devices` sem dispositivo; iOS sem compilação ou smoke físico nesta rodada Windows. Não se declara aceite nativo completo. Os três arquivos funcionais foram copiados para a réplica existente após confirmar ausência de chamadas ativas; hashes idênticos e HTTP 200. Backup restrito de código em `/app/tmp/sidebar-toggle-before-20261021.tar.gz`. Sem novos containers, restart, VPS, commit ou push.

Encerrados navegador e servidor de preview próprios; removidos os quatro arquivos temporários de preview/configuração de teste, todos regeneráveis. Preservados capturas, entregáveis nativos, backup de rollback e alterações preexistentes.

### Recuperação de registro e transferência — 21/10/2026

Relatos de homologação: ramal desconectado até F5, sessão local ainda ativa após transferência e ausência de seleção de operador no webphone em tela cheia.

- Causa no cliente: o listener de registro era removido após o primeiro sucesso; apenas a queda do transporte disparava reconexão. Agora os estados Unregistered/Terminated continuam observados, com retentativas sem limite de quantidade, intervalo exponencial de 1–30 segundos e respeito a Retry-After. Falhas de autenticação também continuam tentando, mantendo o erro até registrar. Tentativas concorrentes são consolidadas; parada/troca de conta invalida callbacks antigos. O refresh periódico recupera runtime desconectado mesmo sem mudança da configuração.
- Durante chamada, recupera transporte/REGISTER no mesmo UserAgent, preservando diálogo e mídia; não recria a sessão para registrar. Sem chamada, usa novo bootstrap autenticado. Serviços desativados, ausência de ramal e lock pertencente a outra aba continuam respeitados.
- Transferência: o código anterior só indicava conclusão após NOTIFY, sem liberar sua sessão. Agora um sipfrag final 2xx encerra apenas o diálogo local por BYE, libera mídia e registra `end_reason=transferred` no mesmo histórico/ID. REFER aceito (202), progresso 1xx, rejeição e conteúdo inválido não encerram a chamada original. NOTIFY repetido e BYE tardio não afetam outra chamada. Não há timeout que invente sucesso.
- O gateway local inspecionado emite NOTIFY 100 e final 200 quando seu handler aceita a transferência; o caminho de conclusão no serviço também prevê BYE para o transferidor. Isso não prova que o BYE da chamada relatada chegou ao navegador: os logs disponíveis nesta rodada não permitiram correlacionar esse evento real. O cliente respeita o resultado informado pelo serviço; não foi alterado o gateway nem introduzidos webhooks/CDR. O aceite ponta a ponta permanece necessário, especialmente para confirmar a semântica desse NOTIFY final no serviço.
- Webphone expandido agora oferece diretório paginado e pesquisável dos operadores do mesmo serviço, com nome/avatar/ramal, excluindo o próprio ramal. Selecionar só preenche o destino: exige confirmação explícita. Discagem manual permanece disponível, inclusive se a consulta do diretório falhar. Controles bloqueados enquanto a transferência está pendente; nenhuma ativação de outro serviço.

Validação local: 97 testes frontend em nove arquivos, incluindo perda/recuperação de registro, repetição de falhas, parada, tentativas concorrentes, recuperação durante chamada sem BYE, NOTIFY final/provisório/rejeitado e seleção do operador no fullscreen mobile. ESLint sem erros (dez avisos preexistentes de i18n no webphone). Playwright usou componentes reais e API sintética, conferiu seleção/confirmar, 320/360/390/430/844/1280 px, retrato/paisagem, controles alcançáveis por rolagem e ausência de overflow horizontal. Capturas `output/playwright/voip-transfer-picker-*.png`, conferidas visualmente. Nenhuma chamada real iniciada; testes sintéticos não comprovam a transferência real relatada nem novo áudio ponta a ponta.

Bundle atual recompilado e sincronizado para Android/iOS; `assembleDebug` aprovado, `adb devices` sem dispositivo. iOS sem compilação/smoke nesta rodada Windows; bloqueio de acesso ao Mac documentado anteriormente não foi contornado. Aceite em aparelhos permanece pendente.

Atualizados apenas quatro fontes na réplica existente: AgentSipClient, store agentVoip, AgentWebphone e novo AgentTransferPicker. Backup restrito dos três fontes anteriores em `/app/tmp/voip-recovery-before-20261021.tar.gz`; rollback deve restaurá-los e remover apenas o novo componente desta mudança. Hashes conferidos e app HTTP 200. Antes da cópia, os únicos quatro registros não terminados eram `awaiting_confirmation` antigos (IDs 27, 29, 206 e 208), sem registros active/ringing/initiating; não foram alterados. Sem novos containers, reinícios, alteração de dados, VPS, commit/push ou publicação. Encerrados preview e navegador próprios; removidos os quatro arquivos temporários regeneráveis, preservados capturas, APK/bundles e backup de rollback.

### Aceite da transferência e tons entre ramais — 21/10/2026

Usuário confirmou transferência real com BYE correto após a correção anterior. Esse aceite foi humano; nesta rodada não foi iniciada nova chamada real. Relatado silêncio antes de atender chamadas entre ramais e solicitado toque também no recebimento.

O cliente já iniciava ring recebido, mas criava elementos novos a cada tentativa; o tom de saída dependia exclusivamente do progresso SIP 180. Os dois assets locais foram conferidos por hash com a réplica: não estavam ausentes ou divergentes. Não se comprovou se a chamada relatada ficou sem 180 ou sofreu bloqueio de autoplay; esses são caminhos corrigidos/cobertos, não uma causa externa presumida.

- Tom local de saída passa a começar ao iniciar o INVITE, sem aguardar 180; não altera o estado de domínio para fingir que a ponta já toca. Progresso 180 repetido não reinicia a cadência. Ao atender, rejeitar, terminar ou desconectar, para o tom e reinicia sua posição.
- Elemento de toque reutilizado/pré-carregado; interação de ponteiro/teclado prepara o elemento silenciosamente e retenta o toque ativo quando bloqueado. Isso não desativa políticas do navegador: sem permissão/interação ainda pode ser necessário usar a ação existente de reproduzir áudio, conforme a [política de autoplay documentada](https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Autoplay).
- Ring recebido e tom de saída usam a mesma saída de áudio selecionada para a chamada. Sucesso de REGISTER não apaga mais erros de mídia; somente reprodução confirmada limpa `audio_blocked`, sem apagar `microphone_denied` ou outro erro. AbortError de reprodução já interrompida não gera falso aviso.

Validação: 101 testes em nove arquivos frontend, zero falhas; ESLint dos quatro arquivos sem erros/avisos. Cobertura inclui saída sem 180, cadência, parada ao atender/terminar, reprodução bloqueada e nova interação, sink de áudio e preservação do aviso durante renovação de registro. Playwright reproduziu de fato os assets no Chrome por interação com controles sintéticos, usando o AgentSipClient real sem sinalização SIP: ambos `paused=false` e tempo avançando; pico de sinal medido pelo AnalyserNode de 0,289 no recebido e 0,989 no tom de saída. Isso comprova reprodução/sinal no navegador, não percepção no headset do usuário nem aceite de áudio entre ramais reais. Os únicos erros de console da prévia eram favicon 404, sem erro funcional de áudio.

Build compartilhado aprovado, bundles Android/iOS sincronizados e Android `assembleDebug` aprovado. Sem aparelho Android conectado; iOS sem compilação ou teste físico nesta rodada Windows. Atualizados somente AgentSipClient e store agentVoip na réplica existente, com hashes idênticos e HTTP 200; consulta anterior sem chamadas initiating/ringing/active. Backup restrito em `/app/tmp/voip-tones-before-20261021.tar.gz`. Sem VPS, novos containers, alterações de dados, commits ou publicação. Encerrados navegador/servidor próprios e removidos os quatro arquivos de prévia/configuração temporária; bundles/APK e backup de rollback preservados. Falta aceite auditivo real do usuário para os tons.

### Tema, fechamento da discagem e retorno às conversas — 22/10/2026

- Botões Ligar e Atender, além do ícone do webphone recolhido, usam `n-brand`, o token primário do tema. Abas já usavam esse token. Removido verde fixo das ações primárias; encerrar/recusar continuam vermelhos. Não foram alteradas cores semânticas de estados. Conferidos temas Viper claro/escuro e cor computada do botão igual a `--brand-color`.
- Nova chamada: a modal fecha assim que o webphone possui o novo `client_call_id`, sem aguardar a promessa SIP terminar ou a ponta atender. Usa a versão do contexto da discagem, evitando fechar outra modal após troca de conta/reabertura. Erro antes de criar a chamada mantém a modal aberta. O fechamento após sucesso também permanece como fallback para chamadas já resolvidas.
- Adicionado BackButton icon-only no cabeçalho da central, igual à seta das conversas, com destino explícito `home` da mesma conta, sem depender do histórico do navegador. Voltar dos detalhes continua levando à lista de chamadas. Navegação não encerra chamada nem desregistra o agente.
- Conteúdo da lista limitado e centralizado em telas estreitas, com margens simétricas, preservando alinhamento à esquerda dos nomes, paginação de cinco e duas colunas no desktop. Sem favoritos, removido espaçamento extra antes da pesquisa; borda lateral reservada ao desktop.

Validação: 29 testes em três arquivos (discador, webphone e central), sem falhas; ESLint sem erros, com avisos existentes de i18n/formatação. Teste novo mantém promessa SIP pendente, cria a chamada e confirma fechamento único; erro pré-criação mantém diálogo/aviso. Playwright conferiu componentes reais com APIs/dados sintéticos em 320/360/390/430/844/1280 px: temas claro/escuro, ausência de overflow, botão alcançável, margens simétricas descontando scrollbar e navegação da seta até Todas as conversas. Outra prévia confirmou modal fechada e webphone Iniciando ainda com promessa pendente. Capturas `output/playwright/voip-primary-theme-*.png`, `voip-calls-back-centered-*.png` e `voip-dialer-closed-on-start-390.png`, conferidas visualmente. Roteador global substituído somente na prévia isolada para evitar ciclo de importação; componente BackButton de produção permaneceu real. Nenhuma chamada real disparada.

Réplica existente atualizada com AgentDialer, AgentWebphone, CallsPage e as duas traduções; hashes conferidos e HTTP 200. Antes da primeira cópia não havia chamadas initiating/ringing/active. Backups restritos: `/app/tmp/voip-theme-before-20261022.tar.gz` e `/app/tmp/voip-calls-back-before-20261022.tar.gz`. Sem novos containers, restart, alteração de dados, VPS, commit/push ou publicação.

Build compartilhado atual recompilado, Android/iOS sincronizados e Android assembleDebug aprovado. Encontrado aparelho Android conectado: pacote final instalado com sucesso por `adb install -r`, sem limpar dados. O aparelho estava em uso; não foi forçada a navegação sobre a atividade do usuário, portanto o fluxo VoIP físico não está validado. A abertura inicial do aplicativo não comprova smoke completo. iOS sem compilação/smoke nesta rodada Windows. Não se declara aceite nativo completo.

Encerrados os navegadores/servidor próprios e removidos os seis arquivos temporários de prévia/configuração de teste. O XML temporário criado para inspeção no Android também foi removido. Capturas, APK/bundles, configurações preexistentes e backups de rollback preservados; sem limpeza de caches compartilhados.

### Consolidação autorizada na branch VoIP — 22/10/2026

Preparada publicação dos fontes, regressões e deste plano em `feat/agent-voip-webphone`, incluindo homologação de configuração/destinatário, registro automático e recuperação, transferência/seleção de operadores, tons, sidebar compacta sob demanda e ajustes de tema/navegação/fechamento do discador. Bateria combinada final: **143 testes frontend em 17 arquivos, zero falhas**, cobrindo VoIP e sidebar. A validação backend dos ajustes de configuração/identificação foi registrada acima (42 exemplos); não se trata de nova execução da suíte backend completa.

O worktree estava alinhado ao remoto antes do commit. Revisados diff, escopo e possíveis segredos; configurações nativas geradas preexistentes com caminhos da máquina (`android/app/capacitor.build.gradle`, `android/capacitor.settings.gradle`, `ios/App/CapApp-SPM/Package.swift`), capturas e logs locais ficam fora do commit, preservados no disco. A configuração temporária desta bateria foi removida. Bundles/builds e limitações do aceite físico permanecem conforme os registros anteriores. Esta autorização é somente commit/push: sem nova alteração de runtime, containers, imagem/tag ou VPS nesta consolidação.

### Consolidação do relatório de caixas parceiras — 23/10/2026

Por solicitação expressa do usuário, o relatório e seu simulador foram incorporados
na árvore existente `feat/agent-voip-webphone`, sem criar outra branch e sem
sobrescrever as alterações VoIP que já estavam pendentes. Os 355 arquivos locais
preexistentes foram conferidos por SHA256 antes de acrescentar este registro.

As cinco correções de WhatsApp da base 4.16.0 já possuem commits equivalentes
na branch VoIP (`git cherry` sem patches novos), portanto não foram reaplicadas.
Foram integrados somente os arquivos novos e os seis pontos de entrada do relatório
(API, menu, traduções e rotas), preservando a navegação/configuração VoIP.
As sete capturas foram copiadas com hashes idênticos. Os 14 arquivos funcionais
integrados conferem com a réplica já existente, normalizando apenas CRLF/LF.

Detalhes funcionais, evidências e limitações continuam em
`docs/relatorio-caixas-parceiras-custos-meta.md`. A mudança de branch não altera
regras de faturamento, registros, mídia ou configurações. O aceite nativo continua
pendente pelas falhas de memória já documentadas; nenhuma compilação pesada nova
foi iniciada para uma integração de arquivos idênticos.

Sem commit, push, acesso à VPS, novos containers ou descarte das alterações locais.
Novas branches nesta linha de trabalho exigem alinhamento prévio com o usuário.

Conferência após integração: **42 testes frontend combinados e 24 verificações
backend aprovados**. Removida a referência local `feat/partner-inbox-cost-report`;
pasta antiga preservada em detached HEAD, sem perda de fontes, capturas ou
temporários bloqueados. O trabalho continua na `feat/agent-voip-webphone`, com
as alterações locais ainda não commitadas.

### 23/10/2026 — pesquisa de contatos independente da caixa

Concluída em dev a separação entre cadastro de contatos da conta e visibilidade
dos atendimentos. Agentes com diretório permitido encontram contatos mesmo sem
vínculo à caixa de origem; as conversas, mensagens e caixas continuam protegidas.
Mantidos ocultação explícita do diretório e isolamento entre contas.

Validação direcionada: **199 exemplos aprovados**, regressão reproduzida antes
da correção e RuboCop sem infrações. Atualizados somente dois arquivos de backend
na réplica existente, sem novos containers ou VPS. A conferência READ ONLY do
contato 3679 confirmou a pesquisa e a manutenção das permissões negativas.

Detalhes e limites: `docs/correcao-pesquisa-contatos-conta-20261023.md`.

### 23/10/2026 — bolha única de chamada, gravação e IA

Implementado em dev: gravação, resumo e transcrição atualizam a bolha privada da
chamada. Textos recolhíveis, sem outra nota para as chamadas já vinculadas.
Notas legadas são preservadas por ID e marcadas explicitamente quando seu
conteúdo passa a ser exibido na bolha; nenhum histórico ou áudio é removido.

Validados 122 exemplos backend e 21 testes frontend; caso real na réplica,
capturas desktop/mobile, bundles Android/iOS e APK Debug. Sem dispositivo Android
conectado e Mac inacessível, permanece pendente o aceite nativo em aparelhos.
Sem novos containers, VPS, commit/push ou publicação de apps.

Detalhes: `docs/voip-bolha-unificada-gravacao-ia-20261023.md`.

### 23/10/2026 — tema, orientação e consolidação das pendências

Bolhas VoIP seguem a cor primária do tema, com recebidas à esquerda e efetuadas
à direita. Permanecem privadas; notas comuns não mudam. Player compacto abaixo
de 480 px validado sem corte em 320 px. Fontes já disponíveis na réplica dev.

Por autorização expressa de “commitar tudo”, a consolidação reúne todas as
alterações funcionais pendentes, incluindo relatório de caixas parceiras,
histórico/diagnóstico VoIP, pesquisa de contatos, bolha unificada e documentação.
Ficam fora os caminhos nativos gerados desta máquina, APKs, logs, capturas,
backups e temporários. Nenhuma alteração na VPS.

Conferência da árvore de publicação: 289 exemplos backend, 108 testes frontend
e 24 verificações sintéticas do relatório aprovados. Schema regenerado acompanha
a migração. Limitações de aparelho/iOS e limpeza Windows continuam documentadas.

### 23/10/2026 — avatar do agente originador nas efetuadas

Corrigido em dev o remetente das bolhas efetuadas: agente comprovado no registro
histórico da chamada/ramal, nunca o contato ou o usuário logado por suposição.
Origem ausente ou ambígua recebe ícone neutro; agente conhecido sem foto usa suas
iniciais. Chamadas recebidas permanecem com o contato.

Validados 127 exemplos backend, 23 testes frontend e o caso real da chamada 24,
preservando mensagem 2429132, vínculos, gravação e análise. Interface conferida em
desktop/mobile; bundles Android/iOS e APK Debug recompilados, sem aparelho
conectado e sem Mac acessível para aceite nativo completo. Sem commit/push nesta
tarefa, VPS ou novos containers.

Detalhes: `docs/voip-avatar-agente-origem-20261023.md`.

Publicação do restante autorizada em 23/10/2026: incluir a correção de avatar,
testes e documentação nesta mesma branch, junto das alterações de relatórios
já publicadas. Bolhas antigas na réplica foram corrigidas apenas com agente
histórico comprovado, incluindo a conversa 13954, preservando IDs e artefatos.
Saídas de validação permanecem locais e ignoradas pelo Git; referências nativas
geradas específicas da máquina foram normalizadas para os caminhos portáteis
existentes. Sem acesso à VPS ou implantação.

### 23/10/2026 — cache de abertura e reconexão discreta

Cache IndexedDB isolado por usuário/conta/instalação, com TTL de 24h e limite
de 5 MiB. Restaura conversas e mensagens em modo somente leitura, atualiza pela
rede e deduplica por ID antes de liberar ações. Sessão nativa validada em segundo
plano; indicador discreto substitui o aviso grande de reconexão. Sem envio offline.
221 testes automatizados passaram; ensaio sintético de rede lenta/offline/retorno
validou dois IDs únicos e nenhum envio. Aplicado só na réplica existente.
Limitações de dados locais e validação nativa em `docs/cache-frontend-conversas.md`.

### 24/10/2026 — fila offline de textos e notas

Evolução do cache: bolhas aguardando envio com persistência local, cancelamento e
retomada automática após conexão/autorização. UUID durável no endpoint de mensagens
impede duplicação em resposta perdida; IDs/transportes/notas e referências são
preservados. 239 testes frontend e 35 exemplos backend passaram; ensaio sintético
confirmou três POSTs simulados e apenas duas mensagens. Sem envio real, VPS ou
novos containers. APK Debug gerado e bundles Android/iOS sincronizados; aceite
físico/iOS pendente por indisponibilidade. Detalhes em `docs/fila-offline-texto.md`.

### 24/10/2026 — falha de envio HTTP sem JSON

Tratamento de erro dos provedores WhatsApp passa a persistir falha com código
HTTP quando falta a descrição JSON, evitando bolhas indefinidamente no relógio.
Preserva erro JSON e a proteção contra retentativa/fallback em entrega incerta.
118 exemplos aprovados e ensaio sintético na réplica com rollback e zero envios.
Mensagem original da conversa 17265 preservada, sem reprocessamento retroativo.
Detalhes: `docs/validacao-whatsapp-http-sem-json-20261024.md`. Sem VPS.

### 24/10/2026 — diagnóstico de estado antigo no cache após F5

Reprodução sintética no browser identificou corrida entre HTTP de reconciliação
e confirmação nova do socket: `delivered` pode regredir para `progress`/`sent`
e ser persistido assim no IndexedDB. Corrigido depois de autorização: proteger
recibos confirmados enquanto o HTTP estava pendente sem tornar cache antigo
autoritativo. Corrida repetida no browser preservou `delivered` na memória e no
IndexedDB, com um só ID. 285 testes aprovados e bundles nativos regenerados.
F5 sem concorrência persistiu corretamente; há debounce de 1200 ms no flush.
18 testes existentes passaram, mas não cobriam a corrida. Sem mensagens reais,
alteração no banco ou VPS. Evidência: `docs/diagnostico-cache-status-20261024.md`.

### 24/10/2026 — source_id no cache e ícone antes da API

Corrigida a omissão de `source_id` no snapshot. Recibos entregue/lida agora
renderizam seus checks já com os dados locais completos, sem esperar o HTTP.
294 testes passaram, incluindo primeira montagem dos componentes reais de
recibo/ícone. Playwright confirmou os checks com zero respostas de consulta de
conversa liberadas. Cache legado precisa de uma consulta online para repor o
campo antes omitido, sem apagar histórico ou inventar IDs. Bundles Android/iOS
atualizados. Detalhes: `docs/validacao-cache-source-id-20261024.md`.

### 24/10/2026 — integração do cache e correções de entrega

Publicação solicitada na `feat/agent-voip-webphone`: inclui a base do cache
IndexedDB e sua fila offline/idempotência, dependências das correções de recibos,
ícones e erro HTTP sem JSON. Relatório administrativo de chamadas, ajustes de
artefatos VoIP, layout do prompt nativo e botão de teclado iOS são trabalhos
separados e não fazem parte deste commit. Sem versão nova, deploy ou VPS.
Após autorização, somente o estado da mensagem de teste 2429178 foi regularizado
como falha na réplica; IDs/conteúdo mantidos, sem reenvio ou webhook externo.
Validação final deste escopo: 324 testes frontend e 126 exemplos backend
aprovados; revisão staged sem artefatos gerados, credenciais ou fontes da VPS.

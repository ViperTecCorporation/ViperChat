# Plano: webphone SIP/WebRTC por agente e aba Chamadas

Data: 20/10/2026 — America/Cuiaba. Estado: planejamento consolidado; implementação não iniciada nesta etapa.

Complementa o [levantamento do WhatsApp e do código atual](mapeamento-chamadas-whatsapp-webphone-20261019.md). As decisões abaixo substituem as propostas preliminares desse levantamento quando divergirem.

Contrato do serviço/worker analisado em 20/10/2026: [auditoria de REST, eventos e CDR](auditoria-contrato-voip-cdr-20261020.md). Já existe histórico SQLite/JSON e REST paginado; faltam contrato incremental durável, participações e escopo específico de agente para o aceite completo. Não foi acessada a VPS.

**Ordem definida pelo usuário em 20/10/2026:** implementar primeiro o mecanismo funcional e a interface no ViperChat em dev, usando SIP/WebRTC existente e eventos sintéticos para os contratos futuros. Depois incrementar serviço VoIP e ViperChat com **webhooks, fila persistente, retentativas e recuperação por REST incremental**. Esta atualização reorganiza o planejamento; não inicia a implementação.

## 1. Objetivo e decisões confirmadas

- O serviço VoIP do usuário já integra as chamadas da Meta. O novo webphone ViperChat se conecta a esse serviço por **SIP.js / SIP sobre WebSocket seguro / mídia WebRTC**. Não construir outra integração direta Meta para esse recurso.
- Chamadas deixam de depender da criação ou seleção de uma caixa de entrada Voice/custom. Ramal pertence ao vínculo do agente com um serviço VoIP da conta.
- Administrador pode cadastrar **mais de um serviço VoIP na mesma conta**. Na modal do perfil, selecionar o serviço antes de configurar o ramal.
- Acesso **Chamadas** na sidebar imediatamente abaixo de Conversas.
- Estilo do webphone baseado nas referências extraídas do WhatsApp: controles agrupados/arredondados, contraste, estados de áudio, variantes compacta/completa e organização lista/detalhes. Traduzir isso para componentes Vue/Tailwind e identidade ViperChat, sem incorporar binários, fontes, sons ou SVGs proprietários.
- Desktop: lista à esquerda e detalhes à direita. Mobile: lista em tela inteira → detalhes com Voltar, preservando busca, filtros e rolagem.
- Preservar configurações antigas, histórico, IDs, contatos, mensagens e mídias. Não desligar fluxos legados antes de validar a substituição correspondente.
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

Na segunda entrega, **webhook é o caminho de atualização rápida e REST incremental é recuperação/reconciliação obrigatória**, ambos no backend. Eventos chegam por outbox persistente do serviço, com confirmação de recebimento durável no ViperChat e processamento idempotente. O feed REST de alterações, a acrescentar ao serviço, faz backfill e recupera falhas; não consultar apenas a primeira página/últimos inícios, pois isso perde chamada longa, transferência, gravação tardia e registros sujeitos a prune. A bridge Zapo privada não é uma assinatura ViperChat e não deve receber um segundo consumidor tomando a sessão.

Separar navegador fechado de bridge offline: o serviço já registra chamadas sem o browser; o worker atualmente não reenvia de forma durável chamadas encerradas enquanto a bridge estava indisponível. Prever recuperação do produtor, sem prometer cobertura que o código ainda não oferece. O aviso textual de chamada e a fila de notas privadas de gravação não substituem CDR.

A gravação pertence ao serviço local/S3; a aba nova usa referência/stream autenticado e não gera automaticamente outra cópia em Active Storage/S3. Preservar o fluxo de notas privadas existente quando habilitado sem duplicar o áudio pela nova interface.

- Separar `direction` de resultado. Saída não atendida não é a mesma coisa que entrada perdida.
- Estados previstos: iniciando, chamando, atendida/em curso, encerrada, não atendida, perdida, rejeitada, ocupada, cancelada e falha; manter código SIP/motivo original para diagnóstico. Elaborar tabela de tradução com exemplos reais, sem classificar qualquer 487/erro genérico como perdida.
- Duração de conversa começa no atendimento efetivo; tempo tocando pode ser armazenado separadamente. Clique em atender ou criação de INVITE não inicia duração de fala.
- Duplicação/retentativa de webhook é idempotente. Evento antigo não reabre chamada terminal; correção posterior só por evidência autoritativa e regra explícita, preservando auditoria.
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

- Mesmo padrão da lista de chats: lista em tela inteira; detalhe em rota/tela própria com Voltar, inclusive botão físico/gesto nativo. Preservar filtros, pesquisa, seleção e rolagem ao retornar.
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

## 7.1. Integração posterior: webhook durável + REST incremental

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

1. Prévia somente leitura por conta: serviços inferidos das caixas, parâmetros comuns, bindings candidatos, fonte da credencial e conflitos. Nunca imprimir os valores dos segredos na prévia.
2. Duas caixas com o mesmo domínio não são necessariamente o mesmo serviço; comparar configuração efetiva e exigir confirmação de conflitos. Preferir serviços separados quando a identidade não for inequívoca.
3. Credencial de `InboxMember` é a precedência observada hoje; não ignorá-la em favor de um perfil mais recente sem decisão. Perfil global só é candidato quando a conta/central corretas forem demonstradas; jamais replicar esse segredo para todas as contas/serviços do agente.
4. Migração aditiva e idempotente por conta, com origem legada registrada, dry-run e aprovação antes de escrita. Reexecução não duplica serviços, bindings ou chamadas. Não apagar caixas, usuários, contatos ou registros antigos.
5. Não apagar configuração legada na primeira release. Ao ativar o novo binding, um único responsável registra o ramal; desligar o auto-register antigo apenas para esse vínculo migrado. Não manter dois clientes concorrentes usando as mesmas credenciais.
6. Clientes antigos não devem atualizar/zerar os novos bindings por omissão de campos. Estabelecer versões mínimas e gate de migração para não habilitar registro legado e novo ao mesmo tempo. A tela antiga deve orientar a nova localização quando houver migração.
7. Ativação por feature flag da conta e agente piloto; sem migrar contas sem opt-in. Rollback de UI/registro separado de rollback de dados; não restaurar banco automaticamente sobre tráfego novo. Preservar chamadas registradas após ativação.
8. Histórico legado permanece na origem e pode ser lido sem acoplar nova sessão a inbox. Não alterar chamadas oficiais existentes ou fluxos de mensagem/coexistência como parte desta migração.

## 10. Dependências e atualização

`package.json:116` e o importer do `pnpm-lock.yaml` fixam `sip.js: 0.21.2`. Na consulta de 20/10/2026, o [repositório oficial de releases](https://github.com/onsip/SIP.js/releases) também marca 0.21.2 como Latest. **Manter a versão fixada como baseline; não há atualização identificada a executar só pela idade do código.**

O guia oficial de [transferência](https://sipjs.com/guides/transfer/) é referência para a revisão de REFER; a confirmação operacional depende da central. Auditar as chamadas usadas pelo cliente contra a API da versão fixada, em especial DTMF, eventos de registro e gestão de mídia.

Antes de mudar dependências: conferir versão resolvida/instalada e compatibilidade com Vite, Vue e Capacitor; revisar advisories e testes. Não executar upgrade global de pacote/lockfile. Uma atualização realmente necessária entra em mudança isolada, com justificativa e rollback. Preservar dependências de Twilio/Meta enquanto houver uso por fluxos legados; não removê-las pelo novo foco SIP.

## 11. Contratos propostos de API (a criar, não existentes)

Base account-scoped `/api/v1/accounts/:account_id`:

| Recurso proposto | Operação |
| --- | --- |
| `/voip/services` e `/:id` | CRUD administrativo, com desativação/arquivamento e metadados sem segredos. |
| `/voip/profile` | Lista bindings do próprio agente e seleção ativa; salvar binding vinculado a serviço autorizado. |
| `/voip/registrations/bootstrap` | Credencial efêmera/configuração efetiva do binding autorizado, sem cache. Não cria chamada. |
| `/voip/calls` e `/:id` | Histórico, filtros, detalhe e intenção explícita de chamada, com idempotency key. Não prometer originação server-side se ela for feita no SIP.js. |
| `/voip/calls/:id/actions` | Ações com escopo/estado/capacidade; ação deve ter um único executor de sinalização. Não duplicar BYE/INVITE no backend e no SIP.js. |
| Ingestão de eventos do serviço | Contrato autenticado próprio, conta/serviço resolvidos por credencial confiável, não por `account_id` arbitrário do payload. |

Na primeira entrega, preparar envelope/reconciliador e testes sintéticos, mantendo recepção externa/sincronização autoritativa desabilitadas enquanto não integradas. Persistir observações SIP autenticadas por agente em caminho distinto do webhook externo: relato do cliente não equivale a evento assinado do serviço. Na segunda, ativar recepção durável, processamento, checkpoint e recuperação REST conforme seção 7.1. Não exigir mudanças em produção para testar contratos sintéticos em dev.

Os nomes finais dependem das convenções do projeto e do adaptador do serviço. Manter contratos antigos para consumidores existentes enquanto houver compatibilidade autorizada. Eventos realtime devem publicar mudanças de estado, nunca segredos.

## 12. Fases e critérios de saída

| Etapa | Entrega | Critério para avançar |
| --- | --- | --- |
| 1A — ViperChat: contratos e cadastro | Usar o mapeamento existente; modelos, políticas, múltiplos serviços, modal do perfil e prévia de migração. Preparar interfaces futuras com fixtures sintéticas, sem alterar serviço/worker. | Isolamento por conta/serviço, persistência da escolha, credenciais protegidas e conflitos explícitos. |
| 1B — ViperChat: SIP/WebRTC | Registro pelo ramal do agente, áudio, ações, concorrência e reconexão com o serviço já existente. | Testes sintéticos; depois registro/chamadas controladas quando autorizados. Não depender de webhook novo para o fluxo conectado. |
| 1C — ViperChat: aba e histórico observado | Sidebar, lista/favoritos/detalhes/discador, compacto/completo, mobile com Voltar; backend persiste observações SIP com origem e confirmação limitada. | UI responsiva, navegação sem perder sessão, IDs estáveis; falta de sincronização do serviço informada. Não garantir histórico offline. |
| 1D — Aceite ViperChat em dev | Validar SIP, observações, perfis, transporte e regressões com sintéticos e chamadas autorizadas. | Áudio bidirecional e estados do fluxo conectado; lacunas de navegador fechado/replay não escondidas. É aceite funcional parcial, não de CDR completo. |
| 2A — Serviço/worker: entrega confiável | Implementar outbox/webhooks, retries/quarentena, feed REST incremental, escopo/participações e gaps de desconexão/capacidade da auditoria. | Persistência após reinício, IDs/revisões, captura correta de ramais/tempos e recuperação sem duplicar ligação. |
| 2B — ViperChat: integrar eventos/CDR | Recepção assinada e durável, reconciliador único, checkpoint REST/backfill e projeção de histórico autoritativo. | Navegador fechado, falha de webhook, retomada e atualizações tardias preservadas; observar regras de retenção e associação exata com registros locais. |
| 2C — Aceite integrado completo | Testar falhas/replay, múltiplos dispositivos e transferências ponta a ponta em dev. | Perdidas/atendimento/duração/participações corretos e mídia não duplicada. Testes bloqueados na auditoria anterior precisam ser efetivamente executados antes desse aceite. |
| Publicação de cada entrega | Backup, prévia/aprovação, flag, imagem/builds e monitoramento/rollback. | Autorização separada do usuário; primeira entrega, se publicada antes da segunda, mantém aviso de cobertura parcial. Sem deploy automático por concluir o plano. |

**Próxima implementação: 1A → 1B → 1C → 1D no ViperChat em dev.** As pendências do serviço não são pré-requisito para começar esse trabalho; são obrigatórias para o aceite 2C de histórico completo. Nenhuma etapa autoriza mexer na VPS por conta própria.

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
- Segunda entrega: reinício com fila pendente, indisponibilidade HTTP/429/5xx, backoff, autenticação inválida/quarentena, mesmo eventId entregue repetidamente, crash após persistir inbox antes de enfileirar, cursor REST não avançado por webhook fora de ordem e recuperação após cursor expirado. Replay nunca dispara ações SIP.

## 13. iOS/Android: preparação agora, implementação nativa depois

Compartilhar agora domínio de chamadas, ações idempotentes, IDs e estados. Separar motor de transporte da UI para um adaptador nativo futuro usar os mesmos registros sem abrir uma segunda ligação.

Integração futura deve levantar CallKit/PushKit no iOS e Telecom/ConnectionService/Core-Telecom e notificações/execução em segundo plano no Android, conforme versões e arquitetura adotadas. Serviço precisa notificar/rotear ao dispositivo e coordenar atendimento único entre web e nativo. Isso não está implementado nem garantido pelo SIP.js/Capacitor atual.

Mudança futura de frontend compartilhado exige sync dos bundles Android e iOS e validação em aparelhos quando disponíveis, conforme AGENTS.md. Planejamento/documentação desta etapa não requer builds; não foi feita validação de chamada nativa ou segundo plano.

## 14. O que está fechado e o que falta verificar

Fechado para desenvolver: arquitetura sem inbox, ramal por agente/serviço/conta, cadastro administrativo múltiplo, modal de seleção, migração conservadora, sidebar e organização desktop/mobile, estilo-base extraído e testes de aceite.

Contrato atual de eventos/CDR e REST mapeado localmente na auditoria anexa; não é mais necessário investigar sua existência. A ordem agora é concluir primeiro o mecanismo ViperChat/SIP e a interface em dev, com histórico observado identificado como parcial; depois integrar os webhooks com fila persistente/retentativas e REST incremental. Gaps P0 do serviço permanecem obrigatórios para histórico autoritativo completo, mas não impedem iniciar a primeira entrega. Validar WSS/ICE e autorização antes de chamadas reais. Prints de discador/webphone/menu de áudio refinam aparência sem bloquear lista/detalhes. Uma conexão ativa por agente no ViperChat é o recorte proposto, preservando múltiplos registros autorizados na central.

Nesta etapa somente documentação foi criada/atualizada. Não alterados pacotes, código funcional, credenciais, bancos, serviços, configurações da conta, dispositivos ou VPS; nenhuma ligação/registro real, commit/push ou build. Sem temporários de binários ou cópias volumosas.

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

Na primeira execução remota do PR de correção, o lint detectou oito comentários redundantes `Rails/Output` que ainda estavam nos fontes, mas já haviam sido removidos na cópia temporária local. A correção remove esses comentários sem mudar o comportamento dos scripts; a revalidação deve usar uma exportação limpa do commit para evitar divergência entre fonte enviada e runtime de teste.

O reinício local do Docker Desktop foi autorizado após sobrecarga; os serviços dev voltaram e o endpoint `/api` respondeu HTTP 200. Nenhuma VPS foi acessada/alterada. Nesta correção o frontend funcional, as dependências e os bundles nativos não mudaram; não foram gerados APK/Archive nem feitos novos testes em aparelhos. A integração em `4.16.0` depende ainda da confirmação dos checks desta correção no GitHub.

# Importação de histórico Gmail — próximo host patch

## Operação

Antes de **Entrar com Google**, escolher: somente novas mensagens (padrão),
7 dias, 30 dias, 3, 6 ou 12 meses. Não existe opção de histórico ilimitado.
A mesma seleção fica nas configurações de uma caixa Google já conectada, com
botões para iniciar, interromper e atualizar o progresso. Somente administradores;
início/interrupção respeitam a flag de gestão de caixas de entrada.

Somente a pasta INBOX, incluindo lidas e não lidas. Não importa arquivados,
enviados, spam ou lixeira. O período considera INTERNALDATE do IMAP, não o cabeçalho
Date enviado pelo remetente. O limite é de meses de calendário no início da tarefa.

O formulário leva a opção em estado OAuth assinado e com validade de 15 minutos,
vinculado à conta. Clientes antigos sem a opção e caixas existentes mantêm o fluxo
anterior; reconectar não apaga a configuração nem o progresso já armazenado.

Uma caixa nova com “somente novas” ganha um marco de recebimento no instante da
conexão: e-mails com INTERNALDATE anterior não entram no fluxo normal. Para caixas
já conectadas, a seleção de histórico não muda retroativamente esse marco.

## Processamento

- Usa o agendador de e-mails existente, sem nova fila, cron ou migration.
- Primeiro recebe mensagens recentes; depois importa até 50 mensagens históricas
  de um dia por execução, retrocedendo até a data escolhida. Dias vazios avançam
  uma vez por execução. Doze meses podem levar horas ou mais conforme o volume.
- Tempo máximo de 60 segundos por lote histórico; cursor UID e UIDVALIDITY gravados
  após cada item examinado. Cancelar pode permitir finalizar o item já em andamento.
- Mesmo mutex por inbox utilizado pelo recebimento normal, deduplicação por
  Message-ID e rastreador de mensagens excluídas existentes. Não reenvia e-mails.
- Status running/completed/stopped/failed, dia em processamento e itens examinados.
  “Examinados” inclui duplicados e itens ignorados: não representa novas conversas.
- Falha interrompe a importação e expõe somente a classe do erro. Após corrigir a
  conexão, iniciar novamente reexamina o período sem recriar mensagens existentes.
- O pipeline normal cria conversas, atividades, automações e notificações; importar
  muitos e-mails pode gerar muitas notificações. Não é uma importação silenciosa.
- Progresso em channel_email.provider_config, preservado durante refresh OAuth com
  lock de linha. A API de progresso não retorna tokens.

## Implantação e validação

Preparado localmente, não aplicado na VPS nesta tarefa. Não executar importação
em produção automaticamente ao implantar. Para validar, usar uma caixa de teste
com lidas/não lidas e mensagens dentro/fora do período, iniciar com 7 dias, conferir
progresso, cancelamento, reinício e ausência de duplicação. Conferir o consentimento
https://mail.google.com/; configurar períodos não concede permissões Google.

Backup e reversão devem usar o manifesto do pacote combinado; preservar os patches
anteriores (multipart, SuperAdmin, fotos, localização/Places e notificações).
Reverter o código interrompe o consumo de histórico; mensagens já importadas não
devem ser apagadas na reversão. Não houve mudança no schema do banco.

## Validação local desta entrega

- 51 exemplos RSpec e 3 testes Vitest aprovados; RuboCop dos seis arquivos
  principais sem infrações; ESLint sem erros (dois avisos de chaves i18n dinâmicas).
- Builds web e mobile concluídos; bundles sincronizados para Android e iOS;
  Android assembleDebug concluído.
- Nenhum dispositivo ADB conectado. Mac de desenvolvimento indisponível na porta
  SSH: não houve build nativo nem teste em aparelho iOS.
- Validação visual responsiva e fluxo real com Gmail ainda pendentes. Testes
  automatizados usam respostas IMAP simuladas, não e-mails de produção.
- Pacote complementar: `C:/Users/caita/.codex-tmp/viper-gmail-history-hostpatch-ready.tar.gz`.
  Requer a base do patch Places/notificações anterior; preflight valida hashes.
  Não aplicar sobre outra imagem ou após recriação dos containers sem reavaliar a base.

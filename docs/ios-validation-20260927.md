# Validação iOS — 27/09/2026

Ambiente: macOS 15.7.9, Xcode 26.2, simulador iPhone 16e com runtime iOS 26.3.
Projeto isolado no Mac: `/Users/rodrgo/Developer/ViperChat-ios-validation-20260927`.
O projeto anterior em `Developer/ViperChat` não foi substituído.

## Compilação e abertura

- Frontend e dependências Capacitor atuais, incluindo ajustes de FPS e SD.
- Reutilizada a configuração Firebase já existente no Mac para o mesmo bundle ID;
  nenhum segredo incluído neste relatório.
- Build Debug para `iphonesimulator` concluído. Build final com
  `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` (assinatura local de simulador).
- App instalado e iniciado, preservando a sessão existente. A lista de conversas
  renderizou no simulador. Não houve envio de mensagens reais.
- Houve tela branca na tentativa inicial sem assinatura, junto a avisos do WebKit
  sobre leitura de entitlements. A abertura passou na tentativa assinada; isso não
  isola completamente a causa da falha inicial.

## Teste de vídeo: não aprovado

Foi utilizada instrumentação temporária somente na cópia de validação do Mac,
com arquivo sintético de 4 segundos, 480×1014, 59,94 FPS e áudio AAC, sem upload.
O teste executou o worker empacotado dentro do WKWebView do app.

- O WKWebView expôs `VideoEncoder` e `VideoDecoder`, em contexto seguro.
- A tentativa HD excedeu o timeout de 120 segundos do diagnóstico.
- Não foi obtido resultado válido SD; a sequência foi interrompida para restaurar
  a instalação normal. Nenhum arquivo iOS foi aprovado como passthrough.
- Os logs de `com.apple.WebKit.GPU` registraram falhas XPC de bootstrap
  (`No such process`). Não foi comprovado se a causa é a VM/runtime ou o pipeline
  do editor. A mera presença das APIs não comprova funcionamento do encoder.
- O teste não valida aceleração de hardware ou desempenho de um iPhone físico.

A instrumentação e os assets de diagnóstico foram removidos do projeto/bundle
final; fontes funcionais do editor não foram modificadas nesta tarefa.
Não foram validados envio ao WhatsApp, upload S3, push APNs, câmera/microfone,
vídeo longo ou assinatura/distribuição para aparelho físico.
ViperChat e ViperConnect locais permaneceram ativos; produção não foi alterada.

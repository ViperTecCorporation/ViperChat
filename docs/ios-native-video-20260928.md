# Exportação nativa de vídeo no iOS — 2026-09-28

## Retorno do teste físico

Após a entrega da correção de tamanho, o usuário confirmou que o problema foi
resolvido no iPhone e autorizou commit/push das alterações. Não foi fornecido
nesta rodada um novo laudo ffprobe ou log `mode=passthrough`; a confirmação do
envio não é registrada como prova independente desses dois critérios.

## Correção da finalização após teste físico da 4161226

HD e SD retornaram `finalize: App.NativeVideoError (2)`. O código agrupava tamanho
zero com excesso de 256 MiB e consultava repetidamente `URL.resourceValues` no
mesmo URL. Reproduzido no Mac: consulta inicial em arquivo vazio, gravação de
4096 bytes e nova consulta no mesmo URL ainda retornou zero. O tamanho real
obtido por `FileManager.attributesOfItem` foi 4096. Isso comprova o defeito de
cache; não comprova que o arquivo específico do iPhone estava vazio.

O exportador consulta agora o tamanho atual pelo caminho, durante a exportação
e depois de `finishWriting`. Vazio final é `INVALID_VIDEO`, excesso real continua
`VIDEO_TOO_LARGE`, e falhas de leitura não são convertidas silenciosamente em zero.
O diagnóstico inclui bytes medidos e teto; exige também reader concluído antes
da finalização, além da verificação existente do writer concluído. Perfis, cores,
FPS, corte e áudio não foram alterados nesta correção.

`ios/NativeVideoSizeTests.swift`, compilado com o exportador real no Mac, passou:
arquivo crescendo, vazio durante/final, exatamente 256 MiB, excesso durante/final,
substituição do arquivo, arquivo ausente e diagnóstico em bytes. Arquivos grandes
são esparsos, sem gravar 256 MiB de conteúdo. Os 16 testes JS do adaptador e
validador passaram. Isso não substitui exportação real no iPhone/ffprobe.

Archive `4161227`: `/Users/rodrgo/Library/Developer/Xcode/Archives/2026-09-28/ViperChat-sizefix-4161227.xcarchive`.
Compilação e codesign estrito/deep concluídos com exit 0; app e ShareExtension
com CFBundleVersion 4161227. Fonte no Mac conferida por SHA-256 igual ao checkout.
Sem upload ao TestFlight nesta execução. Android/Web não modificados.

## Implementação

`NativeVideoPlugin.swift` registra o adaptador Capacitor `NativeVideo`. Somente
o app iOS usa esse caminho; Android e Web/PWA mantêm o worker WebCodecs existente.
Não há alteração nos botões, legenda, qualidade enviada ao ViperConnect ou upload.

- AVAssetReader/VideoComposition realiza rotação nos pixels, escala proporcional
  com dimensões pares, sem ampliação, e cadência até 30 FPS.
- Saída do compositor: NV12 **video range**, verificada em cada buffer. Isso
  solicita conversão dos pixels, não troca apenas a identificação de full range.
- AVAssetWriter usa H.264 Main 4.0, BT.709, SAR 1:1, MP4 com otimização de rede
  (faststart). Sem rotação residual no writer.
- HD: até 1280x720 / 720x1280, teto 2,5 Mbps; SD: até 854x480 / 480x854,
  teto 1,2 Mbps. O bitrate solicitado usa 80% do teto para margem e DataRateLimits.
- Áudio AAC-LC, 48 kHz, mono preservado, no máximo estéreo; HD 96 kbps,
  SD 64 kbps. Mudo/sem áudio não cria faixa de áudio.
- Corte compartilha intervalo/relógio entre áudio e vídeo; limite de 256 MiB.
- CRF e preset x264 não são controles desse encoder nativo. Não declarar
  equivalência desses controles nem garantir teto apenas pelo valor solicitado.

Após exportar, `inspectVideoExport` verifica os bytes reais: faixa no SPS,
FPS, bitrate, dimensões, SAR, rotação, áudio e faststart. Arquivos reprovados
continuam bloqueados com detalhes em tela e opção explícita do original ao worker.
Erros nativos mostram etapa e domínio/código, sem expor caminhos do usuário.

### Correção de faixa do contêiner (mesma build 4161226, ainda não publicada)

Os dois originais HD/SD fornecidos pelo usuário reproduziram uma aprovação
incorreta: SPS sem VUI retornava faixa limitada por padrão, mas o `colr/nclx`
do MP4 declarava full range (`0001000d000180`). O decoderConfig de Mediabunny
expõe essa declaração em `colorSpace.fullRange`; ffprobe detectou `yuvj420p/pc`.

`avcColorRange` agora cruza SPS e colorSpace. Qualquer indicação full range
reprova a saída, inclusive quando as duas fontes discordam. SPS ilegível continua
reprovado mesmo se o contêiner declarar faixa limitada. Sem retagging de pixels.
O resultado guarda `spsFullRange`, `declaredFullRange` e a faixa efetiva.

Reteste dos dois arquivos reais: `valid=false`, exclusivamente `FULL_RANGE`,
`actual=true`, `expected=false`. Foram removidos novamente após o teste; os
links assinados e as mídias não são guardados no repositório. Os testes permanentes
usam apenas SPS sintético e metadados equivalentes, incluindo conflito inverso.
Essa correção é compartilhada por Web, Android e iOS. Não comprova ainda a
conversão nativa no iPhone: mantém-se o aceite real descrito abaixo.

## Memória, cancelamento e limpeza

Transferência JS/nativo em blocos de 512 KiB, nunca uma string base64 do vídeo
inteiro. O resultado ainda é materializado como File para o uploader existente.
Temporários pertencem exclusivamente a `tmp/viper-video-export/<UUID>` no app.
São removidos no finally, inclusive em falha/cancelamento, e resíduos de execução
interrompida são removidos quando o plugin carrega novamente. Não acessa nem
remove a biblioteca de fotos, arquivos originais ou uploads do usuário.

## Validação e limites

- 62 testes focados passaram: adaptador, cancelamento, diagnósticos, worker web,
  validação do arquivo, editor, perfis, faixa de cor, FPS e faststart. ESLint focado passou.
- Build nativo Vite e sync das duas plataformas concluídos. Android assembleDebug
  passou e APK foi instalado no S10e (`adb install --no-streaming -r`: Success),
  preservando os dados; app iniciado. Fluxo completo de vídeo no Android não foi
  exercitado nesta rodada.
- Archive iOS `4161226` criado em
  `/Users/rodrgo/Library/Developer/Xcode/Archives/2026-09-28/ViperChat-native-video-4161226.xcarchive`.
  Archive exit 0, codesign --verify --deep --strict exit 0, CFBundleVersion conferido.
  Aberto no Organizer; não enviado ao App Store Connect nesta execução.
- Compilação iOS Release sem assinatura passou durante o desenvolvimento.
- O executável de teste `ios/NativeVideoSmoke.swift` compila com o mesmo motor,
  sem Capacitor, usando `swiftc -parse-as-library` no Mac.
- Entrada sintética confirmada por ffprobe: H.264 590x1280, 60 FPS,
  `yuvj420p`/faixa completa e AAC. Exportação SD com corte na VM falhou na etapa
  `encode`: AVFoundation -11800, suberro VideoToolbox -12904 (allocation failed).
  Não houve arquivo convertido válido para inspeção de saída com ffprobe.
- A causa da falha na VM não foi comprovada no iPhone. Compilar não equivale a
  validar conversão, cor ou aceleração no aparelho.

## Aceite obrigatório no iPhone

Instalar a nova build e testar HD/SD, com/sem corte, áudio/mudo, paisagem/retrato,
vídeo de 60 FPS e fonte full range. Conferir cor visual, sincronização e cancelamento.
Inspecionar o arquivo exportado com ffprobe e confirmar no ViperConnect
`mode=passthrough` e bytes inalterados. Isso permanece pendente até teste real;
nenhuma mensagem foi enviada para validar essa implementação.

Pacotes de transferência, vídeo sintético, cópias de entrada dos testes e executável
temporário foram removidos do Windows/Docker/Mac após uso. Preservados fontes,
logs pequenos de diagnóstico, APK e Archive de entrega. Nenhum serviço local foi parado.

### Archive corrigido, mantendo 4161226 por solicitação do usuário

- Nova rodada: 65 testes permanentes aprovados e dois testes adicionais com os
  originais reais, rejeitados apenas por FULL_RANGE. ESLint focado aprovado.
- Build Vite e sincronização Android/iOS aprovados. APK recompilado, reinstalado
  no S10e sem apagar dados, app confirmado em primeiro plano. Não houve envio real.
- Usar **`ViperChat-colorfix-4161226.xcarchive`**, em
  `/Users/rodrgo/Library/Developer/Xcode/Archives/2026-09-28/`.
  Este substitui para envio o Archive anterior `ViperChat-native-video-4161226`.
  Archive exit 0, assinatura verificada exit 0; app e extensão com CFBundleVersion
  4161226. Os hashes SHA-256 dos bundles MediaEditor e dashboard no Archive foram
  comparados com os do build local e são idênticos.
- Aberto o Archive corrigido no Xcode. Sem validação Apple/upload nesta execução;
  teste físico da conversão no iPhone e passthrough continuam pendentes.

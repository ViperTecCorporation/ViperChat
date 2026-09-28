# Editor de mídia — teste inicial local

O progresso do upload aparece dentro da modal (preparação, percentual/MiB e
finalização), incluindo upload multipart, direto e POST com arquivo. O 100%
representa transmissão, não entrega ao WhatsApp. A finalização aguarda o servidor.

Fast start: o muxer usa `fastStart: 'in-memory'` (moov antes do mdat). Antes de
preservar um original, o worker agora verifica essa ordem; arquivos sem fast start
passam pela preparação. Não há garantia dos controles x264 CRF 23/27, preset
veryfast ou VBV no WebCodecs. O editor solicita CBR com margem e valida a saída;
não declara equivalência exata com x264. O patch versionado de Mediabunny 1.60.0
grava `pasp` também para pixels quadrados. A saída é reaberta para conferir SAR
explícito 1:1, H.264 8-bit 4:2:0 pelo SPS, áudio AAC-LC, dimensões, FPS médio,
rotação, bitrate de todos os pacotes e fast start antes de liberar o arquivo.

Vídeos enviados pelo editor ao ViperConnect persistem a escolha em
`content_attributes.video_quality` e incluem `video.quality: "sd" | "hd"`
no payload do provedor, inclusive quando a conversão fica para o servidor.
Imagens, outros provedores e mensagens antigas sem a escolha não recebem esse campo.

## Onde testar

Na conversa WhatsApp/ViperConnect, anexe JPEG, PNG, WebP ou vídeo MP4/MOV/WebM/MKV
pelo clipe do editor compacto, editor normal, colagem ou compartilhamento nativo.
O editor abre antes do upload quando não há documentos/contatos anexados.
Notas privadas, outros canais, áudio, GIF e documentos mantêm o fluxo anterior.
Arquivos HEIC ainda seguem o fluxo de documento, sem edição.

O rodapé permite adicionar mais arquivos, selecionar miniaturas e remover itens.
O texto já digitado fica somente no primeiro anexo; cada item tem legenda própria.
Cancelar preserva o rascunho original. Não há upload ao abrir/editar/cancelar.
O lote suporta até 20 arquivos e 512 MiB de entrada. Envie lotes menores no celular.
O envio é sequencial, na ordem das miniaturas. Trocar conta, conversa ou modo fecha
o editor e impede novos envios pelo contexto antigo.

## Ferramentas

- Imagem: desenho com espessura de 1 a 32, seletor de emojis com busca, texto
  com dez opções de fonte, negrito, itálico, sublinhado e sombra; girar 90 graus
  e desfazer até cinco edições. As cópias são locais;
  o arquivo original do dispositivo não é sobrescrito.
- Corte: ajuste as alças nos cantos/bordas, mova a área e confirme em Aplicar corte;
  Cancelar corte não modifica a imagem.
- Texto/emoji: use Adicionar texto ou escolha um emoji. Toque no objeto para
  selecionar, arraste para mover e use as alças para tamanho/rotação. Edite o
  campo, fonte/cor e confirme Aplicar ao selecionado; a lixeira remove o objeto.
  As camadas permanecem editáveis após cortar, girar e trocar de anexo durante
  esta sessão. Não é possível editar separadamente texto já gravado numa foto
  original ou reabrir camadas depois que a mensagem foi enviada.
  As fontes são do sistema: quando uma não existe no dispositivo, o navegador
  usa uma substituta. Formatação/fonte/cor se aplicam diretamente ao selecionado;
  para alterar o conteúdo do texto, use Aplicar ao selecionado.
- O envio usa o mesmo botão circular do compositor compacto.
- Zoom de prévia: pinça com dois dedos ou lupas (+/−), de 100% a 400%, com
  arraste para navegar. Toque na porcentagem para voltar ao enquadramento inicial.
  É somente visualização: não altera camadas, recorte, resolução nem o arquivo.
  Durante a ampliação, a edição fica suspensa para evitar mover texto sem querer.
- Vídeo: prévia, intervalos de início/fim em segundos, remover áudio e SD/HD.
- Download salva a imagem editada atual; para vídeo salva o original (não o corte).
- A barra superior pode ser deslizada horizontalmente em celulares estreitos.
- Sem IA, visualização única, biblioteca de stickers ou reordenação nesta versão.

## Processamento

Konva/Canvas fazem a edição da imagem. A exportação final usa JPEG quando é
necessário reduzir/normalizar; transparência vira fundo branco nessa conversão.
HD limita o lado maior a 2560 px; SD a 1600 px, sem ampliar. Esses são perfis
do aplicativo, não reprodução dos parâmetros proprietários do WhatsApp.

Mediabunny/WebCodecs rodam em Web Worker, carregado somente quando necessário.
HD: até 1280×720 ou 720×1280; SD: até 854×480 ou 480×854. Mantém proporção, não
amplia, gera MP4/H.264 e AAC 48 kHz, preservando mono e limitando a dois canais.
Áudio: 96 kbps no HD, 64 kbps no SD. Preserva FPS quando a média de entrada é
até 30; acima disso converte para 30 fps. Dimensões são arredondadas para pares
(por exemplo, 16:9 em SD pode resultar em 852×480).
Se o encoder AAC do dispositivo não aceitar 64 kbps, usa 96 kbps com aviso na
modal, sem remover áudio nem alterar o perfil de resolução SD.
Tetos do bitrate médio de vídeo medido: 2,5 Mbps (HD) / 1,2 Mbps (SD), sem
tolerância extra de 5%. Solicita CBR inicialmente a 80% do teto. Android 12 no
S10e elevava VBR SD para 1.472.256 bps por política de qualidade mínima, mesmo
com alvo menor. CBR evita esse comportamento no teste realizado. Se houver
excesso, faz apenas uma nova tentativa com alvo reduzido conforme a medição;
se continuar fora do contrato, bloqueia e oferece processamento no servidor.
Isso não é garantia de pico instantâneo/VBV nem de CRF do x264.
Entrada até 256 MiB. A saída deve caber no menor limite entre o upload da caixa
e 256 MiB (entrada do worker ViperConnect). Se ultrapassar, mantém o arquivo e
oferece SD/corte, sem reduzir qualidade automaticamente. Não há meta de 15 MiB.

MP4/H.264/AAC compatível com dimensões, FPS e bitrate do perfil selecionado,
sem cortes/mute e dentro do limite de upload é preservado. Isso também vale
para SD e arquivos maiores que 15 MiB. Em HD, 1080p agora é reduzido para 720p.
Áudio HD e SD aceita até 96 kbps + 5%; vídeo não tem tolerância extra.
O servidor continua responsável por validar o arquivo;
não foi alterado o worker do ViperConnect nesta tarefa. Validar no teste integrado
que ele reconhece a saída e não faz conversão redundante. O selo HD do WhatsApp
não é garantido por essa opção de qualidade.

O aviso `VIDEO_TRANSCODED` do status é exibido na mensagem original como aviso
de compatibilidade, sem botão de tentar novamente, regressão de status ou reenvio.

Suporte a codecs depende do navegador/dispositivo. Se não puder converter sem
perder áudio/vídeo, não faz upload. O operador pode escolher explicitamente enviar
o original ao worker; essa escolha descarta cortes e remoção de áudio.
Cancelar preparação encerra o Worker. Durante upload/envio, aguarde; não há
cancelamento garantido de uma mensagem que já foi entregue à API.

## Envio e falhas

Usa os mesmos adaptadores de upload direto/multipart/indireto existentes. Somente
arquivos preparados são enviados. Se upload falhar, mantém o item para tentativa.
Após criação da mensagem otimista, o editor nunca recria esse item: falha HTTP
fica na bolha existente e o retry pertence a ela. Os demais anexos permanecem no
editor. Não foi implementada idempotência nova no backend.

## Plataformas e validação

### Validação da proteção de exportação — 27/09/2026

**Atualização SD (posterior aos testes abaixo):** corrigida a faixa de cor por
conversão real de pixels, após redimensionamento e ajuste de FPS. O Canvas fornece
sRGB; a preparação ajusta a curva de transferência e converte para BT.709 I420
limitado, com amostragem cromática 2×2. Não é uma troca isolada de tags/SPS.
Aplicado somente a SD; a validação final continua obrigatória.

Teste no S10e com vídeo sintético vertical de 4 segundos a 59,94 FPS e áudio:
SD exportado 404×854, `yuv420p`, faixa `tv`, FPS médio/nominal 30, SAR 1:1,
958.548 bps de vídeo e AAC-LC 64.001 bps, 48 kHz, estéreo. Serviço local do
ViperConnect retornou `reused=true`, `transcoded=false`, SHA-256 inalterado.
Desktop também aceitou o SD. 66 testes passaram. O processamento de cor custa
CPU no dispositivo; desempenho em vídeo real longo e iOS físico ainda não
foram validados. Nenhuma mensagem real ou objeto S3 foi enviado nestes testes.
As referências à limitação SD abaixo descrevem o diagnóstico anterior à correção.

Correção posterior do FPS: o editor passou a examinar todos os timestamps,
incluindo a cadência máxima e a estimada, em vez de usar somente a média dos
pacotes. A conversão sempre define uma cadência de saída até 30 FPS. A saída
é verificada novamente; 24/25/29,97 FPS constantes não são elevados a 30.
Isso não implementa o algoritmo interno de `r_frame_rate` do ffprobe, portanto
a validação independente pelo worker continua necessária.

Teste sintético vertical de 4 segundos, 480 × 1014 a 59,94 FPS: no S10e,
HD saiu 480 × 1014 e SD 404 × 854. O ffprobe confirmou `avg_frame_rate=30/1`
e `r_frame_rate=30/1` em ambos. HD passou na validação; SD foi bloqueado pelo
SPS full-range (`yuvj420p`), não pelo FPS, mantendo a opção explícita do worker.
Desktop HD/SD também passaram na validação. Este teste foi sem áudio; a
cobertura de áudio da etapa anterior permanece, sem alegar teste deste arquivo
específico do cliente ou entrega no WhatsApp.
O HD produzido no S10e também passou pelo serviço local real do ViperConnect:
`reused=true`, `transcoded=false`, SHA-256 inalterado, sem S3/envio real.
Após o ajuste de FPS, 61 testes focados de frontend passaram.

Teste real com vídeo sintético de 6 segundos no Edge desktop e WebView do
Samsung S10e (Android 12). Desktop: HD 2.037.280 bps e SD 977.009 bps,
SAR explícito 1:1, MP4 faststart, H.264 8-bit 4:2:0 limitado. No S10e,
CBR controla o bitrate, mas o encoder sinaliza faixa completa no SPS.
Há também divergência entre sinalização SPS e leitura da faixa pelo contêiner
em algumas saídas Android. A validação é conservadora: não retifica apenas
metadados nem declara essas saídas prontas; oferece envio do original ao worker
por escolha explícita, descartando as edições conforme o aviso da interface.

O serviço compilado de preparação do ViperConnect local foi chamado com os
arquivos desktop e armazenamento de teste em disco: ambos retornaram
`reused=true`, `transcoded=false`, mesma chave e SHA-256 inalterado (passthrough).
Isso testa o serviço real, não uma entrega WhatsApp nem uma fila de produção.

Assim, passthrough no Android não está garantido nesta etapa. CRF/VBV/preset
x264 não são controles garantidos pelo encoder WebCodecs. Não há motor nativo
Media3/AVFoundation implementado nesta alteração.

53 testes focados do frontend passaram, incluindo teto estrito, SAR, SPS,
tentativa limitada de bitrate, fallback explícito e aviso VIDEO_TRANSCODED.
17 exemplos backend do tratamento de avisos passaram em banco de teste.
Os testes de exportação não enviam mensagens reais, não usam S3 e não substituem
um teste completo de vídeo longo ou a confirmação de entrega no destinatário.
Bundles Android e iOS regenerados. APK debug compilado, instalado com preservação
de dados e iniciado no S10e. iOS somente sincronizado: sem compilação ou aparelho
iOS nesta execução. Nada publicado na VPS.

Esta etapa implementa o motor web, inclusive quando executado em WebView.
Ainda não implementa Media3/AVFoundation nem promete o mesmo suporte/performance
dos apps nativos. Os adaptadores nativos são a próxima etapa; a interface/upload
foram separados do motor de preparação para essa evolução.

Testes focados: perfis, preservação do original, legendas, lote, falha de upload,
falha HTTP sem recriação, conta/conversa trocada e ambos os modos de upload.
Resultado: 51 testes passaram (incluindo regressão do editor compacto).
Build web de produção e Android assembleDebug concluídos com sucesso.
Assets iOS sincronizados; compilação iOS e teste em aparelho não realizados.
Smoke no Edge: imagem girada + texto, exportação, vídeo WebM com áudio convertido
em MP4/H.264/AAC, trecho de 1 s, preservação subsequente do arquivo compatível.
Responsividade: 320, 360, 390, 430, 844 (paisagem) e 1366 px. Nenhuma mensagem
real foi enviada nesses testes. Validar ainda aparelhos reais e o destinatário
WhatsApp antes de publicar. Sem publicação na VPS.

Regressão dos controles no Edge: alça do corte redimensionada com mouse,
texto editado em Georgia, arrastado e excluído; texto preservado após corte e
troca de anexo; emoji escolhido no seletor e desenho com espessura 15 verificada.

Vídeo longo: testado MP4 sintético com duração de 900 s e tamanho de 185 MiB
(quadros esparsos, com preenchimento MP4; não é uma transcodificação completa de
15 minutos). O original que já atende ao perfil HD foi preservado, incluindo
os 185 MiB. Conversões curtas reais passaram: 1080p para HD/SD, 60 para 30 fps,
preservação de 24 fps, áudio mono, vídeo vertical e erro de saída acima do limite.
No Edge testado, SD utilizou o fallback de áudio a 96 kbps. Ainda falta validar
um vídeo real longo, consumo de memória em aparelhos e envio ao destinatário.
A dependência mediabunny foi incluída na pré-otimização do Vite local: o log do
primeiro uso mostrou otimização tardia seguida de recarga, interrompendo o editor.

Dependências: Konva (MIT) e Mediabunny (MPL-2.0); preservar os avisos/licenças
de distribuição. O navegador utiliza seus codecs disponíveis.

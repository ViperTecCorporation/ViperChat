# Envio de localização fixa

No editor compacto: **+ → Enviar localização**. Escolha um ponto, pesquise um
empresa (por exemplo, `Vipertec Sinop`) ou endereço e selecione um resultado,
ou solicite a posição atual. Os resultados mostram nome e endereço; a seleção
preenche ambos no envio. Confira e envie.
O nome e o endereço são opcionais. O rascunho de texto permanece no editor.
Não há localização em tempo real nem coleta em segundo plano.

## Configurar no Google Cloud

1. Crie/selecione um projeto e habilite faturamento.
2. Ative **Maps JavaScript API**, **Places API (New)** e **Maps Static API** na biblioteca de APIs.
   A busca usa Text Search (New), somente ao clicar na lupa ou pressionar Enter.
   Não usa Autocomplete nem pesquisa a cada tecla.
3. Em **APIs e serviços → Credenciais**, crie uma chave dedicada ao ViperChat.
4. Restrição de aplicativo: **Sites**. Autorize somente os domínios da instalação,
   por exemplo `https://chatwoot.vipertec.net/*`. Para desenvolvimento, use outra
   chave com os endereços locais e portas necessários.
5. Restrição de APIs: Maps JavaScript API, Places API (New) e Maps Static API.
   Se a chave já existe, inclua Places API (New) na lista permitida: ativar a API
   no projeto sem atualizar a restrição da chave não basta. Geocoding API não é
   mais utilizada por este recurso; preserve-a se outros recursos usarem a chave.
6. Configure cotas nas APIs e alertas de orçamento. Alertas NÃO interrompem
   cobrança; confira quais cotas podem bloquear uso e monitore o consumo.
7. No **Super Admin → Configurações → Google**, preencha
   **Google Maps — chave pública do navegador** (`GOOGLE_MAPS_API_KEY`).
   Também está disponível em Configuração de instalação. Não use a chave de
   OAuth/login. Nunca coloque uma chave de servidor neste campo.
8. Abra novamente a janela de localização para carregar a configuração.

O SDK usa `DEMO_MAP_ID`, identificador de exemplo do Google para marcadores
avançados; não é uma credencial e não elimina cobrança nem a necessidade de chave.
Não é necessário ativar rotas ou Places legado.

## Prévia na bolha de localização

Mensagens enviadas e recebidas mostram uma imagem do Maps Static API com um
marcador nas coordenadas. A imagem é solicitada quando a bolha entra na área
visível, sem carregar o mapa interativo. Cada nova solicitação ao Google pode
consumir a cota da API; reabrir conversas não deve ser tratado como uso gratuito.
Não armazenamos a imagem permanentemente no S3.

A rota `/location-map/preview` usa a mesma chave pública e o mesmo isolamento de
origem do seletor. Inclua Maps Static API nas restrições da chave, além de ativar
a API no projeto. Autorize também o domínio de desenvolvimento ou localhost
quando utilizados. Não faça cache dessa rota no proxy/CDN.

Se a imagem falhar, os detalhes e o link de abrir no Google Maps permanecem.
Com nome/detalhes do local, o link pesquisa esse texto e centraliza nas
coordenadas; sem nome, abre diretamente pelas coordenadas. Nenhuma mudança
é feita no payload enviado à UnoAPI.

O cartão compacto usa uma única área clicável (mapa e detalhes), preserva horário
e status de entrega e não repete o ícone nem a frase de compartilhamento. Sem
detalhes, ou se a imagem falhar, exibe o link “Ver localização”. O layout foi
conferido em larguras de 320, 360, 390, 430, 844 e 1280 px, sem overflow horizontal.

## Busca de empresas e endereços

`Place.searchByText` consulta até oito resultados com os campos `id`, `displayName`,
`formattedAddress` e `location`. A área visível do mapa é uma preferência geográfica
(`locationBias`), não uma restrição: ainda é possível buscar locais de outra cidade.
Não solicita GPS automaticamente. Arrastar o mapa ou usar a posição atual muda
a região preferida nas próximas buscas. Selecionar um ponto manualmente limpa
nome/endereço do estabelecimento anterior para não enviar informações incorretas.

Nome/endereço são exibidos como texto, sem HTML. Respostas de buscas antigas não
substituem uma seleção mais recente. Nenhuma busca envia mensagem automaticamente.
Ausência de resultados e falha da API têm mensagens diferentes; quando houver
falha, conferir ativação de Places API (New), restrições, cotas e faturamento.
O mapa/GPS e a seleção manual continuam disponíveis se apenas a busca falhar.

Text Search tem faturamento próprio, conforme os campos solicitados. Não tratar
a busca como gratuita nem como incluída no carregamento do mapa; conferir a tabela
vigente do Google, configurar cotas e acompanhar consumo antes de liberar amplamente.

## Web, Android e iPhone

O mapa é servido por `/location-map`, um documento HTTPS isolado da instalação.
Isso mantém o referrer no domínio autorizado pelo Google, inclusive dentro dos
aplicativos Capacitor. Não remova as restrições da chave para liberar WebViews.
O app deve alcançar o mesmo servidor atualizado; não basta atualizar só o APK.

O frame não tem sessão de envio nem recebe IDs de conta/conversa. A comunicação
valida a janela e a origem; a página só permite ser incorporada pela própria
origem e pelas origens locais conhecidas dos aplicativos. Não altere globalmente
X-Frame-Options/CSP. Proxy que imponha SAMEORIGIN nessa rota impedirá o uso nativo.
Não faça cache de `/location-map` no proxy/CDN; a resposta usa `no-store`.

GPS usa o navegador na web e `@capacitor/geolocation` no Android/iOS.
Permissões só são solicitadas ao clicar em **Usar minha localização atual**.
Não há watchPosition nem permissão de localização em segundo plano.
As descrições iOS exigidas pelo plugin não significam rastreamento contínuo.

## Envio

- UnoAPI e WhatsApp Cloud: `type: location`, latitude/longitude e nome/endereço.
- Persiste uma única mensagem com anexo `file_type: location`, sem upload.
- Sem opção em nota privada, outros canais ou editor com resposta bloqueada.
- Validação de coordenadas e canal no backend; não mistura localização com arquivos.
- Falhas seguem a bolha de erro/retry existente; não há reenvio automático adicional.
- Nenhuma migration, assinatura Google ou alteração de produção é feita pelo código.

## Validação antes de publicar

Extensão Places: 27 testes focados JavaScript passaram (busca, seleção, nome e
endereço, texto malicioso, falha da API e regressões do editor). Lint sem erros,
com aviso de chave dinâmica i18n. Builds web/mobile e Android debug passaram;
bundles Android/iOS sincronizados. Mac inacessível e nenhum dispositivo ADB
conectado: iOS não compilado e validação física/visual final pendente. Testes
Google usam mocks, não comprovam faturamento, chave real ou resultados reais.
Esta extensão foi aplicada na VPS em 25/09/2026, junto da correção reativa de
notificações, no pacote `viper-places-notifications-20260925`. O checkout combinado
passou em 63 testes JS; fontes/assets foram conferidos nos três containers e
login/mapa/assets públicos responderam HTTP 200. Isso não substitui o teste real
de busca/envio pelo operador. A chave não foi alterada pela implantação.

Preparação inicial (antes de Places): 72 testes Ruby e 56 testes JavaScript passaram; builds web,
bundle compartilhado Android/iOS e APK debug Android passaram. iOS foi sincronizado,
mas não compilado: o Mac não estava acessível. Não havia dispositivo ADB conectado.
A tentativa de revisão visual automatizada ficou bloqueada pelo servidor local
de prévia sem resposta; não há aprovação visual nem teste real com chave Google.
Nenhuma mensagem real foi enviada nesses testes. A versão inicial de endereços
foi aplicada por host patch em 25/09/2026; a extensão Places foi aplicada como
complemento na mesma data. Configurar a API no Google Cloud não atualiza o código instalado.

Com chave restrita real, verificar: pesquisa, selecionar/arrastar ponto, GPS
permitido/negado/indisponível, envio Uno/Cloud, bolha após recarga, destinatário
WhatsApp e manutenção do rascunho. Testar em navegador e aparelhos Android/iOS,
reconexão, fechar modal e trocar conversa enquanto busca ou GPS estão pendentes.
Confirmar Maps/Places API (New) no console e atribuições Google visíveis no mapa.
Testar empresa por nome, endereço, ausência de resultados, chave sem Places,
cotas excedidas, seleção com nome/endereço e busca seguida de seleção manual.
Revisar declarações de privacidade das lojas para o compartilhamento voluntário.

Referências:
- https://developers.google.com/maps/documentation/javascript/get-api-key
- https://developers.google.com/maps/documentation/javascript/place-search
- https://developers.google.com/maps/api-security-best-practices
- https://developers.google.com/maps/billing-and-pricing/pricing

# ViperChat — changelog e roteiro de demonstração

## Escopo

Resumo das alterações recentes deste ciclo de desenvolvimento e dos host patches de validação. Não é uma comparação de todas as versões históricas do aplicativo. As novidades abaixo estão no frontend compartilhado; publicar o site não atualiza automaticamente os aplicativos instalados pelas lojas.

## Implantação para esta gravação

- Host patch aplicado à VPS em 13/09/2026, incluindo o backend de links e o frontend com o alinhamento corrigido.
- Arquivos de backend deste ciclo conferidos nos três containers; frontend compilado aplicado no serviço web.
- Sem nova imagem, tag, commit ou push nesta entrega. Sem migration adicional e sem alterações na UnoAPI ou no relay.
- Backup e scripts de reversão preservados em `/root/viper-deploy-20260913-2330` e `/root/viper-deploy-20260913-2330.sh`.
- Verificação do serviço de links em produção, com transação de banco somente leitura: 843 ocorrências no histórico examinado, 25 itens por página e ordenação recente primeiro. Nessa amostra, cerca de 121 ms na primeira consulta e 7 ms com cache; não é um benchmark geral.
- Validação local final: 7 testes de frontend e 7 testes de backend, sem falhas; lint do ajuste de ordenação aprovado.
- A validação técnica não substitui a demonstração com o seu usuário. APK e bundles móveis haviam sido gerados no ajuste anterior; nesta implantação não houve instalação em aparelhos nem publicação nas lojas.

## 1. Conversas fixadas

- Fixar e desafixar pelo menu de contexto da conversa.
- Até três conversas fixadas por usuário, em cada conta.
- Ícone de pino para identificar as conversas fixadas.
- Fixadas aparecem antes das demais, independentemente da ordenação escolhida, desde que pertençam à aba/filtro atual e sejam acessíveis ao operador.
- A fixação não dá acesso a conversas restritas.

**No vídeo:** fixe duas conversas e altere a ordenação. Mostre os pinos e a permanência no topo. No celular, pressione e segure a conversa para abrir o menu.

## 2. Mensagens favoritas

- Favoritar e remover dos favoritos pelo menu da mensagem, tanto para texto quanto para mídia.
- Estrela na mensagem para identificar a marcação.
- Acesso às favoritas no painel do contato/conversa.
- Modal com prévia, identificação e data das mensagens, com carregamento de mais resultados.
- Ao selecionar uma favorita, navegação até a mensagem original, inclusive quando ela não estava carregada na conversa.
- Favoritas são pessoais e respeitam as permissões de acesso atuais.

**No vídeo:** favorite um texto e uma imagem. Abra a lista de favoritas e toque em uma mensagem antiga para mostrar o salto até a bolha original.

## 3. Arquivamento pessoal de conversas

- Opção de arquivar disponível na aba **Minhas**, para conversas atribuídas diretamente ao próprio agente.
- A conversa arquivada sai da lista Minhas desse usuário; arquivar não resolve a conversa nem a oculta dos demais usuários autorizados.
- Modal de arquivadas com prévia de conteúdo, como na lista de conversas.
- Possibilidade de abrir e desarquivar a conversa.
- Notificações comuns ficam silenciadas enquanto a conversa estiver arquivada.
- **Menções diretas são exceção:** continuam elegíveis para notificação, conforme as preferências do agente e a entrega do canal.
- Arquivar e fixar não devem mais provocar o aviso indevido de socket reconectando.

**No vídeo:** arquive uma conversa sua, abra a modal, mostre a prévia e desarquive. Para demonstrar notificações, use uma segunda conta de teste.

## 4. Menções e participação dos agentes

- Ajustado o processamento de menções a agentes nas notas privadas e no chat interno.
- Verificação de acesso antes de acrescentar participantes e gerar a notificação.
- Nova configuração de conta: **Último agente como participante**.
- Ativada por padrão quando não há configuração explícita, inclusive em contas existentes.
- Nas próximas atribuições, o agente atribuído passa a ser o único participante; os outros participantes são removidos.
- Com a opção desativada, os participantes anteriores são preservados.
- O ajuste não faz uma limpeza retroativa de todas as conversas ao abrir a configuração.
- Interruptor alinhado à direita, seguindo o padrão dos demais ajustes da conta.
- Na aba Minhas, conversas com time também mostram o agente atribuído, quando houver.

**No vídeo:** mostre o ajuste da conta, atribua uma conversa de teste a outro agente e confira os participantes. Depois mostre uma conversa de time na aba Minhas.

## 5. Nova conversa digitando telefone ou identificador

- Possibilidade de informar diretamente telefone ou BSUID/LID, sem precisar cadastrar o contato antes.
- Telefone brasileiro com DDD e sem código do país recebe `+55` automaticamente; números internacionais completos preservam o país informado.
- Validação do número para evitar criação com dados incompletos.
- Busca por contato existente e seus vínculos antes de criar um novo cadastro.
- Quando não existe contato, criação usando o número/identificador como nome inicial; o nome pode ser editado depois.
- Seleção da caixa WhatsApp UnoAPI corrigida nesse fluxo.
- Restrições de acesso continuam valendo; o campo livre não contorna bloqueios de contato ou conversa.
- Regras do provedor continuam válidas, incluindo restrições da API oficial para iniciar mensagens.

**No vídeo:** digite um número com DDD, mostre a normalização, selecione uma caixa UnoAPI e use um destinatário de teste. Depois repita com um contato já existente.

## 6. Fotos dos contatos e identificação dos grupos

- Ampliação da foto em modal ao tocar no avatar, nos pontos ajustados da conversa, lista de conversas e painel lateral do contato.
- Grupos sem foto não devem mais herdar indevidamente a imagem de um participante.
- Nas novas mensagens de grupo recebidas pela UnoAPI, menções por telefone ou BSUID/LID são substituídas pelo nome cadastrado quando a identificação é inequívoca.
- Identificadores sem correspondência segura são mantidos, evitando mostrar o nome da pessoa errada.

**No vídeo:** amplie a foto pela lista e pelo painel lateral. Mostre um grupo sem imagem e uma nova menção recebida em um grupo de teste.

## 7. Anexos e prévias na lista

- Seletor de arquivos mais livre no editor compacto, sem a lista restritiva anterior de extensões.
- Miniaturas de imagens e vídeos quando o navegador consegue gerar a prévia.
- Identificação pela extensão para documentos e arquivos sem miniatura suportada, em vez de uma área visual quebrada.
- Ajustes de largura e truncamento para preservar nome, tamanho e controles no mobile.
- Prévia de áudio/mídia com transcrição na lista de conversas.
- Tratamento de respostas vazias legadas que escondiam a última mensagem útil e provocavam “Nenhum conteúdo disponível”.

**Observação:** liberar o seletor não elimina os limites de tamanho e de formato impostos pelo WhatsApp ou pelo provedor.

**No vídeo:** anexe uma imagem, um vídeo e um documento. Mostre uma conversa cujo último áudio tenha transcrição.

## 8. Galeria de mídia e links

- Navegação corrigida: direita avança para a próxima mídia na ordem cronológica; esquerda retorna à anterior.
- Identificação de anexos ajustada para mensagens com mais de uma mídia.
- Zoom por pinça no mobile, além dos controles de zoom existentes.
- Botão **Fechar** visível no mobile e melhor distribuição dos controles em telas pequenas.
- Links agora consultam o histórico da conversa, em vez de depender apenas das mensagens já carregadas na tela.
- Contagem de links e carregamento em páginas de 25 itens.
- Mensagens com links ordenadas da mais recente para a mais antiga, incluindo desempate pelo identificador da mensagem.
- Reconhecimento de URLs `http`, `https` e `www`, com limpeza de pontuação final comum.
- O mesmo link repetido dentro de uma mensagem conta uma vez; enviado em mensagens diferentes, aparece em cada ocorrência.
- Busca iniciada ao abrir a galeria, não a cada simples abertura de conversa.
- Cache de cinco minutos por conversa, invalidado por alterações relevantes nas mensagens com links.
- A primeira consulta sem cache examina as mensagens candidatas daquela conversa; a paginação é feita sobre o resultado em cache. Não há promessa de custo zero para históricos muito grandes.

**No vídeo:** abra uma imagem, avance e volte, faça pinça em um navegador mobile e feche pelo botão. Depois abra Links em uma conversa com histórico antigo e carregue mais resultados.

## 9. Atualização da lista e recuperação de conexão

- Atualização da lista e da conversa ativa ao recuperar conexão ou retornar de um período em segundo plano.
- Reinício da paginação e substituição dos dados antigos para reduzir a necessidade de F5 ou reabrir o aplicativo.
- Tratamento de solicitações concorrentes para evitar atualizações duplicadas.
- Gesto adicional no mobile: no final da lista, puxar para cima e soltar para atualizar.
- Atualizações manuais, fixação e arquivamento separadas dos eventos reais de reconexão do socket.

**No vídeo:** deixe a tela em segundo plano, receba uma mensagem de teste e volte. Mostre também o gesto de atualização no final da lista.

## 10. Atalhos personalizados no perfil

Novos atalhos de navegação, editáveis nas configurações do perfil:

| Atalho padrão | Destino |
| --- | --- |
| Alt + T | Todas |
| Alt + M | Minhas |
| Alt + @ | Menções |
| Alt + G | Grupos |
| Alt + N | Não atendidos |
| Alt + P | Participante |
| Alt + I | Chat interno |

**No vídeo:** navegue com dois atalhos, abra o perfil e personalize uma combinação. A combinação de `@` depende do layout do teclado.

## 11. Figurinhas pela UnoAPI/Zapo

- Imagens usadas como figurinha passam por conversão para WebP quando necessário.
- Redimensionamento proporcional para no máximo 512 × 512 pixels.
- Compressão progressiva para no máximo 100.000 bytes, com remoção de metadados desnecessários.
- WebP já válido é reaproveitado.
- Falha de conversão marca a mensagem como falha com motivo explícito, sem repetir a mesma conversão indefinidamente.
- Resposta HTTP 413 recebida diretamente no envio de sticker recebe mensagem específica; erros encapsulados pelo provedor preservam o tratamento correspondente.
- Imagens, vídeos, áudios e documentos comuns não passam por essa conversão de figurinha.
- Alteração restrita ao fluxo UnoAPI; não é uma nova função de sticker da Meta.

**No vídeo:** se quiser demonstrar, use uma figurinha de teste originada de uma imagem grande. Evite enviar ao cliente real durante a gravação.

## Sequência sugerida para gravar

1. Fixar conversas e mostrar os pinos.
2. Favoritar texto e mídia; localizar a mensagem original.
3. Arquivar/desarquivar e mostrar a prévia.
4. Mostrar configuração de participantes e menção a agente.
5. Criar conversa digitando um telefone e escolhendo UnoAPI.
6. Ampliar avatar e apresentar identificação de grupos.
7. Anexos, transcrição e prévia da última mensagem.
8. Galeria, zoom e histórico de links.
9. Atualização da lista após retorno à janela.
10. Personalizar atalhos no perfil.
11. Encerrar com o resumo da correção das figurinhas.

## Cuidados antes de gravar

- Atualize o navegador com Ctrl + F5 para carregar o frontend novo.
- Use contatos e conversas de teste; o vídeo não deve expor telefones, mensagens privadas ou credenciais de clientes.
- Para demonstrar diferenças de permissão, use também um agente comum, não somente administrador.
- Para notificações, deixe o segundo usuário com as permissões e preferências de notificação habilitadas.
- Host patch é uma aplicação de arquivos aos containers atuais: não é uma nova imagem/tag e pode ser perdido ao recriar os containers.
- APK/bundles gerados localmente não significam publicação nas lojas nem validação em aparelho físico. A implantação web não instala uma nova versão nos celulares.

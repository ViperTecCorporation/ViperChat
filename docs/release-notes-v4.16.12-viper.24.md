# ViperChat v4.16.12-viper.24

## Novidades

- Fixação de até três conversas por usuário e conta, com pino e prioridade na ordenação das listas autorizadas.
- Mensagens favoritas de texto e mídia, com estrela, lista por contato/conversa e navegação até a mensagem original.
- Arquivamento pessoal na aba Minhas para conversas atribuídas ao próprio agente, com prévia e restauração pela modal de arquivadas.
- Silenciamento de notificações comuns das conversas arquivadas, mantendo menções diretas como exceção.
- Configuração “Último agente como participante”, ativada por padrão para contas sem preferência explícita e aplicada nas próximas atribuições.
- Atalhos de navegação personalizáveis nas configurações do perfil.
- Criação de conversa por telefone ou BSUID/LID, com normalização de números brasileiros, reaproveitamento de contatos e seleção de caixa UnoAPI.
- Ampliação da foto do contato pela lista e pelos painéis da conversa.

## Correções e melhorias

- Galeria de links baseada no histórico completo da conversa, com cache, paginação e ordenação recente primeiro.
- Navegação cronológica das mídias, zoom por pinça e botão de fechamento acessível no mobile.
- Seletor de anexos menos restritivo, miniaturas de imagens/vídeos e identificação de arquivos sem prévia suportada.
- Prévia de transcrições e tratamento de respostas vazias que encobriam a última mensagem útil.
- Recuperação da lista e da conversa ativa após reconexão ou retorno do segundo plano; gesto de atualização ao puxar para cima no final da lista mobile.
- Arquivar e fixar deixam de disparar indevidamente a indicação de reconexão do socket.
- Nome do agente atribuído visível em conversas de time na aba Minhas.
- Menções de agentes em notas privadas e chat interno com verificação de acesso antes da notificação.
- Grupos sem foto deixam de herdar indevidamente a imagem de um participante.
- Menções recebidas em grupos UnoAPI identificadas pelo nome cadastrado quando há correspondência segura por telefone ou BSUID/LID.
- Figurinhas UnoAPI convertidas para WebP, com até 512 × 512 pixels e 100.000 bytes; falhas de conversão reportadas sem repetição indefinida.
- Alinhamento dos interruptores das configurações de conta e ajustes de responsividade.

## Atualização

- A implantação deve executar as migrations, incluindo a criação de `message_favorites`.
- Use a mesma imagem no serviço web e nos workers. Não é necessário limpar o Redis para atualizar.
- Após atualizar o servidor, recarregue o navegador para carregar os novos assets.
- A publicação da imagem não instala uma versão nova nos aplicativos móveis; os pacotes móveis e a distribuição pelas lojas têm ciclo próprio.
- A nova configuração de participantes não remove retroativamente participantes de todas as conversas: age nas próximas atribuições.
- Os filtros e as permissões continuam sendo respeitados por fixação, favoritas e criação direta de conversa.

O roteiro detalhado de demonstração está em [changelog-demonstracao-2026-09-13.md](changelog-demonstracao-2026-09-13.md).

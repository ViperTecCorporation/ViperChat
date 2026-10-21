# Seletor de transporte sem F5 — 21/10/2026

Correção em dev na branch `4.16.0`, separada do patch de edição/exclusão. Commit e push das duas correções e dos planos autorizados pelo usuário em 21/10/2026. Sem publicação de imagem ou deploy à VPS nesta etapa.

## Causa e correção

Ao selecionar uma conversa já carregada na lista/cache, `setActiveChat` buscava somente mensagens quando necessário. Se o objeto parcial não continha `whatsapp_transport_options`, o ReplyBox ocultava o seletor até uma atualização completa, como o F5. Além disso, a atualização genérica da conversa descarta respostas com `updated_at` inferior ao snapshot atual, mesmo quando contêm detalhes de transporte que ainda não foram carregados.

- Ao ativar uma conversa WhatsApp individual, buscar os detalhes autenticados em paralelo com a carga de mensagens, inclusive quando `dataFetched` já está preenchido.
- Hidratar exclusivamente `whatsapp_transport_options`, sem sobrescrever mensagens, rascunhos, timestamps ou a conversa selecionada. Não depender da comparação de `updated_at` da mutação genérica.
- Aplicar a resposta somente a um objeto ainda existente com o mesmo ID e conta. Uma resposta tardia não seleciona outra conversa nem recria registros removidos do estado.
- Campo ausente na resposta autenticada significa `null`: remover opções antigas não autorizadas. Em falha de rede, não inventar provedores nem alterar a preferência do operador.
- Preservar `useWhatsappTransport`, seu cache de preferência por usuário/conta/conversa/vínculo e as regras de capacidade. O mesmo ReplyBox e seletor atendem aos layouts compacto e completo. Sem alteração de CSS, posição ou dimensões.
- Não buscar opções individuais para grupos ou outros canais. Nenhuma alteração nas regras de envio ou autorização do backend.

## Validação

Novo `transportHydration.spec.js`, nove testes, com as actions/mutations reais, composable e seletor montado. Os dois layouts usam a condição real de visibilidade do ReplyBox. Cobertura: conversa em cache sem opções; detalhe mais antigo que o snapshot de mensagens; reaparecimento sem reload; preferência Meta preservada em nova hidratação; opções omitidas; conta diferente; conversa removida; resposta tardia após selecionar outra conversa; falha de rede; grupos/outros canais.

Rodada ampliada: **119 testes, dez arquivos, zero falhas**, incluindo ReplyBox, CompactReplyComposer, seletor, preferências, mutations/helpers de conversas e regressões adjacentes do editor. ESLint nos três arquivos JS alterados/adicionados e `git diff --check` aprovados.

Build do frontend nativo concluído, com assets atualizados sincronizados para Android e iOS. O pnpm padrão do shell era 11 e incompatível com o projeto; foram usados Corepack/pnpm 10.2 e os comandos equivalentes `corepack pnpm build:native`, `corepack pnpm exec cap sync android` e `corepack pnpm exec cap sync ios`, sem desativar engines ou alterar dependências. O sync iOS gerou caminhos Windows no Package.swift; somente essa alteração gerada foi revertida, preservando os caminhos portáveis originais.

Não há aceite nativo completo:

- Android físico detectado pelo ADB. A tentativa de `:app:assembleDebug --no-daemon --max-workers=2` falhou no Gradle ao ler `android/capacitor-cordova-android-plugins/src/main/res/.gitkeep`, apresentado pelo filesystem Nextcloud como arquivo não regular. Não foram desabilitadas as verificações do Gradle, nem removido o aplicativo/dados do aparelho. Sem APK novo instalado ou teste funcional no telefone.
- Mac `192.168.0.138` alcançável, mas SSH em BatchMode recusou autenticação. Nenhuma tentativa de contornar acesso ou alterar chaves/permissões. Assets iOS sincronizados localmente, sem compilação Xcode ou teste em simulador/iPhone nesta rodada.

Assets sincronizados permanecem disponíveis para a validação nativa pendente. Builds/caches preexistentes, credenciais, dependências e dados do usuário foram preservados; não foram criados containers ou pacotes de transferência temporários. A versão interna e as versões nativas existentes não foram alteradas. O backend de edição/exclusão e seu plano permanecem no checkout, sem mistura na lógica deste ajuste.

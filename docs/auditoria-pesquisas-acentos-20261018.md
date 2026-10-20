# Pesquisas com e sem acentos — validação em dev

## Escopo entregue

- API de contatos: nome, e-mail, telefone, identificador, BSUID e username. Atende também aos seletores de nova conversa e encaminhamento que usam essa API.
- Pesquisa geral: contatos, conversas, nomes de grupos, mensagens e artigos.
- Busca de conteúdo na lista de conversas e variantes SQL/GIN da pesquisa de mensagens.
- Membros e solicitações de entrada de grupos, contatos compartilhados e menções.
- Respostas prontas: filtro e ordenação pela pesquisa.
- Empresas, associação de contatos, documentos/respostas do Captain e ferramentas de pesquisa do copiloto.
- Filtros locais de agentes, equipes, caixas, etiquetas, automações, macros, atributos, integrações, menus, comboboxes, templates e países.

As normalizações são exclusivamente para comparação. Não alteram nomes salvos, textos das mensagens, telefones, IDs, vínculos, mídias ou objetos retornados pelos seletores. O wrapper de busca fuzzy preserva as referências dos objetos, as opções de ponderação e a capitalização usada para pontuar limites de palavras.

Os escopos por conta, caixas permitidas, atribuição, datas, paginação e limites de busca permanecem nos chamadores. Comparações de identidade, igualdade de etiquetas e regras de automação não foram transformadas em pesquisas sem acento. O destaque visual de termos em mensagens continua usando o formatador existente.

## Implementação e publicação futura

`Search::TextQuery` centraliza comparações SQL Unicode normalizadas. Valores de pesquisa continuam parametrizados e os curingas literais são escapados. A pesquisa GIN mantém a condição indexada e acrescenta a comparação normalizada no mesmo escopo; os termos são escapados para não virarem operadores tsquery.

`shared/helpers/search.js` centraliza os filtros locais e a adaptação do Pico Search.

Artigos continuam utilizando pg_search, com prefixos, pesos e relevância. A migration `20261018150000_enable_unaccent_for_article_search.rb` habilita a extensão PostgreSQL `unaccent`, necessária para essa parte. Aplicada somente nas bases dev e de testes. Na publicação futura, executar as migrations antes de servir a nova versão. O rollback não remove uma extensão compartilhada do banco.

Searchkick já configura `asciifolding` nos analisadores da versão instalada; foi inspecionado no código da dependência. Não houve teste contra Elasticsearch de produção nem reindexação de produção. A consulta normalizada SQL não usa os mesmos índices de expressão dos filtros antigos; monitorar planos e latência no volume de produção antes de uma implantação ampla.

## Evidências

- 160 testes: normalização, APIs de pesquisa, artigos, respostas prontas e ConversationFinder; sem falhas.
- 134 testes: contatos, membros de grupos, empresas e Captain; sem falhas.
- 452 testes frontend em 30 arquivos, incluindo referências dos objetos, combobox, membros de grupos e filtros de conversas; sem falhas. Reexecução focada após ajuste de preservação de caixa: 14 testes aprovados.
- Reexecução final do núcleo de pesquisa: 86 testes aprovados.
- RuboCop: 16 arquivos de produção sem infrações. ESLint dos arquivos alterados: sem erros após formatação, com avisos preexistentes de i18n.
- Base dev com 19.036 contatos: `joao`/`João` e `claudia`/`Cláudia` retornaram os mesmos IDs. Consultas amostradas de 0,2 a 21,3 ms, com cache ativo; não constitui benchmark de produção.
- Playwright: componente ComboBox real montado com dados sintéticos na página local, sem criar contatos ou sessões de usuários. Busca e seleção exercitadas em larguras 320, 360, 390, 412, 430 e 1440, além de paisagem 844×390; sem overflow horizontal. `joao` encontrou `João — Manutenção`, `claudia` encontrou `Cláudia — Câmeras`; seleção manteve o ID 42. Captura mobile inspecionada visualmente.

## Plataformas e pendências operacionais

- Bundles nativos regenerados no container dev com `pnpm native:sync:android` e `pnpm native:sync:ios`. Nova sincronização Android utilizou o mesmo bundle final do iOS. Os três `index.html` tinham SHA-256 `b955a973576b871cc95d8029110fe56a387a127fe9af1293fd32ca75f4052c88`.
- A compilação Android do checkout Windows com SDK configurado passou, mas usava os assets locais anteriores: não comprova um APK com o bundle atualizado. A tentativa de atualizar os assets locais removendo chunks obsoletos foi bloqueada pelo ambiente antes de executar. Não reportar APK novo como entregue.
- `adb devices` não encontrou aparelho ou emulador conectado. Sem teste físico Android. Sem build/Archive Xcode ou teste iPhone nesta tarefa.
- Assets nativos atualizados permanecem no container dev; não foram copiados sobre os assets antigos do checkout Windows. Não houve alteração de assinatura, versão nativa, publicação em loja ou aplicação na VPS.
- Intermediário `dist-mobile` no container (~30 MB), captura `output/playwright/accent-search-mobile-20261018.png` e snapshots/logs Playwright desta execução foram preservados: a operação de limpeza foi bloqueada pelo ambiente. Não houve prune, remoção de cache Docker ou de dados persistentes.

Sem commit, push, nova imagem ou implantação na VPS nesta etapa.

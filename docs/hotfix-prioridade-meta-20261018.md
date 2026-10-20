# Hotfix: salvar prioridade inicial da Meta

Aplicado por SSH via hostpath em 18/10/2026, sobre `viperchat:unified-20261018-r1`. A imagem em si não foi substituída.

## Correção e validação

O botão geral **Atualizar** agora persiste também as preferências alteradas do vínculo. Em vínculos já ativados, editar a prioridade/quantidade inicial ou o transporte padrão não depende da revisão dos conflitos históricos; ativação/desativação e mudanças estruturais continuam com as proteções existentes. Falhas de persistência são propagadas, sem aviso falso de sucesso.

Dev: 38 testes de frontend e 95 de backend aprovados, incluindo salvar/recarregar, ativar/desativar a política, conflitos históricos, leitura pelas duas caixas e erro de rede. O frontend foi recompilado isoladamente a partir da imagem r1, com apenas quatro fontes atualizadas: Settings.vue, WhatsappUnifiedInbox.vue e as traduções en/pt_BR.

VPS: login HTTP 200, bundle corrigido HTTP 200 e conteúdo conferido por SHA-256; mount somente leitura verificado. Somente o web foi recriado. Os dois workers permaneceram com os mesmos IDs. Sem migrações ou alterações em contatos, mensagens e mídias. O aceite autenticado do salvamento na interface fica para o administrador; nenhuma preferência real foi modificada para testar o patch.

## Aplicação e recuperação

Diretório: `/var/snap/docker/common/viperchat-hostpaths/meta-priority-save-20261018`.

- `private/`: compose original, configuração anterior resolvida, inventário mínimo e assets anteriores; acesso restrito.
- `vite/`: assets ativos, mantendo também os arquivos com hash antigo para sessões já abertas.
- `stack-after.json`: compose efetivamente aplicado.
- `ROLLBACK.md`: recuperação do frontend sem restauração de banco.

Rollback do web:

```sh
docker compose -p chatwoot-uno \
  -f /var/snap/docker/common/viperchat-hostpaths/meta-priority-save-20261018/private/stack-before.json \
  up -d --no-deps --pull never --force-recreate chatwoot-web
```

O Portainer ainda mantém o compose anterior. Antes de reimplantar a mesma imagem pelo painel, adicionar **somente ao serviço web** o bind abaixo, ou usar uma nova imagem que já incorpore a correção:

```yaml
volumes:
  - /var/snap/docker/common/viperchat-hostpaths/meta-priority-save-20261018/vite:/app/public/vite:ro
```

Preservar os demais volumes e configurações. Sem esse ajuste, uma reimplantação do Portainer pode remover o hotfix.

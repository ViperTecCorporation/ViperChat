# Recuperação automática do PID do servidor

Após um desligamento abrupto, o container pode preservar
`/app/tmp/pids/server.pid` com o valor `1`. No próximo início, esse PID pertence
ao processo de inicialização do container, mas o Rails pode interpretá-lo como
um servidor já ativo e encerrar antes de carregar `config/puma.rb`.

A imagem inclui `docker/entrypoints/container.sh` como entrypoint padrão.
Antes de executar `rails s`, `rails server` ou `puma` diretamente (com ou sem
`bundle exec`), ele remove apenas os arquivos de PID padrão e usa `exec` para
entregar ao servidor o PID 1 e os sinais do Docker.

O entrypoint não limpa PIDs para Sidekiq, migrations ou outros comandos. Não
apaga cache, uploads, bancos ou volumes. Deve existir apenas um servidor web
por container; não compartilhe o diretório de PIDs entre réplicas.

## Aplicação em uma instalação

A mudança exige publicar uma nova imagem e recriar o container com ela.
Reiniciar um container com a imagem antiga não incorpora este entrypoint.

Stacks com `entrypoint:` explícito substituem o padrão da imagem. O
`docker/entrypoints/rails.sh` existente já faz a limpeza; mantenha-o se sua
stack utiliza esse script. Se a stack sobrescrever o entrypoint com outro
comando, remova essa substituição ou use o novo script. Um comando executado
dentro de `sh -c` não é reconhecido como servidor: prefira a lista direta.

Exemplo para a nova imagem:

```yaml
services:
  rails:
    image: ghcr.io/viperteccorporation/chatwoot:<nova-tag>-ce
    entrypoint: ["/app/docker/entrypoints/container.sh"]
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    restart: always
```

Para uma imagem antiga que já contém o script tradicional, configure
`entrypoint: ["sh", "/app/docker/entrypoints/rails.sh"]` na stack. Esse script
também aguarda PostgreSQL e verifica/instala gems, diferentemente do novo
entrypoint leve. Recriar o serviço para alterar a stack causa interrupção;
faça isso em uma janela autorizada.

Na validação pós-atualização, confira os logs e a saúde HTTP após reiniciar o
serviço, preservando os volumes de dados. Não simule queda forçada em produção.
Para rollback, retorne à imagem/configuração anterior; a correção não exige
migração nem modifica dados persistentes.

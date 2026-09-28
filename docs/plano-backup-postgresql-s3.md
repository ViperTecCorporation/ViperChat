# Plano pendente — backup PostgreSQL em S3

Status: planejado, sem instalação, agendamento ou alteração da VPS. Executar somente após o usuário preparar o destino e autorizar a implantação.

## Política aprovada

- Banco do ViperChat/Chatwoot na VPS: backup lógico PostgreSQL em formato custom (`pg_dump -Fc`). Revalidar container, banco e versão antes da implantação.
- Frequência: a cada 6 horas.
- Horários propostos: 00:00, 06:00, 12:00 e 18:00, no fuso `America/Cuiaba`.
- Retenção: sete slots fixos, um por dia da semana, separados por instalação e banco.
- As quatro execuções do mesmo dia atualizam o mesmo slot. Não guardar quatro backups diários permanentes.
- O último backup bem-sucedido do dia permanece no slot até a primeira execução bem-sucedida daquele dia da semana na semana seguinte.
- Com os horários propostos, o backup final do dia é o das 18:00, não uma captura das 23:59.
- Definir o slot pela data local de início da execução, mesmo se o upload terminar após a meia-noite.

## Organização do destino

Prefixo proposto: `<instalacao>/postgresql/<banco>/`.

| Slot | Objeto |
| --- | --- |
| Segunda | `segunda.dump` |
| Terça | `terca.dump` |
| Quarta | `quarta.dump` |
| Quinta | `quinta.dump` |
| Sexta | `sexta.dump` |
| Sábado | `sabado.dump` |
| Domingo | `domingo.dump` |

São sete backups disponíveis após completar a primeira semana com sucesso. A atualização do slot substitui o backup daquele mesmo dia da semana anterior. Não usar uma expiração genérica de sete dias que possa apagar o último backup válido quando houver falhas prolongadas.

## Execução e proteção contra falhas

1. Adquirir um lock para impedir execuções simultâneas.
2. Registrar data, fuso, slot, instalação, banco e versão do PostgreSQL, sem segredos.
3. Gerar o dump em arquivo temporário local com permissões restritas e verificar código de saída e espaço disponível.
4. Validar o inventário com `pg_restore --list` e calcular SHA-256. A leitura do inventário não substitui um teste de restauração.
5. Enviar o dump completo ao objeto do slot. Validar a semântica de substituição do provedor S3: o objeto anterior não deve ser apagado antes de o novo upload concluir.
6. Guardar checksum, horário e identificação do banco nos metadados do objeto. Confirmar tamanho e integridade usando os mecanismos suportados pelo destino; ETag multipart não deve ser tratado como SHA-256.
7. Somente registrar sucesso após a confirmação remota. Limpar os temporários da execução após a verificação.
8. Em falha de dump, validação ou upload, preservar o slot anterior, registrar o erro e alertar. Se a resposta do upload for incerta, conferir o objeto antes de repetir.

Configurar limites de duração, retentativas limitadas, limpeza de uploads multipart abandonados e rotação de logs. As retentativas devem manter o slot original da execução.

## Infraestrutura a preparar

- Endpoint S3, região, bucket privado e prefixo exclusivo para esta instalação.
- Destino independente do disco da VPS; preferencialmente também independente do host físico.
- HTTPS e criptografia no armazenamento conforme suporte do provedor.
- Credencial exclusiva e de menor privilégio, com acesso apenas ao prefixo necessário; não gravar segredos no Git, logs ou neste documento.
- Espaço temporário suficiente na VPS e canal de alerta a definir.
- Serviço separado de backup no compose, preservando `x-base` e os serviços atuais. Ferramentas compatíveis com a versão do PostgreSQL.
- Definir versionamento do bucket: se estiver ativo, sobrescrever mantém versões anteriores e deixa de limitar o armazenamento a sete dumps. Desabilitar no destino apropriado ou acordar uma política explícita para versões não atuais antes da implantação. Object Lock pode impedir a substituição exigida por esta política.

## Validação antes de ativar

- Executar manualmente um backup e restaurá-lo em banco isolado, nunca sobre produção.
- Verificar que duas execuções no mesmo dia substituem apenas o slot correto e que os demais slots permanecem intactos.
- Simular falha de dump e de upload, confirmando preservação do último backup válido.
- Verificar fuso, mudança de dia, ausência de sobreposição e alertas de falha/atraso.
- Validar consumo de disco, duração e impacto no PostgreSQL antes de ativar o agendamento.
- Definir testes periódicos de restauração e alerta quando a última execução bem-sucedida ultrapassar o intervalo esperado mais a tolerância acordada.

## Limitações

- Não é recuperação contínua por WAL/PITR. Com execuções saudáveis a cada 6 horas, a perda potencial corresponde aproximadamente ao intervalo mais o tempo de geração/envio; falhas podem ampliar essa janela.
- O snapshot representa o início do dump, não o término do upload.
- O dump não inclui os arquivos externos de anexos, credenciais, configuração do compose ou roles globais do cluster. A proteção desses itens deve ser definida separadamente.
- Backup não corrige corrupção de índices. Manter a investigação e a verificação de integridade independentes.

## Pendências para a próxima execução

Receber os dados do destino e a credencial por canal seguro, confirmar horários e alertas, implementar o serviço, testar restauração e falhas e obter autorização para ativar na VPS. Nenhuma automação foi criada nesta etapa.

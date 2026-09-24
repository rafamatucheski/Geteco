# Serviços nativos V2

`runtime/Services.gd` é um Node independente. `configure(session)` recebe a sessão; `nearest_action()` fornece ações físicas e `perform(id)` mostra falas originais de `data/catalogs/ServiceDialogue.gd`. `snapshot()`, `restore_snapshot(data)` e `validate_snapshot(data)` usam versão1 com `hospital_cooldown`, `auto_serial`, `serviced_count`, `last_vehicle`.

## Integração

1. Instanciar/adicionar o Node, restaurar `state.world_state.services` caso exista, validar falha antes de autosave, e configurar sessão. Não chamar o processamento manualmente: Node usa `_physics_process` e respeita pausa.
2. Priorizar `nearest_action` para triagem, terminal policial e alarme. Ação usa `id=original_service`, `target` string; encaminhar `perform(target)` na interação.
3. Para serviço hospital/police/fire_station, encaminhar `perform(service)` e retirar o fallback genérico correspondente. Isso somente conversa; cura é física.
4. Antes de salvar, preencher `state.world_state.services=services.snapshot()`. GameState valida esse campo quando presente. Saves antigos sem campo começam com pickup disponível e nenhuma cobrança de oficina concluída.
5. Remover cura de botão do hospital e pickup genérico substituto nesses ambientes. A cruz hospitalar é criada pelo Services no ponto real, duas malhas sem sombras/SubViewport/luz adicional.
6. Retirar oficina instantânea150 de Northgate. O reparo correto inicia automaticamente com condutor no carro, parado na vaga original; cobra100 somente após4,5s. Sair/mover/morrer/interromper cancela sem pagamento. Reparos incompletos reiniciam no carregamento; permanência na vaga após serviço/reload não cobra novamente.

## Fontes e comportamento

| Fonte produção | Comportamento V2 |
|---|---|
| `HarborHospitalInterior3D` + `HospitalHealthPickup` + `HealthPickup` | Vida completa grátis, jogador ferido a pé, local(2,0,-1), renasce180s; cheio não consome. Triagem(2,0,-3.5) mostra texto original e não cura. |
| `HarborFireStationStandard` + `HarborFireStationInterior` | Área local(10,0,-120/28) cura9HP/s; sair interrompe. Alarme(-10,0,-120/28) exibe inspeção original. |
| `HarborPoliceInterior` | Diálogo Morales e terminal(-4.2,0,1.5) com ocorrência304; não apaga crime, não oferece multa. Dados preservam também falas dos outros quatro NPCs para futura integração dos personagens correspondentes. |
| `HarborAutoService` + `HarborNorthDistrict` | Origem Apron(4925,-1198)/16, retângulo local(-20,-155,40,48)/16, preço100, duração4,5s, repara veículo e limpa procurado na conclusão. |

Pontos de hospital/fire confirmados pelo agente de mundo em teste de cápsula; entrada física de um veículo completo na vaga Auto ainda depende da integração. Oficina não reproduz persiana, repintura aleatória e reparação específica de pneus. Alarme não sintetiza a sirene original. Dados de cinco policiais não implicam cinco NPCs já instanciados. Banco/assaltos do posto não fazem parte deste módulo; não há menu financeiro inventado.

## Verificação

`tests/test_services.gd`: 17 checks aprovados, Godot4.7.2, exit0. Verifica proximidade, cooldown, cura por tempo, crime intacto na polícia, tempo/preço/cancelamento da oficina e repetição/restauração sem débito duplicado. Fixture substitui a sessão e a consulta física da vaga; não comprova colisão do ambiente. A execução restrita relatou somente impossibilidade de escrever logs user:// e ler certificados do SO. Comparação renderizada de desempenho está a cargo da integração root; não é certificada por estes testes.

# Validação da bagagem em grade

Estado em 28/09/2026. Não houve gravação no save pessoal. A implementação e o protótipo estão prontos para revisão; **desempenho não aprovado e regressão ampla de combate ainda parcialmente falha**.

## Funcionalidade

| Execução | Resultado |
|---|---|
| `tests/test_inventory_grid.gd` | 36 verificações aprovadas; última execução após otimização da validação espacial |
| `tests/test_inventory_field.gd` | 30 verificações aprovadas na Main renderizada, incluindo coleta real, limites da UI, cura, acesso físico/remoto ao porta-malas, colisão do objeto no chão, recuperação e save completo |
| `tests/test_campaign_economy.gd` | 162 verificações aprovadas |
| `tests/test_full_save.gd` | Aprovado, zero falhas |
| `tests/test_garage_rewards.gd` | 47 verificações aprovadas |
| `tests/test_garage_driver_restore.gd` | 26 verificações aprovadas |
| `tests/test_garage_vehicle_transfer.gd` | 11 verificações aprovadas |
| `tests/test_combat_flow.gd` | 76 verificações, 3 falhas restantes nas expectativas de denúncia/pontos de crime |
| Protótipo no Chrome headless | 16 verificações aprovadas, nenhuma exceção JS capturada |

As três falhas restantes do teste amplo de combate, em `combat-fixture.log`, são:

- `disparo em civil gera crime`;
- `crime escalou para procurado`;
- `escopeta: uma denúncia por vítima ferida e uma pelo disparo (4 + 12 por vítima)`.

Não foram removidas ou afrouxadas essas asserções. O checkout teve alterações simultâneas no sistema policial. A origem dessas divergências não foi corrigida nesta tarefa de inventário. Os casos de dano, armas, recarga, garagem, proteção de Maciota/mecânico, restauração e interrupção de animação passaram nessa execução.

A preparação das duas últimas situações de animação do teste foi ajustada: após restaurar, o cheat não está mais ativo e as armas guardadas no porta-malas precisam ser movidas para o equipamento antes do ensaio. A expectativa de interromper a animação foi preservada.

Durante a validação foram corrigidos: custo excessivo de procurar células para milhares de tiros do cheat; normalização de números da grade após JSON; margem transparente dos ícones; verificação de ambos os contextos nas transferências; colisão e obstrução de interação da bagagem. O registro final de integração é `field-collision.log`. Os logs anteriores permanecem como histórico e não representam a aprovação final.

## Desempenho — diagnóstico, não aprovação

Main real, RTX 4060 Laptop, Vulkan Mobile, resolução 1280 × 720. Cada cenário teve 8 segundos de aquecimento e pelo menos 30 segundos de amostras reais. VSync/limitador e amostras completas estão nos JSONs. Meta provisória: 60 FPS / 16,67 ms; aumento acima de 5% em p95/p99 exige investigação em condições comparáveis.

| Cenário | FPS antes → depois | p50 ms | p95 ms | p99 ms | Máximo ms |
|---|---|---|---|---|---|
| Fechado | 71,11 → 67,93 | 14,40 → 15,43 | 19,29 → 20,42 | 29,51 → 29,80 | 36,58 → 41,24 |
| Aberto | 40,76 → 42,68 | 19,15 → 19,71 | 44,83 → 32,89 | 65,44 → 48,08 | 162,69 → 67,69 |

Fechado: 7 → 6 quadros acima de 33,3 ms, nenhum acima de 66,7 ms. Aberto: 143 → 58 acima de 33,3 ms e 13 → 1 acima de 66,7 ms.

O p95 fechado aumentou aproximadamente 5,9%; o cenário aberto permanece abaixo da meta absoluta. Havia outras instâncias de Godot e alterações concorrentes em sistemas do mundo, impossibilitando atribuir essas diferenças à bagagem. Parte das execuções registrou erros temporários de compilação em `PoliceTankWeapon.gd` e `PoliceHelicopterArt.gd`, corrigidos posteriormente por outra sessão. As capturas funcionais também mostraram quedas momentâneas até 9 FPS, sem amostra controlada para atribuição.

Não é válido declarar performance aprovada nem comparar esses números como um A/B isolado. Fica pendente uma medição com o checkout estável, mesmos processos, cena/população e ambiente controlado. Não foram terminadas instâncias alheias para produzir um número favorável.

## Limites da apresentação

A retirada/abertura da bagagem usa movimento procedural do modelo e tampa, sem uma animação esquelética nova das mãos. Os ícones de arma são os existentes do jogo, reaproveitados com recorte de transparência; não são uma nova coleção de ilustrações. A bagagem no chão é estática e sólida, sem simulação de quique. A distribuição inclui oito coletáveis exteriores; mais pontos e lojas podem ser adicionados ao catálogo sem alterar a regra central.

Avisos de liberação de textura/RID no encerramento aparecem também no baseline. Não foram considerados prova de falha da regra de inventário, mas permanecem nos logs.

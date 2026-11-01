# Análise de arquitetura do código — 01/11/2026

Leitura e contagem estática de 1.440 `.gd` de jogo (~279 mil linhas, fora tests/tools/addons),
no ramo `viagem-lages-testar` (checkpoint `checkpoint-20261101-antes-arquitetura`). Nada executado.

## Bom
- Mediana 120 linhas por arquivo; 90% < 420; só 18 > 1.000.
- Pastas por domínio (world 427, gameplay 353, runtime 268, activities 108, assets 103, ui 65).
- Regras de desempenho escritas e seguidas (streaming, prewarm, StallWorkTrace, LightBudget).
- Tipagem estática quase total; 6 autoloads; suíte core + CI.

## Maiores
| Arquivo | Linhas | funções | vars | preloads |
|---|---|---|---|---|
| runtime/ProductionWorld.gd | 2.527 | 109 | 60 | 161 |
| gameplay/Gameplay.gd | 2.496 | 199 | 141 | 53 |
| runtime/FullSession.gd | 2.483 | 116 | 117 | 110 |
| world/regions/NativeRegion.gd | 2.267 | 88 | 48 | 106 |
| runtime/prologue/BlitzScene.gd | 2.231 | — | — | — |

## Problema central: tudo passa por sessão/mundo
- 223 arquivos usam `session.`, 206 usam `world.`; `session.world` 1.769×, `session.state` 1.490×.
- Cadeias: `session.world.player.global_position` 222×, `session.world.gameplay.health` 218×,
  `session.world.driving.occupied` 180×.
- 884 acessos a privados de outro objeto (`session._button` 159×).
- 482 `has_method`/`call("...")` por nome.
- 327 scripts com `_process`/`_physics_process`; 99 `get_nodes_in_group`; só 156 sinais.

## Recomendações (ordem de retorno)
1. Fachada de leitura do jogador (`PlayerQuery`) no lugar das cadeias de 3–4 níveis.
2. Tornar públicas as funções privadas usadas por fora (`_button` → `button`, mantendo o antigo).
3. Trocar `call("nome")`/`has_method` quentes por métodos tipados ou sinais.
4. Revisar `_process` que rodam sempre e varreduras de grupo por quadro (precisa medição).
5. Continuar a divisão de `ProductionWorld` e `NativeRegion`.

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

## Conferência dos itens 3, 4 e 5 (leitura estática, sem medição)

**3. Chamadas por nome em caminho quente** (trocáveis por chamada direta, método existe numa classe só):
GameplayWeaponVisuals.gd (7×, por quadro no jogador), Gameplay.gd:993/1457, CameraRig.gd:723-738,
RainPuddles3D.gd:117, DispatchUnit.gd:907/908/1004 e PoliceAgent.gd (por quadro por policial).
Precisam de interface ou cache antes: CivilianModel.gd:433 (bool ao ligar o modelo),
TrafficJunctions.gd:265-350 (Callable guardado no carro), Driving.gd:551-564 (StealableMeetCar também dirige),
DesertLocals.gd:61, TrafficDriverPool.gd:71 (grupo misto). Os de VehicleCarjacking/StreetPhysics são por evento.

**4. `_process` caro ou sempre ligado**
- Varredura por quadro sem espaçamento: DesertRuntime.gd:127 (`desert_car_neon`), VerticeCompany.gd:443/465
  (`port_logistics_truck` + reescrita de luzes longe do jogador), DesertNorthPass.gd:25 (`get_node("Model")` a 20 Hz).
- `get_node_or_null("/root/GameInput")` por quadro: TankDriverControls.gd:50, AimReticle.gd:48,
  BarGameScreen.gd:133, CoastalBinoculars.gd:143; SkyMenu.gd:150 (`LoadingCurtain`, só no menu).
- Sempre ligados com guarda na 1ª linha: MountainRoadLamp3D.gd:80 (um por poste), ContainerLockpick.gd:68,
  BankLockpick.gd:59, VehicleBoardingPresentation.gd:240, BagVisual.gd:39, ColdSurvival.gd:24,
  VerticeUndercroftPlace.gd:50, HouseCat.gd, ArmoredGuard.gd:172, CanyonGuard.gd:31, SewerHostility.gd:73.

**5. Divisão proposta**
- ProductionWorld: Prewarm (485-1005, risco médio), Population (1791-1962 + 2187-2402, baixo/médio),
  Traffic (1963-2186 + 2403-2448, médio), Residency (1169-1577, alto: 66 testes), `build()` em etapas (alto).
- NativeRegion: RoadSurfaces (1152-1293 + 1532-1669, baixo), Land (1006-1151, baixo), Retirement (888-993, médio),
  TerrainTasks (1414-1531, médio), RecordBuilders (1670-2260, médio/alto), `_prepare` (297-490, médio).

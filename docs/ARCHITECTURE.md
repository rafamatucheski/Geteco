# Arquitetura do GETECO

Mapa técnico do que existe hoje. Para estrutura de pastas e como rodar, veja o
[README.md](../README.md); para convenções de trabalho, o [CLAUDE.md](../CLAUDE.md).

## Cadeia de entrada

```
project.godot  run/main_scene
      └── ui/MainMenu.tscn                    (menu; entrypoint declarado)
            └── world/harbor/HarborGame.tscn  (o jogo)
```

`HarborGame.tscn` é uma cena **herdada** de `HarborPreview.tscn`, e `HarborGame.gd`
estende `HarborPreview.gd`. A camada `HarborPreview` monta o distrito; a camada
`HarborGame` acrescenta campanha, missões e HUD de jogo.

Existe uma segunda rota: `HarborSceneRoute.for_save()` decide entre `HarborGame.tscn` e
`legacy/Main.tscn` conforme o save. Saves sem a flag `harbor_campaign_active` vão para
`legacy/Main.tscn` — a primeira geração do jogo, que continua carregável por isso.
`tests/test_legacy_save_route.gd` guarda esse contrato.

## Autoloads

Dez singletons declarados em `project.godot`, todos na raiz do projeto:

| autoload | responsabilidade |
|---|---|
| `Localization` | idioma e traduções |
| `SettingsManager` | vídeo, áudio, resolução, modo de janela |
| `WantedManager` | nível de procurado, despacho de viaturas, alvo de perseguição |
| `EmergencyPool` | pool fixo de veículos de emergência (4 polícia, 2 ambulância, 2 bombeiro, 2 rabecão) |
| `CityAudioManager` | ambiência sonora da cidade |
| `TrafficLightManager` | semáforos |
| `CampaignState` | flags e progresso de campanha |
| `DistrictRestriction` | bloqueio de acesso a regiões |
| `SaveManager` | save/load |
| `RegionTravel` | viagem entre regiões |

## Física 2D com apresentação 3D

A decisão estrutural mais importante do projeto: **a simulação é 2D** (`CharacterBody2D`,
`Area2D`, `Path2D` para faixas de trânsito), mas personagens, veículos e vários props são
**modelos 3D renderizados em `SubViewport`** e exibidos como sprite no mundo 2D.

Números medidos numa partida real carregada (2026-09-09):

| | |
|---|---|
| nós na árvore | 14.962 |
| `MeshInstance3D` | 6.419 |
| `SubViewport` | 249 (cada um com `Camera3D` e `DirectionalLight3D` próprios) |
| draw calls / frame | ~16.100 |
| VRAM | ~1,3 GB |
| RAM estática | ~630 MB |

Os `SubViewport` usam majoritariamente `UPDATE_ONCE` / `UPDATE_DISABLED` (ver
`Collectible.gd`, `world/shared/traffic/TrafficVehicle.gd`, `AnimatedPedestrian3D.gd`): eles
renderizam uma vez e ficam em cache. Ou seja, **custam pouco por frame, mas caro na
construção e em memória**. Pausar a atualização deles não muda FPS mensuravelmente.

## Carregamento

Perfil medido com `tests/profile_load_time_0909.gd` (renderização real, não headless):

| fase | tempo |
|---|---|
| `load()` do `.tscn` + dependências | ~1,9 s |
| `instantiate()` | ~0 s |
| `add_child()` (`_ready()` síncrono) | ~1,2 s |
| **primeiro frame depois do add_child** | **~9,2 s** |
| frames seguintes até estabilizar | ~4 s |

O dominante é um único frame de ~9 segundos: `HarborPreview._ready()` faz
`call_deferred("_start_review")`, e `_start_review()` constrói o mundo inteiro — distritos,
serviços de emergência, frota, auditorias espaciais — de uma vez só. É congelamento, não
carregamento progressivo. **Pendência conhecida e de maior impacto percebido.**

## Streaming entre regiões

`world/harbor/ContinuousWorld.gd` mantém uma única árvore com as duas regiões:

- A cena da montanha é pré-carregada em thread (`ResourceLoader.load_threaded_request`)
  e instanciada quando o jogador se aproxima da emenda.
- Fora da vizinhança ativa, a região fica com `process_mode = PROCESS_MODE_DISABLED` e
  `visible = false` — **não simula nem renderiza**.
- Tráfego ambiente a mais de 3.400 px do jogador tem `_process`/`_physics_process`
  desligados, preservando a instância e o estado (`_budget_traffic`).
- Veículos que cruzam a ponte são transferidos de faixa entre as regiões
  (`_transfer_bridge_traffic`), sem respawn.

## Emergência e polícia

Cadeia de despacho:

```
WantedManager._dispatch_police()
   └── HarborEmergencyDirector.request_dispatch()   (world/harbor/)
         └── EmergencyDepotDirector.request_dispatch()   (world/shared/emergency/)
               └── EmergencyPool.get_vehicle()      (autoload, pool finito)
```

Pontos que já causaram confusão e valem conhecer:

- `request_dispatch()` recusa despachar enquanto `can_process()` for falso — e a cutscene
  de chegada (`HarborArrivalMission._begin_arrival()`) **pausa a árvore inteira**. Um
  teste automatizado que não pula a cutscene vê todo despacho retornar `null`.
- O roteamento usa `EmergencyLaneRouter` (`world/shared/roads/`), um planejador sobre o
  grafo de `Path2D` do grupo `unified_traffic_lane`. Ele só liga um veículo à malha se
  estiver a **≤180 px** de uma faixa; fora disso cai num caminho alternativo.
- `EmergencyVehicle.gd` não usa `NavigationAgent2D`: é direção manual com `lerp_angle`
  rumo a um waypoint, e recuperação de travamento por ré. Se o waypoint for inalcançável,
  o ciclo de ré pode se repetir.

## Pendências conhecidas

- **Congelamento de ~9,2 s** num único frame no carregamento (`_start_review`).
- **`RegionTravel.gd:190`** faz `load("res://PlayerCar.tscn").instantiate()` e essa cena
  não existe em lugar nenhum — crash latente. Registrado em
  `tools/check_references.py` (`KNOWN_BROKEN`).
- **Circulação de emergência**: uma viatura observada com 15 ciclos de ré em 45 s sem
  causa isolada; ambulância que não sai do pool para uma ocorrência junto ao hospital.
- **`.tscn` com BOM não carrega**: dois arquivos começam com byte order mark UTF-8 e o
  parser do Godot recusa (`Expected '['`) --
  `legacy/district/bairro1_v2/landmarks/LandmarksV2.tscn` e
  `prototypes/living_cast/FleetShowcasePhase2.tscn`. Nenhum está no jogo vivo. Os `.gd`
  com BOM (30 arquivos) o Godot aceita normalmente.

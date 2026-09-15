# Plano de reorganização de pastas por domínio

> Status (2026-09-15): **5 de 8 domínios executados e commitados** —
> `economy/`, `guns/`, `cars/`, `geodata/`, `systems/`. Cada um foi movido via
> `tools/move_folder_refactor.py`, verificado com `check_references.py` +
> `--import` + carregamento real do jogo (`test_menu_flow_integration.gd` e um teste
> focado por domínio), e commitado separadamente — ver `git log` para as mensagens
> detalhadas de cada um.
>
> **`police/`, `emergency/` e `characters/` ficam pendentes de propósito**: os três
> exigem mover `PoliceOfficer.gd`, `WantedManager.gd`, `EmergencyVehicle.gd` ou
> `Player.gd` — os próprios arquivos, não só referências dentro deles — e esses quatro
> têm trabalho não commitado de outra sessão (Antigravity) por dentro. Assim que esse
> trabalho for commitado (ou descartado), esses três últimos domínios seguem o mesmo
> procedimento dos outros cinco.
>
> `world/shared/` hoje só tem `emergency/`, `pedestrians/` e `pickups/` — exatamente os
> três domínios adiados.

## Objetivo e escopo decidido

Objetivo do usuário: abrir o projeto e entender o que é o quê pelo nome da pasta —
`/Cars`, `/Guns`, `/Police`, `/Systems`, `/Geodata`, `/Assets`, `/Characters` — em vez de
uma pilha de scripts soltos.

Duas decisões já tomadas (2026-09-15):

1. **Escopo**: só o que é global/compartilhado. `world/harbor/` e `world/mountain_pass/`
   **continuam existindo como estão** — são as duas regiões jogáveis do mapa, não
   sistemas, e misturar o conteúdo das duas dentro de `/Police` ou `/Cars` dissolveria
   essa organização por região sem necessidade. O que entra neste plano é: os **82
   scripts soltos na raiz do projeto** (6 deles são só do jogo legado, vão para
   `legacy/`, não para um domínio — ver adiante) e os **160 scripts de `world/shared/`**
   (14 subpastas + 6 arquivos soltos na própria raiz de `world/shared/`) — o material que
   hoje não tem nenhum dono de região, ou está solto sem categoria nenhuma.
2. **Timing**: só planejar agora. Execução fica para quando `EmergencyVehicle.gd` e
   `PoliceOfficer.gd` — sendo editados por outra sessão no momento deste plano — forem
   commitados. Ver nota no topo de [ESTADO_DO_PROJETO.md](ESTADO_DO_PROJETO.md).

## Os 8 domínios propostos

Pastas novas na **raiz do projeto** (nome em minúsculo, para bater com a convenção já
usada em `ui/`, `world/`, `audio/`, `assets/`):

Contagem exata (recontada arquivo por arquivo depois de resolver os casos ambíguos):

| pasta | conteúdo | origem | arquivos |
|---|---|---|---|
| `cars/` | veículos, motos, ferro-velho/garagem, corrida | raiz (19) + `world/shared/traffic,motorcycles,salvage` (33) | 52 |
| `guns/` | armas, projéteis, efeitos de combate/dano | raiz (8) + `world/shared/combat,ammunation` + solto (28) | 36 |
| `police/` | polícia, procurado, apreensão | raiz (4) + `world/shared/pickups,emergency(Police*)` (6) | 10 |
| `emergency/` | ambulância, bombeiro, coroner, despacho | raiz (8) + `world/shared/emergency` restante (33) | 41 |
| `characters/` | jogador (a pé e de carro), pedestres, NPCs, gangues, roupas | raiz (12) + `world/shared/pedestrians` (15) | 27 |
| `geodata/` | malha viária, ferrovia, natureza, trânsito intermunicipal, props de mundo | raiz (5) + `world/shared/roads,rail,nature,transit` + soltos (34) | 39 |
| `economy/` | coletáveis, dinheiro, loja, conquistas | raiz (5) | 5 |
| `systems/` | autoloads genéricos, apresentação/render, manutenção de mundo | raiz (11) + `world/shared/atmosphere,interiors,traffic(PopulationActivity)` + soltos (11) | 22 |

Total: 232 arquivos (72 da raiz + 160 de `world/shared/`), fora os 6 que vão para
`legacy/` e os 4 que vão para `ui/`/`audio/`.

`world/shared/` fica **retirado** ao final (todo o conteúdo redistribuído); `world/harbor/`
e `world/mountain_pass/` continuam apontando para esses domínios pelos novos caminhos
(ex.: `res://police/PoliceOfficer.gd` em vez de `res://police/PoliceOfficer.gd`).

Dois casos **não** viram pasta de domínio nova, por já terem endereço melhor:
- `HUD.gd` (raiz) → entra em `ui/`, que já existe e já é o lugar certo pra interface.
- `CityAudioManager.gd`, `ProceduralAudio.gd`, `ExpressiveVoice.gd` (raiz) → entram em
  `audio/`, que já existe e já concentra tudo de som do projeto.

## Mapeamento completo

### `cars/`

| origem | arquivo |
|---|---|
| raiz | `VehicleCatalog.gd`, `VehicleDoorVisual.gd`, `VehicleDrivetrain.gd`, `VehicleGeometryCache.gd`, `VehicleLaunchControl.gd`, `VehicleMeshBatcher.gd`, `VehicleMotionSafety.gd`, `VehicleSkidMarks.gd`, `VehicleSurfaceWear2D.gd`, `VehicleTireTrail.gd`, `VehicleBoarding.gd` |
| raiz | `RaceCatalog.gd`, `DriftZoneCatalog.gd`, `DriftChallengeZone.gd`, `NightRaceController.gd` |
| raiz | `ChopShopCrusher3D.gd`, `ChopShopZone.gd`, `CarChalkboard.gd`, `CustomsWorkshopMenu.gd` |
| `world/shared/traffic/` | 14 (todos exceto `PopulationActivity`, que vai para `systems/` — ver abaixo): `CameraSimulationArea`, `EmergencyRoadManeuver`, `LanePedestrianCorridor`, `ParkedVehicleSpawn`, `TaxiDestinations`, `TaxiRoute`, `TaxiService`, `TrafficBodySweep`, `TrafficEmergencyYield`, `TrafficFlowModel`, `TrafficHorn`, `TrafficSimulationBudget`, `TrafficSirenManeuver`, `TrafficVehicle` |
| `world/shared/motorcycles/` | todos os 7: `CruiserMotorcycle`, `DanteMotorcycleRider`, `MotorcycleCatalog`, `MotorcycleModel`, `MotorcycleSilhouette`, `SportMotorcycle`, `UrbanMotorcycle` |
| `world/shared/salvage/` | todos os 12: `Neco`, `SalvageAudio`, `SalvageBayMarker`, `SalvageFloodlights`, `SalvageLedger`, `SalvageLocation`, `SalvageLocator`, `SalvageSign`, `SalvageTargetMarker`, `SalvageYard3D`, `TowJobs`, `TowService` |
| raiz (legado, não vivo) | `VehicleUpgradeManager.gd` — **não vai para `cars/`**, vai para `legacy/` (ver seção de legado abaixo) |

### `guns/`

| origem | arquivo |
|---|---|
| raiz | `WeaponCatalog.gd`, `WeaponStore.gd`, `WeaponWheel.gd`, `WeaponIcon3D.gd`, `Bullet.gd`, `GrenadeProjectile.gd`, `FlameJet.gd`, `AmmuNationInterior.gd` |
| `world/shared/combat/` | todos os 23: `BlastImpulse`, `BloodTransferSystem`, `BodyFragmentMesh`, `BodyWound`, `BodyWoundTrail`, `BulletReaction`, `CombatWorld`, `ExplosionRemains`, `ExplosionVisual`, `FragmentAtlasPresentation`, `GroundBlood`, `InteriorRemainsPresentation`, `PersonBurning`, `ShotFeedback`, `ShotQuery`, `VehicleBlast`, `VehicleDamageParticles`, `VehiclePersonImpact`, `VehicleSplash`, `WeaponBlastDamage`, `WeaponEffects`, `WeaponReload`, `WoundedPose` |
| `world/shared/ammunation/` | todos os 4: `AmmunationArt`, `AmmunationBranchView`, `AmmunationFacade3D`, `AmmunationPassage` |
| `world/shared/` (solto) | `ImpactDebris.gd` |

Nota: `combat/` cobre também dano corpo-a-corpo (o próprio `WeaponCatalog` trata soco,
faca, taco e machado como "armas"), por isso fica dentro de `guns/` e não vira um domínio
`melee/` separado.

### `police/`

| origem | arquivo |
|---|---|
| raiz | `PoliceOfficer.gd`, `WantedManager.gd`, `PoliceVehicleStop.gd`, `SpikeStrip.gd` |
| `world/shared/pickups/` | `PoliceLoot.gd` |
| `world/shared/emergency/` | `PoliceAppearance.gd`, `PoliceFootNavigation.gd`, `PoliceMotorcycleCrew.gd`, `PoliceMotorcycleModel.gd`, `PoliceVehicleCombat.gd` (os 5 arquivos de `emergency/` com prefixo `Police*`, que são especificamente sobre policiamento, não sobre despacho médico/bombeiro) |

`WantedManager.gd` é autoload — muda só o caminho no `project.godot`
(`res://police/WantedManager.gd` → `res://police/WantedManager.gd`), não o comportamento.

### `emergency/`

| origem | arquivo |
|---|---|
| raiz | `EmergencyPool.gd`, `EmergencyVehicle.gd`, `EmergencyVehicleVisual3D.gd`, `EmergencyCrewTransition.gd`, `Firefighter.gd`, `Paramedic.gd`, `Mortician.gd`, `ResponderNavigation.gd` |
| `world/shared/emergency/` | os 33 restantes (todos exceto os 5 `Police*` movidos para `police/`): `AmbulanceApproach`, `AmbulanceManeuverReservation`, `AmbulanceTrafficPassage`, `CoronerCare`, `CoronerGrave`, `CoronerInteriorAccess`, `CoronerRecoveryBag`, `DepotDriveway`, `DepotGate`, `DocksParking`, `EmergencyDepotDirector`, `EmergencyDepotMarker`, `EmergencyLightbar3D`, `EmergencyStandbyPoint`, `EmergencyVehicleTheft`, `EmergencyVehicleYard`, `FireSuppression`, `HospitalArrival`, `HospitalParkingSearch`, `MedicalFormationNavigation`, `MedicalOutdoorDepth`, `MedicalParkingRouteSearch`, `MedicalRescueSequence`, `MedicalRescueWorkZone`, `MedicalStretcher`, `MedicalWitness`, `ModernTrafficFactory`, `NPCMedicalCare`, `RescueDanger`, `ServiceIncidents`, `VehicleResidualFire`, `VehicleWaterCannon`, `VehicleWaterWash` |

`EmergencyPool.gd`, `NPCMedicalCare.gd` e `CoronerCare.gd` são autoloads — só o caminho
no `project.godot` muda.

### `characters/`

| origem | arquivo |
|---|---|
| raiz | `Player.gd`, `PlayerCar.gd`, `PlayerCombatPose.gd`, `AnimatedPedestrian3D.gd`, `PedestrianDanger.gd`, `JagerNPC.gd`, `CarjackedDriver.gd`, `GangManager.gd`, `CharacterFallPresentation.gd`, `CharacterPreview3D.gd`, `OutfitCatalog.gd`, `ClothingStore.gd` |
| `world/shared/pedestrians/` | todos os 15: `AuthoredSidewalkPedestrian`, `CitizenAppearance`, `CitizenDetails`, `CitizenFace`, `CitizenGait`, `CitizenGeometry`, `CitizenMorphology`, `CitizenSculpt`, `NPCCombatRig`, `PedestrianNeighborhood`, `PedestrianWalkSpace`, `PersonMotion`, `ProfessionalDriverModel`, `ServiceUniformDetails`, `WinterWardrobe` |

### `geodata/`

| origem | arquivo |
|---|---|
| raiz | `TrafficLightManager.gd`, `ProceduralBuilding.gd`, `StreetLamp.gd`, `Puddle.gd`, `PhoneBox.gd` |
| `world/shared/roads/` | todos os 9 + subpastas: `BridgeSurfaceStyle`, `CityIntersection`, `EmergencyLaneRouter`, `RoadLighting`, `RoadLuminaire3D`, `RoadPostSpacing`, `StaticCanvasGeometry`, `TrafficSignalPost`, `UnifiedRoadNetwork2D`; `safety/DistrictRoadSafetySystem2D`, `safety/RailLevelCrossing2D`, `safety/RoadCrossingArea2D`; `traffic/FixedTrafficSignal`, `traffic/JunctionSignalVisual2D`, `traffic/JunctionTrafficController`, `traffic/TrafficSignalModel3D` |
| `world/shared/rail/` | todos os 8: `AmbientTrain`, `DistrictRailLine`, `HarborMountainRailRoute`, `RailMinimapOverlay`, `RailStructure3D`, `RegionalRailScenery`, `TrainAudioBank`, `TrainPiece3D` |
| `world/shared/nature/` | todos os 4: `GrassDetail`, `ProceduralStreetTree`, `ProceduralUrbanRock`, `WaterPresentation` |
| `world/shared/transit/` | todos os 4: `HarborMountainCoach`, `HarborMountainCoachService`, `RegionalCoachLanePlanner`, `RegionalIntercityCoachModel` |
| `world/shared/` (soltos) | `BreakableProp.gd`, `PhysicalCargo.gd` — os dois são a mesma coisa: física de objeto de mundo empurrável/quebrável (caixote, carga), com dano por impacto de veículo e debris ao quebrar. Só usado por `world/harbor/HarborStorageArt.gd` (caixotes do armazém do porto) e pelo teste do `WorldRenewal`. |

### `economy/`

| origem | arquivo |
|---|---|
| raiz | `Collectible.gd`, `CollectibleCatalog.gd`, `CashPickup.gd`, `HealthPickup.gd`, `AchievementCatalog.gd` |

Domínio pequeno de propósito — são só 5 arquivos, mas são conceitualmente distintos de
tudo o resto (recompensa/progressão do jogador, não um sistema de simulação).

### `systems/`

| origem | arquivo |
|---|---|
| raiz (autoloads genéricos) | `SaveManager.gd`, `SettingsManager.gd`, `Localization.gd`, `CampaignState.gd`, `DistrictRestrictionManager.gd`, `RegionTravel.gd`, `PresentationBudget.gd` |
| raiz (apresentação/render) | `DynamicCamera.gd`, `RenderQuality.gd`, `ContactShadow.gd`, `DayNightWeatherManager.gd` |
| `world/shared/atmosphere/` | todos os 3: `AtmospherePalette`, `AtmosphereProfile`, `RegionalAtmosphere` |
| `world/shared/interiors/` | todos os 4: `ExteriorOcclusion`, `InteriorActorPresentation`, `InteriorSolidProjection`, `InteriorVehiclePresentation` |
| `world/shared/traffic/` | `PopulationActivity.gd` — lido a fundo: liga/desliga simulação (`_process`, colisão, SubViewport) de veículos **e** pedestres por proximidade da câmera, para economia de frame. Não é sobre carro, é orçamento de simulação genérico — por isso saiu de `cars/` e veio pra cá. |
| `world/shared/` (soltos) | `WorldRenewal.gd`, `LivePoseShadow.gd`, `StaticGroundShadow.gd` |

\* `PhysicalCargo.gd` é sobre carga física carregável (provavelmente ligado a caminhões
do porto) — poderia ir para `cars/` ou até `geodata/`. Ficou em `systems/` por falta de um
lar óbvio; é o caso mais fraco deste mapeamento, ajuste se souber o uso real.

### Vai para `ui/` e `audio/` (pastas já existentes, não domínios novos)

| destino | origem |
|---|---|
| `ui/` | `HUD.gd` (raiz) |
| `audio/` | `CityAudioManager.gd`, `ProceduralAudio.gd`, `ExpressiveVoice.gd` (raiz) |

### Vai para `legacy/` (não é domínio — é código exclusivo do jogo antigo)

| origem | arquivo | por quê |
|---|---|---|
| raiz | `GarageMenu.gd`, `GarageMenu.tscn`, `GarageTrigger.gd`, `GarageTrigger.tscn` | só referenciados por `legacy/city_demo/scripts/CityDemo.gd` |
| raiz | `VehicleUpgradeManager.gd` | só referenciado por `legacy/CentralDistrict.gd` e por um teste de compatibilidade |
| raiz | `MissionManager.gd` | só instanciado por `legacy/CentralDistrict.gd`. A menção em `CampaignState.gd` é só um comentário dizendo o oposto — que `CampaignState` **não** chama `MissionManager`. Não confundir com o sistema de missão vivo, que é `world/harbor/campaign/` (Cobra) + `MissionVoiceMixer.gd`, que já fica em `audio/`. |
| raiz | `IronCobraMember.gd`, `IronCobraCulDeSac.gd` | implementação antiga da gangue/território "Cobra de Ferro" (cul-de-sac estilo Grove Street, brasão, barris de fogo), usada só por `MissionManager.gd` → `legacy/CentralDistrict.gd`. O sistema de gangue Cobra **vivo** é outro, em `world/harbor/cobras/` (`CobraTerritory.gd` e afins) — os dois coexistem no repositório, só um está no jogo atual. |

Esses 5 arquivos legado-only já estavam no [levantamento de arquivos não utilizados](ESTADO_DO_PROJETO.md#arquivos-não-utilizados-varredura-verificada)
como recomendação de baixo risco (os 3 originais); `MissionManager.gd` e `IronCobra*.gd`
foram identificados como o mesmo caso ao ler o conteúdo pra resolver os itens ambíguos
deste plano — vale atualizar aquele levantamento também.

## Casos que estavam ambíguos — todos lidos e resolvidos

Todos os itens que restavam foram abertos e lidos por inteiro para decidir o destino em
vez de chutar pelo nome:

- **`PlayerCar.gd`** → `characters/` (decisão do usuário, não `cars/`).
- **`PhysicalCargo.gd`** → `geodata/`, ao lado de `BreakableProp.gd`: lido por inteiro,
  é física de objeto de mundo empurrável/quebrável (caixote/carga, dano por impacto de
  veículo, debris ao quebrar), só usado por `world/harbor/HarborStorageArt.gd` e pelo
  teste do `WorldRenewal` — mesma função do irmão, não tem nada de "logística de
  caminhão" como o nome sugeria.
- **`PopulationActivity.gd`** → `systems/`, não `cars/`: lido por inteiro, liga/desliga
  simulação de veículos **e** pedestres pela mesma lógica de proximidade da câmera, é
  orçamento de performance genérico, não comportamento de carro.
- **`IronCobraCulDeSac.gd`/`IronCobraMember.gd`** → **não são domínio nenhum, são
  legado**: lidos por inteiro, só `legacy/CentralDistrict.gd` (via `MissionManager.gd`)
  os usa. É uma implementação antiga da gangue Cobra (cul-de-sac estilo Grove Street) que
  ficou para trás quando o sistema vivo migrou para `world/harbor/cobras/`. Movidos para
  a tabela de legado abaixo, junto com o `MissionManager.gd` que os instancia.
- **`ClothingStore.gd`/`OutfitCatalog.gd`** → confirmados em `characters/`: lidos por
  inteiro, são a loja de roupas (`ClothingStore.gd`, `CanvasLayer` usado por
  `Player.gd` e `world/harbor/interiors/ClothingRoom3D.gd`) e o catálogo de 10 roupas do
  Dante com proteção contra frio (`OutfitCatalog.gd`). Ficam junto do personagem pelo
  mesmo motivo de `WeaponStore.gd` ficar em `guns/` — catálogo+loja de um domínio moram
  no domínio, não em `economy/`, que fica reservado a recompensa/pickup genérico.

## O que fica de fora desta rodada, e por quê

- **`world/harbor/`, `world/mountain_pass/`** — decisão já tomada: continuam como pastas
  de região.
- **`interiors/`** (raiz, 20 scripts — banco, clínica, delegacia, hospital, etc.) — pelo
  conteúdo, isso é específico do Harbor, não compartilhado, mesmo não estando fisicamente
  dentro de `world/harbor/`. É uma inconsistência que já existia antes deste plano; fica
  registrada aqui mas fora do escopo combinado (só material *global/compartilhado*).
- **`missions/`, `scenes/`, `scripts/`, `assets/`, `cutscenes/`, `data/`** — não foram
  auditadas nesta rodada; ao que tudo indica já são pastas de propósito único razoáveis,
  mas não foram confirmadas arquivo a arquivo.

## Procedimento de execução (quando for a hora)

Seguindo o [CLAUDE.md](../CLAUDE.md) à risca, por domínio (não tudo de uma vez):

1. Confirmar que a outra sessão terminou e commitou `EmergencyVehicle.gd`/`PoliceOfficer.gd`
   (ou qualquer outra mudança em andamento) — `git status` limpo antes de começar.
2. Por domínio, do menor para o maior (`economy/` primeiro, `systems/`/`geodata/` por
   último por terem mais dependentes): `git mv` de cada arquivo + `.uid` + `.tscn`
   companheiro, usando `tools/move_folder_refactor.py --dry-run` primeiro para conferir o
   que ele reescreveria.
3. `python tools/check_references.py` — 0 quebras novas.
4. `"$GODOT" --path . --import` — reconstrói o cache de `class_name`.
5. Rodar a suíte de verificação completa do CLAUDE.md (`test_menu_flow_integration`,
   `test_opening_cutscene_runtime`, `test_pedestrian_life_routines`,
   `test_pedestrian_render_lod`, `profile_load_time_0909`).
6. Um commit por domínio, mensagem descritiva em português explicando o que mudou de
   pasta e por quê — facilita reverter um domínio específico se algo quebrar sem
   desfazer os outros.

Estimativa: 8 domínios × (mover + verificar + commitar) é trabalho de várias sessões, não
de uma tarde — por isso a recomendação é executar por domínio, confirmando cada um antes
de seguir pro próximo, em vez de tentar tudo de uma vez.

# Plano de divisão dos arquivos grandes — 01/11/2026

Varredura estática completa dos 18 arquivos de jogo com mais de 1.000 linhas, mais a faixa de
850–1.000. Só leitura e contagem; nada executado. Ponto de volta: ramo
`checkpoint-20261101-antes-arquitetura`.

**Meta:** nenhum arquivo de jogo acima de ~800 linhas; nenhuma função acima de 150 linhas.

**Padrão de extração** (já usado em `GameplayCombatSound`, `SessionMenus`, `ProductionPopulation`,
`NativeLand`): `RefCounted` com `var g` (dono) em `_init`; estado, sinais e funções sobrescritas
ficam no dono; cada função antiga vira delegação de uma linha; dentro do auxiliar, chamada a função
sobrescrevível passa por `g.`. Onde o estado só é usado pelo bloco (pose de combate do Actor,
tráfego do ProductionWorld, cache do NativeRegion), preferir **componente com estado próprio**.

Cada extração vem com `tools/verify_extracted_lines.py` (toda linha removida reaparece, na ordem),
`gdparse` e, depois de cada onda, `tools/run_core_suite.sh full` no Windows.

---

## Onda 0 — limpeza sem risco (antes de dividir)

Código sem nenhum chamador no repositório (nem por string):

| Arquivo | Remover |
|---|---|
| FullSession | `advance_residence_time` e 10 apelidos privados sem uso (`_cancel_for`, `_find_sewer_hatch`, `_perform_urban_action`, `_refresh_routine_context`, `_restore_transition_player_lock`, `_routine_director`, `_service_threatened`, `_sync_location_presentation`, `_toggle_weapon_flashlight`, `_update_world_indicator`) |
| Gameplay | `_sheath_drawing`, `_start_combat_clip` e apelidos `_damage_bullet`, `_evasion_rate`, `_sync_god_mode`, `_update_aim`, `_update_melee_buffer`, `_update_stars` |
| ProductionWorld | `_near_segment` |
| BlitzScene | `_round_shoulders`, `_cab_head` |
| Actor | `_carried_sword_transform` |
| WeaponRigPose | `chain_window`, `_shoulder_swing` (54 linhas) |
| Vehicle | `camera_lookahead` |
| CityChunkDressing | `_inside_building_node` |
| TruckersVillageSecretPassage | `set_keypad_code` |
| DispatchController | `_has_active_tactical` |
| StreetPhysics | `play_body_thud` |
| VicenteReunion | `scene_for` |

Duplicação a unificar: 9 funções de caixa com `SurfaceTool` (VehicleInterior, CityChunkDressing
`_lamp_box`, VehicleUsage, AuroraExecutiveDetail, BenchFinish, DigoWorkshopMaterials, SkateModel…)
passam a chamar `CityPropKit.box`/`_rotated_box`; `_material(color)` repetido em 6 arquivos e
`_solid_box` em 15 viram um kit de construção em lote compartilhado.

---

## Onda 1 — risco baixo (dono não é sobrescrito, poucos chamadores)

| Arquivo (linhas) | Extrair | Dono depois |
|---|---|---|
| **BlitzScene** (2.231) | `BlitzSet` (montagem do cenário + aquecimento, ~790), `BlitzShootout` (~200), `BlitzDanteBeats` (~600) | ~700 |
| **TruckersVillageSecretPassage** (1.277) | dados `VAULT_DIGITS`/`AUDIO_PICKUPS` → `data/catalogs/TruckersPassageClues.gd`; `TruckersCellarBuilder` (~360); `TruckersPassageKeypad` (~105); `TruckersPassageTravel` (~210) | ~560 |
| **VicenteReunion** (1.009) | falas `*_lines` → `Act2Lines.gd` (ajustar `tools/build_voice_registry.py`); `VicenteAct2Objectives` (~75); classes internas `Raider`/`BrotherFighter` em arquivos próprios; `SPOTS`/`CHAIN_TITLES` em dados | ~660 |
| **CityChunkDressing** (1.618, estático) | `CityGroundFaceUp` (~140), `CityRoadDecals` (~150), `CityRooftopDressing` (~355), `CityNightLamps` (~380); tabelas `FURNITURE`, `ROOF_*`, `WORKSHOP_VEHICLE_ACCESS` em dados | ~620 |
| **HarborBuildingDressing** (1.329) | `HarborLifeObjects` (~210), `HarborFurnitureKit` (~405). Não mudar a ordem dos sorteios de `_rng` | ~720 |
| **DispatchController** (1.080) | `DispatchSpaceQueries` (~95), `DispatchEmergencyAssign` (~145), `DispatchPoliceAssign` (~263); unificar o passo comum de `dispatch_police_to`/`dispatch_service_to` | ~580 |
| **FragileProps3D** (1.063, estático) | dados `KINDS`/`MASSES`/`POST_HEIGHT`/`SOFT_KINDS` → `data/catalogs/FragilePropKinds.gd`; `FragileDebrisBodies` (~160), `FragilePostFall` (~205), `FragileTumble` (~270) | ~330 |
| **NativeRegion** (1.862) | `NativeTerrainTasks` (~90), `NativePrewarm` (~120) | — |

## Onda 2 — risco médio (overrides em testes ou subclasses; exige `g.` cuidadoso)

| Arquivo | Extrair | Dono depois | Atenção |
|---|---|---|---|
| **FullSession** (2.517) | `SessionTransitionRules` (~150), `SessionGarage` (~330), `SessionInteraction` (`nearest`, `interact`, corpo do `_input`, ~430), `SessionPlaces` (~560) | ~790 (com Onda 3) | `_input`, `_menu`, `_respawn`, `show_message` etc. sobrescritos em `TestSession`/`DialogueSession` |
| **Gameplay** (2.516) | `GameplayArsenal` (~165), `GameplayKatana` (~260), `GameplayMelee` (~200), `GameplayFire` (~290, quebrar `_stall_fire_at` de 194 linhas), `GameplayDamage` (~260) | ~1.000 → ~800 com `GameplayTuning` (constantes) | 13 subclasses de teste; `_damage`, `_hit_effect`, `_sound` sobrescritos |
| **ProductionWorld** (2.281) | `ProductionTraffic` como componente com estado próprio (~270), `ProductionPrewarm` (~620, quebrar `_prewarm_regions` de 172) | — | `_on_screen` homônimo em 7 arquivos |
| **NativeRegion** | `NativeRecordBuilders` (~440), `NativeRecordCache` + aposentadoria como componente (~200) | ~820 | `EditableRegion` e 10 testes sobrescrevem `_build_record`, `_building`, `prepare_data` |
| **DispatchUnit** (1.499) | `DispatchUnitService` (~160), `DispatchUnitDeparture` (~104), `DispatchUnitSuspension` (~125), `DispatchUnitPoliceCrew` (~115) | ~650 (com Onda 3) | `_target`/`_sees_target` sobrescritos; 12 privados chamados por testes |
| **VehicleInterior** (1.219, estático) | `VehicleCabinMesh` (~320, usar `CityPropKit.box`), `VehicleRoofCut` (~175); `KINDS`/`OVERRIDES` em dados | ~720 | static vars lidas por testes |
| **VehicleBoardingPresentation** (1.104) | `BoardingPathPlanner` (~190), `BoardingDoorMotion` (~85), `BoardingMocapDriver` (~185) | ~680 | testes leem `phase`, `_motion`, chamam `_apply` |
| **StreetPhysics** (1.056) | `StreetDebrisFx` (~205), `StreetVehicleCrash` (~155), `StreetPersonImpact` (~120) | ~580 | 9 subclasses de teste; estáticas de material reexportadas |
| **Faixa 850–1.000** | CombatEffects (`_ready` de 217 linhas → montagem separada), JessicaGetawayDriver (`tick` de 180 em etapas), DesertDrag (`_start` de 152), SettingsMenu (construção de ~470 linhas → `SettingsMenuBuilder`), HarborRouteProps (`create_streetlight` de 150), CanalTunnel3D (tabela `material` → dados) | — | — |

## Onda 3 — risco alto (ordem de inicialização, caminho quente por quadro, dezenas de testes)

Só depois das ondas 1–2 verdes e com medição A/B no export release (`GETECO_*`).

| Arquivo | Extrair | Por que é alto |
|---|---|---|
| FullSession | `SessionStartup` (corpo do `_ready`, 335 linhas, ~54 sistemas com `await`) | ordem dos `await` e do sinal `startup_finished` |
| Gameplay | `GameplayPolice` (procurado, estrelas, ~300) | `stars` lido em 163 arquivos |
| ProductionWorld | `ProductionResidency` (montagem/desmontagem de regiões), `ProductionBuild` (`build` de 324 linhas em etapas) | 66 testes; streaming; ordem de inicialização |
| NativeRegion | `NativePrepare` (`_prepare` de 194 linhas) | dados de toda a região |
| Actor (1.734) | `ActorSeatPose` (~145, baixo), `ActorLocomotionPose` (~230, médio), `ActorCombatPose` como componente com estado próprio (~670; quebrar `_apply_combat_weapon_pose` 216 e `_solve_combat_arm` 176) | roda por quadro e por osso; 9 subclasses de jogo |
| Vehicle (1.515) | `VehicleMotorcycleRider` (~80), `VehicleDoorLayout` (~120), `VehicleLodWreck` (~120), `VehicleTrafficDrive` (~390); quebrar `_ready` (142) e `_stall_physics_tick` (153) | 8 subclasses, física por quadro, 214 testes |
| WeaponRigPose (1.087) | constantes → `WeaponPoseData`, `WeaponRigReload` (~150), `WeaponRigStance` (~150), `WeaponRigGrips` (~90); `update` de 476 linhas em etapas | pose por quadro, visual sensível |
| DispatchUnit | `DispatchUnitPursuit` (~390) | perseguição por quadro |

---

## Resultado esperado

| | Hoje | Depois |
|---|---|---|
| Arquivos > 1.000 linhas | 18 | 0 |
| Arquivos > 800 linhas | 29 | ~3 (Gameplay sem tuning, FullSession, NativeRegion na faixa 800–820) |
| Funções > 150 linhas | 15 | 0 |
| Código morto conhecido | ~30 funções | 0 |
| Funções de caixa duplicadas | 9 | 1 (`CityPropKit`) |

## Ordem de execução sugerida

1. Onda 0 inteira (um commit por arquivo).
2. Onda 1 em paralelo por arquivo (não se tocam).
3. Teste no Windows: `--import`, `run_core_suite.sh full`, jogo.
4. Onda 2, um dono por vez (FullSession e Gameplay não em paralelo).
5. Teste + medição A/B.
6. Onda 3, um bloco por vez, cada um com medição antes e depois.

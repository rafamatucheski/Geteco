# Otimização em paralelo — 2026-10-13

Plano para vários agentes ao mesmo tempo. Cada tarefa tem **dono de arquivos exclusivo**: nenhum agente
mexe em arquivo de outra tarefa. A medição de desempenho é feita **uma vez, no fim, por um só agente**
(tarefa F), porque medições concorrentes se contaminam (comprovado hoje: a mesma base saiu 60% mais lenta
com outro Godot rodando).

## Por que estas tarefas (o que já está medido)

Benchmark controlado (`tests/measure/benchmark_west_route.gd`, editor, oeste do porto, meio-dia, sem
polícia, sem v-sync):

| Rodada | Quadro p50 | Quadro p95 | GPU p50 |
|---|---|---|---|
| Base | 17,7–21,3 ms | 37–45 ms | 2,4–4,9 ms |
| Sem pessoas e trânsito (`--population=0 --no-traffic`) | **7,0 ms** | 11,8 ms | 2,4 ms |
| Sem sombras do sol | 15,5 ms | 24,6 ms | 3,1 ms (draw calls 853 → 474) |
| Sem reflexos / sem fusão de prédios / sem instância de postes | dentro da variação | | |

Conclusão: **CPU é o gargalo**; pedestres + trânsito custam 11–14 ms por quadro no editor; sombras 2–5 ms.
Referência de design: GTA Vice City (reVC) — 25 pedestres e 12 carros no máximo; pedestre some a ~51 m na
tela e ~25 m fora dela; carros longe andam "sobre trilhos" sem física; luzes reais só até 22 m (máx. 32);
farol e sombra como sprite/decalque; 32 marcas de pneu no mundo todo.

## Regras comuns (todas as tarefas)

1. Leia `CLAUDE.md` e `AGENTS.md`. Comentários e logs em português; identificadores em inglês.
2. **Só edite os arquivos da sua tarefa** (coluna "Dono de"). Precisa mexer em outro? Pare e reporte.
   Também são da tarefa, sem precisar de autorização: os **testes e scripts de medição novos que a própria
   tarefa cita** (ex.: `tests/test_traffic_rails.gd`, `tests/measure/<algo da tarefa>.gd`), testes existentes
   da tarefa que precisem só de ajuste de leitura por causa da mudança (sem mudar a intenção), as evidências em
   `evidence/<pasta da tarefa>/` e o relatório `docs/otimizacao-20261013/<ID>.md`.
3. **Arquivos bloqueados para todos** (trabalho em andamento de outras pessoas, sem commit):
   clima do usuário — `runtime/Weather.gd`, `runtime/atmosphere/*`, `world/rain/*`,
   `world/city_look/{CityLook,CityLookMaterials,CityChunkDressing,CityLocalLighting,PoliceStationDressing,CoastalPlanarReflections}.gd`,
   `world/city_look/occluded_silhouette.gdshader`, `world/urban_detail/{HarborBridge3D,HarborGrassTufts,HarborRoadGeometry3D,HarborUrbanSurface3D,RuralRoadEndBlend}.gd`,
   `world/urban_detail/*.gdshader`, `assets/regions/source/world/harbor/UrbanGround.gd`, `runtime/Settings.gd`, `ui/SettingsMenu.gd`,
   `world/editing/world_edits.json`; investigação de CPU em andamento — `gameplay/dispatch/*`,
   `gameplay/street_physics/StreetPhysics.gd`, `audio/WorldAudio.gd`; medição — `tests/measure/benchmark_west_route.gd`.
4. **Interruptor obrigatório**: toda mudança de comportamento fica atrás de uma variável de ambiente
   (padrão de `world/urban_detail/GroundCut.gd`: `static var enabled := OS.get_environment("GETECO_X").is_empty()`
   ou `== "0"` para desligar). Nome na tabela. A tarefa F usa isso para o antes/depois no mesmo build.
5. **Não meça tempo de quadro nem fps.** Contagens (nós, malhas, luzes, sombras, carros ativos) podem,
   inclusive em `--headless`. Testes funcionais podem rodar em paralelo (ficam lentos; timeout → rode de novo).
6. `GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`;
   testes: `"$GODOT" --path . --script res://tests/<nome>.gd -- --no-save`. Compile `dotnet build Harbor.csproj` se mexer em C#.
7. Verificação mínima antes do commit: `test_regions`, `test_native_driving`, `cold/test_admission`
   e os testes da tarefa. Falha que também acontece com o interruptor desligado não é sua: registre.
8. **Commit só dos seus arquivos** (`git add` explícito, nunca `-A`), mensagem em português com porquê,
   números, o que foi verificado e o que não foi. Nunca `git stash/checkout/reset/clean`, nunca push, nunca export.
9. **Relatório** em `docs/otimizacao-20261013/<ID>.md`: arquivos, interruptor, o que mudou, contagens
   antes/depois, testes, o que não foi verificado, riscos visuais para o testador.

## Tarefas

| ID | Tarefa | Dono de | Interruptor | Quem |
|---|---|---|---|---|
| P1 | População e trânsito estilo Vice City + distância da sombra do sol | `runtime/ProductionWorld.gd`, `scripts/World.gd` | `GETECO_POP_VC=0`, `GETECO_SUN_SHADOW_NEAR=0` | Codex |
| P2 | Carros de trânsito "sobre trilhos" | `scripts/Vehicle.gd`, novo `gameplay/traffic/TrafficRails.gd` | `GETECO_TRAFFIC_RAILS=0` | Codex |
| P3 | Pedestres: pose/animação só de perto | `scripts/Actor.gd`, `assets/CivilianModel.gd`, `assets/civilians/MeshyBodyRig.gd` | `GETECO_PED_POSE_LOD=0` | Codex |
| P4 | Faróis e luzes de veículo como brilho + decalque, orçamento global de luzes | `gameplay/VehicleEquipment.gd`, `gameplay/VehicleLightProfiles.gd`, novo `gameplay/lights/LightBudget.gd` | `GETECO_LIGHT_BUDGET=0` | Codex |
| P5 | Detalhes de prédio e rua só de perto (`visibility_range`) e sem sombra | `world/city_look/{BuildingLife,BuildingLifeKit,CityPropKit}.gd`, `world/urban_detail/Urban*Building*.gd` (exceto Factory) | `GETECO_DETAIL_RANGE=0` | Codex |
| P6 | Piloto: prédio "assado" em arquivo (um tipo) | `world/urban_detail/UrbanBuildingFactory.gd`, `world/urban_detail/HarborBuildingBatch.gd`, novo `tools/building_bake/*`, `assets/buildings/baked/*` | `GETECO_BAKED_BUILDINGS=0` | Codex |
| P7 | Marcas de pneu com orçamento global | `gameplay/vehicle_effects/VehicleTireEffects.gd`, novo `gameplay/vehicle_effects/SkidmarkBudget.gd` | `GETECO_SKID_BUDGET=0` | Codex |
| P8 | Faixas tracejadas da rua numa peça por trecho | `world/urban_detail/HarborRoadGeometry3D.gd` (só a parte de `_build_markings`/`_add_mark`, separando o clima do usuário no commit) | `GETECO_DASH_BATCH=0` | Claude |
| P9 | Polícia: `dispatch.doors.prewarm` e `dispatch.controller.tick` (20–39 ms/quadro em perseguição) | `gameplay/dispatch/*` | `GETECO_DISPATCH_FAST=0` | Codex, **só depois do relatório da investigação de CPU** |
| P10 | Reflexo planar mais barato | `world/city_look/CoastalPlanarReflections.gd` | `GETECO_CHEAP_REFLECTIONS=0` | **bloqueada**: é do clima do usuário; só com o ok dele |
| F | Integração, medição e release | benchmark e evidências | — | Claude, no fim |

---

### P1 — População e trânsito estilo Vice City + sombra do sol mais curta

- **Começo**: em `runtime/ProductionWorld.gd`, ache `MAX_POPULATION` (40), `TRAFFIC_TARGET` (40),
  `POPULATION_SPAWN_MIN/MAX` (45/95 m), `POPULATION_DESPAWN` (120 m) e o laço de remoção de pedestres e carros
  (`_process`, ~linhas 1100-1150). A sombra do sol: `sun.directional_shadow_max_distance = 110` (ProductionWorld ~141)
  e `= 90` em `scripts/World.gd:58`.
- **Meio**:
  - Com `GETECO_POP_VC` ligado (padrão): pedestres no máximo **25**; trânsito ambiente no máximo **16**
    (não conta estacionados, missão, polícia nem o carro do jogador); pedestre comum some a **55 m** na tela e
    **30 m** fora da tela (use `_on_screen`, que já existe); nascimento continua fora da tela.
  - Revise pedestres em rodízio (uma fração por quadro), não a lista inteira todo quadro, se hoje for a lista inteira.
  - Com `GETECO_SUN_SHADOW_NEAR` ligado: `directional_shadow_max_distance` **55 m** (a câmera fica a ~36 m do foco).
  - Desligado: valores de hoje, idênticos.
- **Fim**: script de contagem (headless pode) que carrega o oeste (`--play-at=harbor,64,82`), espera 30 s e conta
  pedestres, trânsito ambiente e distância do mais longe, com e sem os interruptores.
- **Output**: contagens antes/depois; testes `test_regions`, `test_native_driving`, `cold/test_admission`,
  `test_persistent_vehicle_support`, `test_roadside_parking*`, e o que o grep achar de população/densidade.
- **Aceitar se**: ≤25 pedestres e ≤16 trânsito ambiente no oeste; nenhum carro persistente some; interruptores
  restauram o comportamento exato; testes passam ou falham igual com interruptor desligado.
- **Risco para o testador**: rua com menos gente e menos carros; sombra some a ~55 m (olhar se aparece linha
  de corte da sombra na borda da tela).

### P2 — Trânsito "sobre trilhos"

- **Começo**: `scripts/Vehicle.gd` — `_physics_process` → `_stall_physics_tick`, `_lod_gate`/`_lod_stride`
  (já existe passo a cada 4 quadros longe), `_drive_traffic`, `move_and_slide`. Entenda como a rota do trânsito
  chega ao carro (pontos/segmentos da rota do roteador C#).
- **Meio**: carro de trânsito ambiente (`traffic == true`, não controlado, não polícia, não missão, vivo, no chão)
  que esteja **fora da tela e a mais de 40 m do jogador** (ou a mais de 70 m mesmo na tela) entra em modo trilho:
  posição e rumo avançam pela rota com a velocidade alvo, altura pelo raio de chão já usado, **sem
  `move_and_slide` e sem os passes de street_physics**. Volta para a física completa quando: entra no raio, o
  jogador/projétil/veículo encosta (teste barato de esfera contra vizinhos), precisa manobrar (fim de rota,
  retorno), ou vira alvo de algo. Na transição, preserve velocidade e posição (sem salto).
- **Fim**: teste novo `tests/test_traffic_rails.gd`: carro longe entra no trilho, segue a rua por 30 s sem sair
  dela, volta à física ao aproximar o jogador, e um esbarrão força a física. Contagem: quantos carros em trilho
  e em física no oeste após 30 s.
- **Output**: contagens; testes acima + `test_native_driving`, testes de trânsito (`*traffic*`, `test_road_network_connectivity`,
  `test_canal_tunnel_traffic`).
- **Aceitar se**: a maioria do trânsito longe fica em trilho; nenhum carro atravessa prédio ou some; transição sem
  salto visível no teste; interruptor desliga tudo.
- **Risco para o testador**: carro longe "flutuando" sobre a rua, parado em cruzamento, ou dando um tranco ao virar físico.

### P3 — Pedestres: pose só de perto

- **Começo**: `scripts/Actor.gd` (`_physics_process`, LOD a 45 m com passo de 3), `assets/CivilianModel.gd`,
  `assets/civilians/MeshyBodyRig.gd` (`PoseDriver._process` → `rig.sync` todo quadro).
- **Meio**: com `GETECO_PED_POSE_LOD` ligado: fora da tela, não sincroniza pose; a mais de 30 m na tela,
  sincroniza a cada 2–3 quadros; o `PhysicalBoneSimulator3D` só ativa quando precisa (queda/ragdoll). Nada muda
  para o jogador e para quem está em diálogo, combate ou reação.
- **Fim**: teste: pedestre fora da tela não chama `sync`; pedestre perto continua chamando todo quadro; ragdoll
  continua funcionando (procure os testes de ragdoll/queda existentes).
- **Output**: quantos `sync` por segundo no oeste antes/depois (contagem); testes de Meshy
  (`test_meshy_*`, `test_role_meshy_bodies`, `test_police_meshy_body`), `test_regions`.
- **Aceitar se**: queda clara de syncs; nenhum pedestre visível "congelado" perto; interruptor desliga.
- **Risco para o testador**: pedestre ao longe andando "em câmera lenta" ou travando a animação.

### P4 — Luzes de veículo e orçamento global

- **Começo**: `gameplay/VehicleEquipment.gd` (projetores, `npc_beam`), `gameplay/VehicleLightProfiles.gd`.
  O log `light_owners` (adicionado hoje em `runtime/SessionSystemProfile.gd`) mostra quem acende luz.
- **Meio**: com `GETECO_LIGHT_BUDGET` ligado: veículos de trânsito usam **sprite de brilho + `Decal`** no chão
  como farol (sem `SpotLight3D`/`OmniLight3D`); só o carro do jogador e no máximo **8** luzes de veículo reais
  no total, as mais próximas da câmera, até **25 m**. Crie `gameplay/lights/LightBudget.gd` como registro global
  (estático) que decide quem acende. Sirenes de polícia: brilho piscando sem luz real fora do orçamento.
- **Fim**: teste à noite: no oeste com 16+ carros, luzes reais de veículo ≤ 8; o carro do jogador ilumina a rua;
  com o interruptor desligado volta ao de hoje.
- **Output**: contagem de luzes reais à noite antes/depois; testes de luz/veículo (`test_city_local_lighting`,
  `test_fleet_lens_roles`, `test_motorcycle_boarding_continuity`).
- **Aceitar se**: ≤ 8 luzes reais de veículo à noite; farol do jogador intacto; visual aceitável.
- **Risco para o testador**: farol de NPC sem iluminar o chão de verdade (só a mancha).

### P5 — Detalhes só de perto

- **Começo**: `world/city_look/BuildingLife.gd`/`BuildingLifeKit.gd` (varal, ar-condicionado, escada de incêndio),
  `world/city_look/CityPropKit.gd` (mobiliário), `world/urban_detail/Urban*Building*.gd` (molduras, letreiros, grades).
- **Meio**: com `GETECO_DETAIL_RANGE` ligado: `visibility_range_end` ~**40 m** (com `visibility_range_end_margin`
  para fade) e `cast_shadow` desligado em detalhes pequenos (altura ou maior lado < 1,5 m, ou classificados como
  detalhe); volumes grandes não mudam. Não mexa em portas, letreiros que acendem e no que `TunnelCutaway`/
  `ExteriorReveal` procuram.
- **Fim**: contagem headless no oeste e no leste: geometrias com visibility_range, sombras a menos.
- **Output**: contagens; testes de prédios (`urban_detail/test_urban_building_factory`, `test_harbor_building_source_fidelity`,
  `test_harbor_building_batch`, `test_harbor_access_exteriors`, `test_tunnel_cutaway`).
- **Aceitar se**: sombras de detalhes caem e nada some a menos de 40 m; testes passam.
- **Risco para o testador**: detalhe "aparecendo" ao se aproximar (pop-in).

### P6 — Piloto de prédio assado

- **Começo**: `world/urban_detail/UrbanBuildingFactory.gd`, `HarborBuildingBatch.gd` (fusão de hoje), e como a
  frota faz isso: `runtime/RedesignedFleet.gd` + `tools/fleet_fixups/*` (montar uma vez, fundir, salvar `.scn`).
- **Meio**: escolha **um** tipo (sugestão: `UrbanCommercialBuilding`). Ferramenta em `tools/building_bake/` que
  gera, para cada variação usada no porto, uma cena com malha fundida, colisão simplificada (poucas caixas) e uma
  versão LOD (volume com a cor/textura da fachada) usada a partir de ~50 m via `visibility_range`. A factory usa a
  cena assada quando existe e o interruptor está ligado. Partes vivas (portas, letreiros acesos, acessos) ficam separadas.
- **Fim**: contagem de malhas/colisões por prédio desse tipo antes/depois; custo de montagem do registro medido em
  ms **headless e marcado como indicativo** (montar 20 vezes e tirar a mediana) — é o único tempo permitido aqui.
- **Output**: arquivos assados, contagens, testes de prédios e de acesso.
- **Aceitar se**: o tipo escolhido fica visualmente igual de perto, com bem menos malhas e colisões e montagem mais
  rápida; portas e acessos funcionam.
- **Risco para o testador**: prédio diferente do original, porta que não abre, colisão estranha.

### P7 — Marcas de pneu com orçamento global

- **Começo**: `gameplay/vehicle_effects/VehicleTireEffects.gd` (`MAX_MARK_SEGMENTS = 320` por veículo, redesenho a cada 0,1 s).
- **Meio**: com `GETECO_SKID_BUDGET` ligado: `SkidmarkBudget.gd` estático com no máximo **256 segmentos no
  mundo inteiro** (os mais antigos saem primeiro), uma malha compartilhada por região/trecho ou um anel de
  buffer; redesenho só quando muda; material único (já existe `mark_material()`).
- **Fim**: teste: 10 carros derrapando não passam de 256 segmentos; marcas somem por idade; o material continua um só.
- **Output**: contagens; `test_vehicle_effects` e o que o grep achar de pneu/derrapagem.
- **Aceitar se**: orçamento respeitado e marcas visualmente iguais em uso normal.

### P8 — Faixas tracejadas (Claude)

- `HarborRoadGeometry3D._build_markings/_add_mark`: hoje cada tracinho é um `MeshInstance3D` (~64 por área de 128×64 m).
  Juntar num `MultiMeshInstance3D` (ou numa malha) por trecho e por cor. Commit separando o trabalho de clima do usuário.

### P9 — Polícia (depois do relatório da investigação de CPU)

- Só comece quando `evidence/profile-west-cpu-20261013/resumo.md` existir. Alvos: `dispatch.doors.prewarm` (aparece
  centenas de vezes; 20–39 ms por quadro em perseguição) e `dispatch.controller.tick`. Medir com contagem de chamadas
  e spans (sem fps), corrigir o que o relatório apontar, interruptor `GETECO_DISPATCH_FAST`.

### F — Integração, medição e release (Claude, no fim)

1. Quando todas as tarefas aceitas estiverem commitadas: rodar a verificação completa uma vez.
2. Benchmark serial, sem outro Godot aberto: base (todos os interruptores desligados) ×2, tudo ligado ×2, e cada
   interruptor sozinho; de dia, à noite e com chuva. Release exportado: base ×2 e tudo ligado ×2.
3. Relatório com a tabela final e o export para o usuário testar.

## O que esperar no fim (estimativa, a confirmar na tarefa F)

Oeste do porto, editor, de dia: de 18–21 ms para **~6–9 ms** por quadro; release de 47–62 fps para **~120–144 fps**;
travadas de montagem de prédio perto de zero; ganhos maiores à noite (luzes) e com chuva (reflexo). Cada número
precisa sair do benchmark; o que não melhorar mais que a variação entre rodadas repetidas não conta.

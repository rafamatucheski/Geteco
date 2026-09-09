# Atualização de estrutura — 2026-09-09

**Para: Antigravity e Astra.** Leiam antes de continuar. A estrutura de pastas do projeto
mudou hoje e caminhos que vocês conheciam não existem mais. **Nenhum comportamento do jogo
foi alterado** — só organização, nomes e documentação.

O trabalho de vocês está intacto: nada em `prototypes/gameplay_repair_art_0909/` foi
editado, e o sistema de reação de civis a tiroteio entregue em paralelo hoje
(`PedestrianDanger.gd` + integração em `Bullet.gd` e `AnimatedPedestrian3D.gd`) foi
commitado e passa na verificação.

Cinco commits, a partir de `5ce5fd0`. Documentação de referência: [ARCHITECTURE.md](ARCHITECTURE.md).
Dados brutos de tudo que é afirmado aqui: [measurements/review-0909/](measurements/review-0909/).

---

## 1. De-para de caminhos

| antes | agora |
|---|---|
| `district/harbor_preview/` | **`world/harbor/`** |
| `district/mountain_pass/` | **`world/mountain_pass/`** |
| `district/roads/` | `world/shared/roads/` |
| `district/pedestrians/` | `world/shared/pedestrians/` |
| `district/nature/`, `district/rail/` | `world/shared/nature/`, `world/shared/rail/` |
| `district/Emergency*`, `DepotGate`, `DocksParking`, `EmergencyVehicleYard`, `ModernTrafficFactory` | `world/shared/emergency/` |
| `city_demo/scripts/TrafficVehicle.gd` (+ `.tscn`) | `world/shared/traffic/` |
| `city_demo/scripts/WeaponEffects.gd` | `world/shared/combat/` |
| `city_demo/scripts/roads/CityIntersection.gd` | `world/shared/roads/` |
| `city_demo/scenes/pickups/PoliceLoot.{gd,tscn}` | `world/shared/pickups/` |
| `city_demo/art/` | **`assets/art/`** |
| `Main.tscn` | **`legacy/Main.tscn`** |
| `CentralDistrict.*`, `DistrictInteriorManager.*`, `DistrictRestrictionFeedback.*` | `legacy/` |
| `district/{bairro1,bairro1_v2,borough_one,coast,highway}` | `legacy/district/` |
| `city_demo/` (o que sobrou) | `legacy/city_demo/` |

**`district/` não existe mais.** O nome misturava região viva, malha viária e protótipos
mortos. E `harbor_preview` não era preview nenhum — era o jogo principal. Foi o nome mais
enganoso do repositório e custou tempo real.

```
world/     o jogo que roda    harbor/ (principal), mountain_pass/, shared/
ui/        MainMenu.tscn = entrypoint declarado no project.godot
legacy/    geração anterior — AINDA CARREGA em runtime, ver seção 4
OLD/       arquivo morto, tem .gdignore
raiz       72 .gd de sistemas globais (Player, PlayerCar, WantedManager, HUD, catálogos)
tools/     check_references.py, move_folder_refactor.py
docs/      estrutural na raiz; measurements/, history/
```

Os 72 scripts da raiz **não** foram reorganizados — adiado de propósito (seção 6).

---

## 2. Para o Antigravity

**Sua pasta não foi tocada.** `prototypes/gameplay_repair_art_0909/` está exatamente como
você deixou: `Casket3D`, `FuneralSequenceController`, `GraveSiteVisual`,
`EliasStorytellerModel`, `ShovelTool3D`, `PoliceDriverExtraction`,
`ExtractionDemoRigFactory`, as capturas, os três vídeos e o `INTEGRATION_CONTRACT.md`.

Duas coisas que te afetam:

**Os alvos de integração do seu contrato mudaram de lugar.** O `INTEGRATION_CONTRACT.md`
nomeia os arquivos onde a Astra deve integrar. Onde eles estão agora:

| no contrato | caminho atual |
|---|---|
| `PoliceOfficer.gd` | raiz — inalterado |
| `PoliceVehicleStop.gd` | raiz — inalterado |
| `HarborCemetery.gd` | **`world/harbor/HarborCemetery.gd`** |
| `HarborWorldEvents.gd` | **`world/harbor/events/HarborWorldEvents.gd`** |
| `scripts/player/DanteVisualAdapter.gd` | inalterado (seu `ExtractionDemoRigFactory.gd` o referencia) |

**Um `.tscn` seu não carrega.** `prototypes/living_cast/FleetShowcasePhase2.tscn` começa
com BOM UTF-8 e o parser do Godot recusa (`Expected '['`). É defeito **pré-existente**, não
do refactor — não mexi para não misturar com mudança estrutural. O mesmo vale para
`legacy/district/bairro1_v2/landmarks/LandmarksV2.tscn`. Arquivos `.gd` com BOM (30 no
projeto, incluindo vários seus) o Godot aceita normalmente; só `.tscn` quebra.

Se for referenciar o mundo compartilhado de dentro de `prototypes/`, use os caminhos novos.
Hoje há só duas referências para fora: `res://scripts/player/DanteVisualAdapter.gd` e
`res://world/mountain_pass/WinterResidentModel.gd` (esta já atualizada).

---

## 3. Para a Astra

Seu escopo pelo contrato do Antigravity é IA, física, rotas, performance, ativação de
regiões por proximidade e integração final. Tudo isso mudou de endereço:

- Roteamento e malha viária: `world/shared/roads/` (inclui `EmergencyLaneRouter.gd`)
- Despacho de emergência: `world/shared/emergency/` (classe base `EmergencyDepotDirector`)
  e `world/harbor/HarborEmergencyDirector.gd`
- Streaming e ativação por proximidade: `world/harbor/ContinuousWorld.gd`
- `WantedManager.gd`, `PoliceOfficer.gd`, `EmergencyVehicle.gd`, `Paramedic.gd`,
  `Mortician.gd`: continuam na raiz, inalterados

### Sobre "ativação de regiões por proximidade"

Já existe e funciona — não comece do zero. `ContinuousWorld.gd` mantém as duas regiões na
mesma árvore e desliga a distante: `process_mode = PROCESS_MODE_DISABLED` e
`visible = false`. Tráfego a mais de 3.400 px do jogador tem `_process`/`_physics_process`
desligados preservando instância e estado (`_budget_traffic`), e veículos que cruzam a
ponte são transferidos de faixa sem respawn (`_transfer_bridge_traffic`).

Ou seja: quando você está no porto, a montanha **não simula nem renderiza**. Ela continua
ocupando memória, e isso é o que falta atacar — não a simulação.

---

## 4. `legacy/` não é código morto

Não confunda com `OLD/`. **`legacy/` não tem `.gdignore` e é carregada em runtime.**

`world/harbor/HarborSceneRoute.gd`:

```gdscript
const GAME   := "res://world/harbor/HarborGame.tscn"
const LEGACY := "res://legacy/Main.tscn"
```

Save **sem** a flag `harbor_campaign_active` carrega `legacy/Main.tscn`. Quem começou a
jogar antes da campanha do porto continua na primeira geração do mapa. Apagar a pasta ou
colocar `.gdignore` nela quebra o save dessas pessoas.

`tests/test_legacy_save_route.gd` guarda esse contrato — instancia a cena legada de
verdade, não só confere a string. As duas gerações compartilham `Player.gd`, `PlayerCar.gd`,
`DynamicCamera.gd` e `world/shared/emergency/EmergencyDepots.tscn`; só o mapa difere.

---

## 5. Duas armadilhas que custaram tempo hoje

**Corrigir todas as strings de caminho não basta.** O projeto referencia recursos por
string, não por UID (653 `preload` + 903 `load`, e quase nenhum `path=` de `.tscn` tem
`uid=`). Mas mesmo com tudo certo no código, o registro global de `class_name`
(`.godot/global_script_class_cache.cfg`) continua apontando para os caminhos antigos e
quebra a resolução de classes. O verificador dizia 0 quebras e o jogo não carregava.

Procedimento ao mover arquivo — o passo 4 não é opcional:

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
# 1-2. tools/move_folder_refactor.py  (git mv + reescrita de referências, tem --dry-run)
python tools/check_references.py                                   # 3. 0 quebras novas
"$GODOT" --path . --import                                         # 4. reconstrói o cache
"$GODOT" --path . --script res://tests/profile_load_time_0909.gd   # 5. carrega de verdade
```

**A cutscene de chegada pausa a árvore inteira.** `HarborArrivalMission._begin_arrival()`
faz `get_tree().paused = true`, e `request_dispatch()` checa `can_process()`. Teste que
carrega `HarborGame.tscn` e não chama `campaign_controller.skip_cinematic()` vê **todo**
despacho de emergência retornar `null` — parece sistema quebrado e é só o teste. Isso já
me fez perseguir um bug inexistente por um ciclo inteiro.

### `tools/`

- `check_references.py` — valida toda referência `res://`. Distingue por contexto:
  sondagem opcional (`ResourceLoader.exists`) e destino de escrita (`save_png`) não contam
  como quebra. Falha só em quebra **nova**.
- `move_folder_refactor.py` — fez as duas movimentações de hoje (306 e 105 arquivos).
  Tem `--dry-run` e o procedimento completo no docstring. Pronto para a próxima.

---

## 6. O que continua aberto

Em ordem de impacto.

**Congelamento de ~9,2 s no carregamento.** É o que se sente ao abrir o jogo.
`HarborPreview._ready()` faz `call_deferred("_start_review")` e `_start_review()` constrói o
mundo inteiro — distritos, emergência, frota, auditorias — **em um único frame**. Perfil
completo em `docs/measurements/review-0909/load_profile.txt`. A correção é fatiar o
trabalho entre frames.

**`RegionTravel.gd:190` — crash latente.** `load("res://PlayerCar.tscn").instantiate()`, e
`PlayerCar.tscn` não existe em lugar nenhum: `load()` devolve null e `.instantiate()`
estoura. É autoload, no caminho que reconstrói veículo a partir do save. Não corrigi porque
não sei qual era a cena pretendida — precisa de quem conhece o histórico.

**Circulação de emergência, investigação parada no meio.** Em 45 s de perseguição real, três
viaturas de quatro andam normal; a quarta deu **15 ciclos de ré** (~1 a cada 3 s) e mesmo
assim progrediu — taxa anormal com causa **não isolada**. As duas ambulâncias do pool nunca
saíram do estacionamento apesar de um atropelamento real perto do hospital, e junto apareceu
erro reproduzível: `Paramedic.gd:368` chama `rescue_from_emergency()` em
`AnimatedPedestrian3D.gd:1424`, que reconecta o sinal `arrived_at_depot` já conectado.
Reprodução: `tests/reproduce_review_0909_stage2.gd`; log em
`docs/measurements/review-0909/review0909_stage2.txt`; a folha de contato da viatura girando
em `docs/measurements/review-0909/evidencias/video2-sheet0.jpg`.

**Reorganizar os 72 scripts da raiz.** Adiado de propósito: são alvo de ~1.556 caminhos
hardcoded e dos 10 autoloads de uma vez. `tools/move_folder_refactor.py` está pronto —
basta preencher a lista `MOVES`.

**`.tscn` com BOM** — os dois citados na seção 2.

---

## 7. Sobre a performance — o que foi descartado e o que não foi

Três amostras de 60 s em cada resolução, renderização real:

| | 720p | 1080p |
|---|---|---|
| frame time mediano | ~22 ms | ~22,7 ms |
| p95 | ~82 ms | ~92 ms |
| p99 | ~124 ms | ~140 ms |
| draw calls | ~16.050 | ~16.420 |

**A resolução não explica a queda percebida.** 1080p renderiza 2,25× mais pixels com frame
time mediano praticamente igual. O que aparece nas duas é stutter forte na cauda, não
framerate baixo constante.

Uma bisecção pausando os 249 `SubViewport` não mostrou efeito — eles já usam
`UPDATE_ONCE`/`UPDATE_DISABLED`, então custam pouco por frame (mas caro na construção e
~1,3 GB de VRAM).

**Cuidado ao citar isso:** a bisecção rodou em fases sequenciais com o estado do mundo
crescendo ao longo dela, então é ausência de evidência numa rodada confundida — **não**
prova de que resolução e SubViewport estão descartados. A hipótese mais sustentada é custo
crescente ligado à duração da perseguição, e ela não foi confirmada com medição isolada.

Reportem percentis em **milissegundos**, não convertidos para FPS: percentilar uma métrica
invertida distorce a cauda.

---

## 8. Territórios e higiene

- `prototypes/gameplay_repair_art_0909/` é do Antigravity. Astra não edita.
- `OLD/` é arquivo morto com `.gdignore`. Só entra arquivo verificado sem referência **por
  caminho e por UID** — a varredura só por nome já produziu conclusão errada aqui: `car.png`
  parecia sem uso e é usado por `EmergencyVehicle.gd`, `PlayerCar.gd` e `VehicleCatalog.gd`.
- Antes de mover ou apagar, confira se outra sessão está com o repositório aberto. Arquivo
  novo com timestamp recente que você não criou é o sinal.
- Script que gera arquivo grava **dentro do projeto**. Saída que não é versionada não é
  encontrada por quem clona.

**Suíte verde não prova que o jogo está correto** — prova que aqueles casos passaram. Vários
defeitos reais desta base apareceram em partida de verdade com a suíte aprovada. Ao
reportar, digam o que foi medido **e o que não foi**.

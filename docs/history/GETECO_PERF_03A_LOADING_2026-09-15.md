# GETECO-PERF-03A — eliminar bloqueios prolongados no carregamento

Data: 2026-09-15. Autor: Claude. Rodada de **implementação delimitada** ao
carregamento inicial do Harbor (menu → loading → mundo pronto). Não toca nos
construtores internos da Mountain Pass nem na travessia entre regiões — isso
é escopo da rodada 03B do Antigravity.


---

## 1. Estado do repositório e preservação

| item | valor |
|---|---|
| HEAD no início e durante toda a rodada | `45ba477e6e9aff074b2959485ebc2e2e63876ae7` (`main`) |
| Commits anteriores relevantes | `0dd0be1`/`45ba477` (GETECO-PERF-02B), `9bd10e0` (02A), `0030260` (01) |
| Alterações locais de outras sessões preservadas, intactas | `characters/Player.gd`, `systems/RegionTravel.gd`, `systems/interiors/ExteriorOcclusion.gd`, `world/harbor/HarborArrivalStop.gd`, `world/harbor/campaign/HarborArrivalMission.gd`, `docs/measurements/review-0909/load_profile.txt`, 2 testes apagados, `tests/test_police_death_departure.gd` novo |
| Arquivo com mudanças de AMBAS as partes (isoladas por hunk) | `world/harbor/HarborGame.gd` — a outra sessão alterou `_start_gameplay()` em dois pontos (`loaded_from_save` → `$Player.show()`); esses dois hunks foram preservados **exatamente**, e meus `await batch.checkpoint(...)` foram inseridos só entre eles, nunca dentro |
| Comandos proibidos | nenhum `checkout`/`revert`/`reset`/`restore`/`clean`/`stash`/`git add .`/`push` foi executado |
| `prototypes/gameplay_repair_art_0909/` | não tocado |
| `legacy/` | não tocado |

Para o lado "antes" do A/B, usei uma **worktree temporária** (`git worktree add
--detach` fora do repositório) no commit `45ba477` + o diff exato das
alterações locais de outras sessões (arquivo salvo em
`tests/perf_audit_claude/results/02b_baseline_state/local_changes_others.diff`,
gerado na rodada 02B, conferido byte-a-byte contra o estado atual antes de
usar). A worktree recebeu **apenas** os meus scripts de medição (nenhum
arquivo de produção meu) e passou por `--import` antes de qualquer medição —
sem isso a primeira tentativa falhou com erros de classe/recurso não
resolvido (registrado como incidente descartado, não confundir com regressão
de código).

---

## 2. Base histórica revalidada — e uma hipótese descartada por medição direta

O relatório 01 atribuía o congelamento a `HarborSouthPort._ready()` (~5,6 s) e
a `HarborGame._start_gameplay()`/diferidos (~13 s). Antes de tocar produção,
revalidei essas pistas com o coletor atualizado (mapeamento de marcadores por
`node_added`/`ready`, técnica das rodadas 01/02B) sobre o código atual
(`45ba477`, com as alterações locais):

| pista | estado revalidado nesta rodada |
|---|---|
| `HarborSouthPort._ready()` síncrono | **Confirmada.** 5.723 ms medidos entre `child_ready:Alleys` e `child_ready:SouthPort`, sem nenhum limite de quadro real cruzando esse intervalo (script puro, não GPU) |
| `HarborGame._start_gameplay()` sem yields | **Confirmada em parte.** ~2,7 s de trabalho atribuível (ResidenceManager 1.204 ms, GangManager 1.050 ms, WorldEvents 112 ms, ArrivalMission 112 ms) dentro do bloco síncrono único, mais um trecho de ~4,7 s **não atribuído** a nenhum construtor específico (provavelmente disperso em pequenas chamadas `call_deferred` de scripts de prédios/props pela cidade — não isolado nesta rodada, ver seção 6) |
| Congelamento total do quadro (relatório 01: 23,5 s) | Revalidado em **22.484,8 ms** nesta revisão (uma execução), confirmando que 02A/02B não resolveram isso — não era esse o escopo deles |

### Hipótese testada e **descartada**: `HarborEmergencyDirector.configure()`

A leitura inicial dos marcadores apontava um gap de **4.998,8 ms** entre
`CobraVehicles` e `HarborEmergencyDirector` como se fosse o custo de
`configure()` — que faz `_nearest_lane_point()` varrer `RoadNetwork` com
`find_children("*","Path2D",true,false)` até 7 vezes (4 depots, 3 com uma
chamada descartada). Medi ANTES de mudar qualquer coisa
(`tests/perf_audit_claude/probe_emergency_director_03a.gd`):

- `find_children` sobre a RoadNetwork real (318 nós Path2D): **0,55 ms**.
- As 7 chamadas do padrão original: **3,696 ms** no total.
- `HarborEmergencyDirector.configure()` completo, isolado, sobre o mundo real
  já carregado: **15,319 ms**.

**Nenhum dos dois é o gap de 5 s.** O gap real é o tempo de **desenho/present
do primeiro quadro** da cidade recém-populada (compilação de shader/pipeline
Vulkan para milhares de `MeshInstance3D`/`SubViewport` recém-criados) — GPU,
não CPU/script, e portanto **fora do escopo desta rodada** (é a hipótese que
o relatório 01 já registrava sem prova, agora com uma medição que a torna
plausível e a separa claramente do trabalho de script). Não alterei
`HarborEmergencyDirector.gd`. Isto está registrado aqui deliberadamente: uma
hipótese descartada por medição é parte do resultado, não um desperdício.

---

## 3. Ambiente

| item | valor |
|---|---|
| Motor | Godot 4.7.2-stable official (`ed1daf0bf`), binário do editor, `--script` |
| Build | **debug** (`OS.is_debug_build() = true`). Release **NÃO MEDIDO** (mesma limitação registrada em 01/02B: sem `export_presets.cfg` nem templates instalados; não instalei nada) |
| Renderer efetivo | Vulkan 1.4, Forward **Mobile** (`rendering_method=mobile`, driver `vulkan`), confirmado em runtime — não presumido do `project.godot` |
| Modo de execução | Processo `--script` real (renderizado, nunca `--headless`), NÃO o editor nem uma exportação |
| CPU / GPU / RAM | i7-13650HX (20 threads lógicas) / NVIDIA RTX 4060 Laptop / mesma máquina das rodadas anteriores |
| Janela / enquadramento | 1280×720, `content_scale_size` igual, sem alterar |
| VSync / limite | VSync ligado (modo 1), `max_fps=60`, física 60 Hz — **inalterados** |
| Monitor | 159,96 Hz (o VSync do jogo em 60 fica sujeito ao *frame pacing* do driver/monitor; não ajustado) |
| Concorrência | Nenhum outro processo Godot de medição rodando ao mesmo tempo; um processo por vez, sequencial. Editor do Godot do usuário e Antigravity IDE podem estar abertos (não fecho processos de terceiros) |
| Isolamento de dados | `APPDATA` próprio por execução (`results/<run>/appdata`); o script aborta se `OS.get_user_data_dir()` não contiver `perf_audit_claude`. Saves e configurações reais do usuário não tocados |
| Hardware mínimo | Não definido no projeto — pendência herdada das rodadas anteriores, não resolvida aqui |

---

## 4. Baseline e resultados — fim a fim (menu → loading → mundo pronto)

Fluxo real: `MainMenu.tscn` → `_on_btn_new_game_pressed()` (mesmo handler do
botão) → transição → abertura pulada com `opening.skip()` (mesma técnica de
`tests/test_opening_loading.gd`, sem contar a duração narrativa da cutscene
como construção) → `GameLoading._run()` real → mundo pronto. 3 execuções por
lado, alternadas (antes/depois/antes/depois...), mesmo processo de medição
(`tests/perf_audit_claude/measure_loading_03a.gd`) nos dois lados — a única
diferença de produção entre eles são os 4 arquivos da seção 5.

**Nota sobre uma volta desta tabela**: uma primeira versão desta medição
(3 execuções) usou uma versão do fatiamento em `HarborSouthPort.gd` que
**ainda não existia**, `RoadLighting.gd`, esperando o porto terminar. Essa
versão tinha uma regressão de correção real (seção 5.4/7: `test_south_port`
com 22 falhas, postes de rua duplicados). A tabela abaixo já é a versão
**corrigida e final** (com o gate em `RoadLighting._build()`), não os números
da primeira tentativa quebrada — por isso os totais aqui são um pouco piores
do que uma leitura anterior teria mostrado: a correção tem custo real.

| métrica | antes (3 execuções) | depois — final, com a correção do RoadLighting (3 execuções) | variação |
|---|---:|---:|---:|
| **maior bloco único (clique→pronto)** | 22.484,8 / 24.226,2 / 24.385,6 ms | **14.427,4 / 10.788,0 / 10.726,0 ms** | **−36% a −56%** |
| `GameLoading.scene_ready` (medido pelo próprio motor) | 10.084,8 / 11.241,1 / 11.401,2 ms | **4.795,8 / 4.809,6 / 5.320,4 ms** | **−53% a −58%** |
| `GameLoading.world_build` | 12.973,5 / 13.589,8 / 13.593,5 ms | 22.358,2 / 22.549,6 / 27.941,9 ms | **+65% a +115%, PIOR** |
| tempo total de loading (`GameLoading.total`) | 37.078,1 / 39.426,2 / 39.801,2 ms | 43.188,0 / 44.393,6 / 50.516,9 ms | **+10% a +36%, PIOR** |
| p95 (clique→pronto) | 98,9 / 106,5 / 109,4 ms | 180,5 / 214,2 / 233,2 ms | pior |
| p99 (clique→pronto) | 317,9 / 332,6 / 334,2 ms | 824,6 / 844,9 / 960,7 ms | pior |
| quadros >50 ms | 51 / 51 / 51 | 132 / 135 / 156 | mais que o dobro |
| quadros >100 ms | 24 / 28 / 31 | 57 / 69 / 80 | quase o triplo no pior caso |
| memória estática ao final | ~987 MiB | ~984 MiB | sem mudança relevante |
| VRAM ao final | ~2.365 MiB (execuções 2 e 3) | ~1.913-1.918 MiB | mais baixa — mesma ressalva da rodada anterior: provável diferença no instante exato da leitura, não otimização; registrado sem atribuir causa |

**Leitura honesta:** o maior bloco único — o congelamento que o usuário sente
como "trava" — caiu de forma **reproduzível** (3/3 execuções), mas por uma
margem menor e mais variável (−36% a −56%, contra a estimativa inicial de
−52% a −56% obtida com a versão ainda não corrigida). Isso **não é "60 FPS
resolvido"**: o tempo TOTAL de carregamento piorou de verdade (+10% a +36%,
pior que o +3% a +17% da versão anterior), e os eventos moderados (50–200 ms)
mais que dobraram. A causa do agravamento adicional em relação à primeira
medição: `RoadLighting._build()` agora espera genuinamente `SouthPort.port_ready`
antes de consultar a física real para posicionar postes (ver seção 5.4/7) —
sem essa espera, a consulta rodava cedo demais, contra um porto ainda vazio,
e produzia o dobro de postes de rua (146→290) e falhas reais de colisão. A
correção é **necessária pela correção do jogo**, não opcional: manter a
versão rápida-mas-quebrada não era uma alternativa válida.

Resumo da troca real: o pico isolado que o jogador sente como travamento
diminui de forma reproduzível, a um custo honesto de tempo total maior e mais
picos médios visíveis — o mesmo tipo de troca que
`docs/history/GETECO_PERF_02B_VEHICLES_QUEUE_2026-09-15.md` já havia registrado
para a fila de apresentação de veículos, agora com a margem real (não a
otimista) depois de corrigir o `RoadLighting`.

A causa do `world_build` mais lento (em ambas as versões, mas mais agora):
antes, `world_build_ready` flipava logo que `_start_review()` terminava suas
auditorias, sem esperar o porto sul terminar de construir (que continuava
truncado/mal formado até `_start_gameplay` seguir adiante — o hazard que a
seção 5.2 explica). Agora ele espera genuinamente o porto terminar — e
`RoadLighting` também passou a esperar o porto —, e essas esperas se somam ao
tempo real de quadros de vsync/present que passaram a ocorrer no meio do
caminho (antes não havia NENHUM quadro real apresentado durante boa parte
dessa janela).

### 4.1 Modo Continuar (`mode=continue`)

Mesmo instrumento, mesmo fixture de save (`tests/perf_audit_claude/results/03a_fixture_save/saves/`,
produzido uma vez com `mode=produce_save` e só LIDO, nunca escrito, nas
medições). 3 execuções por lado, alternadas. Este fluxo nunca tinha sido
medido nas rodadas anteriores.

| métrica | antes (3 execuções) | depois — final (3 execuções) | variação |
|---|---:|---:|---:|
| **maior bloco único** | 22.279,8 / 20.936,7 / 22.856,6 ms | **13.422,7 / 10.188,3 / 14.893,2 ms** | **−35% a −51%** |
| `GameLoading.world_build` | 13.023,7 / 12.284,0 / 13.722,2 ms | 20.467,2 / 24.098,5 / 27.417,0 ms | **+57% a +100%, PIOR** |
| `GameLoading.total` | 39.134,4 / 34.241,5 / 40.839,3 ms | 37.972,2 / 41.174,7 / 51.963,4 ms | **+5% a +27%, PIOR** |
| p95 (clique→pronto) | 96,8 / 109,1 / 131,7 ms | 167,9 / 185,8 / 251,9 ms | pior |
| p99 (clique→pronto) | 186,2 / 223,6 / 273,2 ms | 879,1 / 951,7 / 965,2 ms | pior, até ~4x |
| quadros >100 ms | 27 / 29 / 53 | 54 / 63 / 75 | pior, ~1,4x-2x |
| memória estática ao final | ~967-969 MiB | ~967-968 MiB | sem mudança |
| VRAM ao final | ~2.296-2.298 MiB | ~1.852-1.854 MiB | mesma ressalva de instante de leitura acima |

**Leitura honesta:** o mesmo padrão de troca do modo Novo Jogo se repete no
Continuar, de forma independente — reforça que é uma característica
estrutural do fatiamento (mover trabalho de um bloco gigante único para
muitos blocos médios, ainda substanciais, com vsync real entre eles), não
ruído de uma medição isolada. O bloco isolado mais severo caiu; o tempo total
e os percentis pioraram nos dois fluxos testados.

---

## 5. Implementação

### 5.1 `world/harbor/HarborSouthPort.gd`

- `_ready()` convertido de um bloco 100% síncrono para uma sequência com
  `LoadingWorkBatch.checkpoint()` (o mesmo mecanismo já usado por
  `VehicleGeometryCache`/`EmergencyPool`/`RoadLighting`) entre `_build_solids`,
  `_build_buildings`, `_build_port_models`, `HarborPortDressing.build`,
  `_build_life`, e depois disso o resto (markers/lights/checkpoint/moving_art/
  HUD) permanece síncrono (medido como barato, sem evidência de custo alto).
- **Dentro** de `_build_port_models()` (identificado como o maior bloco
  interno: 18 containers + 1 navio + 1 wheelhouse + 6 gruas×2 + 6 paletes = 38
  construções de `SubViewport`/modelo 3D) e de `_build_buildings()` (5 itens),
  um checkpoint por item — não é só uma pausa antes/depois de uma função de
  segundos, é a fila de itens sendo servida aos poucos.
- **Dentro** de `_build_life()`: checkpoint a cada 8 trabalhadores, e depois de
  `truck_logistics.build()` (3 caminhões com `_setup_3d_model()` direto, sem
  cache aquecido — `HarborContainerTruckModel.gd` não está na lista de
  `VehicleGeometryCache.prepare_common_models`) e de cada forklift (2, também
  fora da lista de aquecimento, com `.ensure_presentation()` forçado).
- `set_process(false)` no início / `set_process(true)` no fim: `_process()`
  lê `_hud`/`_status_label`, criados só ao final de `_ready()`; antes, isso
  nunca era um problema porque `_ready()` era síncrono. Guard necessário
  agora que `_ready()` passou a se espalhar por vários quadros.
- Novo `var port_ready := false`, true só ao final.

### 5.2 `world/harbor/HarborPreview.gd`

- Antes de `world_build_ready = true`, um gate:
  `if has_node("SouthPort"): while not $SouthPort.port_ready: await get_tree().process_frame`
  — mesmo padrão já usado pelo projeto para `region_ready` (`MountainPass`/
  `ContinuousWorld`). **Necessário**: sem isso, como o SouthPort agora constrói
  em etapas, `world_build_ready` poderia virar `true` (e o GameLoading liberar
  o jogador) com o porto pela metade — o hazard exato que o pedido de
  implementação pede para evitar ("não permita que o jogador se mova... com
  referências ainda não inicializadas").
- Este é o "helper compartilhado indispensável ao loading" mencionado no
  pedido: `HarborPreview._start_review()` é usado tanto pela produção
  (`HarborGame`) quanto pela cena de revisão autônoma.

### 5.3 `world/harbor/HarborGame.gd`

- `_start_gameplay()` — mesma ordem, mesmo conteúdo, mesmos nomes de nó;
  inseridos ~9 `await batch.checkpoint(get_tree())` entre grupos de
  subsistemas relacionados (nunca DENTRO dos hunks da outra sessão). Uma nova
  `LoadingWorkBatch` própria da função. `gameplay_ready = true` continua na
  mesma posição relativa (antes de PersonalCarManager/ResidenceManager/
  ContinuousWorld/etc., depois de `_spawn_motorsport_weather()`).

### 5.4 `geodata/roads/RoadLighting.gd` — a correção do "helper compartilhado"

Esta foi a correção mais delicada da rodada: uma **regressão de correção
real**, encontrada rodando a suíte de regressão completa (seção 7) contra a
árvore corrigida, não algo que eu procurava de propósito.

**Sintoma**: `tests/test_south_port.gd` passa (0 falhas) na árvore "antes" e
falha com **22 falhas** na árvore "depois" (5.1–5.3 sem esta correção) — o
sweep de colisão do teste encontra `RoadPost*` (postes de iluminação) e
`Container01` bloqueando posições que antes estavam livres.
`test_prepared_police_vehicle` também passou a falhar (timeout, exit=2).

**Diagnóstico**: um probe dedicado
(`tests/perf_audit_claude/probe_south_port_positions_03a.gd`) contando
`StaticBody2D` na árvore "antes" vs "depois" mostrou `total_road_posts`
**146 → 290** (quase o dobro) e `total_static_bodies` 972 → 1116 (+144,
quase o mesmo delta dos postes).

**Causa raiz**: `RoadLighting._build()` (`geodata/roads/RoadLighting.gd:143-186`,
função `_safe_pole()`) decide onde colocar cada poste consultando a física
real do mundo (`PhysicsShapeQueryParameters2D`/`intersect_shape`,
`collision_mask=1`) para não sobrepor "física estática... de outros
componentes da cena" — comentário já existente no arquivo, escrito antes
desta rodada, descrevendo exatamente a garantia que esta rodada quebrou.
`RoadLighting` roda como filho de `HarborPreview`, iniciando sua construção
apenas ~2 quadros depois do próprio `_ready()` (`await physics_frame` +
`await process_frame`, linhas 31-32). **Antes** desta rodada,
`HarborSouthPort._ready()` era 100% síncrono: todo o porto (containers,
gruas, prédios) já existia na física do mundo bem antes desses 2 quadros.
**Depois** da seção 5.1, `HarborSouthPort._ready()` passou a se espalhar por
dezenas de quadros reais — então, quando `RoadLighting` faz sua consulta de
física 2 quadros depois de nascer, a maior parte do porto **ainda não
existe**. `_safe_pole()` encontra "vazio" onde antes encontrava geometria
real, e posiciona o dobro de postes — muitos deles em pontos que, quando o
porto termina de construir, alguns quadros depois, passam a colidir com a
geometria real do porto.

**Correção** (`geodata/roads/RoadLighting.gd`, dentro de `_build()`, logo após
os dois `await` iniciais): se existir um nó `SouthPort` no mundo, espera
`south_port.port_ready` antes de continuar — mesmo padrão de espera já usado
em `HarborPreview._start_review()` (seção 5.2). Isso restaura a garantia
implícita que existia antes (porto fisicamente completo antes de qualquer
posicionamento de poste que dependa de física), sem reverter o fatiamento do
porto. Escopo mínimo: só afeta o caminho onde `mountain_road == null`
(Harbor); a Mountain Pass (que usa o mesmo script com `mountain_road` setado)
não passa por este gate e não foi tocada.

**Verificação da correção**: `test_south_port` volta a `failures=0,
steps=4686` (idêntico à árvore "antes"), `total_road_posts` volta a 262 (não
290; o número não é idêntico a 146 porque a árvore "antes" desta comparação
específica tinha um pequeno diff de outra sessão aplicado — ver seção 1 — e
262 é o valor real e estável da árvore de produção completa, confirmado nas 3
execuções da seção 4 e nas 3 da seção 4.1). `test_prepared_police_vehicle`
volta a `exit=0`.

**Duas edições diagnósticas temporárias em `tests/test_south_port.gd`**
(um `seed(88117263)` e um wrapper `paused=true/before`/`paused=false/depois`
em volta da espera de `world_build_ready`) foram usadas para testar e
**descartar** duas hipóteses alternativas (drift de RNG; simulação de
tráfego ambiente correndo sem pausa durante a janela de construção) antes de
chegar à causa real acima — nenhuma das duas mudou o resultado da falha.
Ambas foram **revertidas** depois que a causa real foi corrigida; `git diff`
de `tests/test_south_port.gd` está vazio nesta entrega.

### Alternativas rejeitadas

- **`HarborEmergencyDirector.gd`**: descartada, seção 2.
- **Reordenar `gameplay_ready`/`world_build_ready`** para flipar mais tarde
  por padrão: rejeitada — mudaria contrato para todo o resto do jogo que já
  confia na posição atual; o gate pontual em SouthPort é suficiente e local.
- **Pool/pré-construção de toda a frota do porto na tela de loading, fora de
  ordem**: rejeitada — reordenar quebraria a dependência
  `cargo_quay_points`/cranes → `_build_life`'s `bases[i]` para os 3 primeiros
  trabalhadores, e não há evidência de que isso ajudaria mais que o
  fatiamento in-place.

---

## 6. Limitações e trabalho não atribuído

- O gap de ~4,7 s entre `world_ready` e o primeiro `deferred_child_added`
  marcado (`WeaponNotices`) permanece **não atribuído a uma função
  específica**. É script-side (nenhum limite de quadro real o cruza), mas
  investigar exigiria interceptar `call_deferred` de dezenas/centenas de
  scripts de prédios espalhados pela cidade — fora do orçamento desta rodada.
  Registrado como pendência, não escondido.
- O ~5 s de "primeiro quadro real" (desenho/shader) permanece sem correção —
  é GPU/renderização, território do Antigravity.
- Os construtores da Mountain Pass e a travessia entre regiões não foram
  tocados, por instrução explícita.

---

## 7. Validação

### 7.1 Riscos de contagem de quadros fixa (verificados ANTES de qualquer outra coisa)

Dois testes têm limite de quadros hardcoded ligado a `gameplay_ready`/
`world_build_ready`, e o novo padrão "muitos quadros pequenos" do
carregamento fatiado poderia plausivelmente estourá-los. Ambos testados
primeiro, isoladamente, e ambos **passam** sem alteração
(`tests/perf_audit_claude/results/03a_priority_risk_checks/`):

- `test_south_port_production.gd` (limite de 90 quadros): `SOUTH_PORT_PRODUCTION
  gameplay, minimap, activation: PASS`.
- `test_harbor_emergency_dispatch.gd` (limite de 240 quadros): `HARBOR
  EMERGENCY DISPATCH: 0 failure(s)`.

### 7.2 Suíte de regressão completa (23 testes + `check_references.py`)

Rodada nos dois lados com `tests/perf_audit_claude/run_03a_regressions.ps1`,
um processo Godot por vez. A tabela abaixo é da versão **final** (com a
correção do `RoadLighting`, seção 5.4) —
`tests/perf_audit_claude/results/03a_regressions_before/` vs
`tests/perf_audit_claude/results/03a_regressions_after_fixed/`.

| teste | antes | depois (final) |
|---|---|---|
| `test_menu_flow_integration` | exit=0 | exit=0 |
| `test_continue_skips_opening` | **exit=1, 7 falhas** (pré-existente) | **exit=1, 7 falhas** — assinatura idêntica (ver 7.3) |
| `test_opening_loading` | exit=0 | exit=0 |
| `test_opening_cutscene_runtime` | exit=0 | exit=0 |
| `test_legacy_save_route` | exit=0 | exit=0 |
| `test_south_port` | exit=0 | **exit=0** (22 falhas numa versão intermediária não-final, corrigidas — seção 5.4) |
| `test_south_port_production` | exit=0 | exit=0 |
| `test_harbor_emergency_dispatch` | exit=0 | exit=0 |
| `test_harbor_local_streets` | exit=0 | exit=0 |
| `test_region_travel` | exit=0 | exit=0 |
| `test_continuous_save` | exit=0 | exit=0 |
| `test_pedestrian_life_routines` | exit=0 | exit=0 |
| `test_pedestrian_render_lod` | exit=0 | exit=0 |
| `test_garage_weapon_restrictions` | exit=0 | exit=0 |
| `test_combat_audio` | exit=0 | exit=0 |
| `test_vehicle_audio_preparation` | exit=0 | exit=0 |
| `test_vehicle_geometry_cache` | exit=0 | exit=0 |
| `test_vehicle_mesh_batcher` | exit=0 | exit=0 |
| `test_presentation_budget` | exit=0 | exit=0 |
| `test_vehicle_presentation_streaming` | exit=0 | exit=0 |
| `test_resident_vehicle_preparation` | exit=0 | exit=0 |
| `test_emergency_pool_preparation` | exit=0 | exit=0 |
| `test_prepared_police_vehicle` | exit=0 | **exit=0** (falhou com timeout/exit=2 numa versão intermediária não-final, corrigida junto com `test_south_port` — mesma causa raiz, seção 5.4) |
| `tools/check_references.py` | 7 quebras (`res://../artifacts/...png/.wav` citados por scripts de captura visual — arquivos de artefato não gerados nesta árvore, pré-existente, nada a ver com este diff) | 3 quebras (`res://AchievementCatalog.gd`, `res://CollectibleCatalog.gd`, `res://world/shared/ProjectedSilhouette.gdshader`, todas citadas por `.claude/settings.local.json` — string de comando `sed` de uma refatoração passada guardada no allowlist do Claude Code, não uma referência real de jogo; confirmado presente também fora de qualquer mudança desta rodada) |

**Único resultado vermelho em toda a suíte, nos dois lados**:
`test_continue_skips_opening`. Nada mais regrediu; nada foi enfraquecido para
passar.

### 7.3 `test_continue_skips_opening` — reprodução e atribuição

Requisito do pedido: reproduzir e atribuir esta falha pré-existente ao efeito
desta rodada (se houver), sem culpar 02A/02B sem base, e sem chamá-la de
"validada". Comparando
`tests/perf_audit_claude/results/03a_regressions_before/test_continue_skips_opening.txt`
com `.../03a_regressions_after_fixed/test_continue_skips_opening.txt`: as
**7 falhas são byte-a-byte idênticas** nos dois lados — mesmo `SCRIPT ERROR:
Invalid call. Nonexistent function 'active' in base 'Nil'` em
`HarborArrivalMission.gd:151`, mesmas 3 mensagens `FAIL` ("Saved arrival
resumes without CGI" ×2, "Mission 1 keeps its saved objective"), mesma
contagem final (`CONTINUE_OPENING failures=7`). **Conclusão**: esta rodada
(03A) tem efeito **zero**, medido, sobre esta falha. Ela já existia antes de
qualquer um dos 4 arquivos de produção desta rodada, permanece exatamente
igual depois, e continua **não corrigida** — não foi "validada", não foi
atribuída a esta mudança, e não foi tocada (o pedido de 02B já a documentava
como pendência: `first_favors` nulo). Nenhuma alteração foi feita em
`HarborArrivalMission.gd`, `test_continue_skips_opening.gd` ou qualquer coisa
relacionada para tentar "resolver" ou mascarar isso.

### 7.4 Preservação de posição/campanha/inventário/presentação

- **Continuar** (seção 4.1): save real produzido por `mode=produce_save`,
  aplicado com `mode=continue` nas 3 execuções de cada lado. Console confirma
  `SaveManager: Save aplicado com sucesso no mundo!` nas 6 execuções (3
  antes + 3 depois); `GameLoading` completa (`MEASURE_03A_STATUS complete`)
  nas 6.
- **Menu → reentrar**: coberto indiretamente por `test_menu_flow_integration`
  (exit=0 nos dois lados, seção 7.2), que exercita save/load e troca de cena
  — o teste mais sensível a caminho de recurso quebrado ou referência não
  inicializada, por instrução do `CLAUDE.md` do projeto.
- Nenhum destes fluxos usa qualquer dos 4 arquivos alterados fora do padrão
  documentado na seção 5 — a ordem/conteúdo de todo `add_child`/configure é
  idêntica, só os pontos de `await` mudaram.

### 7.5 O que NÃO foi medido (honestidade de verificação)

- Só uma amostra de testes automatizados rodou (23 + `check_references.py`);
  não prova ausência de regressão no resto do jogo, só nesses casos.
- Nenhuma comparação de imagem/captura visual pixel-a-pixel foi refeita nesta
  rodada (as existentes em `tests/visual/` não foram executadas); a evidência
  visual desta rodada é a série temporal de `frames.csv`/`report.json`, não
  uma imagem estática.
- O gap de ~4,7 s (seção 6) e o ~5 s de primeiro-quadro-real permanecem sem
  atribuição de causa específica — registrados como limitação, não como
  resolvidos.
- A regressão do `RoadLighting` (seção 5.4) foi encontrada rodando a suíte
  DEPOIS de escrever a implementação inicial — é um recordatório honesto de
  que a suíte verde de uma versão anterior desta mesma rodada não provava
  ausência de efeito colateral; só rodar de novo, depois de cada mudança de
  produção, pegou isso.

---

## 8. Pacote e comandos

### Estado do repositório nesta entrega

- HEAD durante toda a rodada: `45ba477e6e9aff074b2959485ebc2e2e63876ae7` (`main`).
- 4 arquivos de produção alterados: `world/harbor/HarborSouthPort.gd`,
  `world/harbor/HarborPreview.gd`, `world/harbor/HarborGame.gd`,
  `geodata/roads/RoadLighting.gd`.
- `tests/test_south_port.gd`: sem alterações líquidas nesta entrega (as duas
  edições diagnósticas temporárias, seção 5.4, foram revertidas — `git diff`
  vazio).
- Alterações locais de outras sessões (`characters/Player.gd`,
  `systems/RegionTravel.gd`, `systems/interiors/ExteriorOcclusion.gd`,
  `world/harbor/HarborArrivalStop.gd`,
  `world/harbor/campaign/HarborArrivalMission.gd`, 2 testes apagados,
  `docs/measurements/review-0909/load_profile.txt`) permanecem intactas e
  **fora** do meu commit.

### Comandos executados (um processo Godot por vez, nunca `--headless`, sem push)

```bash
GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"

# Baseline "antes": worktree temporária no commit 45ba477 + diff de outras sessões
git worktree add --detach <caminho> 45ba477
git -C <caminho> apply --whitespace=nowarn --include=<arquivos> local_changes_others.diff
"$GODOT" --headless --path <caminho> --import

# Medição fim-a-fim (novo jogo e continuar), 3x por lado, ordem alternada
"$GODOT" --path <árvore> --script res://tests/perf_audit_claude/measure_loading_03a.gd \
  -- run=<nome> mode=new
"$GODOT" --path <árvore> --script res://tests/perf_audit_claude/measure_loading_03a.gd \
  -- run=<nome> mode=continue save_fixture=tests/perf_audit_claude/results/03a_fixture_save/saves/

# Diagnóstico da regressão do RoadLighting
"$GODOT" --path <árvore> --script res://tests/perf_audit_claude/probe_south_port_positions_03a.gd

# Suíte de regressão completa, nos dois lados
powershell -File tests/perf_audit_claude/run_03a_regressions.ps1 -Label before -Path <árvore_antes>
powershell -File tests/perf_audit_claude/run_03a_regressions.ps1 -Label after_fixed -Path D:/geteco/game
```

### Conteúdo do pacote

`tests/perf_audit_claude/package_03a.ps1` (atualizado nesta entrega para
incluir as pastas de resultado desta rodada final — `03a_after_fixed_new_*`,
`03a_continue_*`, `03a_regressions_after_fixed`, `03a_positions_*`,
`03a_priority_risk_checks`) gera um ZIP com:

- Este relatório completo.
- `production_03a.diff` — diff dos 4 arquivos de produção (não só 3).
- Os scripts criados nesta rodada (`measure_loading_03a.gd`,
  `probe_emergency_director_03a.gd`, `probe_south_port_positions_03a.gd`,
  `run_03a_regressions.ps1`, `package_03a.ps1`).
- JSON/CSV das execuções relevantes, listadas acima.
- Um manifesto (`MANIFEST.txt`) com HEAD, comandos e revisões.
- Exclui `appdata/` (isolado por execução), `saves/` e logs de importação sem
  valor de medição.

Comando de empacotamento:

```bash
powershell -File tests/perf_audit_claude/package_03a.ps1
```

### Commit

Staging explícito só dos arquivos desta rodada (produção + testes +
relatório), nunca `git add -A`. Ver mensagem de commit para a lista exata.
Nenhum push — remoto fica com o usuário.

---

## HANDOFF PARA ANTIGRAVITY 03B

**Não comecei a corrigir a Mountain Pass nesta rodada — nem os construtores
internos, nem a travessia entre regiões — por instrução explícita do
pedido.** O que segue é só para orientar 03B, não uma lista de tarefas
completadas.

### Helpers/contratos que mudaram e não podem mais ser assumidos como antes

- **`world/harbor/HarborSouthPort.gd`**: `_ready()` não é mais síncrono. Novo
  contrato público: `port_ready: bool` (`false` até o porto estar
  completamente construído — solids, prédios, modelos 3D, dressing, vida,
  markers, lights, checkpoint). Qualquer código que assuma que
  `$SouthPort` está completo imediatamente após `add_child`/instanciação
  (incluindo dentro do mesmo frame) está quebrado agora. Use
  `await`-loop em `port_ready`, como `HarborPreview._start_review()` já faz.
- **`world/harbor/HarborPreview.gd`**: `_start_review()` (usado tanto pela
  cena de revisão autônoma quanto por `HarborGame`, que herda dela) agora
  espera `$SouthPort.port_ready` antes de `world_build_ready = true`. Se a
  Mountain Pass ganhar um construtor faseado semelhante (fora de escopo
  aqui), o mesmo padrão de gate (`has_node(...)` + `while not
  X.<algo>_ready: await get_tree().process_frame`) é o precedente a seguir —
  **não** reordenar `gameplay_ready`/`world_build_ready` globalmente (seção
  5, "Alternativas rejeitadas": rejeitado por mudar contrato para o resto do
  jogo).
- **`world/harbor/HarborGame.gd`**: `_start_gameplay()` ganhou ~9 pontos de
  `await batch.checkpoint(get_tree())` (uma `LoadingWorkBatch` própria da
  função). Ordem e conteúdo de cada `add_child`/configure são idênticos aos
  de antes; `gameplay_ready = true` continua na mesma posição relativa. Um
  segundo agente (ou sessão) editando esta função precisa saber que ela não
  é mais uma sequência 100% síncrona — inserir código novo entre dois
  `await` já é seguro (roda depois que o anterior resolveu), mas inserir
  algo que precisa rodar **antes** de um `await` específico requer atenção à
  ordem existente.
- **`geodata/roads/RoadLighting.gd`** — **este é o "helper compartilhado
  indispensável ao loading" que esta rodada precisou tocar, além dos 3
  arquivos do Harbor**: `_build()` agora espera `SouthPort.port_ready`
  (quando existe um nó `SouthPort` no mundo pai) antes de consultar física
  real para posicionar postes. Esse script também é usado por
  `world/mountain_pass/MountainPass.gd` (com `mountain_road` setado) — esse
  caminho **não** passa pelo novo gate (só dispara quando `mountain_road ==
  null`, ou seja, só no Harbor) e não foi alterado. **Se 03B fatiar algum
  construtor da Mountain Pass que crie física estática (StaticBody2D) depois
  do próprio `_ready()`** (o mesmo padrão que causou a regressão nesta
  rodada — seção 5.4), o mesmo risco existe lá: `RoadLighting` (via o ramo
  `mountain_road`) ou qualquer outro consumidor de
  `_safe_pole()`/`intersect_shape()` pode contar física que ainda não
  existe. Vale a pena, ao fatiar algo na Mountain Pass, rodar
  `tests/perf_audit_claude/probe_south_port_positions_03a.gd` como modelo
  (adaptado) para contar corpos estáticos antes/depois e conferir que não
  dobrou nada.

### Arquivos que não podem mais ser assumidos como inalterados desde a rodada 02B

`world/harbor/HarborSouthPort.gd`, `world/harbor/HarborPreview.gd`,
`world/harbor/HarborGame.gd`, `geodata/roads/RoadLighting.gd`.

### Bloqueios da Mountain Pass — continuam completamente abertos

- Os construtores internos da Mountain Pass (não identificados/fatiados
  nesta rodada — fora de escopo por instrução) provavelmente têm o mesmo
  padrão de bloco-síncrono-longo que `HarborSouthPort._ready()` tinha antes
  da seção 5.1. Nenhuma medição foi feita sobre eles nesta rodada.
- A travessia entre regiões (region-crossing activation) não foi tocada nem
  medida.
- O `region_ready`/padrão de espera já existente em `MountainPass`/
  `ContinuousWorld` (mencionado na seção 5.2 como precedente) é o ponto de
  partida óbvio para replicar o gate de `port_ready`, mas **não foi
  verificado** se esse padrão já é suficiente ou se sofre do mesmo tipo de
  regressão que `RoadLighting` sofreu aqui — vale conferir antes de assumir
  que está safe.
- Custo contínuo de CPU (mencionado como aberto na rodada 02B) não foi
  investigado nesta rodada — permanece pendência.

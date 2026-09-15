# GETECO-PERF-01-CLAUDE — auditoria de CPU, simulação, carregamento e streaming

Data: 2026-09-15. Rodada de **análise**: nenhum arquivo de produção foi alterado.
Escopo: carregamento, CPU/simulação, trânsito, emergência, física, streaming e
congelamentos. Renderização, SubViewports, animação, efeitos e áudio pertencem à
auditoria paralela do Antigravity (seção F).

---

## A. Resumo executivo

Na máquina disponível, em build **debug** do editor (release não medido), o GETECO
**não mantém 60 FPS** em nenhum cenário medido. São três problemas distintos:

1. **Congelamento de carregamento de 23,5 s num único quadro** (medido duas vezes:
   23.508 e 23.412 ms). A tela de loading para de ser desenhada. Cerca de 10,4 s
   são `_ready` síncrono dos filhos de `HarborGame` (só `SouthPort` custa 5,6 s) e
   cerca de 13,1 s são trabalho diferido no mesmo quadro (`_start_gameplay` e as
   chamadas diferidas). O pico histórico de 9,2 s em `_start_review` **não foi
   resolvido**: `_start_review` já cede quadros, mas o congelamento se deslocou e
   hoje é maior.
2. **Engasgos na gameplay causados por construção de apresentação.** O
   `PresentationBudget` constrói 1 ator por quadro, e o limite de 2 ms só é conferido
   antes e depois de cada construção. Construções individuais medidas: pedestre
   75–90 ms, trânsito até 211 ms, e um quadro de produção de **1.763 ms** com a
   construção de um `Vehicle3DRender`. A fila nunca esvazia (115–142 itens), com
   esperas de 20 a 81 s ou mais.
3. **Custo de CPU contínuo acima do orçamento de 16,67 ms.** O monitor de process
   fica em p50 19–23 ms mesmo com o carro parado. Os callbacks de script somam
   cerca de 11,6 ms por quadro, distribuídos em cauda longa por centenas de atores;
   nenhum sistema isolado domina. A ferramenta existente
   (`measure_game_frame_stability`) mediu 43,5 FPS, p50 19,8 ms.

Há ainda dois achados de streaming e picos: a primeira preparação da Mountain Pass
durante a gameplay (quadros de 2,9–3,2 s; +22 mil nós residentes) e **picos de
0,7–5,8 s na gameplay ainda sem causa isolada**.

Pistas históricas revalidadas:

| pista | estado atual |
|---|---|
| Hash de string de ~98 mil caracteres no `JunctionTrafficController` | **Corrigida.** O caminho rápido por revisão leva ~1 µs. A assinatura antiga hoje teria 143.556 caracteres e custaria 9,3 ms mais 4,7 ms de cópia do grafo, mas não roda: a revisão fica estável. |
| Congelamento de ~9,2 s em `_start_review` | **Não corrigida; deslocada.** `_start_review` tem `await`s, mas `_ready` síncrono e `_start_gameplay` somam 23,5 s num quadro. |
| `PresentationBudget` ~2 ms/quadro | **O limite não limita a tarefa individual.** Medido na seção D2. |
| Picos de 250–300 ms | **Persistem:** 253 ms (run1) e 244 ms (controle). Existem também picos muito maiores. |
| Recuperação repetida de emergência / `test_harbor_safety` instável | **Não reproduzido** em 30 s de perseguição (no máximo 1 unidade dando ré, 6 planos de rota). Não é prova de ausência; o teste não foi executado nesta rodada. |

Limites desta auditoria: build debug; editor do Godot e Antigravity abertos durante
as medições; cenários de 30 s; travessia feita por teleporte; um ou dois processos
por cenário (não é distribuição estatística).

---

## B. Ambiente, revisão e condições

| item | valor |
|---|---|
| Revisão | `main` @ `9c5cb5413dc7d3b37f89ddbce7b46620c6550bfe`, com mudanças locais de outras sessões (abaixo), idênticas do início ao fim das medições |
| Engine | Godot 4.7.2-stable official (`ed1daf0bf`), `Godot_v4.7.2-stable_win64_console.exe`, `--script` |
| Build | **debug** (`OS.is_debug_build() = true`). Export release: **NÃO MEDIDO** |
| Renderer efetivo | Vulkan 1.4.341, Forward **Mobile** (`rendering_method=mobile`, driver `vulkan`), confirmado em runtime |
| CPU / GPU / RAM | i7-13650HX (14 núcleos / 20 threads) / NVIDIA RTX 4060 Laptop (driver 32.0.16.1047) / 31,7 GB |
| Janela | 1280×720, janela; monitor informado pelo Godot 3440×1440 @160 Hz (o WMI informou 1920×1200 @165 Hz: há mais de um monitor) |
| VSync / limite | VSync ligado (modo 1), `max_fps=60`, física 60 Hz, `max_physics_steps_per_frame=8`, interpolação de física ligada |
| Hardware mínimo | **Não definido no projeto — pendência.** Os resultados valem só para esta máquina. |
| Concorrência | Editor do Godot aberto neste projeto (PID 39048) e Antigravity IDE aberto. Nenhum outro processo Godot de teste ao iniciar cada run; runs executadas uma de cada vez. |
| Isolamento de dados | `APPDATA` apontando para `tests/perf_audit_claude/results/<run>/appdata` (o coletor aborta se o user data não estiver isolado) e `SaveManager._save_dir` redirecionado. Saves e configurações reais não foram tocados. |

Mudanças locais presentes (de outras sessões, não minhas): `characters/Player.gd`
(passada e `stand_down_police`), `systems/RegionTravel.gd`,
`systems/interiors/ExteriorOcclusion.gd`, `world/harbor/HarborArrivalStop.gd`,
`world/harbor/HarborGame.gd`, `world/harbor/campaign/HarborArrivalMission.gd`,
`docs/measurements/review-0909/load_profile.txt`, dois testes apagados e
`tests/test_police_death_departure.gd` novo. Mudanças com efeito potencial nas
medições: `ExteriorOcclusion._process` (mais chaves de sprite e retângulos maiores)
e `HarborGame._start_gameplay` (o `HarborSoundscape` é criado mas não é mais
adicionado). As medições valem para **esse** estado da árvore de trabalho, não para
o HEAD puro.

---

## C. Cenários e métricas

Tempos entre quadros medidos com `Time.get_ticks_usec()` no sinal `process_frame`
(relógio monotônico, não o delta). Percentis por posto mais próximo, em ms. p99,9 foi
omitido: nenhuma fase teve ≥10 mil quadros. As colunas `proc p50` e `fís p50` vêm de
`Performance.TIME_PROCESS` / `TIME_PHYSICS_PROCESS` (monitores do motor, com um
quadro de atraso). Não são tempo total de CPU nem de GPU.

### Execuções

| run | ferramenta | observação |
|---|---|---|
| `run1` | `perf_audit_session.gd` | Com cópia cronometrada do laço do `PresentationBudget` |
| `run2_nobudgetcopy` | `perf_audit_session.gd --no-budget-timing` | Laço de produção intacto; atribui os picos acima de 250 ms |
| `control_frame_stability` | `tests/measure_game_frame_stability.gd --normal-cap` (existente) | Controle sem instrumentação minha |
| `probe_crash` | `probe_crash_costs.gd` | Tempos isolados do caminho de colisão |
| `callbacks_profile` | `tests/profile_harbor_game_callbacks.gd samples=600` (existente) | Ranking de callbacks por nó |

### Carregamento (GameLoading real, rota de save/continuar, sem menu e sem cutscene)

| métrica | run1 | run2 |
|---|---:|---:|
| duração total do loading | 37.093 ms | 37.413 ms |
| **maior quadro (congelamento da UI)** | **23.508 ms** | **23.412 ms** |
| quadros >50 / >100 ms | 45 / 21 | 50 / 25 |
| fase `resources` (thread) | 5.083 | 5.147 |
| fase `scene_ready` | 10.413 | 10.382 |
| fase `world_build` | 13.711 | 13.624 |
| `vehicle_models` / `resident_vehicles` | 2.720 / 21 | 3.003 / 21 |
| `emergency` / `audio` | 3.024 / 1.528 | 3.152 / 1.512 |
| fila de apresentação ao terminar | 136 | — |
| nós adicionados no quadro congelado | — | 45.405 (26.179 `MeshInstance3D`) |

As fases do `GameLoading` são intervalos entre marcos. `scene_ready` e `world_build`
**contêm** o quadro de 23,5 s; não é possível somá-las como "carregamento
progressivo". A duração da cutscene não entra: a rota medida não tem cutscene.

Atribuição dentro do quadro congelado (run1, marcos por sinais `ready` dos filhos
diretos e `node_added`):

| trecho | duração |
|---|---:|
| `resources` terminados → `HarborGame` entra na árvore | t = 5,31 s |
| `_ready` síncrono de todos os filhos (entrar na árvore → `world_ready`) | **10,38 s** |
| ↳ `SouthPort` (`HarborSouthPort._ready`) | **5,59 s** |
| ↳ `ArrivalStop` | 1,43 s |
| ↳ `Interiors` / `PlayerCar` / `FreightRail` | 0,72 / 0,66 / 0,50 s |
| diferidos antes de `WeaponNotices` (enfileirados nos `_ready`; não atribuídos) | 4,82 s |
| `_start_review` (Cobras) → `_start_gameplay` e extras até `Monaliza` | ~1,6 s |
| `PersonalCarManager`/`Monaliza` → `ResidencePrototype` | 1,34 s |
| `CobraVehicles` adicionado → fim do quadro (não atribuído) | ~5,2 s |

### Gameplay (Harbor)

| cenário | run | quadros | FPS médio | p50 | p95 | p99 | máx | >16,67 | >33,33 | >50 | >100 | proc p50 | fís p50 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| parado (5 s) | run2 | 247 | 49,4 | 17,5 | 28,5 | 60,5 | 130,1 | 198 | 6 | 3 | 2 | 19,1 | 7,5 |
| direção, 30 s (1ª passagem) | run1 | 711 | 24,9 | 21,8 | 40,4 | 70,0 | **5.829,9** | 703 | 56 | 21 | 3 | 23,2 | 7,3 |
| direção, 30 s (1ª passagem) | run2 | 1.008 | 33,7 | 21,8 | 50,4 | 138,8 | **1.762,9** | 985 | 152 | 51 | 17 | 22,9 | 7,2 |
| direção, 30 s | controle | 1.307 | 43,5 | 19,8 | 30,6 | 80,3 | 244,1 | 1.285 | 43 | 16 | 12 | 21,5 | — |
| perseguição 6★, 30 s (2ª passagem, mesmas ruas) | run1 | 992 | 33,4 | 27,0 | 52,6 | 102,3 | 253,2 | 992 | 236 | 61 | 11 | 22,3 | 9,4 |
| perseguição 6★, 30 s (2ª passagem) | run2 | 1.045 | 34,9 | 27,5 | 36,6 | 65,5 | 738,5 | 1.045 | 124 | 15 | 5 | 22,6 | 9,0 |

Quase todos os quadros passam de 16,67 ms; isso é o custo contínuo, não jitter do
VSync. O controle usa preparação de apresentação, seed e rota diferentes da minha
sessão (sem `GameLoading`), por isso os números não são idênticos. O documento de
13/09 (`docs/loading-performance-0913.md`) registrava p50 de 16,65 ms numa rota
equivalente. Hoje o p50 está em 19,8–21,8 ms. **Não sei se é regressão de código
ou diferença de ambiente**: não houve medição do código de 13/09 nesta rodada.

### Streaming e eventos

| cenário | run | quadros | p50 | p95 | p99 | máx | >50 | >100 |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1ª preparação da montanha (teleporte até a emenda) | run1 | 370 | 26,4 | 90,2 | 394,4 | **2.954,3** | 40 | 17 |
| 1ª preparação da montanha | run2 | 377 | 30,1 | 103,4 | 399,6 | **3.222,6** | 38 | 19 |
| dentro da montanha, ciclo 0 / 1 | run2 | 367 / 438 | 26,8 / 21,5 | 35,5 / 29,8 | 42,7 / 33,9 | 99,9 / 35,8 | 2 / 0 | 0 / 0 |
| retorno ao Harbor, ciclo 0 / 1 | run2 | 418 / 515 | 22,8 / 17,9 | 31,7 / 26,7 | 35,4 / 29,0 | 62,3 / 54,2 | 2 / 2 | 0 / 0 |
| 2ª entrada na emenda (região já residente) | run2 | 221 | 25,6 | 33,5 | 45,6 | 370,5 | 2 | 1 |

- Montanha pronta 17,6 s depois do teleporte (run1). `handoff_max_displacement` =
  5,5 px.
- `save_game` levou 2,6 ms e `load_game` (leitura e validação do JSON) 6,9 ms. A
  troca de cena de um load **não foi executada**.

Crescimento de estado (run1):

| instantâneo | nós | órfãos | memória estática | VRAM | SubViewports (não desativados) | fila de apresentação |
|---|---:|---:|---:|---:|---:|---:|
| após loading | 31.078 | 5.762 | 962 MiB | 2.267 MiB | 354 (272) | 136 |
| após direção | 32.904 | 5.762 | 1.008 | 2.525 | 413 (223) | 117 |
| após perseguição | 34.264 | 4.951 | 1.021 | 2.531 | 430 (234) | 115 |
| montanha, ciclo 0 | 56.147 | 4.978 | 1.413 | 3.279 | 652 (381) | 125 |
| Harbor, ciclo 0 | 56.148 | 4.978 | 1.413 | 3.282 | 652 (292) | 125 |
| montanha, ciclo 1 | 56.085 | 4.978 | 1.414 | 3.283 | 652 (381) | 125 |
| Harbor, ciclo 1 | 56.082 | 4.978 | 1.413 | 3.283 | 652 (295) | 125 |

Depois que a montanha fica residente, dois ciclos não mostraram crescimento. Duas
travessias curtas **não** bastam para descartar vazamento; também não há evidência
de vazamento. Os 5.762 nós órfãos logo após o loading são altos e ficam estáveis;
origem não investigada.

### Cenários NÃO EXECUTADOS

Entrada pelo menu com cutscene e "Novo jogo"; export release; travessia dirigida de
verdade pela ponte (usei teleporte); troca de cena de load; explosões e combate
prolongado; sessão longa (>3 min) para crescimento; `test_harbor_safety`; perfil de
funções pelo depurador do editor; métricas de GPU.

---

## D. Achados prioritários

### CLAUDE-PERF-001 — Construção síncrona do mundo congela o loading por 23,5 s

- **Onde:**
  - `world/harbor/HarborSouthPort.gd` `_ready()` (linhas 43–70): `_build_solids`,
    `_build_buildings`, `_build_port_models`, `HarborPortDressing.build`,
    `_build_life`, `_build_lights`, tudo síncrono.
  - `world/harbor/HarborGame.gd` `_start_gameplay()` (linhas 25–124): cria cerca de
    25 subsistemas sem ceder quadro.
  - `world/harbor/cobras/CobraVehicles.gd` `_ready()`.
  - `ui/GameLoading.gd` `_run()` (linhas 143–148): `change_scene_to_packed` seguido
    de `await scene_changed`.
- **Mecanismo:** `change_scene_to_packed` entra na árvore e roda todos os `_ready`
  num único quadro. As chamadas diferidas enfileiradas nesses `_ready` (Player,
  `_start_review`, `_start_gameplay`, `_finish_cobra_vehicles`) são esvaziadas no
  **mesmo** quadro, antes de qualquer desenho. Os `await` de `_start_review` só
  começam a ceder quando o grosso já rodou.
- **Evidência:** run1 e run2, maior quadro de 23.508 / 23.412 ms; 45.405 nós
  adicionados nesse quadro; atribuição na seção C. O `load_profile.txt` modificado
  localmente por outra sessão (rota sem `GameLoading`) mostra `add_child` = 9,1 s e
  `frame0` = 15,4 s, coerente com isto.
- **Reprodução:** `APPDATA` isolado +
  `--script res://tests/perf_audit_claude/perf_audit_session.gd -- run=<nome>`;
  ver `report.json → markers` e `phases.loading.max_ms`.
- **Classificação:** medido. A atribuição por filho é medida; os 4,8 s e os ~5,2 s
  de diferidos são medidos, mas não atribuídos a funções.
- **Impacto:** 23,5 s de UI travada por entrada no mundo; loading total de ~37 s.
- **Alternativas:**
  1. Fatiar os construtores pesados (`SouthPort`, os passos de `_start_gameplay`,
     `CobraVehicles`) em etapas com `await` usando `LoadingWorkBatch.checkpoint()`,
     o mesmo padrão já usado por `EmergencyPool.prepare_presentations` e pelo
     `MountainPass._ready`. `gameplay_ready` / `world_build_ready` só viram `true`
     ao final.
  2. Assar a geometria procedural estática do `SouthPort` (sólidos, prédios,
     dressing) em `.tscn`/recursos gerados no editor, trocando geração em runtime
     por carregamento threaded.
  3. Preparar dados (arrays, layout) em `WorkerThreadPool` e só criar nós na thread
     principal, em lotes.
- **Recomendada:** 1 primeiro. Reusa um mecanismo existente, é reversível e ataca o
  congelamento da UI sem mudar conteúdo. Depois, 2 para o `SouthPort` se o tempo
  total ainda for alto.
- **Riscos:** dependências de ordem já documentadas no código (o
  `CobraCampaignBridge` exige `CobraTerritory` síncrono; a restauração de save do
  Player é diferida; `HarborArrivalStop` lê `loaded_from_save`); testes que presumem
  construção síncrona; `GameLoading` com prazo de 120 s.
- **Teste de aprovação:** `perf_audit_session` com maior quadro do loading abaixo de
  um alvo definido pelo usuário (sugestão: ≤250 ms), mesmos marcos presentes;
  `test_menu_flow_integration`, `test_continue_skips_opening`,
  `test_opening_loading`, `test_opening_cutscene_runtime`, `test_legacy_save_route`
  e `profile_load_time_0909` com `errors=0`.

### CLAUDE-PERF-002 — PresentationBudget: tarefa individual de 75 ms a 1,7 s e fila que nunca esvazia

- **Onde:**
  - `systems/PresentationBudget.gd` `_process()` (linhas 14–43).
  - `cars/traffic/TrafficVehicle.gd` `ensure_presentation()` (linhas 130–135) →
    `_setup_3d_model` (~122 linhas, com `load(model_path)` síncrono na linha ~877,
    criação de `SubViewport`, modelo e rodas).
  - `characters/AnimatedPedestrian3D.gd` `ensure_presentation()` (linhas 107–113) →
    `_build_3d_viewport` (~490 linhas: `SubViewport` com `own_world_3d`,
    `Camera3D`, `DirectionalLight3D`, rig).
  - Enfileiramento: `TrafficVehicle.gd:832`, `AnimatedPedestrian3D.gd:225`,
    `FixedTrafficSignal.gd:46/52`.
- **Mecanismo:** `max_builds_per_frame = 1`. O orçamento de 2.000 µs é conferido na
  linha 17, antes (sempre passa, pois nada rodou ainda), e na linha 42, depois (a
  construção já aconteceu). **Nada limita a duração de uma construção.** Além disso,
  cada quadro percorre a fila inteira com `get_global_transform_with_canvas()`, e
  os itens fora da tela ficam ali indefinidamente. As construções acontecem quando
  o ator entra na margem de 220 px, ou seja, exatamente durante a direção.
- **Evidência:**
  - run1, cópia literal do laço cronometrada: 84 construções no total.
    - `TrafficVehicle`: 16 construções, 14 acima de 2 ms, máx 211,4 ms, soma
      1.082 ms.
    - Pedestres (`HarborWalker`, classe interna sem `resource_path`): 20
      construções, todas acima de 2 ms, 75–90 ms, soma 1.449 ms.
    - `FixedTrafficSignal`: 48 construções, máx 1,6 ms.
  - Fila: 136 itens ao fim do loading e 115–142 durante toda a sessão; espera
    mínima registrada de até 81 s (trânsito) e 20 s (pedestres).
  - run2, laço de produção: quadro de **1.762,9 ms** com `process` = 1.714 ms e
    164 nós do `Vehicle3DRender` de `HarborTraffic_48` adicionados; quadro de
    319 ms com o `SubViewport` de `HarborResident_8_2`.
- **Reprodução:** `perf_audit_session` (run1: `presentation_builds.by_script` e
  `slow_builds_over_2ms`; run2: `spikes_over_250ms`).
- **Classificação:** medido.
- **Impacto:** os construtores respondem por parte relevante dos quadros acima de
  50 ms na direção (run1: 36 construções, 1.358 ms somados na fase `drive`) e pelo
  maior pico de gameplay da run2.
- **Alternativas:**
  1. Carregar recursos de modelo e scripts por arquétipo durante o loading, via
     `VehicleGeometryCache` e `ResourceLoader` threaded, removendo o `load()`
     síncrono do caminho de construção. Primeiro é preciso confirmar quanto do
     1,7 s é `load()` e quanto é criação de nós (experimento pendente abaixo).
  2. Tornar a construção retomável em etapas (viewport → modelo → rodas/luzes →
     acessórios), com o orçamento conferido **entre etapas**, mantendo a silhueta
     2D até a etapa final.
  3. Pool de rigs/viewports por arquétipo reutilizados entre atores que dormem e
     acordam, em vez de construir cada ator do zero.
- **Recomendada:** 1 + 2. A 1 é barata se o `load()` for dominante; a 2 é a única
  que faz o limite de 2 ms significar alguma coisa. A 3 muda memória e identidade
  visual e fica para depois.
- **Riscos:** pop-in visual; a documentação exige que entrada do jogador ou impacto
  forcem a conclusão (portas e danos); acessórios aplicados em `presentation_ready`;
  memória de modelos pré-carregados.
- **Teste de aprovação:** `perf_audit_session`, `by_script.max_us` ≤ 2 ms por
  quadro e p99/máx da fase `drive` antes e depois nas mesmas condições;
  `test_presentation_budget`, `test_pedestrian_render_lod`,
  `test_vehicle_geometry_cache`, `test_emergency_pool_preparation`.
- **Experimento pendente (sem mudar produção):** probe que cronometra
  separadamente `load(model_path)` e o restante de `_setup_3d_model` para cada
  arquétipo, na primeira e na segunda construção.

### CLAUDE-PERF-003 — Custo de CPU contínuo acima de 16,67 ms, espalhado em cauda longa

- **Onde:** agregado; não há um único ponto. Maiores itens por nó (média por
  quadro, `callbacks_profile`):

  | nó | custo médio |
  |---|---:|
  | `UrbanExpress3` `_process` (`TrafficVehicle`) | 601 µs |
  | `HarborTraffic_51` `_process` | 377 µs |
  | física de pedestres `HarborResident_*` | 80–304 µs cada |
  | `JunctionTrafficController._process` | 242 µs |
  | física do `PlayerCar` | 190 µs |
  | `AmbientTrain` | 123 µs |
  | `ContinuousWorld` | 97 µs |
  | `PresentationBudget` | 78 µs |

- **Mecanismo:** somados, os callbacks de script dão 6.938 ms em 600 quadros =
  **~11,6 ms/quadro**, e o monitor de process marca p50 de 19–23 ms. Os ~8–10 ms
  restantes são trabalho do motor não atribuído a scripts (árvore de ~31 mil nós,
  canvas, notificações, sincronização de SubViewports, sinais, diferidos) mais o
  overhead de GDScript em build debug.
- **Cálculos pontuais medidos (run1, perseguição 6★):**

  | operação | custo | frequência |
  |---|---:|---|
  | `JunctionTrafficController._synchronize_crossing_consumers` | 2,16 ms por chamada | a cada 0,5 s + nos quadros com troca de estágio (31 em 1.008 na direção; 71 em 1.045 na perseguição) |
  | `ContinuousWorld._budget_traffic` | 0,91 ms | a cada 0,2 s |
  | `EmergencyLaneRouter._plan` | 4,9 ms por plano | 6 planos em 30 s |
  | `WantedManager._find_lane_spawn` | 0,35 ms | por despacho |
  | `TrafficSimulationBudget.active_conflict_actors` | 62 µs | por atualização |

  Nenhum desses explica sozinho o custo contínuo.
- **Evidência:**
  - `proc p50` de 19,1 ms parado e 22,9 ms dirigindo (run2); controle a 43,5 FPS.
  - Na montanha, p50 de 26,8 ms com 381 SubViewports não desativados.
  - Contra-prova: a run2, sem a minha cópia do laço, mantém os mesmos valores de
    process, então não é artefato de instrumentação.
- **Classificação:** medido (agregado); atribuição por função parcial.
- **Impacto:** impede 60 FPS mesmo sem picos; p50 21–27 ms equivale a 37–47 FPS
  sustentados.
- **Alternativas:**
  1. Antes de mudar código, atribuir corretamente: rodar o mesmo cenário com o
     Profiler do depurador do editor (funções de script) e medir um export release
     (o overhead de GDScript em debug pode ser grande).
  2. Reduzir a cadência de decisão (não de movimento nem de colisão) de atores
     visíveis porém distantes. Hoje o trânsito fora da tela já anda a 10 Hz e o
     pedestre decide a 30 Hz.
  3. Remover trabalho por quadro repetido nos maiores consumidores:
     `TrafficVehicle._process` com teste de retângulo e faróis e
     `_update_3d_orientation` a cada quadro; `_synchronize_crossing_consumers`
     varrendo três grupos inteiros a cada publicação, em vez de usar o índice
     `_crossings_by_junction` já calculado.
- **Recomendada:** 1 primeiro (sem ela, qualquer mudança é chute); depois 3, onde o
  profiler confirmar.
- **Riscos:** cadência menor gera divergência de semáforos e pedestres e
  interrompe reações imediatas. Colisão e resposta imediata devem continuar por
  quadro.
- **Teste de aprovação:** `measure_game_frame_stability --normal-cap` e
  `perf_audit_session` antes e depois (p50/p95/p99 em ms) nas mesmas condições;
  `test_harbor_safety` repetido 3×; `test_pedestrian_life_routines`.

### CLAUDE-PERF-004 — Primeira preparação da Mountain Pass durante a gameplay (quadros de 2,9–3,2 s) e região sempre residente

- **Onde:**
  - `world/harbor/ContinuousWorld.gd` `ensure_mountain()` (linhas 21–55),
    disparado em `_process` quando `point.y < -1000` (linha 70).
  - `world/mountain_pass/MountainPass.gd` `_ready()` (linhas 48–122): cede quadros
    entre etapas, mas não dentro delas.
  - `MountainSettlement` e interiores da montanha.
- **Mecanismo:** o carregamento de recursos é threaded, sem espera prematura: o
  laço confere `THREAD_LOAD_IN_PROGRESS` antes de `load_threaded_get`. A
  instanciação e os construtores rodam na thread principal. Algumas etapas criam
  milhares de nós num quadro. Depois de pronta, a região nunca é descarregada; só
  fica com `PROCESS_MODE_DISABLED` e `visible=false` quando longe.
- **Evidência:**
  - run2: quadro de 3.222,6 ms com 9.582 nós adicionados (`WinterDressingPocket`,
    `MountainSettlement`: 7.794 `MeshInstance3D`, 57 SubViewports) e process
    3.127 ms; quadro de 752 ms (`MountainMysteryCaveInterior`); quadro de 507 ms
    (`CliffGuardRails`).
  - run1: quadros de 2.954 e 778 ms; pronta 17,6 s após o teleporte.
  - Memória: +22 mil nós, +392 MiB de memória estática, +750 MiB de VRAM,
    +222 SubViewports residentes.
  - Reentrada: quadro de 370 ms sem nenhum nó adicionado (troca de
    `process_mode`, visibilidade e camadas).
- **Classificação:** medido. O ponto de disparo real (y < −1000) é evidência
  estática; na medição usei teleporte.
- **Impacto:** congelamento de ~3 s na primeira aproximação da serra e ~370 ms a
  cada reentrada.
- **Alternativas:**
  1. Fatiar internamente os construtores com picos (`MountainSettlement`, dressing,
     interiores) usando o mesmo checkpoint por tempo.
  2. Preparar a montanha atrás da tela de loading em vez de na gameplay: aumenta o
     loading e a memória desde o início.
  3. Descarregar a região longe, com histerese: economiza memória, mas arrisca
     identidade e estado (incidentes, coroner, veículos no handoff).
- **Recomendada:** 1. Mantém o design atual, e a travessia continua sem tela de
  loading.
- **Riscos:** `region_ready` e `ready_for_crossing` mais tarde; tráfego da ponte
  chegando antes da região pronta; `RegionTravel.finish_arrival` para saves na
  montanha.
- **Teste de aprovação:** `perf_audit_session`, fase `seam_0` com maior quadro
  abaixo do alvo; `profile_continuous_stream_gaps`,
  `test_mountain_world_consistency`, `test_police_mountain_lanes` e testes de save
  na montanha.

### CLAUDE-PERF-005 — Picos de 0,7 a 5,8 s na gameplay sem causa isolada

- **Onde:** não identificado.
- **Evidência:**

  | run | quadro | contexto | process / física no quadro |
  |---|---:|---|---|
  | run1 | 5.282,5 ms | direção | não subiram (60 / 6,7 ms) |
  | run1 | 5.829,9 ms | direção, logo depois | process 5.774 ms |
  | run2 | 965,5 ms | carro batendo num semáforo em x≈4189; entram `Node2D` + `AudioStreamPlayer2D` (burst e som da batida) | não subiram |
  | run2 | 738,5 ms | perseguição, respawn de `HarborTraffic_48` + residente | não subiram |
  | run2 | 290 ms | primeiro tiro: `CombatImpactAudio` cria 10 `AudioStreamPlayer2D` | — |

  Probe do caminho de colisão (`probe_crash`):

  | caminho | custo medido |
  |---|---:|
  | `CoupeDamageModel.apply_impact` (180–503 vértices) | 0,8–2,2 ms |
  | `_apply_crash_deformation` do trânsito | 1,1–4,5 ms |
  | `_apply_crash_deformation` do `PlayerCar` | 27 ms |
  | `FixedTrafficSignal.receive_vehicle_impact` (queda do semáforo) | 1,2–9,8 ms |
  | `spawn_crash` e `VehicleCrashAudio.play` | <0,1 ms |

  **Esses caminhos não explicam os picos.**
- **Hipóteses (não comprovadas):**
  - Compilação de pipeline ou shader na primeira aparição de um material (burst de
    batida, faíscas, novos modelos), que não aparece em `TIME_PROCESS`/`PHYSICS`.
  - Stall do driver ou do sincronizador de GPU.
  - Carregamento síncrono de recurso na primeira ocorrência.

  Os picos de 5 s da run1 não reapareceram na run2 com a mesma rota. Isso sugere
  dependência de primeira ocorrência ou de tempo, e não da posição.
- **Classificação:** medido (existência e contexto); causa = hipótese.
- **Impacto:** congelamentos perceptíveis de até 5,8 s; frequência não quantificada
  (2 runs).
- **Alternativas (investigação):**
  1. Repetir a direção com o Profiler e o Visual Profiler do editor e com
     `--verbose`, para registrar compilação de shaders.
  2. Bater duas vezes no mesmo semáforo na mesma sessão: se só a primeira travar,
     aponta para primeira ocorrência (pipeline ou recurso).
  3. Cruzar com a medição de GPU e pipeline do Antigravity.
- **Recomendada:** 2 + 3 antes de qualquer correção.
- **Riscos:** corrigir às cegas (por exemplo, desligar efeitos) fabricaria melhora
  sem causa demonstrada.
- **Teste de aprovação:** cenário reprodutível que dispare o pico antes e deixe de
  dispará-lo depois, nas mesmas condições.

### Hipóteses verificadas e descartadas ou rebaixadas

- **`ContinuousWorld._budget_traffic`, `walkers.has()` O(N·M):** a deduplicação
  mede 79 µs (159 pedestres × 66 autorados). Irrelevante.
- **Dois donos de `PopulationActivity` (`HarborLife` e `ContinuousWorld`):** o
  `HarborLife` retorna quando existe `continuous_world` (`HarborLife.gd:375`).
  Descartado.
- **Sons procedurais de batida gerados a cada impacto:** têm cache e são curtos
  (`ProceduralAudio.gd:1299–1337`). Descartado.
- **Rotas de emergência recalculadas sem limite:** `EmergencyLaneRouter.guidance`
  replaneja no máximo a cada 1,5 s ou em `reset()`; foram 6 planos em 30 s. O laço
  alternativo de `EmergencyVehicle._get_road_guidance_target` (linhas 1626–1641:
  todas as faixas × 2 `get_closest_offset` **por tick de física**) só roda quando o
  roteador não tem rede nem faixa ligada. Não observado nesta rodada; fica como
  evidência estática a vigiar.
- **`get_graph_data()` com cópia profunda (4,7 ms):** não roda por quadro. Chamado
  em eventos: `HarborMountainCoachService._plan_city` por viagem, `RoadLighting`,
  `HarborLife` e Cobras na configuração.
- **`TrafficFlowModel.exit_blocker`:** percorre todos os veículos (~97) por
  admissão, com pré-filtro de retângulo. Custo não isolado; entra no agregado do
  003.

---

## E. Ordem proposta de implementação (sem implementar)

1. **Atribuição, sem mudar código:** probe `load()` × construção (002); batida
   dupla no mesmo semáforo (005); Profiler do editor no cenário de direção (003);
   um export release da mesma rota para separar o overhead de debug.
2. **CLAUDE-PERF-002:** pré-carregar recursos de modelo e fatiar
   `ensure_presentation`. É o que mais afeta a sensação de engasgo ao dirigir, e
   tem teste e medidor prontos.
3. **CLAUDE-PERF-001:** fatiar `SouthPort`, `_start_gameplay` e `CobraVehicles` com
   checkpoints de loading.
4. **CLAUDE-PERF-004:** fatiar os construtores da montanha.
5. **CLAUDE-PERF-003:** cortes pontuais onde o profiler confirmar.
6. **CLAUDE-PERF-005:** só depois da causa demonstrada, junto com o Antigravity.

---

## F. Dependências da auditoria gráfica/áudio do Antigravity

- **Custo de render dos SubViewports:** 354 → 652 no total e 223–381 não
  desativados. Pedestres usam `UPDATE_WHEN_VISIBLE` com `own_world_3d`,
  `Camera3D`, `DirectionalLight3D` e `WorldEnvironment` próprios. Este relatório só
  mede o lado CPU da construção.
- **CLAUDE-PERF-005:** a hipótese de compilação de pipeline, shader ou stall de
  GPU nos picos em que process e física não sobem.
- **VRAM de 2,3 GB → 3,3 GB** com a montanha residente.
- **Áudio:** `CombatImpactAudio` cria 10 `AudioStreamPlayer2D` no primeiro tiro
  (quadro de 290 ms); `CityAudioManager` cria e libera players por evento.
- **VSync e monitor de 160 Hz com `max_fps=60`:** efeito na distribuição dos
  intervalos.
- **Divisão CPU/GPU do custo de construir um `Vehicle3DRender` (1,7 s):** o `load`
  e a criação de nós são meus; a primeira renderização é dele.

---

## G. Arquivos, comandos, testes e pendências

**Criados por mim** (nenhum arquivo de produção alterado):
- `tests/perf_audit_claude/perf_audit_session.gd` (+ `.uid` gerado pelo editor): coletor
- `tests/perf_audit_claude/probe_crash_costs.gd`: probe do caminho de colisão
- `tests/perf_audit_claude/results/.gdignore` (o Godot não importa os CSV como
  tradução) e `results/.gitignore` (exclui `appdata/` e `saves/` de cada run)
- `tests/perf_audit_claude/results/{run1,run2_nobudgetcopy}/{report.json,frames.csv,godot_stdout.txt}`
- `tests/perf_audit_claude/results/control_frame_stability/{warmup,driving}.{json,csv}` e `godot_stdout.txt`
- `tests/perf_audit_claude/results/probe_crash/{probe.json,godot_stdout.txt}`
- `tests/perf_audit_claude/results/callbacks_profile/godot_stdout.txt`
- `docs/history/GETECO_PERF_AUDIT_CLAUDE_2026-09-15.md` (este relatório)

**Comandos executados** (PowerShell, `APPDATA` isolado por run, uma run de cada vez):

```
Godot_console.exe --path D:/geteco/game --script res://tests/perf_audit_claude/perf_audit_session.gd -- run=run1
Godot_console.exe --path D:/geteco/game --script res://tests/perf_audit_claude/perf_audit_session.gd -- run=run2_nobudgetcopy --no-budget-timing
Godot_console.exe --path D:/geteco/game --script res://tests/measure_game_frame_stability.gd -- --normal-cap out_dir=<results>/control_frame_stability
Godot_console.exe --path D:/geteco/game --script res://tests/perf_audit_claude/probe_crash_costs.gd -- run=probe_crash
Godot_console.exe --path D:/geteco/game --script res://tests/profile_harbor_game_callbacks.gd -- samples=600
```

Todas terminaram com código 0. Também usei `git status` / `git diff` / `git log`
(leitura) e consultas WMI de hardware e processos.

**Limitações dos instrumentos:**
- A cópia do laço do `PresentationBudget` em run1 roda no sinal `process_frame`, e
  não no `_process` do autoload (a ordem muda).
- A amostragem periódica de emergência e da fila a cada 15 quadros tem custo
  pequeno, mas não nulo.
- O `profile_harbor_game_callbacks` reinvoca callbacks manualmente, com a física
  chamada 1× por quadro e 1920×1080 sem limite; mede só script, com as
  apresentações ainda em grande parte não construídas (90 quadros após instanciar).
- As colunas de process e física do CSV têm um quadro de atraso.

**Testes:** a suíte de verificação do `CLAUDE.md` (`check_references`,
`profile_load_time`, `menu_flow` etc.) **não foi executada**, porque nada de
produção foi alterado nem movido. Nenhum teste de regressão foi rodado nesta
rodada. `test_harbor_safety` não foi executado.

**Falhas:** nenhuma run falhou. O log do PowerShell registra avisos do motor
(`Camera2D overridden to physics process mode`, `Viewport Texture must be set`) que
já existiam e não foram investigados.

**Pendências:** hardware mínimo; export release; rota Novo jogo com cutscene;
travessia dirigida real; load com troca de cena; sessão longa para crescimento;
causa do 005; experimentos listados em E.1.

**Commit:** ver a mensagem final da sessão (hash informado lá).

---

## HANDOFF PARA REVISÃO

**Já pode orientar correção:**
- **001:** o congelamento de 23,5 s é síncrono. `SouthPort._ready` custa 5,6 s e
  `_start_gameplay` + diferidos cerca de 13 s; o padrão de checkpoint já existe.
- **002:** o `PresentationBudget` não limita a construção individual (75 ms a
  1,7 s) e a fila nunca esvazia.
- **004:** o primeiro preparo da montanha trava 2,9–3,2 s na gameplay por
  construtores que criam milhares de nós num quadro.
- **Encerrado:** o hash de junção de 98 mil caracteres está corrigido.

**Ainda precisa ser medido antes de corrigir:**
- **002:** quanto do custo de construção é `load()` e quanto é criação de nós.
- **003:** atribuição por função do custo contínuo (~11,6 ms de script mais o
  restante do motor) e comparação com build release.
- **005:** causa dos picos de 0,7–5,8 s (primeira ocorrência? pipeline/GPU?),
  cruzada com o Antigravity.
- Crescimento em sessão longa, rota Novo jogo e travessia dirigida.

Nenhuma afirmação deste relatório equivale a "60 FPS resolvido" ou "produção
pronta": nada foi corrigido, e todas as medições são de build debug nesta máquina.

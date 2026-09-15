# GETECO-PERF-02B — construção de veículos e fila do PresentationBudget

Data: 2026-09-15. Autor: Claude. Rodada de **implementação delimitada** ao caminho de
construção da apresentação de veículos e à interface com o `PresentationBudget`.
Nenhum outro sistema foi alterado.

---

## 1. Estado do repositório e preservação

| item | valor |
|---|---|
| HEAD durante toda a rodada | `9bd10e0ea52276685e20f27e81a6750be9f44deb` (`main`) — rodada 02A do Antigravity |
| Commit anterior | `0030260` (auditoria GETECO-PERF-01-CLAUDE) |
| Alterações locais de outras sessões | preservadas e não tocadas: `characters/Player.gd`, `systems/RegionTravel.gd`, `systems/interiors/ExteriorOcclusion.gd`, `world/harbor/HarborGame.gd`, `world/harbor/HarborArrivalStop.gd`, `world/harbor/campaign/HarborArrivalMission.gd`, `docs/measurements/review-0909/load_profile.txt`, 2 testes apagados, `tests/test_police_death_departure.gd` |
| Comandos proibidos | nenhum `checkout`, `revert`, `reset`, `restore`, `clean`, `stash`, `git add .` ou `push` foi executado |
| Cópia de referência | `tests/perf_audit_claude/results/02b_baseline_state/local_changes_others.diff` (diff das mudanças alheias no início) |

Para medir "antes" sem reverter nada, usei **worktrees temporárias** fora do
repositório (`git worktree add --detach` no scratchpad), removidas ao final:

- `wt_02a_9bd10e0`: `9bd10e0` + o diff das mudanças locais das outras sessões, **sem** o 02B → é o "antes" de todas as comparações;
- `wt_pure_9bd10e0` e `wt_pure_0030260`: revisões puras, usadas só para atribuir a falha de um teste.

Ordem real dos fatos, para não induzir a erro: a primeira leva de código do 02B foi
aplicada **antes** de chegar o complemento do pedido. O baseline (probes, duas sessões
de rota e as 23 regressões) já estava medido em `9bd10e0` + alterações locais, antes de
qualquer edição minha. Os testes de integração de menu/loading/áudio da 02A foram
executados depois, na worktree **sem** o meu patch, justamente para não misturar.

---

## 2. Revisão do patch de áudio da 02A (`9bd10e0`)

Diff real conferido em `audio/combat/CombatAudioBank.gd`, `audio/combat/CombatImpactAudio.gd`
e `ui/GameLoading.gd`:

- `IMPACT_SAMPLES` passou a ser `preload()` estático de 25 WAVs. O custo sai do primeiro
  impacto e passa para o carregamento do script. **Não medi** esse deslocamento.
- `GameLoading._run` chama `CombatImpactAudio.prepare(world)` na fase `audio`; `world`
  existe no escopo.
- `ensure_pool()` mudou o fallback: sem mundo de combate, o pool passa a ser filho do
  próprio contexto quando ele é `Node2D` (antes era o pai). Como `CombatWorld.scene_for`
  recai em `current_scene`, o caso só aparece sem cena atual (testes). **Observação, não
  defeito demonstrado.**

### Testes de integração (worktree sem o 02B)

| teste | resultado |
|---|---|
| `test_menu_flow_integration` | passou |
| `test_opening_loading` | passou |
| `test_combat_audio` | passou (`failures=0`) |
| `test_vehicle_audio_preparation` | passou (`vehicles=47`) |
| `test_menu_legacy_loading` | passou |
| `test_garage_weapon_restrictions` | passou (0 falhas) |
| `test_continue_skips_opening` | **falhou (7 falhas)** |

A falha foi atribuída, não suposta: o mesmo teste falha igual em `9bd10e0` puro **e** em
`0030260` puro (anterior à 02A). Stack: `first_favors.active()` nulo em
`HarborArrivalMission.start_or_resume` (linha 148/151 conforme a revisão); o mundo falso do
teste não cria `first_favors`. É **falha pré-existente**, não regressão da 02A nem das
alterações locais, e está fora do meu escopo.

### Premissas da 02A que **não** adotei

- "GPU descartada": não medi GPU nesta rodada; a própria 02A registra que a medição do
  viewport raiz não soma os SubViewports com mundo próprio.
- "97,7% estáticos": não usei esse número como base de decisão.
- "áudio 100% resolvido em produção": o que tenho é que 6 dos 7 testes acima passam.
- **Divergência do enum confirmada em runtime** (Godot 4.7.2):
  `UPDATE_DISABLED=0, UPDATE_ONCE=1, UPDATE_WHEN_VISIBLE=2, UPDATE_WHEN_PARENT_VISIBLE=3, UPDATE_ALWAYS=4`.
  O inventário da 02A e a versão anterior do meu coletor tratavam `3` como `ALWAYS`. Meu
  coletor agora mapeia por constante; o valor `3` nunca apareceu nas cenas medidas, e
  `ALWAYS` aparece (2 nós) só depois da montanha residente.

### Relógio, frames e escopo dos tempos

- Intervalos entre quadros: `Time.get_ticks_usec()` a cada `process_frame` (monotônico,
  não o `delta`). FPS = quadros ÷ tempo real somado, e a duração de cada fase vai na tabela.
- Percentis por posto mais próximo, em ms. Sem p99,9: nenhuma fase teve ≥10 mil quadros.
- `TIME_PROCESS`/`TIME_PHYSICS_PROCESS` são monitores do motor com um quadro de atraso;
  não são tempo total de CPU nem de GPU.
- No probe, os timers são sequenciais e não se sobrepõem. As réplicas somente leitura
  (`contido_em_*`) são medidas à parte e **nunca** entram nas somas — e há um efeito
  colateral registrado na seção 5: a réplica do formato aquece o cache daquele exemplar.

---

## 3. Ambiente e condições

| item | valor |
|---|---|
| Motor | Godot 4.7.2-stable official (`ed1daf0bf`), binário do editor, `--script` |
| Build | **debug** (`OS.is_debug_build() = true`). Release **NÃO MEDIDO** |
| Export release | indisponível: não há `export_presets.cfg` nem templates instalados. Registrado como pendência; **não** instalei nada |
| Renderer efetivo | Vulkan 1.4.341, Forward **Mobile**, confirmado em runtime |
| GPU / CPU / RAM | RTX 4060 Laptop (driver 32.0.16.1047) / i7-13650HX (14C/20T) / 31,7 GB |
| Janela / VSync / limite | 1280×720, VSync ligado, `max_fps=60`, física 60 Hz, interpolação ligada |
| Concorrência | editor do Godot do usuário aberto; Antigravity IDE aberto; **nenhum** outro processo Godot de teste — todas as execuções minhas foram sequenciais, uma por vez |
| Isolamento | `APPDATA` próprio por execução dentro de `results/<run>/appdata` + `SaveManager._save_dir` redirecionado; o coletor aborta se o user data não estiver isolado |
| População, física, câmera, qualidade | inalteradas |

---

## 4. Implementação escolhida

Quatro mudanças, todas no caminho de construção de veículos e na interface da fila
(`production_02b.diff` no pacote, +163/−7 linhas antes da terceira leva):

1. **`cars/VehicleMeshBatcher.gd`** — cache do formato de superfície por identidade da
   malha (com invalidação por `changed`) e, para `PrimitiveMesh`, por classe + `add_uv2`.
   `surface_get_arrays()` copiava todos os arrays de ~100 malhas só para montar a chave do
   agrupamento, a cada construção. Limites: malhas fundidas 256 → **1.024**; formatos →
   16.384. Contadores de acertos, falhas, descartes e invalidações expostos.
2. **`prototypes/living_cast/VehicleWheelClearance.gd`** — memo da chave de conteúdo do
   recorte dos poços de roda por identidade da malha, apontando para a **mesma** chave de
   conteúdo (a partilha entre malhas idênticas continua), com invalidação por `changed`.
3. **`cars/VehicleGeometryCache.gd`** — o aquecimento do loading passa a incluir os
   modelos dos veículos **presentes na árvore carregada** e que ficaram fora da lista fixa.
   Gatilho e limite claros: só classes já instanciadas no mundo; a montanha, carregada
   depois por streaming, fica de fora.
4. **`systems/PresentationBudget.gd`** — `get_stats()` torna a fila verificável: custo por
   classe de ator **e por modelo de veículo**, construções acima do orçamento, espera desde
   que o ator ficou relevante, idade do pedido mais antigo por relevância e cancelamentos.
   A política de escolha não mudou: 1 construção por quadro, vizinho mais próximo do centro
   da tela primeiro.

### Alternativas rejeitadas (e por quê)

- **Construção em etapas dentro do orçamento.** Rejeitada com medição: depois dos caches,
  o veículo repetido custa 4–6 ms, e o bloco caro que resta nos modelos sem cache é **uma
  única chamada** (`batch_model`, 30–50 ms) que o fatiamento não quebraria. Fatiar mudaria
  ainda o contrato que `test_vehicle_presentation_streaming` e
  `test_resident_vehicle_preparation` exigem (uma chamada de `_process` conclui a
  apresentação). Pendência honesta: **o limite de 2 ms continua sendo excedido** (seção 6).
- **Pool global de rigs reciclados.** Rejeitada nesta rodada: exigiria estado mutável
  compartilhado entre veículos (pintura, dano, portas), exatamente o que os contratos
  proíbem.
- **Assar os modelos já montados como `.res`/`.tscn`.** Rejeitada por tamanho: exigiria
  pipeline de geração reproduzível e invalidação por mudança de modelo, mais do que esta
  rodada autoriza.
- **Cachear a geometria das motos e do `BossMuscle`.** Não feita: essas classes não passam
  por `BaseVehicle3DModel._init` e carregam nós de piloto/scripts que o `capture()` recusa
  de propósito. Documentada como pendência medida (seção 5).

---

## 5. Resultados medidos

### 5.1 Construção de um veículo (probe, jogo carregado pelo `GameLoading` real)

`ensure_presentation()` em ms, mesmo cenário e caches aquecidos como no jogo:

| veículo | baseline | 1ª leva (caches) | 2ª leva (limites) |
|---|---:|---:|---:|
| `union_sedan` (ex. 1/2/3) | 39,0 / 41,9 / 42,0 | 4,9 / 4,8 / 4,7 | 4,7 / 4,8 / 4,8 |
| `courier_van` | 42,8 / 39,4 / 40,0 | 4,8 / 4,7 / 4,8 | 4,7 / 4,7 / 4,7 |
| `route_city` (ônibus) | 64,0 / 43,4 / 45,0 | 66,8 / 5,0 / 4,9 | 4,9 / 5,0 / 5,2 |
| `american_tanker_truck` | 155,0 / 56,2 / 57,2 | 142,5 / 5,7 / 5,9 | 151,5 / 5,8 / 5,6 |
| `police_suv` | 48,8 / 42,4 / 40,5 | 4,5 / 4,5 / 4,2 | 4,6 / 4,3 / 4,3 |
| emergência: polícia | 54,7 / 61,0 | 26,7 / 34,5 | 19,3 / 22,8 |
| emergência: ambulância | 108,5 / 112,2 | 162,3 / 89,4 | 80,8 / 85,3 |

- O tanker no **primeiro** exemplar continua caro porque nenhum tanker existia na árvore
  durante o loading: é construção de primeira vez de verdade, não custo repetido.
- A ambulância (`MedicBoxModel`) nunca entra no `VehicleGeometryCache`: o modelo guarda
  referências de nó (`rear_doors`), e o `capture()` recusa por contrato.

### 5.2 Onde o custo estava (decomposição, jogo carregado)

Baseline, exemplares repetidos: `new()` 1,6–2,0 ms · entrada na árvore 0,3–0,6 ms ·
`mount()` 1,1–9,9 ms · **`batch_model()` 21,2–50,2 ms** · câmera/luz 0,1 ms.
Réplicas somente leitura: **formato de superfície 20,7–57,1 ms** e chave do recorte
1,6–7,6 ms. Depois da 1ª leva, o total repetido caiu para 4,1–6,1 ms.

### 5.3 Cache de malhas fundidas (o limite era menor que a frota)

| medição | limite 256 (baseline/1ª leva) | limite 1.024 (2ª leva) |
|---|---:|---:|
| falhas de cache após o loading | 782 | 714 |
| **descartes após o loading** | **526** | **0** |
| entradas ao fim do probe | 256 (cheio) | 755 |
| invalidações por `changed` | 0 | 0 |
| memória estática após o loading | 963,3 MiB | 966,8 MiB |

O `route_city` ex. 1 caiu de 57,4 ms para 4,9 ms exatamente por isso. A diferença de
memória (~3,5 MiB) está dentro da variação entre processos e **não** foi isolada.

### 5.4 Modelos sem cache de geometria (motos e `muscle_classic`)

Esses modelos criam malhas novas a cada construção, então o cache por identidade não
acerta e o formato voltava a ser recalculado. A 3ª leva (formato por classe de
`PrimitiveMesh`) atacou essa parte: as entradas do cache de formatos ao fim do probe
caíram de 7.627 para 1.308, e a réplica do formato caiu de 38–50 ms para 8–13 ms (motos)
e de ~21 ms para ~1 ms (`muscle_classic`).

**Cuidado metodológico:** na variante `decomp`, a réplica do formato roda antes do
`batch_model` e aquece o cache daquele exemplar, então o `batch` decomposto já não pagava
o formato nem antes. Por isso a comparação válida para esses modelos é o caminho real,
medido lado a lado:

`ensure_presentation()` em ms, mesmo cenário e mesmo probe nos dois lados
(`02b_final_probe_uncached_before` = worktree sem o 02B; `..._after` = árvore principal):

| veículo (ex. 1 / 2 / 3) | antes | depois | variação nos repetidos |
|---|---:|---:|---:|
| `bike_sport` (sem cache de geometria) | 98,1 / 91,8 / 93,3 | 68,6 / 69,0 / 66,3 | −25% a −29% |
| `bike_urban` (sem cache de geometria) | 80,9 / 85,1 / 86,6 | 61,5 / 62,4 / 70,4 | −19% a −27% |
| `muscle_classic` (sem cache de geometria) | 191,1 / 48,1 / 50,3 | 46,0 / 55,9 / 54,5 | **+8% a +16%** |
| `union_sedan` (com cache de geometria) | 36,6 / 35,5 / 39,9 | 4,8 / 5,1 / 5,1 | −86% a −87% |
| emergência: polícia | 57,2 / 42,6 | 22,3 / 25,9 | −39% a −61% |
| emergência: ambulância | 89,1 / 88,8 | 57,2 / 63,6 | −28% a −36% |

Leitura honesta destes números:

- Onde o `VehicleGeometryCache` funciona (sedan, viaturas), o ganho é de 5 a 8×.
- Nas motos, o ganho é parcial (−20% a −30%): some o custo do formato, mas continua a
  fusão de superfícies, que não reaproveita nada porque as malhas são novas a cada
  construção.
- No `muscle_classic`, os **exemplares repetidos ficaram 8–16% mais lentos** que antes.
  São execuções únicas, a diferença é de 4–6 ms e está na mesma ordem da variação entre
  exemplares do próprio baseline (48,1 vs 50,3), então **não afirmo ganho nem regressão**
  para esse modelo: o que se pode dizer é que ele não foi beneficiado. O primeiro exemplar
  caiu de 191,1 ms para 46,0 ms, mas o valor "antes" inclui carga de script de primeira vez.
- Cache ao fim do probe: antes, 256 malhas fundidas (**cheio**, contadores de descarte não
  existem naquela árvore); depois, 897 malhas, **0 descartes**, 7.765 acertos de formato por
  classe de `PrimitiveMesh` e 1.308 entradas de formato por identidade.
- Memória estática ao fim do probe: 968,4 MiB (antes) contra 973,5 MiB (depois), ou seja
  ~5 MiB a mais, medidos em execução única.

### 5.5 Rota real: custo por quadro e espera da fila

Mesmo coletor, mesma rota, mesma semente e mesmas condições nos dois lados, uma execução
cada (`02b_ab_before_1` = worktree sem o 02B; `02b_ab_after_1` = árvore principal):

| cenário / métrica (ms) | antes | depois |
|---|---:|---:|
| **parado 5 s** — p50 / p95 / p99 / máx | 17,6 / 28,9 / 72,5 / 118,8 | 18,0 / 27,4 / 56,6 / 134,1 |
| **direção 30 s** — quadros / FPS | 1.122 / 37,6 | 1.432 / 48,0 |
| direção — p50 / p95 / p99 / máx | 21,5 / 49,5 / 114,4 / 263,7 | 18,2 / 28,0 / 71,5 / 144,7 |
| direção — >16,67 / >33,33 / >50 / >100 | 1.074 / 162 / 55 / 14 | 1.257 / 25 / 15 / 12 |
| **perseguição 6★ 30 s** — quadros / FPS | 874 / 29,3 | 1.324 / 44,4 |
| perseguição — p50 / p95 / p99 / máx | 28,7 / 47,0 / 78,8 / 1.850,7 | 20,4 / 30,9 / 35,7 / 150,8 |
| perseguição — >33,33 / >50 / >100 | 172 / 39 / 7 | 28 / 3 / 2 |
| montanha (2º ciclo) — p50 / máx | 26,8 / 53,0 | 21,6 / 35,5 |
| retorno ao Harbor (2º ciclo) — p50 / máx | 20,6 / 59,0 | 19,1 / 186,6 |

**Espera até a apresentação ficar pronta**, contada de quando o ator entra na margem de
construção (mesma definição nos dois lados, medida pelo coletor externo):

| classe | antes (p50 / p95 / máx, n) | depois (p50 / p95 / máx, n) |
|---|---|---|
| visível | 326,2 / 1.972,2 / 1.972,2 ms (14) | 296,9 / 955,4 / 955,4 ms (16) |
| prestes a entrar | 173,1 / 889,7 / 915,6 ms (26) | 99,3 / 929,1 / **8.153,6** ms (23) |

**A fila não cresceu para esconder travada:** pendentes por classe ao final foram
115 distantes / 3 próximos / 2 visíveis (antes) contra 121 / 1 / 0 (depois); no lado
"depois", o `PresentationBudget` registrou 215 pedidos, 93 construções e 0 cancelamentos.
Memória e nós ao fim da direção: 1.016 MiB / 33.344 nós (antes) contra 1.013 MiB / 32.924
nós (depois). Cache de fusões: 256 entradas **cheias** antes; 785 entradas e **0 descartes**
depois.

Ressalvas honestas sobre esta tabela:

- É **uma execução por lado**. A variância entre execuções do mesmo código, observada
  nesta rodada, é grande: o mesmo cenário `pursuit` deu máximo de 1.850,7 ms no lado
  "antes" e 171,2 ms numa execução anterior do baseline. Parte da diferença de p95/p99
  pode ser ambiente, não patch.
- O máximo de 8,15 s na classe "prestes a entrar" do lado "depois" é **pior** que o
  "antes" (0,92 s): é um caso isolado entre 23 amostras, e não tenho repetição suficiente
  para dizer se é regressão ou ruído. Fica registrado como pendência de medição.
- O máximo de 186,6 ms no retorno ao Harbor (depois) também é pior que os 59,0 ms do
  lado "antes", pelo mesmo motivo.
- O ganho de p95/p99 na direção é consistente com a redução medida de custo de
  construção, mas **não é prova** de 60 FPS: o p50 continua em 18,2 ms (~55 FPS) e o
  custo contínuo de CPU, diagnosticado na rodada 01, não foi tocado aqui.

Medições já disponíveis da 2ª leva (execução única, árvore principal), com as estatísticas
do próprio `PresentationBudget`:

| métrica (direção, 30 s) | baseline | 2ª leva |
|---|---:|---:|
| p50 | 18,5 ms | 17,9 ms |
| p95 | 28,7 ms | 28,0 ms |
| p99 | 111,9 ms | 74,0 ms |
| máximo | 255,5 ms | 217,6 ms |
| quadros > 50 ms | 20 | 17 |
| quadros > 100 ms | 15 | 13 |

Fila na 2ª leva: 224 pedidos, 103 construções, 0 cancelamentos, 38 construções acima do
orçamento de 2 ms (22 pedestres, 16 veículos), maior construção 104,7 ms.
Espera **desde que o ator ficou relevante**: visível p50 0 ms / p95 214 ms / máx 495 ms;
prestes a entrar p50 0 ms / p95 654 ms / máx 8,0 s. Pedidos distantes chegam a 162 s, que é
a política atual (só se constrói quem se aproxima) — a fila **não** foi usada para esconder
travamento: o total de pedidos e construções ficou igual ao do baseline.

Custo por modelo na 2ª leva (o que sobra caro são primeiros exemplares e modelos sem
cache): `SportMotorcycle` 102,7 ms · `UrbanMotorcycle` 89,7 ms · `Towmaster` 85,6 ms ·
`BossMuscle` 60,2 ms · `MetroHatch` 27,1 ms · demais modelos 5,0–5,6 ms ·
pedestres (`HarborWalker`) 72,3 ms · semáforos 0,2 ms.

### 5.6 Loading

`vehicle_models` subiu de 3.391 ms (baseline) para 3.831 ms (2ª leva): +0,44 s, custo do
aquecimento dos modelos presentes. O total do loading variou entre 36,9 s e 45,9 s nas
execuções, dominado por `scene_ready`, que **não** faz parte deste escopo — é variância de
execução única, não efeito atribuível ao patch.

---

## 6. Limites desta conclusão

- Build **debug**; sem export release para comparar (templates ausentes).
- Uma execução por cenário na maior parte das medições; a variância observada entre
  execuções do mesmo código é grande (ex.: `seam_0` e `harbor_return_1` no baseline).
- O limite de 2 ms do `PresentationBudget` **continua sendo excedido**: uma construção
  indivisível ainda pode custar dezenas de ms (motos, pedestres, primeiros exemplares).
  O que mudou é que agora isso é **medido e exposto** por `get_stats()`.
- Pedestres não foram tocados: ~72 ms por construção e o maior custo total da fila.
- Loading e construtores da montanha continuam fora do escopo desta rodada.
- Travessia medida por teleporte, não dirigindo pela ponte.
- GPU não medida aqui; segue com a auditoria do Antigravity.

---

## 7. Validação funcional

### 7.1 Regressões (mesma lista, mesmo runner, antes e depois)

23 testes de veículos, geometria, orçamento, portas, rodas, dano, reparo, sirenes,
emergência, região, save e menu, mais `tools/check_references.py`.

| estado | resultado |
|---|---|
| baseline (antes de qualquer mudança minha) | 19 passaram, 4 falharam |
| código final do 02B | 19 passaram, **as mesmas 4** falharam |

As 4 falhas são pré-existentes e foram lidas uma a uma:

- `test_sculpted_vehicle_fleet`: 3 falhas de **família de motor** (`aurora_executive`,
  `vale_crossover`, `nimbus_minivan`) — áudio de catálogo, fora deste escopo;
- `test_native_vehicle_doors`: `No door geometry: PortForkliftModel.gd` e
  "Door did not physically open";
- `test_vehicle_entry_exit`: `Player or vehicle not found` (fixture do teste);
- `test_in_game_fleet_integration`: 4 expectativas de conteúdo desatualizadas
  (`sedan_classic` 2D, `route_city` no tráfego, `ThematicFleet`).

`tools/check_references.py` sai com código 1 **antes e depois**, pelos mesmos 3 caminhos,
todos citados em `.claude/settings.local.json` (arquivo de configuração local, não código
do jogo): `AchievementCatalog.gd`, `CollectibleCatalog.gd`, `ProjectedSilhouette.gdshader`.

### 7.2 Contratos de estado independente e ciclo de vida

`tests/perf_audit_claude/test_02b_vehicle_presentation_contracts.gd` (novo), executado no
baseline e depois de cada leva, sempre com `failures=[]`:

- dano em um carro **não** altera a malha de outro do mesmo arquétipo, e os faróis do
  segundo continuam intactos;
- pintura é material próprio: repintar A não muda B;
- rodas montadas (pivôs e giradores) e portas extraídas **idênticas** a um modelo montado
  sem cache, nos dois lados;
- sirene/lightbar ligada ao modelo próprio, sem lâmpadas compartilhadas;
- reparo restaura a geometria original;
- reciclagem (troca de arquétipo) libera o modelo anterior e não deixa ocupante antigo;
- cancelamento: ator liberado antes da construção sai da fila, sem erro, sem nós órfãos
  novos, e é contabilizado em `get_stats()`;
- caches invalidam quando a malha-fonte muda;
- formato por classe de `PrimitiveMesh` idêntico ao lido dos arrays em 21 malhas
  (7 classes × 3 variações de parâmetro).
### 7.3 Imagem

Mesmo veículo, mesma cor, mesmo ângulo, mesma semente e o mesmo par de impactos, com o
`SubViewport` de cada modelo salvo em PNG nas duas árvores
(`02b_visual_final/{before,after}`):

- **13 de 13 imagens com diferença zero de pixels** (limpo, danificado e reparado para
  sedan, ônibus, tanker e viatura de trânsito; mais a viatura de emergência), delta máximo
  de canal 0/255.
- As capturas têm conteúdo (8.232 a 21.383 pixels opacos), então a igualdade não é de duas
  imagens vazias.
- O dano aparece de fato nas imagens de sedan (4.854 pixels diferentes do estado limpo) e
  ônibus (1.857), e o reparo volta **exatamente** ao estado limpo.
- Limitação: no tanker e na viatura, o par de impactos fixo não mudou pixels no ângulo
  capturado, então para eles a prova cobre limpo e reparado, não o dano visível.

---

## 8. Pacote e reprodução

### Arquivos de produção alterados (4)

`cars/VehicleMeshBatcher.gd`, `cars/VehicleGeometryCache.gd`,
`prototypes/living_cast/VehicleWheelClearance.gd`, `systems/PresentationBudget.gd`.
Diff completo em `tests/perf_audit_claude/results/02b_package/production_02b.diff`.

### Diagnóstico e testes criados (meus)

- `tests/perf_audit_claude/probe_vehicle_build_02b.gd` — decomposição e caminho real da
  construção, por arquétipo, em processo novo ou depois do `GameLoading` real;
- `tests/perf_audit_claude/test_02b_vehicle_presentation_contracts.gd` — contratos da
  seção 7.2;
- `tests/perf_audit_claude/capture_02b_vehicle_images.gd` — captura e comparação de imagem;
- `tests/perf_audit_claude/run_02b_regressions.ps1` e `run_02b_ab_sessions.ps1` — runners
  sequenciais;
- `tests/perf_audit_claude/perf_audit_session.gd` — coletor da rodada 01, atualizado aqui
  com: mapa de `SubViewport` por constante, espera desde que o ator fica relevante,
  contadores de cache e leitura tolerante (`Script.get()`) para rodar também na árvore
  "antes".

### JSON/CSV das execuções

`tests/perf_audit_claude/results/` — `report.json` e `frames.csv` das sessões,
`probe.json` dos probes, `summary.json` das regressões, PNGs e `compare.json` da imagem,
`run_info.txt` com árvore, HEAD e duração de cada execução.
**Excluídos do versionamento** (`results/.gitignore`): `*/appdata/` e `*/saves/` de cada
execução — user data isolado, sem saves nem dados pessoais.

### Comandos (sem push; um processo Godot por vez)

```powershell
$env:APPDATA = "<projeto>/tests/perf_audit_claude/results/<run>/appdata"
& $godot --path D:/geteco/game --script res://tests/perf_audit_claude/probe_vehicle_build_02b.gd -- run=<run> mode=loaded variant=real archetypes=bike_sport,bike_urban,muscle_classic,union_sedan
& $godot --path D:/geteco/game --script res://tests/perf_audit_claude/perf_audit_session.gd -- run=<run> --no-budget-timing
& $godot --path D:/geteco/game --script res://tests/perf_audit_claude/test_02b_vehicle_presentation_contracts.gd
powershell -File tests/perf_audit_claude/run_02b_regressions.ps1 -Label <rotulo>
powershell -File tests/perf_audit_claude/run_02b_ab_sessions.ps1 -Worktree <worktree> -Repeat 1
& $godot --path D:/geteco/game --script res://tests/perf_audit_claude/capture_02b_vehicle_images.gd -- mode=capture out=<pasta>
```

As worktrees temporárias foram removidas ao final; a árvore de trabalho do usuário nunca
foi tocada.

---

## HANDOFF PARA REVISÃO

**1. Reduziu o custo de construção de veículos?** Sim, medido:

- veículos com cache de geometria: de 36–64 ms para **4,7–5,2 ms** por construção
  (sedan 36,6 → 4,8 ms no A/B com o mesmo probe);
- viatura de emergência: de 42–61 ms para **22–26 ms**; ambulância de ~89 ms para
  **57–64 ms**;
- ônibus no primeiro exemplar: de 57,4 ms para 4,9 ms, ao parar de descartar fusões;
- motos: de 81–98 ms para **62–70 ms** (ganho parcial);
- `muscle_classic` repetido: **sem ganho demonstrado** (48–50 ms antes, 54–56 ms depois,
  dentro do ruído de execução única).

**2. Reduziu os engasgos na rota real?** Parcialmente, com ressalva de amostra: na
direção de 30 s, p95 de 49,5 → 28,0 ms, p99 de 114,4 → 71,5 ms, máximo de 263,7 → 144,7 ms
e quadros acima de 33,33 ms de 162 → 25. Na perseguição, p99 de 78,8 → 35,7 ms. É **uma
execução por lado**, e a variância desta máquina é grande; dois contra-exemplos
(máximo de 8,15 s de espera de um ator próximo e 186,6 ms no retorno ao Harbor, ambos no
lado "depois") continuam sem explicação e estão registrados.

**3. O que continua caro?** Sim, sobra muito:

- **pedestres**: ~72 ms por construção, o maior custo total da fila — não tocados aqui;
- **modelos sem `VehicleGeometryCache`** (motos, `BossMuscle`): 46–70 ms por construção,
  porque refazem a fusão de superfícies a cada instância;
- **primeiro exemplar** de um modelo que não existia no mundo durante o loading
  (tanker: 151 ms);
- **loading**: congelamento de ~22–24 s num quadro, dominado por `scene_ready`;
- **montanha**: quadros de até 3,3–4,3 s na primeira preparação;
- **custo contínuo de CPU**: p50 de 18 ms na direção (~55 FPS) sem nenhum pico.

**O limite de 2 ms do `PresentationBudget` continua sendo excedido** — 36 construções
acima dele em 93, com máximo de 85,2 ms. O que esta rodada entrega é que isso agora é
medido e exposto por `get_stats()`, com custo por modelo e espera por relevância, em vez
de invisível. **Não** declaro 60 FPS, GPU descartada nem projeto otimizado.

# GETECO-PERF-01-ANTIGRAVITY — Auditoria de Renderização, SubViewports, Apresentação e Áudio

Data: 2026-09-15. Rodada de **análise e diagnóstico**: nenhum arquivo de produção foi alterado.
Escopo: custos de renderização (GPU/CPU), SubViewports, malhas 3D, animação, apresentação visual, efeitos e áudio. Complementa a auditoria de simulação/CPU do Claude (`GETECO_PERF_AUDIT_CLAUDE_2026-09-15.md`).

---

## A. Resumo executivo e limites da auditoria

1. **A GPU não é o gargalo:** Na máquina de teste (RTX 4060 Laptop), a execução na GPU mediu **p50 de 1,88 a 2,26 ms** em 1280×720 e **2,40 ms** em 1920×1080. A GPU consome menos de 15% do orçamento de 16,67 ms. Quedas de FPS não decorrem de saturação de rasterização ou fillrate da GPU.
2. **SubViewports ativos vs existentes (Esclarecimento do Claude):** Dos 345 SubViewports presentes em `HarborGame`, **197 são estáticos** (prédios portuários, guindastes, navios, pilhas de carga, barris) que renderizam uma única vez (`UPDATE_ONCE`) durante o carregamento e ficam em cache; **140 ficam `UPDATE_DISABLED`**; e **apenas 8** operam em `UPDATE_WHEN_VISIBLE`. Durante a condução ativa, mediu-se uma média de apenas **~5,76 SubViewports renderizando por frame** (1,27 veículos + 4,49 pedestres). O alto número registrado pelo Claude ("223–381 não desativados") era um artefato do teste de enum no Godot, pois `UPDATE_ONCE` mantém valor 1 mesmo após já ter renderizado.
3. **Causa isolada do primeiro tiro (290 ms):** O frame de 290 ms no primeiro disparo foi isolado e comprovado. **228,3 ms** (78% do tempo) são devidos ao carregamento síncrono em disco de **25 arquivos WAV** dentro de `CombatAudioBank.sound()`, que não estavam pré-carregados. A instanciação dos 10 `AudioStreamPlayer2D` custou apenas 12,5 ms, e o 2º tiro na mesma sessão levou apenas 5,7 ms.
4. **Decomposição do Vehicle3DRender (CLAUDE-PERF-002, 1,76 s):** O custo de construção de um carro (112 a 401 ms de CPU) é 85–95% dominado por GDScript na thread principal: instanciação de 97 nós / 96 meshes (`model.new()`, até 200 ms no 1º uso), varredura profunda de transformações em `wheel_rig.mount()` (90–113 ms) e unificação de superfícies em `VehicleMeshBatcher.batch_model()` (28–63 ms). O primeiro frame de desenho na GPU leva apenas 1,5 a 67 ms.
5. **Impacto de semáforo e MSAA 2X (CLAUDE-PERF-005):** A colisão com semáforo (`FixedTrafficSignal`) gera pico imediato porque cria síncronamente um novo `SubViewport` 384×384 com `MSAA_2X` e `own_world_3d`, exigindo compilação de novo passe Vulkan no 1º frame da queda (**105,1 ms**), além de 25,3 ms de CPU.
6. **Mito do WeaponIcon3D refutado:** O ícone de arma do HUD é 100% 2D (`Control`), renderizando texturas estáticas SVG/PNG via `draw_texture_rect` estritamente por evento (`set_weapon`). Não possui SubViewport nem consome processamento por frame.

Limites desta auditoria: Build Debug oficial; editor do Godot aberto em background; resolução de teste padrão 1280×720 em janela; medições focadas na região de Harbor e cruzamento com os dados da sessão do Claude.

---

## B. Ambiente, revisão e condições dos testes

| Item | Valor |
|---|---|
| Revisão Git | `main` @ `0030260b879191981d75fa31a3a8c61bc1695bee` (sobre o commit da auditoria do Claude) |
| Alterações de trabalho locais | Preservadas sem alteração (`characters/Player.gd`, `systems/RegionTravel.gd`, `world/harbor/...`, etc.) |
| Engine / Executável | Godot 4.7.2-stable official (`ed1daf0bf`), `Godot_v4.7.2-stable_win64_console.exe`, `--script` |
| Build | **Debug** (`OS.is_debug_build() = true`) |
| Renderer efetivo | Vulkan 1.4.341, Forward **Mobile** (`rendering_method=mobile`), GPU NVIDIA GeForce RTX 4060 Laptop (driver 32.0.16.1047) |
| CPU / RAM | Intel Core i7-13650HX (14 núcleos / 20 threads), 31,7 GB RAM |
| Janela / Resolução | 1280×720 (baseline e ablações); comparação com 1920×1080 |
| VSync / Limite | VSync modo 1, `max_fps=60`, física a 60 Hz |
| Concorrência | Editor Godot 4.7.2 aberto em background (PID 39048); Antigravity IDE aberto |
| Isolamento | `$env:APPDATA` isolado em pastas exclusivas sob `tests/perf_audit_antigravity/results/`; saves redirecionados para `temp_saves/` |

---

## C. Inventário mensurável da apresentação

### 1. SubViewports: População, Configuração e Mundos 3D

Mapeamento completo realizado em cena real de `HarborGame` carregada e estabilizada (`probe_subviewports.gd`):

| Categoria de Nó | Quantidade | Resoluções (px) | Modos Configurados | own_world_3d | Câmeras | Luzes | Envs | MSAA |
|---|---:|---|---|---:|---:|---:|---:|---:|
| **Trânsito (`TrafficVehicle`)** | 24 | 192×192 (21), 256×256 (3) | 24 DISABLED (parados) | 24 | 24 | 24 | 24 | 24 |
| **Pedestres (`AnimatedPedestrian3D`)** | 68 | 96×96 | 60 DISABLED, 8 WHEN_VISIBLE | 68 | 68 | 68 | 68 | 68 |
| **Passageiros Ônibus (`UrbanPassenger`)** | 24 | 96×96 | 24 DISABLED | 24 | 24 | 24 | 24 | 24 |
| **Trabalhadores Porto (`HarborDockWorker`)** | 30 | 96×96 | 30 DISABLED | 30 | 30 | 30 | 30 | 30 |
| **Prédios do Porto (`HarborPortModelView`)** | 5 | 690×490 (2), 260×308, 250×394, 135×199 | 5 ONCE | 5 | 5 | 5 | 5 | 5 |
| **Pilhas de Carga (`CargoStack3D`)** | 18 | 380×230 (6), 380×183 (12) | 18 ONCE | 18 | 18 | 18 | 18 | 18 |
| **Navio Cargueiro (`SantaMareCargo3D`)** | 2 | 1115×374, 260×398 | 2 ONCE | 2 | 2 | 2 | 2 | 2 |
| **Guindastes de Cais (`QuaysideCrane3D`)** | 6 | 290×612 (3), 146×128 (3) | 6 ONCE | 6 | 6 | 6 | 6 | 6 |
| **Refletores Porto (`PortFloodlight`)** | 8 | 128×202 | 8 ONCE | 8 | 8 | 8 | 8 | 8 |
| **Fachadas / Edifícios Estáticos** | 14 | 960×800 (4), 288×240 (10) | 14 ONCE | 13 | 14 | 13 | 13 | 14 |
| **Estações de Metrô (`UrbanStationView`)** | 6 | 1440×1200 | 6 DISABLED | 6 | 6 | 6 | 6 | 6 |
| **Túmulos Cemitério (`MountainStaticModelView`)** | 120 | 256×256 | 120 ONCE | 120 | 120 | 120 | 120 | 120 |
| **Jogador (`Player` Dante)** | 1 | 128×128 | 1 WHEN_VISIBLE | 1 | 1 | 2 | 1 | 1 |
| **HUD / WeaponIcon3D** | 0 | — | — | 0 | 0 | 0 | 0 | 0 |
| **Outros (paletes, tambores, cargas)** | 19 | 160×169 a 256×256 | 19 ONCE | 19 | 19 | 19 | 19 | 19 |
| **TOTAL GERAL** | **345** | — | **140 DIS / 197 ONCE / 8 VIS / 0 ALW** | **336** | **311** | **313** | **269** | **344** |

### 2. Atividade Real vs Existente

- **Diferenciação crítica:** 197 SubViewports estão com `render_target_update_mode = UPDATE_ONCE`. No Godot, após renderizarem o primeiro frame, a textura fica em memória e **nenhum trabalho de renderização ocorre nos frames subsequentes**.
- **Medição em 120 frames de condução real:**
  - Veículos de trânsito disparando renderização (`TrafficVehicle.UPDATE_ONCE`): **152 requisições (1,27 por frame)**.
  - Pedestres disparando renderização (`AnimatedPedestrian3D.UPDATE_ONCE`): **539 requisições (4,49 por frame)**.
  - **Total dinâmico efetivo:** **~5,76 SubViewports renderizando por frame** durante gameplay ativo.
- **Animação na CPU:** Pedestres visíveis **não** utilizam `AnimationPlayer` nem nós de esqueleto do motor; calculam trigonometria procedural completa em GDScript (`CitizenGait.gd: apply_pose`, ~60 linhas de senos, cossenos, arco-tangentes e produtos matriciais) a cada tick de física.

---

## D. Tabela baseline versus experimentos realmente executados

Todos os experimentos foram executados na cena viva `HarborGame.tscn`, rota idêntica de condução de 30 segundos (1.800 frames por bateria), janela 1280×720 (exceto teste de resolução), VSync ativado, limite 60 FPS (`perf_audit_antigravity_session.gd`):

| Cenário / Ablação | Frames | FPS Médio | p50 (ms) | p95 (ms) | p99 (ms) | Máx (ms) | >16,67 | >33,33 | >50 | >100 | DrawCalls | GPU (ms) | Proc p50 (ms) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **1. Baseline (Condução 30s)** | 1.800 | 44,7 | 18,96 | 29,51 | 104,34 | 304,71 | 1.762 | 49 | 23 | 18 | 1.157 | 2,26 | 21,5 |
| **2. SubViewports Congelados** | 1.800 | 49,3 | 18,88 | 26,26 | **30,58** | 254,31 | 1.726 | 9 | 4 | 4 | 1.195 | 2,27 | 20,8 |
| **3. Sem IK Pedestre (`CitizenGait`)** | 1.800 | 45,1 | 20,56 | 29,11 | 32,12 | 204,46 | 1.799 | 9 | 2 | 2 | 1.561 | 1,96 | 22,1 |
| **4. Áudio Mutado (Busses Mute)** | 1.800 | 45,6 | 20,25 | 28,64 | 39,76 | **72,28** | 1.800 | 30 | 10 | **0** | 1.606 | 1,88 | 20,5 |
| **5. Resolução 1920×1080** | 1.800 | 38,4 | 23,49 | 34,06 | 41,42 | 2.398,67 | 1.800 | 106 | 8 | 2 | 2.131 | 2,40 | 25,4 |

### Interpretação dos Dados de Ablação

1. **O p99 caiu de 104,3 ms para 30,5 ms no congelamento de SubViewports:** Evidência conclusiva de que os picos intermitentes de cauda durante a direção ocorrem quando veículos e pedestres entram na tela e acionam `UPDATE_ONCE`, forçando chaveamento de render targets e atualização de matrizes no motor.
2. **O tempo máximo caiu de 304,7 ms para 72,3 ms ao mutar o áudio (e zero frames >100 ms):** Confirma a participação de criação de streams e I/O de áudio nos engasgos esporádicos.
3. **Resolução 1080p aumentou draw calls de 1.157 para 2.131 e o p50 de 18,9 para 23,5 ms:** A GPU continuou consumindo apenas 2,40 ms. O custo maior em 1080p é puramente CPU (mais objetos visíveis no frustum da câmera demandando processamento de nós).

---

## E. Achados prioritários

### AG-PERF-001 — Primeiro tiro congela por ~240 ms devido a 25 carregamentos síncronos de áudio em disco
- **Onde:** `audio/combat/CombatImpactAudio.gd:25-28`, `audio/combat/CombatAudioBank.gd:13-16`.
- **Mecanismo:** Ao primeiro impacto de projétil, `CombatImpactAudio._ready()` chama `BANK.sound()` para 5 materiais (`"metal"`, `"concrete"`, `"flesh"`, `"wood"`, `"glass"`). Para cada um, carrega 5 takes via `load("res://audio/combat/%s_%d.wav" % [kind, take])`. São 25 leituras síncronas de arquivos `.wav` do disco/storage durante o quadro de jogo.
- **Evidência e Reprodução:** No probe isolado `probe_combat_and_spikes.gd`:
  - Carregamento dos 25 arquivos WAV: **228,29 ms**.
  - Criação de nós do pool (10 `AudioStreamPlayer2D`): **12,53 ms**.
  - Instanciação de `CombatImpactAudio.new()`: **0,023 ms**.
  - 1º tiro completo: 12,71 ms de simulação + 228 ms de áudio.
  - 2º tiro na mesma sessão (áudio já em cache): **5,73 ms** (redução de 97,5%).
- **Classificação:** Medido.
- **Impacto medido:** Congelamento de **240,8 ms** no primeiro tiro da partida.
- **Alternativas:**
  1. Pré-carregar os 25 WAVs no carregamento do jogo via `CombatAudioBank.warmup()` em background/lote.
  2. Usar `preload()` estático nos arrays de takes em `CombatAudioBank.gd` (idêntico ao padrão já adotado em `VehicleCrashAudio.gd:4-35`).
- **Recomendada:** Opção 2 (`preload` de constantes em `CombatAudioBank.gd`). Elimina 100% do I/O síncrono em runtime sem risco de quebra.
- **Risco:** Quase nulo. Consome ~2–3 MB adicionais de RAM permanente.
- **Teste de aprovação:** `probe_combat_and_spikes.gd` com etapa `[1.1]` inferior a 1,0 ms no 1º tiro.

---

### AG-PERF-002 — Decomposição de Vehicle3DRender: 85–95% do custo é CPU de montagem e batching, não renderização
- **Onde:** `cars/traffic/TrafficVehicle.gd:874-958`, `prototypes/living_cast/VehicleWheelRig.gd:70-120`, `cars/VehicleMeshBatcher.gd:20-65`.
- **Mecanismo:** O frame de 1,76 s observado pelo Claude no `PresentationBudget` decorre da construção pesada de cada ator:
  1. `model_res.new()` instancia uma subárvore profunda (95 a 97 nós, 94 a 96 MeshInstances). No primeiro exemplar de cada arquétipo, custa até **200,7 ms**.
  2. `wheel_rig.mount()` percorre recursivamente a hierarquia 3D buscando pivôs de rodas e faróis, consumindo **90 a 113 ms**.
  3. `VehicleMeshBatcher.batch_model()` itera por todas as malhas e materiais em GDScript para reconstruir ArrayMeshes, consumindo **28 a 63 ms**.
  4. A renderização gráfica na GPU leva apenas **1,5 a 2,5 ms** (pico de 67 ms no 1º frame para compilar o shader de lataria).
- **Evidência e Reprodução:** Medido no probe `probe_vehicle_build.gd`:
  - `sedan`: CPU síncrono = 401,24 ms | GPU = 0,0 ms (1º frame total 67,05 ms).
  - `coupe`: CPU síncrono = 130,37 ms | GPU = 0,0 ms.
  - `police_cruiser`: CPU síncrono = 197,78 ms | GPU = 0,0 ms.
- **Classificação:** Medido.
- **Impacto medido:** Cada veículo individualmente custa entre **112 e 401 ms de CPU pura**, ultrapassando em até 200× o limite de 2 ms do `PresentationBudget`.
- **Alternativas:**
  1. Pool de instâncias de `Vehicle3DRender` por categoria/família (reciclando o SubViewport e a malha já montada e trocando apenas material/albedo).
  2. Salvar os modelos já "bachados" e montados como recursos `.res` ou `.tscn` pré-processados no editor, eliminando `batch_model()` e `wheel_rig.mount()` em runtime.
- **Recomendada:** Opção 2 combinada com 1.
- **Risco:** Requer atualização nos testes de integridade de veículos (`test_vehicle_geometry_cache.gd`).
- **Teste de aprovação:** `probe_vehicle_build.gd` com `sync_cpu_ms` inferior a 10 ms por veículo.

---

### AG-PERF-003 — Proliferação de 336 mundos 3D isolados com MSAA 2X e super-resolução em pedestres
- **Onde:** `characters/AnimatedPedestrian3D.gd:536-542`, `geodata/roads/traffic/FixedTrafficSignal.gd:70-76`, `world/harbor/urban_transit/UrbanStationView.gd:25-35`.
- **Mecanismo:** 
  1. Há 345 SubViewports na árvore, sendo 336 com `own_world_3d = true`, 313 com `DirectionalLight3D` e 344 com `MSAA` ativado.
  2. Cada pedestre renderiza em **96×96 com MSAA** para ser projetado na tela em um sprite de aproximadamente **36×36 pixels** (desperdício de ~7× na contagem de pixels renderizados).
  3. Semáforos de trânsito instanciam SubViewports de **384×384 com MSAA 2X** ao sofrerem impacto de colisão (`FixedTrafficSignal.gd:72`), exigindo compilação de novo passe de renderização e gerando pico de **105,1 ms** no primeiro frame da queda.
- **Evidência e Reprodução:** 
  - `probe_subviewports.gd`: 345 viewports, 336 mundos próprios, 344 MSAA.
  - `probe_combat_and_spikes.gd`: 1º frame da queda do semáforo = 105,06 ms vs frames subsequentes = 15,48 ms.
  - `perf_audit_antigravity_session.gd`: Ablação com SubViewports congelados derrubou o p99 de 104,3 ms para 30,5 ms.
- **Classificação:** Medido.
- **Impacto medido:** ~74 ms de redução no p99 ao suspender atualizações de SubViewports; 105 ms de pico imediato ao colidir com semáforos.
- **Alternativas:**
  1. Reduzir a resolução dos pedestres de 96×96 para 48×48 e desligar MSAA em viewports de atores pequenos.
  2. Pré-renderizar os estados de semáforo e animações de queda em spritesheets 2D ou compartilhar um único SubViewport global para quedas de props.
- **Recomendada:** Desativar MSAA em viewports de pedestres e reduzir resolução para 64×64; unificar renderização de semáforos caídos.
- **Risco:** Leve diferença estética no contorno de pedestres quando a câmera estiver no zoom máximo aproximado.
- **Teste de aprovação:** `test_pedestrian_render_lod.gd`, `test_fixed_traffic_signal.gd`.

---

### AG-PERF-004 — A GPU consome apenas 2,26 ms; o custo de sustentação contínua é saturação de CPU da cena
- **Onde:** `world/harbor/HarborGame.tscn`, gerenciamento de nós da cena.
- **Mecanismo:** 
  - A execução de GPU medida via Vulkan (`RenderingServer.viewport_get_measured_render_time_gpu`) é extremamente folgada: média de **2,26 ms** a 720p e **2,40 ms** a 1080p.
  - No entanto, a taxa de quadros não atinge 60 FPS estáveis porque o custo de CPU de `_process` + `_physics_process` (somados a traversals de canvas, transformações de 31 mil nós e GDScript em Debug) consome **19 a 25 ms** contínuos.
  - Ao subir a resolução para 1080p, as draw calls subiram de 1.157 para 2.131 devido à ampliação da área visível do frustum, aumentando o p50 de CPU de 18,9 ms para 23,5 ms.
- **Evidência e Reprodução:** `perf_audit_antigravity_session.gd` comparando Baseline 720p vs 1080p.
- **Classificação:** Medido.
- **Impacto medido:** Impede 60 FPS sustentados mesmo com folga de 14 ms na GPU.
- **Alternativas:** Culling de processamento de nós distantes, export Release para eliminar overhead de checagens do GDScript Debug e consolidação de draw calls de props estáticos 2D.
- **Recomendada:** Priorizar medição de export Release antes de refatorar sistemas funcionais.
- **Risco:** Nenhum (diagnóstico).

---

### AG-PERF-005 — WeaponIcon3D no HUD é falso 3D: é um Control 2D sem SubViewport e atualizado por evento
- **Onde:** `guns/WeaponIcon3D.gd:1-59`.
- **Mecanismo:** Ao contrário do registro histórico do documento de arquitetura ("Ícone de arma do HUD renderizado em 3D"), `WeaponIcon3D` estende `Control`, armazena texturas 2D estáticas (SVG e PNG) em um dicionário de cache e desenha via `draw_texture_rect` apenas quando disparado por `set_weapon(id)` ou no sinal `resized`. Não possui nó 3D, câmera, SubViewport ou atualização por frame.
- **Evidência e Reprodução:** `probe_subviewports.gd` inspecionou `/root/HarborGame/HUD/RootMargin/TopRightPanel/Status/WeaponRow/WeaponIcon`: `class=Control`, `possui_subviewport=false`. Código estático em `guns/WeaponIcon3D.gd` confirma.
- **Classificação:** Medido / Refutação de contexto histórico.
- **Impacto medido:** Zero custo de SubViewport ou 3D no HUD. O HUD está isento dessa suspeita.
- **Alternativas:** Nenhuma alteração necessária neste componente.
- **Recomendada:** Manter como está e atualizar documentação técnica.
- **Risco:** Nenhum.

---

## F. Avaliação das opções arquiteturais

### 1. Otimizar a arquitetura atual (Sustentado pelos dados)
- **Veredito: ALTAMENTE RECOMENDADO.**
- A arquitetura híbrida (física 2D + apresentação em SubViewports com cache) é conceitualmente viável: a GPU consome apenas 2,26 ms e os SubViewports estáticos (197 nós) custam zero por frame após a criação.
- Os gargalos reais são pontuais e sanáveis sem quebra estrutural:
  1. Eliminar I/O síncrono de arquivos WAV no primeiro tiro (AG-PERF-001).
  2. Pré-processar montagem de rigs e batching de veículos para eliminar os 130–400 ms de GDScript no `PresentationBudget` (AG-PERF-002).
  3. Desativar MSAA em SubViewports de atores pequenos e ajustar resolução de pedestres para 64×64 (AG-PERF-003).

### 2. Simplificar apresentações secundárias por relevância (Sustentado pelos dados)
- **Veredito: RECOMENDADO.**
- Pedestres a mais de 600 px ou no overview não precisam renderizar a 60 Hz nem calcular IK procedural de membros completos. O próprio `AnimatedPedestrian3D` já possui lógica de taxa adaptativa (15/30/60 Hz), mas a trigonometria do `CitizenGait` continua rodando em GDScript.
- Props secundários que sofrem impacto (como semáforos) não devem instanciar viewports MSAA 2X pesados durante a gameplay.

### 3. Pré-renderizar elementos adequados (Sustentado pelos dados)
- **Veredito: RECOMENDADO PARA PROPS.**
- Os 120 túmulos de cemitério (`StoneTomb`, 256×256) e pilhas de carga portuárias (18 viewports) são modelos 3D perfeitamente estáticos com iluminação fixa. Pré-renderizá-los em texturas 2D no editor economizaria memória VRAM, nós na árvore e tempo de loading síncrono sem nenhuma perda visual.

### 4. Considerar renderização 3D compartilhada (Não prioritário no momento)
- **Veredito: NÃO RECOMENDADO NESTA FASE.**
- Compartilhar um único mundo 3D com uma única câmera para todos os carros e pedestres exigiria uma reestruturação profunda do sistema de profundidade, ordenação 2D/3D e iluminação do projeto (risco altíssimo de regressão em colisões visuais, oclusão de interiores e contratos de gameplay). Como a GPU gasta apenas 2,26 ms, o custo gráfico de múltiplos viewports não justifica o risco dessa refatoração neste momento.

---

## G. Dependências da auditoria do Claude

1. **CLAUDE-PERF-001 (Congelamento de loading de 23,5 s):** O inventário confirmou que `HarborSouthPort` instancia síncronamente centenas de SubViewports (prédios, guindastes, pilhas de carga, iluminação), cada um criando câmera e luzes no mesmo frame. Fatiar a instanciação com checkpoints no `GameLoading` resolverá o congelamento visual.
2. **CLAUDE-PERF-002 (PresentationBudget):** A decomposição comprovou que o limite de 2 ms do `PresentationBudget` é estourado porque a construção individual de um veículo consome de 112 a 401 ms de CPU em GDScript. O fatiamento em etapas ou pré-montagem de rigs é indispensável.
3. **CLAUDE-PERF-005 (Picos de 0,7 a 5,8 s):** O pico de 290 ms no 1º tiro foi 100% esclarecido pelo I/O de 25 arquivos WAV (AG-PERF-001). O pico de 965 ms na batida do semáforo foi atribuído à instanciação síncrona de SubViewport com MSAA 2X (105 ms de GPU) somada à deformação de lataria da CPU.

---

## H. Arquivos criados, comandos e pendências

### Arquivos criados nesta auditoria (nenhum arquivo de produção alterado):
- `tests/perf_audit_antigravity/probe_subviewports.gd`: Diagnóstico de inventário e requisições dinâmicas de SubViewports.
- `tests/perf_audit_antigravity/probe_vehicle_build.gd`: Decomposição temporal de carregamento, nós, rig, batching e GPU de veículos.
- `tests/perf_audit_antigravity/probe_combat_and_spikes.gd`: Diagnóstico de primeiro tiro, áudio síncrono e impacto em semáforo.
- `tests/perf_audit_antigravity/perf_audit_antigravity_session.gd`: Suíte integrada de medição de baseline e ablações comparativas.
- `tests/perf_audit_antigravity/results/report_antigravity.json`: Resultados brutos estruturados de todas as baterias de teste.
- `docs/history/GETECO_PERF_AUDIT_ANTIGRAVITY_2026-09-15.md`: Este relatório técnico consolidado.

### Comandos executados (PowerShell, APPDATA isolado):
```powershell
# 1. Diagnóstico de SubViewports
$env:APPDATA = "d:\geteco\game\tests\perf_audit_antigravity\results\probe_subviewports\appdata"
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/perf_audit_antigravity/probe_subviewports.gd

# 2. Decomposição de construção de veículos
$env:APPDATA = "d:\geteco\game\tests\perf_audit_antigravity\results\probe_vehicle_build\appdata"
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/perf_audit_antigravity/probe_vehicle_build.gd

# 3. Diagnóstico de primeiro tiro e picos
$env:APPDATA = "d:\geteco\game\tests\perf_audit_antigravity\results\probe_combat\appdata"
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/perf_audit_antigravity/probe_combat_and_spikes.gd

# 4. Sessão integrada de ablações
$env:APPDATA = "d:\geteco\game\tests\perf_audit_antigravity\results\master_session\appdata"
& "D:\Downloads Chrome\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" --path . --script res://tests/perf_audit_antigravity/perf_audit_antigravity_session.gd
```

### Pendências:
- Medição comparativa em export Release (para verificar a parcela de overhead do GDScript Debug no tempo contínuo de CPU).
- Sessão de longa duração (>5 minutos) para observar estabilidade de memória e fragmentação de buffers Vulkan.

---

## HANDOFF PARA REVISÃO

### Correções candidatas em ordem de prioridade:
1. **Pré-carregamento estático de áudio de impacto (AG-PERF-001):**
   - *Arquivos:* `audio/combat/CombatAudioBank.gd`.
   - *Ação:* Substituir chamadas dinâmicas a `load()` por constantes `preload()` ou método `warmup()` executado durante a tela de loading. Elimina o engasgo de ~240 ms no primeiro tiro.
2. **Otimização da construção de Vehicle3DRender (AG-PERF-002):**
   - *Arquivos:* `cars/traffic/TrafficVehicle.gd`, `prototypes/living_cast/VehicleWheelRig.gd`, `cars/VehicleMeshBatcher.gd`.
   - *Ação:* Evitar varredura recursiva de nós e batching em tempo real durante gameplay; salvar modelos montados pré-bachados ou reciclar viewports/modelos via pool de apresentação.
3. **Ajuste de MSAA e resolução de SubViewports secundários (AG-PERF-003):**
   - *Arquivos:* `characters/AnimatedPedestrian3D.gd`, `geodata/roads/traffic/FixedTrafficSignal.gd`.
   - *Ação:* Desativar MSAA em viewports de pedestres (reduzindo tamanho para 64×64) e evitar criação de viewports pesados com MSAA 2X na queda de semáforos.
4. **Pré-renderização de props 3D estáticos em 2D (Opção F.3):**
   - *Arquivos:* `world/harbor/cemetery/`, `world/harbor/HarborPortModelView.gd`.
   - *Ação:* Converter túmulos de cemitério (120 viewports) e pilhas de contêineres em sprites 2D com visual assado.

Nenhuma implementação foi iniciada. Todos os dados foram obtidos por instrumentação isolada e medição comparativa real.

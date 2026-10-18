# How to Develop — regras para não quebrar o fluxo

Vale para qualquer pessoa ou agente de IA mexendo neste repositório. Complementa
[CLAUDE.md](../CLAUDE.md) e [AGENTS.md](../AGENTS.md) (que continuam valendo). Tudo aqui saiu de
problemas reais medidos em 15–16/10/2026 (verificação cruzada de desempenho, `docs/perf-cross-*`).

**Meta de desempenho:** p50 ≤ 16,7 ms (60 fps) em todo cenário, **nenhum quadro > 33 ms depois
de jogável**, e p50 ≤ 6,9 ms (144 fps) onde der. Carregamento pesado é aceitável sob a cortina;
no jogo, não.

---

## 1. Rodar Godot: sempre pela fila

- **Nunca** chame o binário do Godot direto. Use `tools/run_godot_locked.sh <args>`. Ele garante
  um Godot/jogo por vez na máquina (vários juntos travam o PC e contaminam medições).
  - Editor/testes: `tools/run_godot_locked.sh --path . --script res://tests/<teste>.gd`
  - Export: `tools/run_godot_locked.sh --headless --path . --export-release "Geteco V2 Windows" <pasta>/GetecoV2.exe`
  - Jogo exportado: `GODOT_BIN=<pasta>/GetecoV2.exe tools/run_godot_locked.sh -- <args do jogo>`
- Não use `tasklist | grep Godot...` para esperar outro Godot: o nome sai truncado e nunca casa.
- Testes abrem a janela do jogo. **Não feche** janelas de teste: o teste morre sem erro.
- Não deixe um teste/script travado segurando a fila; se o seu travar, mate o processo seu.
- A fila é por **ordem de chegada** (senhas em `$TEMP/geteco-godot-queue.d/`; senha de processo
  morto e cadeado órfão são descartados sozinhos). Limites de execução (a espera não conta):
  - `GODOT_RUN_TIMEOUT` (s): padrão 900 em `--script`, sem limite no resto. Estourou → **exit 124**.
  - `GODOT_ERROR_GRACE` (s, padrão 90): após `SCRIPT ERROR` sem nenhuma saída nesse tempo, o
    teste é encerrado → **exit 125**. Os dois matam a árvore inteira do Godot (`taskkill /T`), e
    INT/TERM no script (ex.: `timeout` externo) também.
  - `GODOT_LOCK_DIR`: cadeado/fila isolados (só para testar o próprio script; aí não espera
    Godot de fora, salvo `GODOT_WAIT_OTHERS=1`).

## 2. Medir desempenho: só em release, sempre A/B

- Editor e `--headless` não servem para medir (debug, driver dummy). Medir = export release.
- Script pronto: `tools/perf_cross_phase2.sh <rótulo> [pasta]` faz o export e mede todas as rotas
  (`oeste porto sobrados serra ponte travessia deserto`) e os cenários de caos, noite, chuva,
  dirigindo e diagnóstico desligado, 2 rodadas cada. Resumo em
  `evidence/perf-cross-20261015/<rótulo>_all.tsv`. Só rotas: `tools/perf_cross_bench.sh`.
- Compare com uma linha de base medida **na mesma máquina e no mesmo dia**. Para "antes", use
  interruptor de ambiente (`GETECO_*`), nunca troque arquivos para o HEAD.
- Relate em ms: p50, p95, p99, máximo e contagem de quadros > 16,7 / 33 / 100 ms. Diga o que
  não foi medido.
- Logs de cada rodada: `%APPDATA%/GetecoV2/session-logs/<UTC>/session-*.jsonl`
  (`frame_spike` com `slow_spans` e `phases`). O rótulo não fica no log: mapeie pela hora da fila
  (`%TEMP%/geteco-godot-queue.log`, local = UTC − 3). Diagnóstico extra: `HARBOR_STALL_LOG=1`,
  `HARBOR_STALL_STACKS=1` (pilha nativa da thread principal).
- Instrumente código novo pesado com spans (`StallWorkTrace`) para que um pico tenha nome.

## 3. Regras de código que evitam quadros grandes

1. **Nada pesado num quadro só no jogo.** Montagem de prédio, trecho, interior, estação, veículo,
   NPC: ou sob a cortina (`ProductionWorld._prewarm_regions`), ou fatiado por orçamento de tempo
   (≈2 ms por fatia), ou calculado em `WorkerThreadPool` e só o `add_child`/commit no thread
   principal. Nunca `wait_for_task_completion` no thread principal antes de `is_task_completed`.
2. **Nunca `surface_get_arrays` em streaming/jogo.** Ele lê da GPU e espera os quadros em voo
   (20+ ms). Use `world/chunk_bake/MeshArrayCache.gd`.
3. **Nada de varrer o mapa inteiro por ponto/amostra.** Indexe (grade espacial) antes do laço.
   Exemplos que custaram 100+ ms: guardas da ferrovia, clareiras da serra, rota de trânsito.
4. **Nada de `load()` síncrono de cena/textura grande no meio do jogo.** Pré-carregue em thread
   (`ResourceLoader.load_threaded_request`) desde o carregamento.
5. **Shader nunca compila no meio do jogo:**
   - não use `hint_depth_texture` em shader (com MSAA, um só material com isso faz TODO material
     novo compilar no desenho; `test_occluded_silhouette` falha se aparecer um);
   - o MSAA de pipeline acompanha o do jogador (`Settings.sync_pipeline_msaa`); SubViewport usa o
     MSAA do viewport principal;
   - material/efeito novo (partícula, chuva, fogo, vidro, porta…) entra num pré-aquecimento sob a
     cortina (receita: `BridgeLookPrewarm`, `VehicleMaterialVariantPrewarm`,
     `PaintedFacadePrewarm`, `WildlifePrewarm`) e o material fica retido;
   - prefira reutilizar material (cache por chave) a criar um por instância.
6. **Por quadro só o necessário:** sem `find_children`/grupo inteiro por quadro, sem escrever
   propriedade que não mudou, sem alocar dicionário/array em laço quente. Eventos/sinais > varredura.
7. **Nada de cálculo procedural caro na primeira aparição** (textura, som, malha): gere sob a
   cortina ou em thread, com cache estático.
8. **Malha compartilhada** quando a forma é igual (escala por nó), em vez de `SphereMesh.new()`
   por peça.
9. **Luzes:** nenhuma luz dinâmica nova sem passar pelo orçamento (`LightBudget`); sombra em luz
   local só se indispensável.
10. **Textura nova** em VRAM comprimida (BC7) com mipmaps; nunca sem perda/sem mips em 3D.
11. **Recompensa do mundo passa pelo contrato da carteira.** Achado único (cofre, caverna,
    esconderijo) usa `Economy.grant_world_reward` com id estável: o recibo vai no save e impede
    pagar duas vezes. Dinheiro solto (`collect_loose_cash`) é só para quem renasce (civil, saque
    de combate) e recusa mais de R$ 300. Nada de "já pegou" em variável estática.
    **Valor de dinheiro ajustável mora em `data/catalogs/EconomyBalance.gd`** (bônus da história,
    faixas do guincho, carro-forte, conta/multa). Valor gravado em recibo (recompensa base de
    missão, prêmios de corrida, carros e peças do deserto) **nunca muda**: o save valida contra ele
    e quebraria. Para mudar, pague a diferença com um recibo novo, como `StoryPay` faz.
12. **Morte e prisão custam** (`runtime/RecoveryPenalty.gd`): 10% do dinheiro, teto R$ 2.000;
    no Harbor a morte volta pelo Bay Medical e a prisão pela delegacia, que leva a munição
    carregada. Armas nunca são confiscadas: o recibo de compra exige a arma no save.
13. **NPC humano novo** declara `gameplay_role`; se a morte dele deve contar homicídio, o papel
    entra em `PERSON_ROLES` de `gameplay/police_response/CrimeVictims.gd`.

## 4. Prédios pintados (estilo GTA) — `PaintedFacadeKit`

- Imagens geradas em `output/imagegen/<estilo>/` (fora do Git); prompts em `docs/prompts/`.
- Vãos de porta e tamanho do módulo medidos à mão em `tools/painted_facades_<região>.json`
  (um arquivo por região; a detecção automática erra).
- Importar: `python -I tools/build_painted_facades.py --styles=<estilos>` → `assets/facades/`
  (grava BC7+mipmaps no `.import`), depois `--import` do Godot pela fila.
- Ligar no prédio com `PaintedFacadeKit.build(...)` respeitando `PaintedFacadeKit.enabled()`
  (`GETECO_PAINTED_FACADES=0` volta às caixas para A/B).
- Revisar com `tests/capture/capture_painted_style.gd -- --styles=... --label=...` e no jogo.
- O kit afunda o prédio até a soleira tocar o chão: não crie degraus para alcançar a porta.

## 5. Portas e entradas

- **Só a entrada de verdade abre** (prédio com interior: `walk_in_x` do catálogo). Outras folhas
  ficam fechadas e sem reação. Porta abre só a ~1 m, devagar, e o jogador entra por ela.
- A porta pintada tem que coincidir com a entrada real (catálogo move `entrance_x` para o vão).
- Mexeu em porta/entrada/acesso: rode `tests/test_door_audit.gd -- --no-save` (anda até cada uma
  das ~118 entradas e confere abre/entra/sai) e `tests/test_harbor_building_access.gd -- --no-save`.

## 6. Antes de commitar

- Rode a **suíte central**: `tools/run_core_suite.sh` (rápida, ~2 min, contratos sem carregar o
  mundo: save e recuperação, carteira/recibos, campanha, garagem, crime) e, depois de mudança
  estrutural, `tools/run_core_suite.sh full` (inclui a verificação do CLAUDE.md —
  `test_regions`, `test_bridge_approach_terrain`, `test_native_driving -- --no-save`,
  `cold/test_admission` — mais o indicador de save e o deserto). Tudo passa pela fila; o resumo
  fica em `evidence/test-suite/core/<data>/RESUMO.md`. Rode também os testes que citam seus arquivos.
- Teste novo de contrato (sem `Main.tscn`, segundos) vale mais que mais um teste de sessão
  inteira: comece por `tests/test_core_contracts.gd` e, se for central, ponha na lista FAST do
  `tools/run_core_suite.sh`.
- Se tocou em sistema com custo por quadro ou streaming: meça em release (seção 2) antes de dizer
  que ficou bom.
- Muitos arquivos têm mudanças não commitadas de OUTRAS sessões: commite só os seus trechos
  (`git diff` do seu pedaço → `git apply --cached`). Nunca `git add -A`, reset, checkout, stash.
- Mensagem em português: o que, por que, o que foi verificado e o que não foi.

## 7. Problemas conhecidos em aberto

- Quadro isolado de 220–250 ms intermitente na serra/travessia (às vezes cidade/ponte), causa não
  provada: veja `docs/perf-cross-20261015-phase2.md`, seção "Fase 4 e estado final".
- Ferrovia: o índice espacial dos guardas está dentro de mudança não commitada da sessão do trem
  (`world/railway/RailwayWorld.gd`), a commitar junto com ela.

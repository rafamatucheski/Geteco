# Caos e performance — handoff do Claude (29/09/2026)

**Estado: causa do custo integrado NÃO demonstrada.** Os dados existentes a restringem ao
*conjunto de resposta policial* (ver "O que os dados dizem"), mas não distinguem viaturas,
equipes a pé, aeronave/K9, tanque ou barreiras. Por isso entrego primeiro o instrumento e a
medição que decidem (parte 1) e uma correção de ciclo de vida demonstrada por leitura e por
evidência (parte 2), **sem** declarar que ela explica os FPS. Nada foi executado: não iniciei
Godot, editor, testes nem benchmarks. Nenhum arquivo do runtime compartilhado foi alterado;
trabalhei em cópias fora do projeto e só conferi os patches com `git apply --check`.

## Arquivos desta pasta

| Arquivo | Conteúdo |
|---|---|
| `changes.patch` | partes 1 + 2 (aplicar **só este**, ou as partes em ordem) |
| `part1-instrumentation.patch` | `DispatchTrace.gd` (novo, desligado por padrão), ganchos em despacho/piloto/barreiras/diretor aéreo, `tests/dispatch/measure_chaos_attribution.gd` (novo) |
| `part2-lifecycle-fix.patch` | `DispatchUnit._service_working` + verificação em `test_dispatch_emergency.gd`; independe da parte 1 |
| `base-hashes.json` | SHA-256 dos arquivos-base (bytes em disco) e dos patches |
| `analyze_trace.py` | resume o rastro (`dispatch.summary` por segundo + trechos lentos) de um `report.json` |

Base: HEAD `622ea48`; os 6 arquivos-base não têm alteração local. Todos os arquivos de
`gameplay/dispatch|police_response|emergency` têm hash **idêntico** ao de `recovery/source-before.json`
(a medição do guardião os viu assim). **Já `scripts/Vehicle.gd` e `scripts/Actor.gd` mudaram
desde essa medição** (são os únicos entre os 687 monitorados): a linha de base do caos precisa ser
refeita antes de comparar com 22 FPS / p99 215,8 ms.
Os arquivos têm fim de linha misto (CRLF/LF; o índice guarda LF): os patches são LF e aplicam
com `git apply` (autocrlf=true), verificado num repositório descartável com os mesmos bytes e
com `git apply --check` no projeto real.

## O que os dados dizem (recovery/report.json)

**Fatos**

1. `physics_ms` e `cpu_ms` do guardião são o **máximo do último segundo**, não custo por
   quadro: cada valor fica constante por ~1 s (ex.: 79,8 ms por ~1 s; 1350,9 ms por ~1 s), o que
   bate com os monitores `TIME_PHYSICS_PROCESS`/`TIME_PROCESS` do motor. As médias dessas
   séries no relatório não são "custo médio de física" e não devem ser citadas como tal.
2. Contraste controlado, sem tiros do jogador (fase `cessation-observation`): com **6 estrelas e
   9–11 unidades** vivas o jogo roda a **12–28 FPS** (segundos 0–6); assim que o resgate chama
   `dismiss_all` e as unidades caem a 0, volta a **58–60 FPS em ~1–2 s** com fogo e incidente
   ainda ativos. O resgate reposiciona o jogador só ~10 m (mesma região, 40 pedestres, ~45 carros) e remove
   ~2 000 nós: o custo sai junto com a resposta policial (viaturas, equipes, aeronave/K9, barreiras
   e a procura), não com o tiroteio, a população, o clima ou o fogo. Não separa qual parte dela.
3. Na fase de carga, 20,8–26,5 s (6–8 unidades): 38 quadros em 5,8 s (6,5 FPS), quadros de 100–280 ms
   com máximo de tick de física de 31–127 ms por segundo e máximo de processo de 10–31 ms. Quadro maior que a
   soma dos dois indica **vários ticks de física por quadro** (espiral do passo fixo: cada tick
   custa mais que os 16,7 ms que ele simula). É inferência do padrão, não medida direta.
4. Antes disso (4–15 s, 1–3 unidades) o jogo já estava a ~38 FPS, enquanto 1–2 unidades de serviço
   *depois* do resgate não degradam (60 FPS): há uma segunda parcela, do cenário de carga
   (tiros/explosões/multidão/estrelas), que este patch não isola.
5. Picos únicos: ~750 ms de física em 3–4 s (coincide com o **primeiro** despacho policial,
   unidades 0→1) e ~1,35 s de tick em ≈27–28,4 s (8 unidades já existiam desde 24,7 s). Os dados
   não têm evento com carimbo de tempo que explique o segundo pico (o contador `police` é só o
   legado; equipes do despacho não aparecem nele). Coincidência de tempo, não atribuição.
6. Os 64 eventos guardados ao fim da carga são **32 `incident_invalid actor_removed fire#1`
   consecutivos** (defeito de ciclo de vida, abaixo).
7. Linha do tempo do README do despacho: medição de 22/09 a 4 estrelas/população 24 não mostrou
   espiral (p99 ≈ 19–26 ms, máx. ≤ 47 ms). A carga atual (6 estrelas, 8–11 unidades, população 40,
   fogo e explosões) e o código de veículos (portas, motorista, áudio de rodagem) são outros; não é
   comparação de regressão.

**Defeito demonstrado (parte 2)** — `DispatchUnit._service_working`: quando a fonte da ocorrência
some (fogo extinto ou corpo removido, o caminho *normal* de bombeiro/legista) com a equipe ainda a
pé, `_begin_departure()` mantém o estado `working` (a equipe volta andando) e a função repetia,
**a cada tick de física**, o evento `incident_invalid`, `_release_incident()` e `crew.age = 0`.
Efeitos: (a) o registro de 64 eventos é enxurrado; (b) o prazo de 120 s do `Responder` nunca vence;
(c) `crew_lost` e o prazo de 300 s ficam inalcançáveis: equipe morta ou presa mantém a unidade
viva, a vaga de `MAX_CREWS`/`MAX_UNITS` e o veículo até `dismiss_all`. **Não** é causa demonstrada dos
FPS (cada evento custa microssegundos e ninguém em produção escuta `dispatch_event`).

## Hipóteses (nenhuma medida) e o que a decide

| # | Hipótese | Base no código | Rótulo do rastro que a confirma |
|---|---|---|---|
| H1 | Construção síncrona de célula por viatura | `_prepare_unit_ground` chama `NativeRegion.prepare_collision_at` (posição e 12 m à frente) por célula de 64 m; `_ensure_chunk` roda `_run_build_job(..., INF)`; o código do streaming registra 8–219 ms por célula | `prepare_ground.build` ≥ 20 ms com `chunks_built`/`jobs_finished` > 0 |
| H2 | Varredura do grafo em GDScript nos despachos | `router.spawn_candidates` percorre todas as arestas e ordena, a cada tentativa de polícia (2–4 s até o teto), de serviço e de barreira (18 s); `plan` = 2–3 varreduras de arestas + Dijkstra completo, e `is_blocked` monta uma `String` por aresta mesmo sem bloqueios | `police.candidates`, `service.candidates`, `roadblock.try_place`, `police.plan` |
| H3 | Primeira criação de cada modelo (frio) | `vehicle.add_child`/equipamento por arquétipo, `officer.spawn` por patamar, `responder.spawn` | `vehicle.add_child:<arq>`, `officer.spawn:tierN` no 1º uso |
| H4 | Custo por viatura por tick fora do meu escopo | viaturas de despacho não são `traffic`: **nunca "dormem"** (só o tráfego pula `move_and_slide` parado, `Vehicle.gd:244`), mesmo estacionadas; mais `StreetPhysics` e `effects.physics_tick` | variante `dispatch_vehicles` da atribuição alta e `controller.tick` baixo |
| H5 | Equipe a pé/K9/helicóptero | `PoliceAgent`/K9/`Responder` fazem `find_path` (2–4,7 ms; 14 registros ≥ 2 ms em 35 s nos dados) a cada 1,2–1,5 s cada | variantes `police_on_foot`, `air_and_k9`; `air.*`, `officer.spawn` |
| H6 | Fora do meu escopo | pedestres em pânico, projéteis, tanque (`TankCannon`), explosões, luzes | variantes `pedestrians`, `ambient_traffic` e resíduo `physics_process_max_ms` − trechos |

## Parte 1: instrumentação (desligada por padrão)

- Só liga com o meta `benchmark_trace` do mundo (o guardião já o liga em `survey.gd`). Desligada,
  cada gancho é uma chamada que lê uma variável estática. Sem rótulo por entidade: conjunto
  fechado (serviço, estado, arquétipo). Escreve em `world.perf_costs` (mesmo formato, teto 512;
  trechos avulsos ≥ 2 ms param em 384 para reservar lugar aos resumos).
- `dispatch.summary` por segundo: contagem/soma/máximo por rótulo, censo de unidades por
  serviço/estado (`:suspended`), `physics_ticks`, `physics_process_max_ms` e contadores de física 3D
  (objetos ativos, pares de colisão, ilhas). Trechos aninhados se sobrepõem.
- `tests/dispatch/measure_chaos_attribution.gd`: reproduz a carga do guardião, espera ≥ 6 unidades e mede
  janelas de 4 s com **um grupo por vez** com `set_physics_process(false)` (controlador, viaturas,
  equipe a pé, equipe de emergência/fogo, aeronave/K9, tráfego ambiente, pedestres), restaurado
  em seguida, entre duas janelas de base. Métrica: custo **por tick** (sentinela de prioridade mínima até
  `process_frame`, dividido pelos ticks do quadro) e frames. É diagnóstico reversível: **não** aprova
  nada e não prova que remover o grupo seja aceitável.

## Comandos para o Codex (um Godot por vez, sozinho na máquina)

```powershell
git status --short -- gameplay/dispatch gameplay/police_response tests/dispatch   # esperado: vazio
Get-FileHash gameplay/dispatch/DispatchUnit.gd   # comparar com base-hashes.json (e os demais)
git apply --check evidence/claude-caos-20260929/changes.patch
git apply evidence/claude-caos-20260929/changes.patch
& $GODOT --path . --import          # scripts novos
```

1. **Funcional** (`.\tests\dispatch\Run.ps1 -Suite all`, depois `-Suite integration`). Esperado:
   `DISPATCH_EMERGENCY groups=4/4 ... failures=0` com **+3 verificações** (uma por serviço) e as
   demais suítes como antes. A verificação nova falha no código original (dezenas de avisos) e passa
   com a parte 2 (≤ 1 por unidade). A regra permanente da garagem/Maciota não é tocada:
   `test_garage_rewards`, `test_garage_driver_restore`, `test_garage_vehicle_transfer` não precisam rodar.
2. **Rastro no stress do guardião** (mesma harness): copie `evidence/guardiao-20260929/Run.ps1`
   trocando `$auditRoot` para `evidence/claude-caos-20260929/runs` (o original grava dentro da
   evidência histórica), e rode
   `.\Run.ps1 -Label claude-trace -Script res://evidence/guardiao-20260929/recovery.gd -Extra '--mode=recovery' -TimeoutSeconds 300`,
   depois `python evidence/claude-caos-20260929/analyze_trace.py <pasta>/recovery.../report.json --phase controlled-chaos`.
3. **Atribuição**: `.\Run.ps1 -Label claude-atrib -Script res://tests/dispatch/measure_chaos_attribution.gd -Extra '--seconds=4' -TimeoutSeconds 360`;
   saída em `tests/dispatch/results/claude-atrib.json`
   (`python analyze_trace.py` também lê `dispatch_costs`). Compare `baseline_before`/`baseline_after`
   (deriva) com cada variante: `physics_tick_ms.mean/p95` e `frame_ms`.
4. Se possível, refazer o stress **com a parte 1 desligada** (sem `--benchmark`/meta): confere que o
   instrumento não muda o resultado.

**Como ler**: `controller.tick`÷ticks é o custo dos scripts do despacho por tick; se for pequeno
(< 2 ms) e a variante `dispatch_vehicles` ou `police_on_foot` liberar a maior parte do tick, o custo
está em `Vehicle.gd`/`StreetPhysics`/`PoliceAgent` (frente do Codex). `prepare_ground.build` com
`chunks_built > 0` em ticks lentos aponta H1: a proposta seria pré-admitir as células ao longo da rota
com orçamento (ou segurar a viatura freando até a célula estar pronta), em `world/regions`. Trechos
`*.candidates` ≥ 10 ms apontam H2: índice espacial de arestas por região, invalidado em
`refresh_roads()`/`configure`. `vehicle.add_child:<arq>` alto só no 1º uso aponta H3: pré-aquecer
os modelos no carregamento, como o diretor aéreo já faz com o helicóptero. Nenhuma dessas correções
foi escrita: falta a medição que escolhe entre elas.

## Contratos preservados e riscos

- Nenhum limite, contagem, intervalo, prazo, população ou dificuldade mudou. Ownership único
  (`claim_dispatch`) e `finish` idempotente intactos. Maciota/mecânico e a garagem sem armas não são tocados.
- Parte 2 muda comportamento **só** no caminho "fonte perdida com equipe a pé": o aviso sai 1 vez;
  `crew.age` reinicia 1 vez (não a cada tick); equipe morta/presa agora chega a `crew_lost` e ao prazo
  de 300 s (antes, nunca), o que libera a unidade e o veículo mais cedo nesses casos. Identifique
  isso no resultado, não o esconda.
- Parte 1: gancho por unidade e por tick só faz chamada barata quando desligada; ligada, o próprio
  `Time.get_ticks_usec` custa ~µs por gancho: use o rastro para atribuição, não para FPS final.
- Não testado: `measure_chaos_attribution.gd` e `DispatchTrace.gd` nunca foram carregados
  (sem Godot); revisão estática apenas. Se houver erro de parse, é do script, não do jogo.

## NÃO executado

Godot, `--import`, qualquer suíte (`tests/dispatch`, regiões, ponte, condução, admissão), medição
renderizada, passagem no jogo normal e teste do caminho "equipe morta após perda da fonte" (a
parte 2 o torna alcançável, mas não há teste dele). Nenhum resultado de FPS foi obtido. Pendente
fora do meu escopo, para o Codex: separar em `Vehicle.gd`/`StreetPhysics` o custo por viatura sem
dormência; `NativeRegion.prepare_collision_at` síncrono; a parcela de 4–15 s do fixture; ciclos
repetidos de caos/resgate (memória: +32 MiB no pico, −11 MiB depois, um ciclo não prova vazamento).

# Quadro de 472 ms no primeiro `dispatch.service.plan` (05/10/2026)

Investigação do máximo de `sdl-bt-off-02` (ver `sdl-input-stalls-20261005.md`, seção 2):
f2124, +9,995 s após READY, quadro de 472,381 ms, dos quais 462,951 ms dentro de
`dispatch.service.plan`, no primeiro callback físico em que `router_native` passa a `true`.

**Resultado:** a causa do pico continua **inconclusiva**, mas a hipótese de custo
determinístico de primeira chamada (JIT, montagem do espelho C#, carga do script ou tamanho
do grafo) foi **descartada** para essa captura. Nenhuma alteração de jogo foi feita: preparar
o roteador sob a cortina não removeria esse pico. Há um custo latente menor (JIT a frio, cerca
de 23 ms) que fica registrado como pendência.

## Caminho do código

`DispatchController._service_tick` → `dispatch_service_to` → para cada candidato,
`router.plan(start, point, heading)` (span `service.plan`, `DispatchController.gd`) →
`DispatchRoadRouter.plan` → `_start_edge`/`nearest_edge` → `_native_graph()`. Na primeira chamada,
`_rebuild_native()` faz `load(RoadGraphSearch.cs)` e `new()`, percorre as arestas em GDScript e chama
`Build`. Depois vêm `NearestEdge`, `Plan` (Dijkstra) e `BuildPath` em `RoadGraphSearch.cs`.
O roteador do despacho é uma instância própria e não reaproveita a do terminal. O JIT, porém,
vale para o processo inteiro: a rota do terminal preparada sob a cortina já executa os mesmos
métodos C#.

Código idêntico entre o projeto congelado `stall1709-project` e o `main` atual (`diff` em
`DispatchRoadRouter.gd`, `RoadGraphSearch.cs`, `DispatchController.gd`, `TerminalRoutes.gd` e
`TerminalOperations.gd`).

## O que a captura mostra

- **JIT já feito no loading:** no frame 486 da mesma captura, `terminal.street.router_plan`
  aparece com `native_active=true`. O 1º plano levou 23,539 ms; os seguintes, 0,479 e 0,402 ms.
  Quando o despacho rodou, os métodos C# já estavam compilados e o `.cs` estava em cache.
- **Grafo pequeno:** o grafo do despacho tem 237 vértices e 237 listas de arestas, o mesmo
  tamanho medido na sonda. O tamanho do problema não explica centenas de ms.
- **Quase tudo foi espera, não CPU:** pelo `ThreadCpuProbe`, a thread principal executou
  34,03 M ciclos em todo o quadro de 472 ms. Na mesma execução, a mediana é de 2.676 ciclos/µs,
  o que dá **cerca de 12,7 ms de CPU**. O callback físico (467,2 ms de parede) usou 20,57 M ciclos,
  cerca de 7,7 ms. O `GetThreadTimes` não avançou nenhum quantum de 15,6 ms. Os outros quadros
  longos da captura rodam a 700–2.800 ciclos/µs; f2124 ficou em 72. JIT e montagem do grafo
  gastam CPU na thread que chama, então não produzem esse padrão.
- **Processo inteiro ocioso:** pelo coletor externo, a janela de 500 ms que contém o pico teve
  140,6 ms de CPU no Godot inteiro. As janelas vizinhas tiveram 400–900 ms. Antes do pico, o
  `ccusage` consumia 2,6–3,5 s de CPU por janela de 0,5 s e caiu para cerca de 0,3 s logo antes.
  É só uma correlação temporal, sem prova de causa. O coletor não vê processos com acesso
  negado (171 deles, incluindo prováveis serviços do sistema).
- **Assinatura parecida com a pausa de 1,7 s:** a pausa histórica de 1,7 s
  (`stall-1709-investigation-20261005.md`) também não teve avanço de CPU, mas ocorreu em outro
  ponto (entre o callback físico e o `process_frame`). Não agrupo as duas sem evidência. Fica
  registrado que esperas longas sem CPU aparecem em pontos diferentes do quadro.

## Comparação com as outras capturas

Varri 64 JSONs em `evidence/intermittent-stalls-20261004/` e `evidence/stalls-1709-20261005/`
procurando o primeiro intervalo retido com `router_native=true` e o pior quadro nos 12 quadros
anteriores. Em todas as outras capturas com C# ativo, esse pior quadro ficou entre
**7,1 e 17,9 ms**; há uma exceção de 32,5 ms em `startup-box-a2`, sem span de despacho.
Nas capturas com spans antigos do roteador, `router.native.script_load` mediu 1,7–2,3 ms e
`router.native.rebuild` 2,5–3,5 ms. Só `sdl-bt-off-02` tem `dispatch.service.plan` ≥ 1 ms.
Isso inclui rec2 (f2749: 9,8 ms) e rec3 (f2339: 8,9 ms). Script de varredura:
`evidence/dispatch-plan-stall-20261005/scan_first_native.py`, só no disco local: `.py` em
`evidence/` não é versionado.

## Reprodução dirigida

Arquivo: `tests/measure/probe_first_dispatch_plan.gd`. Usa a cena real `Main.tscn` renderizada,
1920×1080, `--no-save`, sem arrival, e espera 600 quadros após `ready_for_play`. Antes da medição,
`dotnet build Harbor.csproj` terminou com 0 erros, e o C# esteve ativo em todas as rodadas:
`router_native` passou a `true` e os planos rodaram pelo espelho nativo. A sonda escolhe até
8 candidatos de nascimento fora da vista, como o serviço faz. Ciclos medidos com
`ThreadCpuProbe`. Saídas em `evidence/dispatch-plan-stall-20261005/`.

| Rodada | 1º plano (inclui montar o espelho) | Planos 2–8 |
|---|---:|---:|
| whole-01 | 1,382 ms | 0,459–0,574 ms |
| whole-02 | 1,222 ms | 0,317–0,551 ms |
| split-01 | load 0,014 + `_native_graph` 0,650 + plano 0,410 ms | 0,325–0,537 ms |

Pior quadro nos 120 quadros seguintes: 10,9 / 10,1 / 7,1 ms. Todos os 24 planos deram `ok`.
Na sonda os planos rodam no `process_frame` do script de teste, não dentro do callback físico.
O pico de 472 ms **não reproduziu** nas três rodadas.

**JIT a frio isolado (`--mode=cold_class`):** processo novo, mesma janela, sem o mundo, sem
nenhum método de `RoadGraphSearch` executado antes. Grade sintética de 144 vértices. Duas
rodadas:

| Etapa | 1ª chamada (frio) | Instância nova (quente) |
|---|---:|---:|
| load do `.cs` | 3,30 / 3,30 ms | 0,016 ms |
| `new()` | 0,87 / 0,91 ms | 0,07 ms |
| `Build` | 6,54 / 5,76 ms | 0,19 ms |
| `NearestEdge` | 4,21 / 3,88 ms | 0,03 ms |
| `Plan` | 4,47 / 4,34 ms | 0,04–0,10 ms |
| `BuildPath` | 3,65 / 3,51 ms | 0,24–0,25 ms |
| **soma** | **≈ 23,0 / 21,7 ms** | **≈ 0,6 ms** |

A soma a frio bate com os 23,5 ms do primeiro plano do terminal na captura. Esse é o custo real
de inicialização e JIT, e ele é **CPU**: os ciclos ficam na faixa de 2.700–3.000 ciclos/µs. O
pico de 462 ms não é CPU, então são dois fenômenos diferentes.

## Por que não há correção no jogo

- No cenário da captura (`--no-save`, início perto do terminal), a rota do terminal já paga o
  JIT sob a cortina. O primeiro plano do despacho custa 1,2–1,4 ms. Uma preparação a mais não
  mudaria esse caso, e o pico de 462 ms não reproduziu.
- **Pendência real (custo latente, não medido no jogo):** `TerminalOperations.prepare_startup_route`
  só roda com o jogador a menos de 100 m do terminal no porto. Num save que começa em outro
  lugar, o primeiro uso nativo de qualquer `DispatchRoadRouter` paga cerca de 22–23 ms de JIT
  durante o gameplay. Esse uso pode ser o despacho, o terminal ou PortHaul. Para corrigir,
  é preciso uma chamada sob a cortina em `ProductionWorld.gd`, ao lado de `prepare_startup_route`.
  A chamada seria uma rota pura do roteador, sem RNG, sem atores e sem mutação além do cache do
  espelho. Essa edição não foi feita: o arquivo está modificado por outra sessão. A/B por
  toggle e equivalência de plano ficam para quando o hook for possível.

## O que não foi medido

- A causa da espera de cerca de 450 ms: falta trace de agendador (WPR) nesse instante. Não
  separa Waiting de Ready, nem I/O, page fault, lock, suspensão de GC ou carga externa.
- Não houve tentativa de reproduzir a coincidência com o `ccusage` em carga, nem de rodar com
  memória sob pressão.
- O custo de JIT foi medido isolado, não num save real longe do terminal.
- Sem métricas de FPS e percentis nesta investigação: as rodadas são sondas dirigidas de um
  evento, não benchmark.

## Verificação

Nenhum arquivo de jogo foi alterado. Os únicos arquivos novos são a sonda de teste e este
relatório. Mesmo assim, rodei a verificação mínima do CLAUDE.md com o lock adquirido e com
`dotnet build` sem erros:

- `test_regions`: PASS.
- `test_native_driving -- --no-save`: PASS.
- `cold/test_admission`: 11 checks, 0 falhas.
- `dispatch/test_road_graph_native` (equivalência C# × GDScript): passou.
- `test_bridge_approach_terrain`: **FAIL (3)**, todas em `_check_mountain_hill` ("mountain east
  of tunnel": colina com altura `-inf`, sem malha nem colisor de terreno no ponto). Isso não
  tem relação com despacho nem com roteamento, e nenhum código foi alterado aqui. Não investiguei
  se a falha já existia em `HEAD` ou se vem das alterações locais de outra sessão.
  Logs em `evidence/dispatch-plan-stall-20261005/verify-*.log`.

O jogo não foi aberto via `Jogar.cmd`: a sonda carrega `Main.tscn` renderizada até
`ready_for_play` e roda 720 quadros de gameplay, mas não houve teste interativo.

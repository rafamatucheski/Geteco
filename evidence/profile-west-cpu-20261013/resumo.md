# CPU no oeste do porto — 2026-10-13

**Veículos e atores lideram o custo dos scripts medidos.** Os quadros lentos também acumulam vários passos físicos: a primeira baseline teve 148 quadros no teto de 8 passos, contra 1 na segunda. A decomposição ainda deixa trabalho sem dono dentro dos callbacks e antes de process. A variação das baselines impede atribuir ganho causal a qualquer interruptor desta bateria.

Foram executadas **16 rodadas renderizadas, em série**: 14 sem erros detectados de execução/probes, com 26.936 quadros e 697,74 s medidos; esse total não significa equivalência causal, pois algumas rodadas tiveram foco diferente. As 2 rodadas com erro foram preservadas e excluídas dos comparativos. Nenhuma otimização foi feita. Os spans temporários dos 14 arquivos foram removidos; conteúdo original conferido, 11 arquivos iguais byte a byte e 3 com fim de linha canônico do repositório e texto original (`StreetPhysics.gd`, `DispatchRoadRouter.gd`, `WorldAudio.gd`). Os diffs de produção estão vazios e o estado final limpo; produção não foi commitada.

## Cenário e método

Godot **4.7.2 .NET**, build `editor`, renderer `mobile`, resolução `3440×1440`, i7-13650HX / RTX 4060 Laptop, VSync 0, FPS sem limite, física a 60 Hz e teto de 8 passos/quadro. Mesmo circuito de 283,574 m a 12 m/s, uma volta de aquecimento e duas medidas, mínimo de 30 s; meio-dia, céu limpo, `--no-save --benchmark --no-dispatch --play-at=harbor,64,82`. Os 1058 hashes de fontes/binário conferem em todas as rodadas: digest `31bf304e9ef9838f4994fc9b9bad615c36680c76a2c6f7c1bbaaa8eda6742d1e`.

O carro-alvo e Dante têm a física desativada e seguem posições do circuito, como no benchmark original. Os demais atores/veículos e sistemas do mundo continuam. **Direção manual real, perseguição, noite, chuva e outros mapas não foram avaliados.** Os benchmarks anteriores do usuário permanecem separados em `evidence/benchmark-west/` e não entraram nas comparações abaixo.

Probes delimitam callbacks físicos/process por prioridade, sentinel `call_deferred` e `frame_pre_draw/post_draw`. A física é contabilizada por passo e por quadro. Percentis usam todos os quadros de medição, incluindo zeros; aquecimento fica fora. Não usamos médias de `TIME_PROCESS/TIME_PHYSICS_PROCESS`, que são monitores de outra janela. GPU/CPU de viewport são últimas amostras assíncronas, sem atribuição exata a picos.

## Ranking dos sistemas nas duas baselines

Ordenação pela média de cada rodada com peso igual; não agrupamos frames, o que favoreceria a rodada mais rápida. Intervalos p50/p95 mostram os resultados independentes das duas baselines. Tudo é **ms/quadro**, inclusivo; pais/filhos e percentis não se somam.

| Sistema | Média base_1 / base_2 | Intervalo p50 | Intervalo p95 |
|---|---:|---:|---:|
| Veículos — `vehicle.physics` | 14.832 / 4.707 | 3.264–7.636 | 11.722–56.036 |
| Atores — `actor.physics` | 5.975 / 2.193 | 1.527–3.340 | 5.424–21.222 |
| Perfil de sessão — `west.telemetry.profile_process` | 1.646 / .608 | .186–1.609 | 2.149–4.567 |
| Timer de marcas de pneus — `vehicle_tires.redraw_marks` | 1.026 / .526 | .389–.696 | 1.331–2.786 |
| Produção/streaming — `west.world.process` | .837 / .479 | .292–.415 | 1.155–3.108 |
| Gameplay — `gameplay.physics` | .944 / .332 | .214–.531 | .751–3.151 |
| Ônibus urbanos — `urban.physics` | .801 / .354 | .220–.590 | .934–2.079 |
| Terminal — `terminal.physics` | .737 / .279 | .184–.410 | .661–2.551 |
| Reflexos, contador já existente — `reflection.process` | .553 / .388 | .021–.026 | 2.252–3.219 |
| Logger C# — contador cumulativo do corpo de callback | .482 / .186 | não coletado | não coletado |
| Áudio de veículos próximos | .221 / .148 | .109–.127 | .311–.524 |
| Câmera | .180 / .152 | .142–.169 | .221–.275 |
| Callback de física de rua | .152 / .054 | .007–.016 | .393–.704 |
| Áudio do mundo | .110 / .075 | .054–.063 | .201–.277 |
| TrafficYield | .082 / .030 | .020–.045 | .064–.285 |
| Estacionamento, controlador | .038 / .014 | .009–.021 | .033–.127 |
| Áudio de clima | .016 / .014 | .013–.015 | .017–.024 |
| Callback da região | .010 / .007 | .006–.007 | .008–.012 |

Detalhes de `vehicle.physics`: `vehicle.drive` p50 1.017–2.069/p95 3.304–14.789; `vehicle.street_pre` .526–1.440/2.036–11.310; `vehicle.effects` .528–1.308/1.932–9.749; `move_and_slide` .304–.808/1.168–5.929 ms. Nos atores, `move_and_slide` .587–1.333/2.062–7.879 e degraus .438–.974/1.523–6.210 ms. Esses custos já estão nos pais. `vehicle.effects.tires` é filho de `vehicle.effects`; o Timer de redraw é separado e não se divide por passos físicos.

O router C# esteve ativo, confirmado no aquecimento (`native=true planned=true`). Durante cada baseline houve 2 chamadas instrumentadas de Build, 12 de NearestEdge, 6 de Plan e 6 de BuildPath; p50/p95 por quadro são zero pela baixa frequência. Médias por quadro: Build .000217–.000543 ms, NearestEdge .000106–.000337, Plan .000072–.000185, BuildPath .000343–.001007. São fronteiras inclusivas com marshalling, esparsas e aninhadas em chamadores diferentes; não atribuem custo exclusivo a todo o roteamento. `NativeTrafficRoutes`/direção de tráfego são GDScript, e métodos nativos de `Curve3D` não são o router C#.

O contador cumulativo do corpo de `SessionDiagnostics._Process` mede médias .482/.186 ms por quadro nas baselines, sem p50/p95 de callbacks individuais. O contador do perfil GDScript fornece médias 1.611/.583 ms; já pertence à raiz `west.telemetry.profile_process` da tabela e não se soma a ela. Contadores não cobrem integralmente dispatch/instrumentação nem o writer em outro thread.

## Decomposição do quadro e parcela sem dono

| Fase | Média base_1 / base_2 ms | p50 base_1 / base_2 ms | p95 base_1 / base_2 ms |
|---|---:|---:|---:|
| Quadro completo | 55.273 / 24.398 | 34.437 / 19.290 | 169.761 / 47.293 |
| Callbacks físicos | 34.504 / 11.406 | 17.526 / 7.565 | 124.625 / 27.294 |
| Callbacks process | 10.593 / 6.336 | 8.272 / 5.373 | 24.569 / 12.012 |
| Antes de process, excluindo brackets físicos | 4.745 / 2.240 | 3.288 / 1.886 | 12.793 / 3.905 |
| Process → sentinel deferred | .643 / .429 | .660 / .501 | 1.163 / .780 |
| Sentinel deferred → pre_draw | .457 / .321 | .328 / .260 | 1.214 / .647 |
| Pre_draw → post_draw | 4.331 / 3.667 | 4.028 / 3.604 | 6.520 / 4.538 |
| Complemento dentro da física | 10.942 / 3.442 | 5.312 / 2.256 | 39.645 / 8.242 |
| Complemento dentro de process | 7.019 / 4.466 | 5.200 / 3.925 | 15.960 / 7.822 |

Complementos são calculados **em cada quadro**, subtraindo somente raízes regulares síncronas/disjuntas revisadas na fonte, antes de calcular os percentis. Nenhum quadro das baselines apresentou cobertura excedente. Incluem instrumentação fora dos spans, callbacks não medidos e trabalho entre probes; o Timer de pneus fica fora da cobertura por não ter contenção temporal confirmada. Os complementos se sobrepõem aos brackets e não se adicionam a eles.

Continua sem atribuição a simulação nativa, callbacks internos, filas diferidas completas, culling, driver/render, áudio em outros threads, GC e waits. O trecho anterior a process **não prova backend físico**. GPU total p50/p95 das baselines: 5.297/7.087 e 4.966/7.942 ms; a diferença principal aparece nas fases de CPU, sem permitir CPU = frame − GPU nem concluir clocks, temperatura ou throttling.

## Passos físicos e carga

| Baseline | Passos / quadros | Média passos/quadro | Quadros com 8 passos | Bracket individual p50/p95 ms/passo |
|---|---:|---:|---:|---:|
| base_1 | 3140 / 1043 | 3.011 | 148 | 9.861 / 19.645 |
| base_2 | 2845 / 1943 | 1.464 | 1 | 7.492 / 10.850 |

Em quadros com 1 passo, o custo físico p50 é 7.950/6.764 ms (base_1/base_2); com 2 passos, a média p50 por passo dentro do quadro é 8.300/7.732 ms; com 8 passos, 14.470/10.016 ms (segunda baseline n=1). Quantis individuais dos ticks são distintos dessa normalização.

Veículos têm média ponderada de 4.927/3.215 ms por passo para todos os carros, com 37.205/36.469 chamadas por passo. Atores: 1.985/1.498 ms e 33.512/35.896 chamadas. Logo, a mudança não decorre somente da quantidade de entidades: também mudam passos e comportamento/custo de cada passo. Não se demonstrou a causa temporal da variação.

Último inventário de aquecimento perto de `(84,81)` — habilitação ativa, sem prova de visibilidade ou quantidade de invocações no regime medido:

| Script / classe | Ativos base_1 / base_2 |
|---|---:|
| Todos — process / physics | 264/110 e 286/121 |
| Actor / CharacterBody3D — physics | 18 / 30 |
| Vehicle / CharacterBody3D — physics | 33 / 36 |
| CivilianModel / Node3D — process | 43 / 53 |
| VehicleEquipment / Node — process | 29 / 33 |
| PickupPresentation / Node3D — process | 14 / 14 |
| SkateBody / CharacterBody3D — physics | 7 / 4 |
| TerminalCoach / CharacterBody3D — physics | 4 / 4 |
| Timer — internal_process | 5 / 6 |

O inventário completo por script/classe, incluindo áudio e callbacks internos, está em cada JSON bruto e em `analysis.json`. Nas baselines, `world.people` p50=36 e veículos p50=37; o número de nós ativos não identifica custo.

## Interruptores e variação entre repetições

Resultados abaixo são p50/p95 **por rodada**, em ms. Baseline: 34.437/169.761 e 19.290/47.293. A amplitude natural observada é **15.147 ms no p50 e 122.468 ms no p95**. Critério pré-definido conservador: duas repetições válidas, fontes/condições fixas, resultados disjuntos e diferença maior que amplitude baseline + amplitude variante. Não houve efeito que ultrapassasse esse critério.

| Configuração | Rodada 1 p50/p95 | Rodada 2 p50/p95 | Sem erro | Estado |
|---|---:|---:|---:|---|
| `--population=0` | 14.993 / 24.287 | 17.006 / 35.836 | 2 | Inconclusivo |
| `--no-traffic` | 12.243 / 26.772 | 14.474 / 23.577 | 2 | Inconclusivo |
| `--no-traffic-yield` | 25.306 / 146.083 | 53.818 / 144.897 | 2 | Inconclusivo; foco diferente |
| `--no-roadside-parking` | 27.597 / 179.730 | 23.673 / 56.591 | 2 | Inconclusivo |
| `--no-density` | 27.388 / 60.223 | 27.728 / 79.133 | 2 | Inconclusivo; aumenta carga |
| `HARBOR_SESSION_PROFILE=0` | 48.294 / 146.015 **falha** | 18.011 / 46.279 | 1 | Inconclusivo |
| Coleta extra + spans extras desligados | 24.350 / 53.598 | 25.441 / 58.471 **falha** | 1 | Inconclusivo; controle composto |

Redução estimada = mediana dos percentis das baselines − mediana dos percentis das variantes válidas; valores positivos indicam quadro mais rápido. São estimativas, não custos exclusivos:

| Configuração | Δp50 / ruído conservador ms | Δp95 / ruído conservador ms |
|---|---:|---:|
| população 0 | 10.864 / 17.160 | 78.466 / 134.017 |
| sem tráfego | 13.505 / 17.378 | 83.352 / 125.663 |
| sem yield | −12.699 / 43.659 | −36.963 / 123.654 |
| sem estacionamento | 1.229 / 19.071 | −9.633 / 245.607 |
| sem política de densidade | −.695 / 15.487 | 38.849 / 141.378 |
| perfil de sessão 0, somente uma válida | 8.853 / 15.147 | 62.248 / 122.468 |
| controle composto, somente uma válida | 2.513 / 15.147 | 54.929 / 122.468 |

`population=0` mantém atores autorados; `no-traffic` mantém 9 veículos de outros serviços. Retiradas também alteram colisões e passos, sem converter a diferença em custo exclusivo de pedestres/carros. `no-density` força escala 1: elevou people p50 a 40/39 e veículos a 48/44. `HARBOR_SESSION_PROFILE=0` mantém o logger C#; desliga a camada de sistemas/operações. O controle composto desliga `HARBOR_WEST_CPU_TRACE` e `HARBOR_WEST_CPU_SPANS` juntos, mantendo probes e telemetria original; não separa a contribuição de cada toggle.

Foco: ambas as baselines 100%; `no_traffic_yield_1` 98.264%, `no_traffic_yield_2` 0%, `session_profile0_1` 0%, `session_profile0_2` 14.115%; demais rodadas 100%. Nenhum quadro pausado. Amostras sem foco foram mantidas e identificadas; os contrastes sem equivalência de foco são marcados nos comparativos e não qualificam atribuição causal. A segunda rodada sem perfil de sessão teve apenas 6.973 s focados; nenhuma atingiu 30 s focados, portanto esse controle não mede custo robusto do observador. Eventual efeito de apresentação em segundo plano permanece uma limitação, sem atribuir throttling não medido. O custo auto cronometrado do runner nas baselines foi média .266/.208 ms por quadro; não cobre todo o custo de instrumentação, dispatch, agregação e threads, e não autoriza reconstruir FPS sem observador.

## Erros e estado da entrega

`session_profile0_1` teve dois `SCRIPT ERROR`: material `Nil` ao atribuir `emission_energy_multiplier` em `TaxiLivery.gd:65`, na cadeia de pouso/dano de NPC → fechamento da vaga → disponibilidade de táxi; e instância previamente liberada em `CoastalPlanarReflections.gd:100`, `_remove_node` chamado pelo descarte de `NativeRegion`. `instrumentation0_2` repetiu a falha dos reflexos, mesmo com a coleta extra e os novos spans desligados. A origem não foi demonstrada e não foi imputada à wrapper de profiling.

Timings e erros dessas rodadas permanecem em seus JSONs e em `analysis.json.runtime_errors`, com texto, linha do console e backtrace; foram retiradas dos comparativos. A única repetição adicional de perfil de sessão terminou sem erro (`session_profile0_2`), deixando apenas uma amostra válida nessa configuração. Não houve terceira tentativa equivalente nem correção de produção fora do escopo.

Entrega: ranking e decomposição medidos, comparação inconclusiva diante da variação e atribuição de CPU ainda parcial. Não é aprovação de performance ou estabilidade geral. Fontes de clima/reflexos do usuário e o benchmark original foram preservados; nenhum export, push ou commit de produção.

## Evidências reproduzíveis

- `analysis.json`: cálculos por rodada, comparações, hashes/condições, normalização física, inventários e erros preservados.
- `analysis.md`: todas as tabelas detalhadas; JSONs `<label>.json` guardam amostras por quadro, `<label>.inputs.json` os 1058 hashes.
- `span-parent-map.json`, `static-notes.md`: relações dos spans e alcance real dos interruptores; `temporary-spans-manifest.json` / `.patch` documentam a coleta temporária.
- `restoration.json` / `restoration.md`: conferência da restauração das fontes; logs locais `<label>.console.log` / `.engine.log` complementam os registros persistidos.
- `tests/measure/profile_west_cpu.gd` e `tests/measure/analyze_west_cpu.py`: runner e análise. Regerar: `python tests/measure/analyze_west_cpu.py --input evidence/profile-west-cpu-20261013 --output evidence/profile-west-cpu-20261013/analysis.json --markdown evidence/profile-west-cpu-20261013/analysis.md`.

A ferramenta foi validada diretamente com fixtures de zeros, aquecimento, parentesco, passos, residual por quadro, comparação sob ruído/SHA/condições e rejeição de erro sem apagar timing. Nenhuma suíte ampla foi criada para a remoção reversível dos spans. Artefatos preliminares são históricos e não integram o conjunto final da análise.

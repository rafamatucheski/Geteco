# Inspeção estática do oeste do porto — 2026-10-13

Esta inspeção localiza trabalho provável e o alcance dos interruptores. Não atribui custo de CPU a partir da quantidade de código ou de nós. As medidas novas pertencem a `profile_west_cpu.gd`; o benchmark do usuário em `evidence/benchmark-west/` é uma fonte anterior, somente consultada.

## Alcance real dos interruptores

| Interruptor | Efeito confirmado no código | Limitação do comparativo |
|---|---|---|
| `--population=0` | `runtime/ProductionWorld.gd:217` fixa `requested_population=0`; `_population_cap()` e o job `citizen` deixam de repor a população ambiente. | Não desliga atores de rotinas, residentes, funcionários, animais ou atores próprios do estacionamento; inventário de callbacks por script confirma a carga remanescente. |
| `--no-traffic` | `runtime/ProductionWorld.gd:1250` impede o job de criar carros de trânsito ambiente. | Mantém jogador, estacionamento, ônibus, veículos autorados, estacionamento de residências e frota de missões. Os gráficos de ruas e os demais serviços continuam. |
| `--no-traffic-yield` | `runtime/ProductionWorld.gd:191` deixa de criar `TrafficYieldController`. | Remove sua varredura e seus agentes; não remove testes de cruzamentos, bloqueios ou rota feitos pelo `Vehicle`. |
| `--no-dispatch` | `runtime/ProductionWorld.gd:185` deixa de criar `DispatchController`. | É parte comum de todas as rodadas pedidas; não haverá ranking da perseguição. O router C# também é usado por ônibus, táxi, chegada e preparação de rotas. |
| `--no-roadside-parking` | `runtime/RoadsideParking.gd:35` fixa `enabled=false` e desliga seu callback físico antes da primeira visita. | O nó controlador existe, mas não descobre vagas nem cria/manobra carros ou passageiros. Remove também as interações causadas por essas entidades; a diferença não é custo exclusivo do controlador. |
| `--no-density` | `runtime/ProductionWorld.gd:1190` força o alvo de densidade a 1 e os alvos de área a `(1,1)`. | **Não desliga o callback de densidade.** No mercado a política comum usa até `.9` para pedestres e `.7` para tráfego; o interruptor tende a aumentar a população/tráfego. Comparação de carga/política, sem chamá-la de custo da densidade. |
| `HARBOR_SESSION_PROFILE=0` | `runtime/SessionDiagnostics.cs:115` evita o filho `SessionSystemProfile`; `runtime/SessionOperations.gd:5` desativa suas operações. | O autoload C# ainda cria o sink, escreve métricas, coleta GC/memória e executa `_Process`. Mede a retirada da camada de perfil de sistemas, sem desligar toda a telemetria. O agregador independente do runner continua ligado. |

`scripts/World.gd` fixa a seed global em `21092026` antes da construção de produção; não há parser de `--seed=7` nesse caminho. `RoadsideParking` fixa seu RNG em `61006` com `--benchmark`. RNGs locais de outros sistemas e identidade/ordem dos objetos não são integralmente estabilizados por essas duas seeds. Repetições continuam necessárias.

## Fronteiras e candidatos de CPU

| Sistema / entrada | Trabalho observado no código | Interpretação da medida |
|---|---|---|
| `scripts/Vehicle.gd:395`, `vehicle.physics` | Tick completo dos veículos, inclusive caminho estacionado/LOD. Dentro dele: direção, `StreetPhysics` pré/pós, movimento, contato, rodas e efeitos. | Raiz inclusiva. `vehicle.drive`, `vehicle.move_and_slide`, `vehicle.street_pre`, `vehicle.street_post`, `vehicle.effects`, etc. são filhos; não somar pai e filhos. |
| `scripts/Actor.gd:194`, `actor.physics` | LOD, rota/steering, degraus, `move_and_slide`, atualização de pose/animação. | Raiz inclusiva. `actor.steering`, `actor.step`, `actor.move_and_slide`, `actor.pose` são detalhamento, sem custo aditivo. |
| `gameplay/traffic_yield/TrafficYieldController.gd:128` | Hazards por tick e agentes; varreduras de carros quando há emergência. | Callback próprio; pode ser barato sem sirenes. Ausência de despacho não implica ausência de todos os veículos de emergência. |
| `gameplay/street_physics/StreetPhysics.gd:487` | Atualização de restos, props, corpos e efeitos; helpers fazem queries/sweeps no caminho dos veículos. | O callback próprio pode ser separado; helpers chamados dentro do `Vehicle` são aninhados. Física nativa fora dos callbacks não é atribuída pelo tempo do helper. |
| `runtime/ProductionWorld.gd:1089` | Residência física/streaming a cada quadro; um job de população por quadro; a cada .25 s: densidade, metadados, trim, footbridge crossers, ambient journeys e remoção/resgate de veículos. | Medição por quadro deve manter os zeros e mostrar p95; médias por chamada esconderiam a frequência. |
| `world/regions/NativeRegion.gd:581` | Construção e residência incremental de chunks. | Pode haver criação/draw updates diferidos fora do próprio callback. |
| `world/city_look/CityLook.gd:56` | Lentes dos semáforos a cada quadro, fases materiais, TV, silhuetas, orientação do sol; atualização mais ampla a 4 Hz. | Somente inspeção/profiling externo autorizado; não editar os arquivos de clima/reflexo do usuário. |
| `world/city_look/CityLocalLighting.gd:29` | Refresh a 4 Hz, sincronização de luzes do editor; durante o dia pode terminar antes da busca de fontes. | Contar luzes totais não prova custo do callback nem custo de render. |
| `world/city_look/CoastalPlanarReflections.gd:171` | Registro incremental, ambiente/fachada, sincronização de batches/dinâmicos, duas SubViewports condicionais. Com `--benchmark`, publica `last_process_usec` e subcustos sem spans novos. | Campo benchmark é uma observação do próprio callback; GPU das vistas é assíncrona e não se subtrai do frame para obter CPU. Arquivo do usuário preservado. |
| `audio/vehicle_ambience/NearbyVehicleAudio.gd:84` | Seleção periódica, descoberta/ordenação de carros, slots de áudio por quadro. | Callback script não cobre mixagem do thread de áudio nem atualizações internas de `AudioStreamPlayer3D`. |
| `audio/VehicleRoadAudio.gd:62`, `WorldAudio.gd:266`, `ServiceVehicleAudio.gd:155` | Controle de vozes, contato de pneus e sons próximos. | Separar callback script de backend/vozes internas. Inventário inclui players ativos para contexto. |
| `scripts/CameraRig.gd:177` | Interpolação da câmera, input, retícula, oclusão/reveal/túnel e foco. | Callback script não inclui culling/render associados à mudança da câmera. |
| `gameplay/VehicleEquipment.gd:425`, efeitos de pneus/danos/dents | Equipamento e apresentação por carro, com muitos callbacks pequenos. | Custos espalhados aparecem no inventário por script; multiplicidade não é atribuição temporal. |
| `runtime/FullSession.gd:1836`, rotina social, ônibus, trem, terminais, port operations | Serviços simultâneos, atividades e manutenção do mundo. | Podem permanecer mesmo sem pedestres/tráfego ambiente. Inventory delimita o que está instanciado/ativo no oeste. |

## Router C# e telemetria

`gameplay/dispatch/RoadGraphSearch.cs` é `RefCounted`, sem `_Process` ou `_PhysicsProcess`. Suas entradas relevantes são `Build` (38), `NearestEdge` (169), `Plan` (278), `Search` (301) e `BuildPath` (314), chamadas pelo wrapper `DispatchRoadRouter.gd`. Logo, nenhum inventário de callbacks do C# atribuiria seu custo; precisa de span nas chamadas ou wrapper. `NativeTrafficRoutes.gd` e os helpers de `Vehicle` são GDScript; não atribuir toda a navegação do tráfego ao C#.

`ProductionWorld._prewarm_route_jit()` (1410+) prepara o C# durante a cortina; o runner deve confirmar que o backend nativo foi usado e excluir o aquecimento do ranking estável. Rotas de ônibus/táxi/terminais podem usar o router em fases próprias após a carga.

`SessionSystemProfile.gd` consome `StallWorkTrace.take_session()` cedo em `_process`, calcula inventário/contexto, mantém histórico e envia JSON à telemetria. `StallWorkTrace` possui consumidores separados de sessão e agregador: o runner deve ler somente `aggregate_totals` e não roubar o consumidor da sessão.

Os labels de `finish_slow` ainda entram no agregado **mesmo abaixo do limite de evento**. O limite vale para detalhes, permitindo ranking de custo por quadro com zeros sem viés de chamadas lentas. Os eventos `session_slow` retêm somente um subconjunto das chamadas lentas; não são fonte suficiente para percentis de todas as chamadas ou cobertura completa.

`Performance.TIME_PROCESS` e `TIME_PHYSICS_PROCESS` são monitores recentes de uma janela do motor, inadequados para decompor cada quadro ou tirar média das amostras como média dos callbacks. A ferramenta `analyze_west_cpu.py` não os utiliza.

Brackets de probes medem o intervalo dos callbacks das respectivas prioridades; não incluem automaticamente a simulação nativa, filas diferidas, threads de render/áudio ou espera do sistema operacional. A soma física/process/diferidos/render é defensável somente com fronteiras temporais válidas e disjuntas. Não subtrair soma de percentis; um residual precisa ser calculado **por quadro** antes dos percentis e continua sem atribuição causal.

## Fontes anteriores do usuário — separadas das rodadas novas

Os arquivos abaixo foram lidos em 2026-10-13, sem modificação, e não entram na análise do profiler novo:

| Arquivo anterior | Frame p50 ms | Frame p95 ms | GPU total p50 ms | Veículos / people |
|---|---:|---:|---:|---:|
| `evidence/benchmark-west/base_1.json` | 21.25 | 45.08 | 2.38 | 37 / 36 |
| `evidence/benchmark-west/base_2.json` | 33.74 | 148.81 | 5.37 | 38 / 36 |
| `evidence/benchmark-west/sem_pessoas_transito.json` | 7.04 | 11.81 | 2.35 | 9 / 0 |

As duas baselines anteriores diferem 12.49 ms em p50 e 103.73 ms em p95; o GPU p50 também mudou 2.99 ms. Isso demonstra condição instável/variação relevante, sem identificar a causa. A retirada combinada de pedestres e trânsito altera duas variáveis e permaneceu com 9 veículos; não permite dividir o custo entre pedestres e tráfego nem aprovar ganhos pequenos de outros interruptores. O relato inicial de 17.7/36.8 ms é contexto fornecido pelo usuário, distinto desses arquivos e de nossas medidas.

## Ferramenta de análise

`tests/measure/analyze_west_cpu.py` lê somente JSONs com `samples` por quadro do runner novo. Exclui aquecimento, mantém zeros, calcula p50/p95/p99 e FPS por frames/tempo, mostra distribuição de passos físicos e separa raízes/filhos/spans de parentesco desconhecido. Comparações de variantes exigem duas rodadas em cada configuração e diferença acima da soma das amplitudes baseline/variante, com intervalos de resultados disjuntos. Uma rodada isolada de telemetria registra estimativa, sem declarar efeito separado do ruído.

Residual de fase é calculado por quadro somente com garantia explícita do produtor ou revisão das raízes síncronas de callbacks regulares (`span-parent-map.json` + fontes existentes), agregador ativo, ordem válida, nenhum overflow e pares de probes corretos. A raiz do `Timer` de marcas fica fora desse residual, pois a contenção entre probes regulares não foi confirmada. Coverage acima do bracket é rejeitada e contabilizada. O complemento inclui instrumentação fora dos spans e scripts não cobertos; não há classificação automática como física nativa, render ou CPU de scripts.

O arquivo irmão `span-parent-map.json`, produzido pela revisão dos spans temporários, complementa os mapas estáticos da ferramenta. Helpers com vários possíveis chamadores preservam `possible_parents` e não são subtraídos de todos os pais. `reflection.process` e seus filhos usam os contadores de benchmark já presentes no arquivo de reflexos do usuário.

A validação direta da ferramenta em Python usou um fixture temporário, sem iniciar Godot: zeros, exclusão do aquecimento, médias por quadro, parentesco, proteção do residual, comparação dentro/acima da variação, exigência de repetições, exclusão de rodadas inválidas e geração de Markdown passaram. Isso valida a análise matemática e o formato, sem certificar as medidas ainda não executadas.

`gameplay.physics`, `urban.physics` e `terminal.physics` são wrappers existentes de `_physics_process` em `Gameplay.gd`, `UrbanBusService.gd` e `TerminalOperations.gd`; entram como raízes físicas revisadas. `vehicle.effects.tires`, `.powertrain` e `.impact` são filhos de `vehicle.effects`. `VehicleTireEffects._redraw_marks()` tem um único chamador `_tick_mark_lifetime()`, disparado pelo `Timer` de .10 s; não é filho de `vehicle.effects.tires` e não se normaliza por passos físicos. `vehicle_tires.surface_end` é o upload aninhado no redraw.

Os tempos físicos por passo possuem duas apresentações: duração individual real de cada `physics_ticks` bracketado, e custo de um span agregado do quadro dividido pelos passos daquele quadro. A segunda é uma média por passo dentro do quadro; seus quantis não representam durações individuais de chamadas. Quadros com zero passos não entram nessa normalização; permanecem nos percentis por quadro. Raízes/helpers de fase desconhecida e callbacks de process/timers não são divididos pelos passos.

Antes de aprovar comparação, a ferramenta verifica os digests e arquivos SHA256 dos snapshots `.inputs.json` correspondentes, além de resolução, renderer, versão/build, VSync, limite de FPS, tick rate e rota. Mostra a porcentagem de quadros com/sem foco e quadros pausados; quadros sem foco não são descartados automaticamente. Configurações com `HARBOR_WEST_CPU_TRACE=0` e `HARBOR_WEST_CPU_SPANS=0` pertencem ao grupo `instrumentation0`, distinto da baseline e de `session_profile0`.

Equivalência de foco integra os flags do comparativo: rodadas com integridade numérica e sem erro, mas sem foco equivalente à baseline, permanecem como observação nas tabelas e não aprovam efeito causal. O JSON distingue `numerically_valid`, `runtime_usable` e `comparable` para evitar contar todas as rodadas sem erro como comparáveis.

A ferramenta também lê o console irmão, registra `SCRIPT ERROR`, erros de engine/managed e contexto da stack. A presença de erro acrescenta uma invalidação analítica mesmo quando `invalid:[]` do runner indica apenas brackets corretos. O timing fica na tabela identificado como falha; a rodada sai das comparações causais. Console ausente é informado como lacuna, sem inventar ausência de erros.

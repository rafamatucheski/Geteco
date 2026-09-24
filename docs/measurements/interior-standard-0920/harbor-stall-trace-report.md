# Diagnóstico renderizado dos interiores do Porto — 20/09/2026

Execução encerrada com código 0. O cenário, seed, entradas reais e prefixo foram preservados: garagem do Maciota → delegacia → clínica → bombeiros → zelador → Ammu-Nation. Cada sala teve 5 s de primeira visita, 5 s de aquecimento e 30 s de amostra. Janela 1280×720, Mobile, RTX 4060 Laptop, VSync ligado, limite 60 FPS e física 60 Hz. Nenhum sistema de população, polícia, transporte, streaming ou apresentação foi desligado para obter estes números.

O monitor externo registrou **131 snapshots**, aproximadamente a cada 2 s, de **13:36:57 a 13:41:43 UTC**. Não detectou sobreposição com outro teste/captura: apenas editor PID 48296 e os dois processos desta execução. Ao finalizar, restava somente o editor. Isso documenta os intervalos observados, sem presumir a carga de CPU do editor ou do sistema operacional.

## Resultado desta execução

| Sala | FPS | p95 / p99 (ms) | Máximo (ms) | Quadros >33,3 / >66,7 ms | Primeira visita máx. (ms) | GPU da sala, mediana (ms) |
|---|---:|---:|---:|---:|---:|---:|
| Garagem do Maciota | 59,96 | 17,857 / 18,989 | 53,966 | 1 / 0 | 37,063 | 2,354 |
| Delegacia | 52,52 | 33,574 / 47,723 | 364,752 | 82 / 7 | 19,040 | 2,789 |
| Clínica | 60,02 | 17,725 / 18,381 | 22,009 | 0 / 0 | 191,529 | 0,835 |
| Bombeiros | 60,01 | 17,759 / 18,177 | 21,331 | 0 / 0 | 24,567 | 1,912 |
| Zelador | 60,02 | 17,844 / 18,215 | 19,203 | 0 / 0 | 20,080 | 1,601 |
| Ammu-Nation | 60,01 | 18,400 / 18,826 | 20,339 | 0 / 0 | 22,691 | 0,847 |

Clínica e bombeiros têm **amostra isolada aprovada**, com GPU local baixa; os picos das medições anteriores continuam registrados. Não houve mudança de código entre essas medições para corrigir tais picos, portanto não se trata de uma correção demonstrada. O mesmo cuidado vale para a variação observada na Ammu-Nation. A primeira visita da clínica ainda mostra trabalho de carregamento; não confundir a amostra estável com ausência de custo de entrada.

## O que o diagnóstico permite concluir

Na delegacia, o custo está concentrado no processamento de CPU: entre os quadros >33,3 ms, o monitor de processo teve mediana **32,602 ms**, física **10,484 ms**, enquanto a GPU da sala teve mediana **2,939 ms** e máximo **4,742 ms** na janela inteira. Os valores do monitor de processo/render podem refletir a amostra anterior do motor; servem para separar CPU de GPU, não para atribuir cada quadro a uma função sem perfil de chamadas.

PresentationBudget não construiu NPCs durante a janela da delegacia (**14 → 14 builds**), nem houve jobs de prewarm regional de veículos (**0 → 0**). O scheduler de trabalho registrou etapas de `mountain_static_render`; a existência de reservas não equivale a custo alto: no trecho estável da garagem, os últimos 512 registros tinham máximo de apenas 342 µs.

Os sete maiores engasgos da delegacia ocorreram com `mountain_building=true`. O jogador permanecia parado no interior, com âncora externa **(1080,2070)**; o gate de proximidade mantinha `should_load=false`, distância aproximada de **9091 unidades do mapa**, `pending_world={}` e `mountain_load_trigger={}`. A chamada independente foi localizada em `geodata/transit/HarborMountainCoachService.gd:142`: o ônibus inicia `ensure_mountain()` quando chega ao trecho norte. Isso explica carga regional fora do gate do jogador e o início tardio recorrente; não justifica desligar ou atrasar arbitrariamente o transporte durante a visita a um interior.

Delegacia e Quayside **continuam pendentes da meta de 60 FPS** durante esse trabalho concorrente. A origem da solicitação regional foi identificada; este diagnóstico não resolve nem atribui todos os demais quadros lentos. Não foi feita refatoração global de streaming, redução de qualidade, nem suspensão de polícia/ônibus/população.

## Artefatos reproduzíveis

- `harbor-stall-trace.log`: resultados, flags de streaming e contagens de builds.
- `harbor-stall-trace-processes.jsonl`: inventário inicial, snapshots e inventário final de processos.
- `harbor-stall-trace-<Sala>-cold-trace.json` e `harbor-stall-trace-<Sala>-steady-trace.json`: tempo por quadro, CPU/física, CPU/GPU do viewport raiz e da sala, scheduler, PresentationBudget, prewarm e contexto de entrada/saída da amostra.
- `harbor-stall-trace-<Sala>.json/png`: amostra e foto geradas pelo benchmark de produção herdado.
- `_codex_diag/trace_harbor_stalls.gd`: logger separado; `_codex_diag/analyze_harbor_stalls.py`: resumo dos dados.
- `_codex_diag/run_harbor_stall_trace.ps1`: recusa iniciar com outra captura/teste aberto e, se detectar concorrência posterior, invalida a execução e encerra somente os processos correspondentes ao script/label desta medição. Aceita também `measure_harbor_interiors.gd` e seleção de salas para a confirmação isolada de Fuel.

Os históricos anteriores foram preservados. Alertas de RIDs/recursos na desmontagem continuam sendo uma limitação já observada nas cenas grandes; código 0 confirma o término do diagnóstico, não ausência de vazamentos globais.

# Beira de estrada do deserto: A/B em release (19/10/2026)

Export release da árvore de trabalho no commit 644b67c3 (`artifacts/export-20261019-roadside/`),
medido com `tools/perf_cross_bench.sh`, uma rodada por rótulo, alternando ligado (A) e
`GETECO_DESERT_ROADSIDE=0` (B) no mesmo export e no mesmo dia: A1, B1, A2, B2. Notebook i7-13650HX
com RTX 4060 Laptop, 1280x720, vsync, 60 fps de teto. Outra sessão (passe de arte) trabalhava na
máquina ao mesmo tempo; o Godot dela passa pela mesma fila, mas o resto (editor, Python, dotnet)
não, então a primeira rodada pode ter ruído.

| rota | rótulo | quadros | p50 ms | p95 ms | p99 ms | máx ms | >33 ms |
|---|---|---|---|---|---|---|---|
| rota66 | A1 ligado | 52305 | 5,78 | 11,94 | 15,99 | 89,48 | 32 |
| rota66 | B1 desligado | 69020 | 4,50 | 7,84 | 11,15 | 61,06 | 11 |
| rota66 | A2 ligado | 63900 | 4,71 | 8,98 | 12,35 | 66,78 | 11 |
| rota66 | B2 desligado | 70184 | 4,66 | 7,61 | 10,74 | 48,12 | 9 |
| deserto | A1 ligado | 9067 | 4,99 | 8,70 | 10,62 | 53,10 | 1 |
| deserto | B1 desligado | 10996 | 4,12 | 6,67 | 7,83 | 72,50 | 1 |
| deserto | A2 ligado | 11516 | 4,02 | 6,26 | 6,86 | 36,03 | 1 |
| deserto | B2 desligado | 11346 | 4,10 | 6,33 | 6,86 | 33,17 | 0 |

Leitura:

- A1 é ruído, não custo da beira de estrada: o `deserto` (volta na arrancada, a 470 m do lugar
  mais perto, onde nada monta) também piorou só nessa rodada (p50 4,99 contra 4,0-4,1).
- Par limpo A2/B2 na rota66: p50 +0,05 ms, p95 +1,4 ms, p99 +1,6 ms, um quadro a mais acima de
  33 ms. Os quadros acima de 33 ms caem nos mesmos segundos nas duas rodadas (9, 50, 139, 180,
  222 e 311 s): são do streaming da rota, que já passa do critério com tudo desligado. O único a
  mais com a beira de estrada ligada é o segundo quadro em ~50 s, quando a rota passa pelo
  Sol Poente.
- `desert.roadside.build` (log da sessão): 2,62 ms, uma vez (só o Sol Poente monta nessa rota).
  A primeira renderização das peças novas não entra no span.
- Nenhum evento de estrada nasceu nessas rodadas, por um defeito: os trechos de 180 m da Route 66
  nunca cabiam o ponto 240 m à frente. Corrigido em 832bdfa3; o custo dos eventos em release
  ainda não foi medido.

Não medido: os eventos de estrada (acima), o tiroteio do bloqueio, os outros três lugares em
rota de benchmark (nenhuma rota passa por eles), e a noite.

## Eventos de estrada em release (19/10, à tarde)

`--benchmark-road-events` (ReleaseBenchmark, só na rota66) força, em cada volta medida, uma van
quebrada na ida (z -1000) e um bloqueio de bandidos na volta (z -990), 240 m antes, como o jogo.
O carro passa a ser o alvo (`driving.occupied`), senão o jogador escondido dentro da lataria nunca
é visto e ninguém atira; jogador e carro invencíveis. O lado desligado roda com o mesmo interruptor
e `GETECO_DESERT_ROADSIDE=0` (sem eventos). `BENCH_EXTRA="--benchmark-road-events"` passa a opção
pelo `tools/perf_cross_bench.sh`.

Spans das peças (log da sessão, uma peça por quadro; três exports e rodadas do dia):

| peça | chamadas por rodada | máx ms |
|---|---|---|
| `desert.road_event.vehicle` (van ou picape) | 4 | 0,87-1,33 |
| `desert.road_event.driver` | 2 | 1,16-1,77 |
| `desert.road_event.outlaw` | 6 | 1,63 com a janela em foco; 2,0-2,8 sem foco |
| `desert.road_event.props` | 2 | 0,10-0,13 |

Os quatro eventos nasceram nas três rodadas com o interruptor, no ponto marcado (`late_m` 0 a
0,1). Com o carro como alvo o bloqueio atirou: 1877 e 3206 quadros em combate nas duas rodadas
ligadas (antes, 0).

**O A/B de tempo de quadro dessa tarde não vale.** Nas quatro rodadas (evOn1, evOff1, evOn2,
evOff2) a janela do benchmark ficou sem foco em 415 a 514 janelas de medição: alguém usava a
máquina. Há quadros de 7 a 12 s e sequências de ~500 ms (o Windows freando janela de fundo) também
no lado desligado, então p50, p95 e máximo dessas rodadas não medem o jogo. A rodada evA1 da manhã
(janela em foco, eventos sem tiroteio) deu p50 4,29 ms, p95 7,63, máx 69,4, 11 quadros > 33 ms,
na mesma faixa das rodadas sem eventos.

Falta medir: o custo do tiroteio do bloqueio no tempo de quadro, com a máquina parada e a janela
em foco (rodar de novo evOn/evOff). A peça do bandido fica perto de 2 ms; se passar disso com
foco, vale pré-aquecer o modelo do fora-da-lei.

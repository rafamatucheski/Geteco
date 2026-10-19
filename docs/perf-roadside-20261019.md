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

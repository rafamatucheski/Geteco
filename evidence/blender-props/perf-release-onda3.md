# Terceira onda de adereços do Blender em release: A/B (20/10/2026)

Pergunta: as 52 peças novas do kit da cidade (calçada, sinalização, telhado e fachada) e
os 8 objetos do editor, todos com cor e proporção variando por cópia, custam mais que as
procedurais?

## Como foi medido

- Um export release só (`artifacts/perf-blender-onda3`, árvore de trabalho das 14 h, com
  mudanças de outras sessões que valem igual para as duas variantes).
- `GETECO_BLENDER_PROPS` 1 (Blender) × 0 (procedural). O interruptor troca as três ondas de
  uma vez: 9102b89f, 7fba8db1 e esta.
- `tools/perf_cross_bench.sh`, rotas `oeste`, `porto` e `sobrados`, 3 rodadas por variante
  com a ordem alternada (1→0, 0→1, 1→0): 18 sessões entre 14:08 e 15:40.
- **Máquina sem sossego:** a fila de Godot intercalou testes de outras sessões entre as
  rodadas (test_desert_wilds, test_vicente_letters, scripts de compilação). Os números
  das duas variantes subiram em relação às medições da manhã (oeste procedural 6,14 ms
  contra 4,97–5,30 ms de manhã).

## Resultado (ms; média das 3 rodadas, intervalo do p50 entre parênteses)

| Rota | Variante | p50 | p95 | p99 | máx | >33 ms | GPU p50 | draws p50 |
|---|---|---|---|---|---|---|---|---|
| oeste | Blender | 7,51 (6,78–8,95) | 12,12 | 14,25 | 29,5 | 0 | 1,61 | 955 |
| oeste | procedural | 6,14 (5,63–6,81) | 10,43 | 11,71 | 20,8 | 0 | 1,56 | 965 |
| porto | Blender | 5,72 (5,07–6,58) | 10,56 | 11,96 | 23,1 | 0 | 1,34 | 533 |
| porto | procedural | 5,47 (4,57–6,06) | 10,16 | 12,06 | 28,5 | 0 | 1,37 | 529 |
| sobrados | Blender | 5,09 (4,45–5,71) | 9,89 | 12,12 | 40,1 | 3 | 1,30 | 537 |
| sobrados | procedural | 4,87 (4,47–5,10) | 9,62 | 12,11 | 37,2 | 4 | 1,25 | 538 |

p50 rodada a rodada no `oeste`: Blender 6,80 / 8,95 / 6,78; procedural 5,63 / 5,98 / 6,81.

## Leitura

- **Inconclusivo.** A média pende contra o Blender nas três rotas (+1,37, +0,25 e +0,22 ms
  no p50), mas os intervalos se sobrepõem em todas. No `oeste`, a 3ª rodada empatou
  (6,78 × 6,81) e a 2ª teve 3 ms de diferença, no meio de uma fila agitada.
- Chamadas de desenho e GPU p50 ficaram iguais (cor e proporção por cópia continuam numa
  MultiMesh por tipo). Se o custo existir, o suspeito é o número de triângulos: as árvores
  de rua passaram de 749 para ~2.700 e projetam sombra; outras peças de calçada foram de
  centenas para 1.400–2.400. Isso não foi isolado.
- Quadros > 33 ms: 3 com Blender e 4 com procedural, todos na rota `sobrados`.

## O que falta

- Medir de novo com a máquina parada, com mais rodadas e com um interruptor só para esta
  onda (ou só para as árvores), para separar o custo dela do das ondas 1 e 2.
- Noite, chuva, caos, dirigindo, outros presets, destroços.

# Terceira onda do Blender em release, medida limpa (20/10/2026)

Pergunta: os 52 tipos do kit da cidade remodelados no commit 0b34f4b5 (com cor e proporção
por cópia) custam quadro em release? Quanto disso vem das árvores de rua?

A medição anterior (`perf-release-onda3.md`) foi inconclusiva: trocava as três ondas de uma
vez e a fila intercalou testes de outras sessões no meio das rodadas.

## Como foi medido

- **Interruptores novos**, só para esta onda, em `world/city_look/CityPropKit.gd`:
  - `GETECO_BLENDER_WAVE3=0`: os tipos de `WAVE3_KINDS` voltam à procedural e
    `variation_for()` devolve vazio (sem cor nem proporção por cópia). As ondas 1 e 2
    (lixeira, hidrante, banco etc. e o porto) continuam do Blender nas duas variantes.
  - `GETECO_BLENDER_TREES=0`: só `street_tree`, `street_tree_b` e `pot_plant` voltam à
    procedural (e perdem a variação); o resto da onda fica do Blender.
  - `GETECO_BLENDER_PROPS=0` continua desligando tudo.
- Um export release só: `artifacts/perf-onda3-limpo` (árvore de trabalho das 16 h; mudanças
  de outras sessões que estavam no disco valem igual para as duas variantes).
- `tools/perf_cross_bench.sh`, rotas `oeste`, `porto` e `sobrados`, opções gráficas fixas da
  bancada (preset Média, 1280×720), sem despacho.
- **Pares na fila:** em cada rodada e rota, as duas variantes entram na fila juntas (a 2ª
  senha 2 s depois da 1ª), então nada de outra sessão roda entre elas. A ordem alterna por
  rodada (liga→desliga, desliga→liga, ...). Cada variante usa a sua pasta isolada.
- **Validação de cada par:** (1) `%TEMP%/geteco-godot-queue.log` sem nenhuma entrada alheia
  entre o início da 1ª e o fim da 2ª; (2) `perf_window.focused` sempre verdadeiro no log da
  sessão das duas. Par que falhasse era descartado e repetido. Na onda 3, os 15 pares
  passaram de primeira (16:48–18:48). Outras sessões usaram a fila **entre** pares (teste
  `test_desert_act2_reunion`, bancada das cavernas, captura da serra), nunca dentro.
- Registro dos pares: anexo no fim.

## Onda 3 ligada × desligada (5 pares por rota; ms)

| Rota | Variante | n | p50 média (mín–máx) | p95 | p99 | máx | >33 ms | GPU p50 | draws p50 |
|---|---|---|---|---|---|---|---|---|---|
| oeste | ligada | 5 | 5,13 (4,74–5,76) | 9,03 | 10,34 | 62,07 | 3 | 1,63 | 938 |
| oeste | desligada | 5 | 6,01 (4,72–7,32) | 9,99 | 11,60 | 41,89 | 1 | 1,59 | 946 |
| porto | ligada | 5 | 4,56 (3,97–5,35) | 8,79 | 10,09 | 39,52 | 1 | 1,29 | 525 |
| porto | desligada | 5 | 4,55 (3,89–5,34) | 8,84 | 10,28 | 37,40 | 2 | 1,29 | 524 |
| sobrados | ligada | 5 | 3,75 (3,26–4,33) | 7,66 | 9,38 | 33,84 | 1 | 1,16 | 540 |
| sobrados | desligada | 5 | 3,76 (3,29–4,15) | 7,52 | 9,27 | 38,93 | 2 | 1,20 | 537 |

Diferença por par (ligada − desligada), p50:

- oeste: p50 -0,11 / 0,07 / -2,50 / -0,39 / -1,47 → média -0,88 ± 0,49 (erro padrão), 1/5 positivos; p95 média -0,96
- porto: p50 0,08 / 0,12 / 0,09 / -0,26 / 0,01 → média 0,01 ± 0,07 (erro padrão), 4/5 positivos; p95 média -0,05
- sobrados: p50 0,02 / -0,03 / 0,11 / -0,33 / 0,18 → média -0,01 ± 0,09 (erro padrão), 3/5 positivos; p95 média 0,14

## Árvores ligadas × desligadas

**Não medido.** O interruptor `GETECO_BLENDER_TREES` está pronto, mas o usuário pediu para
parar e liberar a fila antes do primeiro par (a onda inteira já não mostrou custo, então as
árvores, que fazem parte dela, também não mostram nestas rotas). Para medir depois: o mesmo
esquema de pares, com `GETECO_BLENDER_TREES=0` contra o padrão, nas mesmas rotas.

## Triângulos por peça

`tests/measure/count_wave3_triangles.gd` (dados em `wave3-triangles.json`). Todas as peças
subiram de 3 a 15 vezes; as de calçada ficaram entre 1.100 e 2.700 triângulos.

| Peça | procedural | Blender | sombra |
|---|---|---|---|
| street_tree | 749 | 2.716 | sim |
| street_tree_b | 609 | 2.116 | sim |
| pot_plant | 215 | 588 | não |
| flower_buckets | 444 | 2.424 | não |
| clothes_rack | 168 | 2.272 | não |
| tire_stack | 360 | 2.184 | não |
| water_tank | 276 | 2.112 | sim |
| bike_rack | 684 | 2.056 | não |
| satellite_row | 126 | 1.788 | não |
| cafe_set | 306 | 1.552 | sim |
| cafe_parasol | 261 | 1.508 | sim |
| ice_freezer | 84 | 1.356 | sim |

(lista completa no JSON; projetam sombra 20 dos 53 tipos de `WAVE3_KINDS`, os de `CityChunkDressing.SHADOW_CASTERS`.)

## Leitura

- **A 3ª onda não tem custo mensurável nesta máquina.** Porto e sobrados: diferença média de
  +0,01 e −0,01 ms no p50, com erro padrão de ~0,1 ms; os pares trocam de sinal. Oeste: −0,88 ms
  a favor do Blender, mas puxado por duas rodadas da procedural (7,32 e 6,21 ms) — ruído da rota,
  não efeito das peças (a mesma rota variou 4,7–7,3 ms entre rodadas de uma variante só).
- **GPU p50 igual** (diferença ≤ 0,04 ms) e **chamadas de desenho iguais**: a cor e a proporção
  por cópia continuam numa MultiMesh por tipo, e os triângulos a mais (3–15× por peça, árvore
  749 → 2.716, com sombra) não aparecem porque a GPU gasta ~1,2–1,6 ms de um quadro de 4–6 ms.
  O quadro aqui é limitado pela CPU.
- **Quadros > 33 ms:** 5 com a onda ligada e 5 desligada no total das 30 sessões; pico de 62 ms
  numa rodada ligada do oeste e de 42 ms numa desligada. Sem padrão por variante.
- **O resultado de 20/10 à tarde** (+1,37 ms no oeste) não se repetiu com a fila limpa; aquele
  número era contaminação.
- **Redução sugerida, não aplicada** (não há ganho para mostrar nesta máquina): se uma GPU
  fraca mostrar custo, os primeiros alvos são (1) menos tufos na copa das duas árvores, que
  são as peças de mais triângulos e projetam sombra, e (2) tirar da sombra peças pequenas e
  densas que entraram em `SHADOW_CASTERS` (`window_ac`, `laundry`, `stop_sign`).

## O que não foi medido

- Só uma máquina (i7-13650HX, RTX 4060 Laptop, Vulkan Forward+), preset Média, 1280×720, meio-dia, sem chuva, sem
  caos e sem polícia. Numa GPU fraca ou em resolução alta o triângulo a mais pesa mais: aqui a
  GPU fica em ~1,2–1,6 ms de um quadro de 4–6 ms, então a máquina está limitada pela CPU e o
  custo de vértice não aparece.
- Os 8 objetos do editor de mundo não estão nestas rotas.
- Quadros grandes isolados (> 33 ms) aparecem nas duas variantes, em número parecido; não foram
  investigados um a um.
- Memória de vídeo e tempo de montagem do chunk não foram medidos separadamente (o p95/p99 e os
  quadros > 33 ms cobrem a montagem só indiretamente).

## Anexos

- Rótulos dos JSON: `o3on_r<n>_t1_<rota>_1` / `o3off_...` em
  `%APPDATA%/GetecoV2/benchmark-west/`; resumos `.tsv` em `evidence/perf-cross-20261015/`.
- Registro dos pares (horário, ordem, entradas alheias, quadros sem foco):

```
16:55:10 rodada=1 rota=oeste tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
17:09:43 rodada=1 rota=porto tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
17:17:16 rodada=1 rota=sobrados tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
17:23:48 rodada=2 rota=oeste tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
17:30:26 rodada=2 rota=porto tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
17:37:56 rodada=2 rota=sobrados tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
17:44:28 rodada=3 rota=oeste tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
17:51:08 rodada=3 rota=porto tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
17:58:55 rodada=3 rota=sobrados tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
18:06:45 rodada=4 rota=oeste tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
18:13:20 rodada=4 rota=porto tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
18:20:52 rodada=4 rota=sobrados tentativa=1 ordem=off/on estranhos=0 sem_foco=0/0
18:30:12 rodada=5 rota=oeste tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
18:36:44 rodada=5 rota=porto tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
18:48:07 rodada=5 rota=sobrados tentativa=1 ordem=on/off estranhos=0 sem_foco=0/0
FIM
```

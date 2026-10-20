# Peças do porto do Blender: o custo de ~0,26 ms na rota `porto` existe? (20/10/2026)

Pergunta: as 13 variantes de `HarborRouteProps` feitas no Blender (7fba8db1,
`_add_modeled`) custam os ~0,26 ms de p50 que o A/B de `perf-release-porto.md` mostrou na
rota `porto`? Aquele A/B trocava as duas ondas juntas (cidade + porto) e teve 3 rodadas.

**Resposta curta: não se confirmou.** Isolando só as peças do porto, com 5 rodadas
alternadas, o p50 médio ficou 4,01 ms (Blender) contra 3,99 ms (procedural): +0,02 ms, com
as diferenças por rodada indo de −0,15 a +0,14 ms e trocando de sinal. O p95 e o p99 ficaram
até um pouco *abaixo* com Blender. As peças novas têm **menos** malhas (75 contra 144 nas
quatro zonas) e mais triângulos (+9,7 mil na cena, +18 mil primitivas por quadro
contando os passes de sombra), o que custa no máximo uns centésimos de ms de GPU.

## O que mudou no código

- `GETECO_BLENDER_HARBOR_PROPS=0` desliga só as peças do porto (`HarborRouteProps`);
  `GETECO_BLENDER_PROPS=0` continua desligando as duas ondas. Padrão: ligado.
- Span `harbor_route_props.modeled_scene` na primeira instanciação do `.glb` em
  `_add_modeled`.
- `tests/measure/count_harbor_route_props.gd`: conta malhas, superfícies, triângulos e
  sombras de cada zona nas duas variantes (não mede tempo).

## Como foi medido

- Um export release (`artifacts/perf-blender-harbor`, com o span já dentro), as duas
  variantes no mesmo exe, só `GETECO_BLENDER_HARBOR_PROPS` 1 × 0 (as peças da cidade da
  primeira onda ficaram ligadas nas duas).
- `tools/perf_cross_bench.sh <export> hb{1,0}_rN 1 porto`, pela fila, sem sobreposição
  (conferido em `geteco-godot-queue.log`). Bancada padrão: Média, 1280x720, Forward+, Vulkan,
  sem despacho. Ordem alternada: r1 1→0, r2 0→1, r3 1→0, r4 0→1, r5 1→0. 10 sessões,
  09:46–10:18 UTC.
- TSV: `evidence/perf-cross-20261015/hb{0,1}_r{1..5}.tsv`; logs de sessão em
  `%APPDATA%/GetecoV2/session-logs/20261020-0946…` a `…-101448…` (no disco, fora do Git).

## Resultado (ms)

| Rodada | Blender p50 / p95 / p99 / máx | Procedural p50 / p95 / p99 / máx | Δ p50 |
|---|---|---|---|
| r1 | 4,10 / 8,62 / 10,20 / 71,6 | 3,96 / 7,83 / 9,08 / 20,2 | +0,14 |
| r2 | 3,68 / 7,46 / 8,61 / 20,1 | 3,83 / 7,80 / 9,09 / 16,5 | −0,15 |
| r3 | 3,71 / 7,36 / 8,40 / 13,8 | 3,59 / 7,20 / 8,47 / 14,3 | +0,12 |
| r4 | 3,88 / 7,80 / 8,97 / 16,3 | 3,84 / 8,07 / 9,56 / 16,7 | +0,04 |
| r5 | 4,69 / 8,59 / 9,77 / 21,7 | 4,73 / 9,12 / 10,45 / 18,1 | −0,04 |
| **média** | **4,01 / 7,97 / 9,19** | **3,99 / 8,00 / 9,33** | **+0,02** |

- Quadros > 16,7 ms: 13 (Blender) × 5 (procedural) somando as 5 rodadas; > 33 ms: 1 × 0.
  > 100 ms: nenhum.
- GPU p50 da bancada: 1,204 × 1,196 ms. Draws p50 da bancada: 530 × 520 (variam 487–583
  entre rodadas da mesma variante).
- A variação entre rodadas da **mesma** variante (p50 3,59–4,73) é ~1 ms, dez vezes a
  diferença entre variantes. A rodada 5 saiu lenta nas duas variantes igualmente (9,7 mil
  quadros contra 11–12,5 mil): a máquina oscila ao longo da meia hora, por isso o pareamento.

## Por que não custa: o que as peças mudam na cena

Contagem por zona (`count_harbor_route_props.gd`), Blender × procedural:

| Zona | Malhas | Triângulos | Malhas com sombra | Triângulos na sombra |
|---|---|---|---|---|
| rodoviária | 21 × 56 | 9.298 × 4.622 | 19 × 54 | 8.724 × 4.608 |
| ruas de ligação | 14 × 23 | 3.728 × 1.632 | 12 × 21 | 2.584 × 1.608 |
| delegacia | 32 × 49 | 7.952 × 5.424 | 31 × 48 | 7.380 × 5.412 |
| Maciota | 8 × 16 | 3.432 × 3.060 | 7 × 15 | 2.860 × 3.048 |
| **total** | **75 × 144** | **24.410 × 14.738** | **69 × 138** | **21.548 × 14.676** |

Materiais por zona são os mesmos (os de `HarborRouteMaterials`), então não há shader novo.

Nos logs de sessão (mediana das janelas `perf_window` de 1 s com região carregada, média
das 5 rodadas):

| | draws | objetos desenhados | primitivas | render CPU | render GPU |
|---|---|---|---|---|---|
| Blender | 662 | 849 | 290 mil | 0,756 ms | 1,280 ms |
| procedural | 667 | 863 | 272 mil | 0,769 ms | 1,253 ms |

- **Número de MeshInstances:** caiu pela metade nas zonas (uma malha por material, contra
  uma por cilindro/caixa), e os objetos desenhados caem ~14 por quadro. Isso joga a favor
  do Blender, não contra.
- **Triângulos:** +9,7 mil na cena, +18 mil primitivas por quadro (com os passes de sombra).
  É o único aumento medido, e vira ~0,03 ms de GPU na janela do log e 0,008 ms no p50 de
  GPU da bancada, abaixo do ruído. Os postes da polícia (~1.500 triângulos cada, 2 na
  delegacia) e os postes padrão pesam mais que as procedurais, mas o total ainda é ~6% das
  primitivas do quadro.
- **Sombras:** 69 casters contra 138; triângulos na sombra +6,9 mil. Mesma leitura: menos
  objetos, um pouco mais de vértices, sem efeito mensurável.
- **Primeira instanciação (span):** `harbor_route_props.modeled_scene` levou 0,18–0,21 ms,
  uma vez por sessão, dentro do quadro de carregamento (sob a cortina). Não aparece em
  nenhum quadro jogável.

## O pico de 71,6 ms da rodada Blender r1

Único quadro > 33 ms das 10 sessões. No `frame_spike` (141,6 s de sessão, já na medição):
`render_bracket_ms` 57,5, nenhum span lento, sistemas somando < 7 ms (física de veículo
3,9 ms). É espera do lado do desenho, sem nada de script. Foi a **primeira sessão depois do
export novo**, e nenhuma das outras quatro sessões Blender repetiu o pico (máx 13,8–21,7 ms);
a causa provável é cache de pipeline do export ainda frio, não as peças, mas isso não foi
provado. O A/B de ontem também teve um quadro de 57 ms, aquele na variante procedural.

## Leitura

- A diferença de +0,26 ms de ontem não reaparece com só a onda do porto trocada e mais
  rodadas. Ou era a primeira onda (cidade), ou era ruído de 3 rodadas; com a variação
  entre rodadas de ~1 ms vista hoje, a segunda hipótese é bem provável.
- Pelo lado de custo, **dá para continuar trocando peças** desse jeito (uma malha por
  material, materiais compartilhados, sem shader novo). O que vale vigiar é o total de
  triângulos com sombra: cada peça de ~1.500 triângulos repetida centenas de vezes (poste
  em toda rua, por exemplo) muda a conta; aqui são ~30 peças.
- Nada foi otimizado: não houve custo para atacar.

## O que não foi medido

- Só a rota `porto`, de dia, sem chuva, sem caos, a pé (bancada padrão). Noite (lâmpadas
  acesas), dirigindo e outros presets/resoluções ficaram de fora.
- A primeira onda (CityPropKit) sozinha na rota `porto`: dá para medir agora com
  `GETECO_BLENDER_PROPS=0` contra `GETECO_BLENDER_HARBOR_PROPS=0` no mesmo export.
- A causa do pico de 71,6 ms (sem pilha nativa; `HARBOR_STALL_STACKS` não estava ligado).
- O A/B não tem poder para enxergar diferenças < ~0,15 ms de p50: as diferenças pareadas
  variam ±0,15 ms entre rodadas.

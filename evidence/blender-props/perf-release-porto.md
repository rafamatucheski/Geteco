# Adereços do porto do Blender em release: A/B (20/10/2026)

Pergunta: as 13 variantes de HarborRouteProps refeitas no Blender (postes padrão,
polícia e industrial; balizadores cívico, polícia e faixa; bancos de 2,0 e 2,2 m;
lixeira; bicicletário; hidrante; floreira; grelha) custam mais que as procedurais?

## Como foi medido

- Um export release só (`artifacts/perf-blender-porto`), interruptor `GETECO_BLENDER_PROPS`
  1 (Blender) × 0 (procedural). **O interruptor também troca as 11 peças da cidade** da
  primeira onda (9102b89f). Este A/B mede as duas ondas juntas.
- `tools/perf_cross_bench.sh`, rotas `oeste` (sai de 64,82) e `porto` (sai de 150,82), que
  passam pelas zonas rodoviária, ruas de ligação, delegacia e Maciota. Bancada padrão
  (Média, 1280x720, Forward+, Vulkan, sem despacho).
- 3 rodadas por variante, com a ordem alternada (1→0, 0→1, 1→0): 12 sessões.
- TSV: `evidence/perf-cross-20261015/hp{0,1}_r{1,2,3}.tsv` (no disco, fora do Git).

## Resultado (ms; média das 3 rodadas, com o intervalo do p50 entre parênteses)

| Rota | Variante | p50 | p95 | p99 | máx | >33 ms | GPU p50 | draws p50 |
|---|---|---|---|---|---|---|---|---|
| oeste | Blender | 5,15 (5,11–5,19) | 9,16 | 10,33 | 16,7 | 0 | 1,59 | 970 |
| oeste | procedural | 5,30 (5,07–5,53) | 9,30 | 10,55 | 57,1 | 1 | 1,57 | 959 |
| porto | Blender | 4,46 (4,31–4,69) | 8,48 | 9,78 | 27,8 | 0 | 1,29 | 548 |
| porto | procedural | 4,20 (4,18–4,22) | 8,00 | 9,17 | 32,0 | 0 | 1,23 | 515 |

## Leitura

- **oeste:** sem diferença. Os intervalos se sobrepõem, e o único quadro > 33 ms (57 ms)
  saiu na variante procedural.
- **porto:** o Blender ficou acima nas três rodadas: +0,26 ms no p50, +0,48 no p95 e +0,61
  no p99. Os intervalos do p50 não se sobrepõem, então **pode haver um custo pequeno**, de
  ~6% no p50 dessa rota. As chamadas de desenho variaram muito entre rodadas (509–600 com
  Blender, 494–531 com procedural), e não deu para atribuir a diferença a elas.
- Na medição da véspera (só a primeira onda, `perf-release.md`), a rota `porto` deu +0,05 ms.
  O que mudou desde então é a onda do porto, mas 3 rodadas não bastam para afirmar que é
  ela.
- Mesmo no pior caso tudo fica bem dentro da meta (p50 ≤ 6,9 ms, nenhum quadro > 33 ms
  depois de jogável com Blender).

## O que não foi medido

- As duas ondas separadas: falta um interruptor só para as peças do porto.
- A causa da diferença na rota `porto`. Não abri os logs de sessão, e o caminho novo
  (`HarborRouteProps._add_modeled`) não tem span.
- Noite (as lâmpadas acesas), chuva, caos, dirigindo, outros presets e outras rotas.

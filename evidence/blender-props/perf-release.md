# Adereços do Blender em release: A/B (20/10/2026)

Pergunta: as 11 peças de calçada feitas no Blender (commit 9102b89f: lixeira, hidrante,
banco, poste de calçada, orelhão, caçamba, banca, balizador, caixa de correio, sacos de
lixo e jardineira) custam mais que as procedurais que substituíram?

## Como foi medido

- Um export release só (`artifacts/perf-blender-props`, feito do HEAD 9102b89f com a árvore de
  trabalho da hora, que tinha mudanças de outras sessões; valem igual para as duas variantes).
- Interruptor no mesmo export: `GETECO_BLENDER_PROPS=1` (Blender, padrão) × `=0` (procedurais).
- `tools/perf_cross_bench.sh`, rotas da cidade com mobiliário de calçada: `oeste`, `porto` e
  `sobrados`. Bancada padrão: preset Média, 1280x720, Forward+, Vulkan, sem despacho.
- 3 rodadas por variante, alternando a ordem (1→0, 0→1, 1→0) para diluir deriva da máquina.
  São 18 sessões no total, entre 00:38 e 01:37 (hora local), na mesma máquina.
- TSV e logs da bancada: `evidence/perf-cross-20261015/bp{0,1}_r{1,2,3}.{tsv,log}`, que ficam
  no disco e fora do Git.

## Resultado (ms; média das 3 rodadas, com o intervalo do p50 entre parênteses)

| Rota | Variante | p50 | p95 | p99 | máx | >33 ms | GPU p50 | draws p50 |
|---|---|---|---|---|---|---|---|---|
| oeste | Blender | 5,09 (5,00–5,27) | 8,83 | 10,01 | 32,7 | 0 | 1,61 | 947 |
| oeste | procedural | 4,97 (4,85–5,08) | 8,71 | 9,73 | 17,2 | 0 | 1,55 | 957 |
| porto | Blender | 4,30 (4,22–4,36) | 8,40 | 9,56 | 39,1 | 1 | 1,27 | 531 |
| porto | procedural | 4,25 (4,16–4,34) | 8,28 | 9,38 | 15,8 | 0 | 1,26 | 510 |
| sobrados | Blender | 3,59 (3,58–3,62) | 7,47 | 9,03 | 29,7 | 0 | 1,19 | 533 |
| sobrados | procedural | 3,62 (3,53–3,67) | 7,42 | 9,14 | 34,5 | 2 | 1,19 | 531 |

Todas as rodadas ficam bem abaixo da meta (p50 ≤ 6,9 ms; nenhum quadro > 33 ms depois de
jogável, com 3 exceções isoladas, citadas abaixo).

## Picos e primeira aparição

- Quadros > 33 ms na janela da bancada: 1 com Blender (porto r3, 39,1 ms) e 2 com as
  procedurais (sobrados r2 e r3, ~34,5 ms).
- O de 39,1 ms (sessão `20261020-042118`, aos 150,8 s) não tem span nomeado. Os 29 ms dele
  ficaram no trecho de render (`render_bracket_ms`), o que lembra compilação de pipeline.
  Mas, contando nas 18 sessões os picos de render > 15 ms depois da carga, deu **1 com
  Blender e 3 com as procedurais**: nada indica que as peças novas compilem algo no jogo.
- Os picos de 50–65 ms que aparecem em todos os logs de sessão (fim da corrida e
  desmontagem) se repetem nas duas variantes.
- Nenhum span das peças novas aparece nos `slow_spans`. Há uma ressalva: o caminho novo
  (`CityPropKit.blender_mesh`, que instancia uma vez a cena pré-carregada de cada peça) não
  tem span próprio. O custo da primeira montagem não foi medido isolado; só se vê que não
  gerou pico.

## Conclusão

**Não deu para ver custo.** Chamadas de desenho e GPU ficaram iguais, como esperado: mesmo
material e mesma MultiMesh. No `oeste` o Blender ficou 0,12 ms acima no p50 e 0,28 ms no p99.
Os intervalos das duas variantes se sobrepõem, e no `sobrados` a diferença inverteu. Com 3
rodadas, um efeito de até ~0,1 ms no p50 não se separa do ruído. Se existir, é desse tamanho,
bem dentro da folga até 6,9 ms.

## O que não foi medido

- Outras rotas (serra, ponte, travessia, deserto) e cenários de caos, noite, chuva e
  dirigindo. As peças são da calçada urbana, mas o poste aparece em toda rua do Harbor.
- Os presets gráficos Alta e Baixa, outras resoluções e o driver D3D12.
- Destroços: carro batendo nas peças. A bancada roda sem despacho e sem colisões dirigidas.
- O custo isolado da primeira montagem de cada peça, que não tem span (ver acima).

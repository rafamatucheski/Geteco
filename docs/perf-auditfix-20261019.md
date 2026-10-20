# Correções da auditoria do Godot 4.7: medição em release (19/10/2026)

Export release `artifacts/export-20261019-auditfix/` (commits d8969407..2fbebd02, Forward+), bancada com
opções fixas (`tools/bench/settings.cfg`: preset Média, 1280x720, sem vsync nem teto). Notebook
i7-13650HX + RTX 4060 Laptop. Tempos em ms; média = `frame_ms.mean` do JSON.

## Rotas da cidade, variantes em sequência no mesmo intervalo (1 rodada cada)

| variante | oeste média | oeste p50 | porto média | porto p50 | pior | > 33 ms |
|---|---|---|---|---|---|---|
| novo (correções ligadas) | 5,61 | 4,99 | 4,55 | 4,05 | 15,5 | 0 |
| `GETECO_SUN_SHADOW_TUNE=0` | 5,48 | 4,77 | 4,70 | 4,21 | 19,9 | 0 |
| `GETECO_GROUND_OPAQUE=0` | 5,51 | 4,85 | 4,83 | 4,37 | 17,9 | 0 |
| `GETECO_LOCAL_SHADOW_PREWARM=0` | 5,59 | 4,88 | 4,63 | 4,09 | 48,0 | 2 (porto) |
| antigo (todos desligados) | 5,44 | 4,80 | 4,74 | 4,23 | 18,2 | 0 |

**Leitura:** nenhuma correção muda a média da cidade além do ruído (±3 %). Sem o pré-aquecimento de luz
com sombra o porto teve 2 quadros de 48 ms; com ele, nenhum (uma rodada: indício, não prova).

## Rodada 1 completa (novo × antigo × Mobile), intercalada

| rota | novo | antigo | Mobile (`--rendering-method mobile`) |
|---|---|---|---|
| oeste | 6,18 | 5,14 | 5,47 |
| porto | 5,17 | 4,02 | 4,21 |
| sobrados | 4,50 | 3,61 | 3,55 |
| serra | 3,04 | 3,04 | 3,42 |
| ponte | 1,70 | 1,72 | — |
| travessia | 2,18 | 2,20 | — |
| deserto | 2,58 | 3,15 | — |

A diferença novo × antigo da cidade nesta rodada (~1 ms) **não se repetiu** na tabela de cima: é variação
entre momentos da máquina. Com as correções desligadas, o Forward+ fica igual ou acima do Mobile na
média. A bancada completa (2 rodadas, occlusion+LOD) foi interrompida em 18/56 para a caça acima.

## Pico de 907 ms (porto, novo, rodada 1)

Aos 148 s, já jogável: 881 ms entre o fim do `_process` e o início do desenho (`late_to_render_pre_ms`),
sem span e com 1,5 ms da sonda adiada. Não se repetiu nas 5 rodadas seguintes do porto. Causa não
identificada.

## Não medido

Occlusion culling e LOD procedural ligados (`GETECO_OCCLUSION`, `GETECO_PROC_LOD`); D3D12; noite e chuva
(faróis e túnel); segunda rodada de todas as rotas; o pico de 220–250 ms da serra/travessia não apareceu
nas rodadas desta noite (ausência numa rodada não prova que sumiu).

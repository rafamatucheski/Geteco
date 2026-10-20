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

## Occlusion culling + LOD procedural (2 rodadas intercaladas)

| rota | desligado (rodada 1 / 2) | ligado (rodada 1 / 2) |
|---|---|---|
| oeste | 5,28 / 5,99 (média 5,64) | 5,22 / 7,16 (média 6,19) |
| serra | 3,01 / 4,31 (média 3,66) | 3,74 / 4,30 (média 4,02) |

Draw calls caem 2-7 %. Não ajudam com a câmera alta: ficam desligados. A variação entre rodadas da
mesma variante (oeste 5,28 → 5,99 ms) mostra que diferenças abaixo de ~10 % precisam de mais rodadas.

## D3D12, noite e chuva (1 rodada cada, mesma build)

| teste | média ms | p50 | pior | > 33 ms |
|---|---|---|---|---|
| serra Vulkan | 4,24 | 3,76 | 39,4 | 1 |
| serra D3D12 (cache aquecido) | 5,10 | 4,58 | 39,6 | 1 |
| travessia dia (Vulkan) | 2,92 | 2,51 | 27,8 | 0 |
| travessia 22 h, correções ligadas | 2,66 | 2,32 | 25,8 | 0 |
| travessia 22 h, faróis/pré-aquecimento antigos | 2,52 | 2,17 | 25,3 | 0 |
| oeste dia | 5,61 | 4,99 | 15,5 | 0 |
| oeste chuva forte | **7,20** | 6,59 | 18,9 | 0 |

**Leitura:** D3D12 ~20 % mais lento na média na serra e com o mesmo pior quadro: fica no Vulkan. À noite
as correções empatam com o antigo (ruído). A chuva forte custa ~1,6 ms no oeste (+28 %) e é o único cenário
medido com média abaixo de 144 fps (139): é o próximo alvo. O pico de 220–250 ms não apareceu em nenhuma
rodada de 19/10.

## Chuva no oeste por peça (20/10, 4 corridas em sequência)

| cenário | média ms | GPU p50 | draws | pior |
|---|---|---|---|---|
| dia | 6,46 | 1,51 | 943 | 16,4 |
| chuva forte | 7,02 | 1,97 | 1031 | 16,9 |
| chuva leve | 7,14 | 1,67 | 1012 | **1105,1** |
| chuva forte, `GETECO_REFLECTION_HZ=20` | 7,47 | 1,89 | 1028 | 17,7 |

A chuva custa ~0,6 ms (+9 %), não 1,6: a comparação anterior era entre momentos diferentes. Reflexos
planares a 20 Hz não ajudam. **Na chuva leve, aos 170 s, um quadro de 1.105 ms com 1.072 ms dentro do
desenho** (`render_bracket_ms`): assinatura de compilação de pipeline ou trava do driver, num efeito que
aparece tarde e não está pré-aquecido (hipótese). Próximo passo: repetir com `HARBOR_STALL_LOG=1` para ter
`pipelines_delta` no quadro.

## Não medido

segunda rodada de todas as rotas; o pico de 220–250 ms da serra/travessia não apareceu
nas rodadas desta noite (ausência numa rodada não prova que sumiu).

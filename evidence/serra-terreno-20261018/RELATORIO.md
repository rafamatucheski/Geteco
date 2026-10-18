# Chão da serra: acabamento de terreno e asfalto (18/10/2026)

Relato do jogador: na serra "nada tem qualidade no que tange a terreno, falta textura, falta
detalhe"; as ruas pareciam lavadas.

## Por que parecia chapado

- **Neve sem detalhe:** cobertura de 0,78 a 0,99 em quase tudo e só ±4,5% de grão. O relevo
  procedural ia em `NORMAL_MAP`, mas a malha do terreno não tem tangente: o relevo era nulo.
- **Asfalto encostando no branco:** a faixa de beira de estrada (`mountain_footpath`) era quase da
  cor da neve, e o leito da máscara de trilha (`packed`) também clareava com a neve.
- **Bordas borradas:** máscara das trilhas de 0,5 m com `smoothstep(0,03, 0,92)` largo.
- **Asfalto igual ao da cidade:** agregado de baixo contraste, sem sal, remendo ou neve; na
  nevasca a pista continuava limpa e azul-escura.
- **Imagem lavada:** névoa de inverno 0,19 desde 18 m e saturação 0,82.

## O que mudou (`GETECO_MOUNTAIN_GROUND=0` volta ao desenho anterior)

- `mountain_ground.gdshaderinc`: ondulação de vento na neve em manchas, vales do vento mais frios,
  seixos só no chão descoberto, estratos na rocha; trilha com borda recortada, leito de cascalho e
  lama com seixos e leira de neve logo depois. Relevo direto em `NORMAL`.
- `mountain_footpath.gdshader`: acostamento de cascalho escuro com seixos junto ao asfalto.
- `coastal_wet_asphalt.gdshader`: só onde o chão é de montanha (mesma rampa de
  `WorldConnection3D.mountain_weight`): manchas de sal, remendos, pó de neve e bancos alongados pelo
  vento que crescem com a frente de neve (`Weather` → `MountainGroundFinish.set_snowfall`).
- `RegionalAtmosphere3D`: na serra, névoa ×0,78, contraste +0,05 e saturação ×1,10.
- Nenhum shader, material ou textura novo: são ramos por uniform em shaders que já são
  pré-aquecidos, então não há compilação nova no jogo.

## Capturas

`tests/capture/capture_mountain_ground_look.gd -- --no-save --label=<rótulo>`: estrada do passo,
encosta, vila, forja e estrada alta (Cume Branco), de dia e na nevasca, na altura de quem dirige e
do alto. `antes/` foi capturado com `GETECO_MOUNTAIN_GROUND=0` no mesmo código; `depois/` com o
padrão; `comparacao/` tem os pares lado a lado. As imagens ficam no disco, fora do Git.

## Desempenho (export release, mesmo export, mesmo dia, ABBA ×4)

`tools/perf_cross_bench.sh artifacts/perf-chaoserra chaoserraB_{off,on}N 1 serra travessia`.
Tempos em ms.

| rota | lado | p50 quadro (4 rodadas) | p99 | máx | >33 ms | >100 ms | GPU p50 |
|---|---|---|---|---|---|---|---|
| serra | sem | 6,75 / 3,51 / 4,46 / 3,75 | 9,3–19,9 | 44–105 | 14/1/1/1 | 1/0/0/0 | 2,44–2,65 |
| serra | com | 3,68 / 3,94 / 4,41 / 4,02 | 10,2–12,5 | 54–67 | 1/2/1/1 | 0 | 2,74–2,93 |
| travessia | sem | 3,07 / 3,24 / 3,38 / 3,18 | 9,4–10,6 | 37–45 | 1/2/2/4 | 0 | 2,25–2,31 |
| travessia | com | 3,81 / 3,13 / 3,58 / 3,37 | 10,0–13,5 | 38–87 | 18/3/2/2 | 0 | 2,34–2,54 |

- Custo real medido: **GPU p50 +0,3 ms na serra** (2,57 → 2,88 de média) e +0,16 ms na travessia.
  O quadro é limitado por CPU aqui, então o p50 do quadro não mudou além do ruído.
- Picos acima de 33 ms existem dos dois lados (problema conhecido da serra/travessia). As rodadas
  com mais picos (sem-1 na serra com 105 ms, com-1 na travessia com 18 quadros > 33 ms) são as
  primeiras do par, e o outro lado não repete; nenhum quadro > 100 ms com o acabamento.
- Não medido: noite, nevasca durante o benchmark e GPU mais fraca que a desta máquina.

## O que não foi resolvido

- De longe a neve ainda é bem uniforme (o grão some com a distância de propósito, para não
  cintilar). Cobertura 3D na neve (pedras, arbustos, como `DesertGroundCover`) ficou de fora.
- O pó de neve no asfalto aparece em pontinhos regulares quando visto de perto na nevasca.

# Piloto: carro do Meshy no lugar do carro de caixas (11/10/2026)

Teste do fluxo para veículos, igual ao piloto do mecânico: um carro só, validado e medido antes de migrar a frota.

## O que foi feito
- Prompt de texto→3D de um hatch compacto esportivo vermelho, pedindo "sem rodas". O Meshy **ignorou** o pedido e trouxe as quatro
  rodas coladas na carroceria (um só componente conexo) e um desenho de microcarro de 3 portas (não o "esportivo" pedido).
  Gasto: malha 20 + textura 10 = 30 créditos (remesh 10K triângulos é grátis; saldo 601 → 571).
- Remesh para ~10 mil triângulos, textura PBR 2K (cor, metálico/rugosidade, normal), GLB estático. `tools/meshy_slim_glb.py` baixou as três
  imagens para 1024 (GLB 9,4 MB → 0,98 MB).
- `tools/build_meshy_car.gd` monta `assets/fleet/meshy/citycar.scn`: gira para a frente ficar em -Z como a frota, escala 1,6, chão em y = 0,
  e **separa as rodas por geometria** (cilindro do pneu medido por ajuste de círculo: raio 0,17, eixos a ±0,636 do centro, face externa
  |z| > 0,42). Cada roda vira uma peça `Wheel_FL/FR/RL/RR` com a meta `wheel_center`, como os outros carros da frota (ex.: `DigoGolModel`).
- `tools/capture_car_compare.gd` coloca o carro atual (`metro_hatch.scn`) ao lado do novo e gira as rodas 50° para provar que se soltam.

## Números
| | carro atual (metro_hatch) | carro do Meshy |
|---|---|---|
| malhas | 80 | 5 (carroceria + 4 rodas) |
| triângulos | 19.188 | 9.894 (carroceria 6.197, rodas ~920 cada) |
| tamanho (m) | 1,96 × 1,57 × 3,87 | 1,95 × 1,61 × 3,04 |

Capturas em `evidence/npc-meshy/car/` (fora do Git): `tres_quartos.png`, `lado.png`, `frente.png`, `topo.png`.

## O que ficou bom
- Aparência muito acima do carro de caixas: faróis, lanternas, retrovisor, maçanetas, vidros com interior, rodas de liga.
- As rodas giram sem rasgar a carroceria nem deixar buraco visível nas vistas de 3/4 e de lado.

## O que NÃO foi feito / pendências para trocar um carro de verdade
- Não foi ligado a `Vehicle`/frota: não há entrada no `assets/fleet/catalog.json` nem teste de condução (`test_native_driving`).
- Porta que abre: `VehicleDoorBuilder` recorta a porta do casco com `data/catalogs/VehicleDoorSpecs.gd`; falta medir o vão deste modelo.
- Dano (`coupe_damage_material_key`), faróis acesos, giroflex, pintura por cor (hoje o vermelho está na textura), interior para a câmera de dentro.
- A tinta tem aspecto "amassado" (ruído do normal map do Meshy); considerar descartar o normal ou reduzir.
- Rodas separadas por corte geométrico: o pneu fica oco por dentro e o vão do arco mostra o interior do casco (não aparece nas capturas, mas
  um ângulo de baixo deve ser revisto).
- Desempenho não medido (menos malhas e metade dos triângulos, mas a textura PBR 1024 × 3 pesa mais que o carro atual sem textura).
- Proporções: o Meshy trouxe um microcarro (3,04 m); o prompt do "hatch esportivo" não foi atendido.

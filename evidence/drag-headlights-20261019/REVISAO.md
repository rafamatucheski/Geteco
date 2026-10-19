# Faróis do rival na arrancada — 19/10/2026

Falha: `tests/test_desert_drag_runtime.gd --drive` — "both real headlight sources remain enabled
throughout race" (80/81 com captura, 74/75 sem).

## Causa

A mudança sem commit de 18/10 (`VehicleEquipment._budget_request`, `LightBudget`) dava prioridade
aos faróis do rival só com o **centro do carro** dentro do frustum da `DesertDragSideCamera`.
Prova (`antes-probe.log`), corrida contra Digo, 3440×1440:

- 18,90 s, Dante 38,9 m à frente, Gol fora do quadro (indicador à esquerda): fora da exceção e
  a 39 m do jogador (> 25 m), energia 0 e projetor oculto.
- 18,90–18,98 s: o projetor alterna oculto ↔ 0,249/0,273 de energia a cada quadro. Na borda do
  frustum a elegibilidade liga e desliga; o handoff começa do zero e é cortado no quadro seguinte.

O facho (alcance 17–29 m, para a frente) entra no quadro antes da carroceria: com o rival 39 m
atrás, a ponta do facho fica 10–22 m atrás de Dante, dentro da imagem.

## Correção (`farol-pelo-facho.patch`)

O critério passou do centro do carro para o volume (AABB) de cada projetor contra os planos do
frustum. Continua valendo só com o marcador `desert_drag_physics` e a câmera lateral corrente,
dentro das mesmas 2 vagas estáveis de NPC e do teto de 8 fontes.

## Verificação

- Corrida real com a mesma prova (`depois-probe.log`): mesmos tempos (Dante 19,94 s, Digo 20,66 s),
  nenhuma transição para apagado nos dois carros; `DESERT_DRAG_RUNTIME checks=75 failures=0`.
- `test_drag_rival_headlights.gd` 11/11, inclusive "out-of-frustum rival releases the same NPC
  slots" a 120 m; `test_vehicle_light_handoff.gd`, `test_traffic_headlights.gd` (50),
  `test_headlight_source_occlusion.gd`: todos com código 0.

## Não verificado

- Desempenho em export release: o rival distante agora mantém os dois projetores com sombra
  enquanto o facho estiver no quadro (antes saíam junto com a carroceria). Não medido.
- Outros rivais, distâncias de 201/402 m e tela 16:9 numa corrida real; só Digo em 800 m a 21:9.
- Inspeção visual quadro a quadro do pisca: a prova lê estado e energia, não imagem.

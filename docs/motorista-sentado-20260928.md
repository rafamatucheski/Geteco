# Motorista visível e interior dos veículos (2026-09-28)

Antes, ao dirigir, o jogador sumia (`world.player.hide()`), os vidros eram opacos e a
empilhadeira não tinha piloto. Agora `gameplay/VehicleInterior.gd` dá ao veículo que o
jogador conduz:

- um interior de uma malha só, em cache por arquétipo (volante, painel, bancos, console,
  pedais, retrovisor, forro, cintos; caminhão/ônibus/empilhadeira têm variantes próprias);
- vidro e teto translúcidos SÓ nesse veículo (o trânsito segue com o modelo achatado);
- a pose de motorista sentado, mãos no volante (`Actor.pose_seated_base/limbs`), que segue o
  veículo com uma atribuição de transform por tique (`follow`, prioridade de física 20).

Integração com as portas: `Vehicle.finish_doors()` roda ANTES de `INTERIOR.open_view`
(o recorte da folha parte das malhas originais; o vidro trocado depois vale também para a
folha). Ver `docs/portas-de-veiculos-20260928.md`.

Testes: `tests/test_seated_driver.gd` (47 veículos), `tests/test_seated_driver_flow.gd`
(entrada/saída/salto em 7 veículos). Capturas em `tests/capture/capture_seated_driver.gd`.
Não medido aqui: custo de quadro do motorista sentado (há `tests/measure/measure_seated_driver.gd`).

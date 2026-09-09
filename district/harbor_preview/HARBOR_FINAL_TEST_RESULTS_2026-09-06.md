# Regressão final Harbor/Cobra — 2026-09-06

Sem commits. 34 testes focados headless; não é a suíte inteira do repositório.
Logs em `D:/geteco/harbor-release-<teste>.log`.

| Teste | Resultado |
| --- | --- |
| test_cobra_campaign_state | PASS (exit 0) |
| test_cobra_campaign_runtime | PASS (exit 0) |
| test_cobra_campaign_spatial | PASS (exit 0) |
| test_cobra_campaign_gameplay | PASS (exit 0) |
| test_cobra_neighborhood | PASS (exit 0) |
| test_cobra_territory | PASS (exit 0) |
| test_cobra_encounter | PASS (exit 0) |
| test_cobra_boss | PASS (exit 0) |
| test_cobra_vehicles | PASS (exit 0) |
| test_cobra_traffic | PASS (exit 0) |
| test_cobra_discovery | PASS (exit 0) |
| test_cobra_race_player_car | PASS (exit 0) |
| test_harbor_campaign_flow | PASS (exit 0) |
| test_harbor_boss_reward | PASS (exit 0) |
| test_harbor_boss_muscle | PASS (exit 0) |
| test_harbor_aftermath | PASS (exit 0) |
| test_harbor_lofts_courtyard | PASS (exit 0) |
| test_harbor_emergency_dispatch | PASS (exit 0) |
| test_harbor_finish_lamps | PASS (exit 0) |
| test_harbor_district | PASS (exit 0) |
| test_harbor_alleys | PASS (exit 0) |
| test_harbor_entrances | PASS (exit 0) |
| test_harbor_gateway | PASS (exit 0) |
| test_harbor_life | PASS (exit 0) |
| test_harbor_safety | PASS (exit 0) |
| test_harbor_road_edges | PASS (exit 0) |
| test_harbor_road_contract | PASS (exit 0) |
| test_harbor_bridge | PASS (exit 0) |
| test_harbor_fire_station_trucks | PASS (exit 0) |
| test_harbor_interiors_gameplay | PASS (exit 0) |
| test_harbor_ship_access | PASS (exit 0) |
| test_harbor_terminal | PASS (exit 0) |
| test_harbor_dante_contract | PASS (exit 0) |
| test_harbor_landscape | PASS (exit 0) |

Interiores atingiu o limite de 150s na primeira execução; repetição inalterada
concluiu com 22 ciclos/23 diálogos/zero falhas. Rodoviária: aviso de quatro
ObjectDB remanescentes no encerramento. Erro ambiental de certificados Windows
presente nas execuções sandbox. Nenhum erro de script/parsing/asserção.

Adicional renderizado: `test_harbor_save_roundtrip_isolated.gd` PASS, usando
slot exclusivo na pasta real, restauração em cena nova e remoção verificada
apenas do próprio arquivo. Log `D:/geteco/harbor-final-real-save.log`.

Capturas, benchmarks, limites e descrição das mudanças estão em
`HARBOR_IMPLEMENTATION_2026-09-06.md`.

# legacy/city_demo/ — o protótipo de origem

Esta pasta é a origem do projeto: o protótipo de cidade de onde o jogo cresceu. Continua
carregável, porque `legacy/Main.tscn` usa o `scripts/CityDemo.gd` daqui — ver
[../README.md](../README.md).

## O que saiu daqui em 2026-09-09

Até então esta pasta era metade viva, metade parada, e isso confundia: uma varredura por
nome de arquivo dizia que várias imagens estavam sem uso, quando na verdade
`EmergencyVehicle.gd`, `PlayerCar.gd` e `VehicleCatalog.gd` dependiam delas. As peças que
o jogo atual usa foram extraídas antes desta pasta virar `legacy/`:

| saiu | foi para |
|---|---|
| `scripts/TrafficVehicle.gd` | `world/shared/traffic/` |
| `scenes/TrafficVehicle.tscn` | `world/shared/traffic/` |
| `scripts/WeaponEffects.gd` | `world/shared/combat/` |
| `scripts/roads/CityIntersection.gd` | `world/shared/roads/` |
| `scenes/pickups/PoliceLoot.{gd,tscn}` | `world/shared/pickups/` |
| `art/` | `assets/art/` — patrimônio compartilhado, as duas gerações usam |

Antes de mover qualquer coisa daqui, rode `python tools/check_references.py`, que confere
**por caminho e por UID**. A varredura só por nome de arquivo já produziu conclusão errada
neste projeto.

## Como o protótipo original funcionava

Registro do README anterior desta pasta, preservado porque explica as escolhas que ainda
se veem no código daqui — e que são **diferentes** das do jogo atual:

- `CityDemo.gd` cria um distrito fixo de quatro quadras.
- Ruas e calçadas usam `TileMapLayer` nativo.
- Doze atores de tráfego visíveis usam `Path2D`/`PathFollow2D` com mão dupla.
- O registro em `data/traffic.json` mantém disponíveis os 50 veículos nomeados.
- Pedestres usam `NavigationRegion2D`/`NavigationAgent2D` e quatro quadros direcionais.
- Prédios são `Sprite2D` + `StaticBody2D` fixos, sem redesenho relativo à câmera.

Note o contraste com o jogo atual: aqui os pedestres usam navegação nativa do Godot,
enquanto `AnimatedPedestrian3D` e `EmergencyVehicle` do jogo vivo fazem direção manual
sobre o grafo de faixas (`EmergencyLaneRouter`), sem `NavigationAgent2D`.

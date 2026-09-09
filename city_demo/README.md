# city_demo/ — protótipo original, parcialmente vivo

Esta pasta é a origem do projeto: o protótipo de cidade de onde o jogo cresceu. A maior
parte está parada, mas **não dá para remover em bloco** porque o jogo vivo ainda depende
de pedaços dela.

## Ainda em uso pelo jogo atual

Scripts:

- `scripts/TrafficVehicle.gd` — veículo de tráfego ambiente
- `scripts/WeaponEffects.gd` — efeitos de combate, instanciado em `HarborPreview._ready()`
- `scripts/roads/CityIntersection.gd`
- `scenes/pickups/PoliceLoot.gd`

Arte (`art/`): `car.png`, `police_car.png`, `ambulance.png`, `firetruck.png`, os ícones de
arma em `art/weapons/`, `tree-round-crown.png` e `shrub-cluster.png`.

Uma varredura por nome de arquivo sugere que várias dessas imagens estão sem uso — elas
não estão. São referenciadas por `EmergencyVehicle.gd`, `PlayerCar.gd`, `VehicleCatalog.gd`,
`CityBuilding.gd` e `ModularUrbanKit.gd`. Antes de mover qualquer coisa daqui, rode
`python tools/check_references.py` e confira **por caminho e por UID**.

## Parado

O resto (`scenes/`, `data/`, a maior parte de `scripts/`) pertence à geração antiga,
junto com `Main.tscn` e `district/`. Continua carregável para saves antigos.

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

# OLD — arquivos fora do projeto ativo

Arquivos movidos para cá em 2026-09-09 depois de uma verificação dupla:
nenhum deles é referenciado por **caminho** (`res://...`) nem por **UID**
(`uid://...`) em nenhum `.gd`, `.tscn`, `.tres`, `.cfg` ou no `project.godot`.

O `.gdignore` nesta pasta faz o Godot ignorar o diretório inteiro: nada aqui
é importado, parseado ou carregado pelo jogo. Os arquivos continuam no
repositório e podem ser restaurados a qualquer momento.

## O que está aqui

**Scripts sem nenhuma referência** (código morto)
- `AnimatedPedestrian.gd` — substituído por `AnimatedPedestrian3D.gd`
- `Building.gd` — substituído por `ProceduralBuilding.gd` / `CityBuilding.gd`
- `city_demo/scripts/PedestrianArt.gd`
- `city_demo/scripts/roads/CityGridBuilder.gd`
- `city_demo/scripts/WeaponRuntime.gd`
- `district/ParkedCar.gd`
- `scripts/SidewalkPedestrianAgent.gd`
- `scripts/TrafficLaneAgent.gd`

**Frames v1 da cutscene de abertura** — `opening_cutscene_timeline.gd` usa os
`frame_v2_*` e os `frame_06`–`frame_10`; os cinco primeiros ficaram para trás.
- `frame_01_city_rain.png` … `frame_05_photo_in_jacket.png`

**Arte sem referência**
- `city_demo/art/building-atlas-expanded.png`
- `city_demo/art/pedestrian-directional-source.png`
- `city_demo/art/pedestrian-directional-safe-v2.png`
- `city_demo/art/pedestrian-directional-safe-v3.png` — só era usada pelos dois
  scripts mortos acima, então veio junto

**Imagens de conceito soltas na raiz do repositório**
- `forest_mountain_snow_progression.jpg`, `forest_mountain_tunnel_concept.jpg`,
  `mountain_altitude_city_vista.jpg`, `summit_suv_3d_concept.jpg`

## O que foi verificado e NÃO veio para cá

Estes pareciam sem uso numa primeira varredura por nome, mas a checagem
precisa mostrou que estão em uso — ficaram no projeto:
- `car.png` — usado por `EmergencyVehicle.gd`, `PlayerCar.gd`, `VehicleCatalog.gd`
- `city_demo/art/tree-round-crown.png` — `CityDemo.gd`, `ModularUrbanKit.gd`
- `city_demo/art/shrub-cluster.png` — `CityBuilding.gd`, `CityDemo.gd`, `ModularUrbanKit.gd`
- `addons/city_layout_editor/` — plugin habilitado no `project.godot`

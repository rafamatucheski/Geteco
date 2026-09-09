# legacy/ — a geração anterior do jogo

**Isto ainda roda.** Não confunda com `OLD/`, que é arquivo morto com `.gdignore`.

`HarborSceneRoute.for_save()` (em `world/harbor/`) escolhe qual mapa carregar conforme o
save:

```gdscript
const GAME   := "res://world/harbor/HarborGame.tscn"
const LEGACY := "res://legacy/Main.tscn"
```

Save **sem** a flag `harbor_campaign_active` carrega `legacy/Main.tscn` em runtime. Quem
começou a jogar antes da campanha do porto continua na primeira geração do mapa. Apagar
esta pasta, ou colocar um `.gdignore` nela, quebra o save dessas pessoas.

`tests/test_legacy_save_route.gd` existe exatamente para guardar esse contrato: ele
instancia a cena legada de verdade, não só confere a string do caminho.

## Conteúdo

| item | o que é |
|---|---|
| `Main.tscn` | Cena raiz da geração anterior |
| `CentralDistrict.{gd,tscn}` | O distrito central original |
| `DistrictInteriorManager.{gd,tscn}` | Interiores da geração anterior (o equivalente atual é `world/harbor/interiors/HarborInteriorManager.gd`) |
| `DistrictRestrictionFeedback.{gd,tscn}` | Aviso de restrição de área; só `Main.tscn` usa |
| `district/` | Bairros antigos: `borough_one/`, `coast/`, `highway/`, `bairro1/`, `bairro1_v2/` |
| `city_demo/` | O protótipo de cidade de onde o projeto nasceu |

## O que saiu daqui e não volta

`Main.tscn` continua referenciando código **vivo** — `Player.gd`, `PlayerCar.gd`,
`DynamicCamera.gd` na raiz, e `world/shared/emergency/EmergencyDepots.tscn`. As duas
gerações compartilham o personagem e o carro; só o mapa é diferente.

Ao isolar esta pasta (2026-09-09), as peças de `city_demo/` que o jogo atual usava foram
extraídas antes, para não deixar código vivo apontando para dentro de `legacy/`:

- `city_demo/scripts/TrafficVehicle.gd` → `world/shared/traffic/`
- `city_demo/scenes/TrafficVehicle.tscn` → `world/shared/traffic/`
- `city_demo/scripts/WeaponEffects.gd` → `world/shared/combat/`
- `city_demo/scripts/roads/CityIntersection.gd` → `world/shared/roads/`
- `city_demo/scenes/pickups/PoliceLoot.{gd,tscn}` → `world/shared/pickups/`
- `city_demo/art/` → `assets/art/` (patrimônio compartilhado: as duas gerações usam)

## Se for mexer aqui

Rode `tests/test_legacy_save_route.gd` e `python tools/check_references.py`. E lembre que
mover arquivo exige `--import` depois, senão o registro global de `class_name` do Godot
fica obsoleto — ver [CLAUDE.md](../CLAUDE.md).

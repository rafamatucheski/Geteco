extends RefCounted
## Prédios altos do porto montados pelo modo alto do PaintedFacadeKit (térreo +
## andares repetidos + topo). Arquivo próprio para não disputar
## PaintedHarborHouses.gd com as outras frentes de trabalho. Sem class_name: quem usa
## faz preload, e o jogo funciona antes de o cache de classes ser refeito (--import).
##
## Piloto LIGADO por padrão desde 16/10 (pedido do usuário): GETECO_PAINTED_TALL=0
## desliga (e GETECO_PAINTED_FACADES=0 continua desligando tudo). Desligado, nenhum
## caminho do jogo muda: style_for devolve "" e height_for devolve a altura de antes.

## id do prédio no jogo -> estilo alto e altura pedida (m). A altura vira
## térreo + N andares + topo (PaintedFacadeKit.tall_layout); o catálogo do interior
## usa a mesma conta para a cobertura e o número de andares baterem com a casca.
## CivicTower: no V1 a silhueta tinha 95/16 = 5,9 m (menor que a ExchangeTower,
## 8 m), baixa demais para térreo + topo (7 m); 10 m = térreo + 1 andar + topo e
## continua abaixo da torre vizinha quando ela também for pintada (13 m).
const TALL := {
	"CivicTower": {"style": "torre-civica", "height": 10.0},
	# Rodada de 18/10 (pacotes do Codex de 15-16/10): GETECO_PAINTED_TALL_18=0 desliga só
	# estes três para A/B. Exchange com 13 m (térreo + 2 andares + topo; V1 tinha 8 m)
	# fica acima da CivicTower vizinha. Os dois de moradia são "office" que usavam a
	# casca/cena assada antiga; a largura de cada um fica a até 16% da pintura (lofts
	# 14 m em 13,1 m; misto 10 m em 11,6 m), e o letreiro pintado FOUNDRY LOFTS não é o
	# nome do jogo (NORTH UNION), como nos prédios de HARBOR em PaintedHarborHouses.
	"ExchangeTower": {"style": "torre-exchange", "height": 13.0, "env": "GETECO_PAINTED_TALL_18"},
	"UnionApartments": {"style": "lofts-fundicao", "height": 13.0, "env": "GETECO_PAINTED_TALL_18"},
	"Apartments": {"style": "predio-misto", "height": 10.0, "env": "GETECO_PAINTED_TALL_18"},
}


static func enabled() -> bool:
	return PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_TALL") != "0"


## Estilo alto do prédio, ou "" (piloto desligado, id sem pacote ou estilo não importado).
static func style_for(building_id: String) -> String:
	if not enabled() or not TALL.has(building_id): return ""
	if TALL[building_id].has("env") and OS.get_environment(TALL[building_id].env) == "0": return ""
	var style: String = TALL[building_id].style
	return style if PaintedFacadeKit.is_tall(style) else ""


## Altura da casca pintada (soma exata das peças); `fallback` quando não é prédio alto.
static func height_for(building_id: String, fallback: float) -> float:
	var style := style_for(building_id)
	if style.is_empty(): return fallback
	return float(PaintedFacadeKit.tall_layout(style, float(TALL[building_id].height)).height)


## Monta o prédio alto em `building` (UrbanBuildingBase) se ele tiver estilo alto.
## Devolve false para o construtor seguir o caminho de sempre.
static func build_into(building: Node3D) -> bool:
	var style := style_for(building.building_id)
	if style.is_empty(): return false
	var size: Vector2 = building.building_size
	var access: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(building.building_id)
	# O catálogo já levou entrance_x para o vão pintado mais próximo (style_for de
	# PaintedHarborHouses devolve este estilo): a folha desse vão é a que abre.
	var walk_in_x: float = float((access.entrance_local as Vector3).x) if not access.is_empty() else NAN
	var visual := Node3D.new()
	visual.name = "PaintedTallOffset"
	building.visuals_root.add_child(visual)
	var solid := Node3D.new()
	solid.name = "PaintedTallSolidOffset"
	building.collision_root.add_child(solid)
	PaintedFacadeKit.build(visual, style, Vector3(size.x, height_for(building.building_id, 0.0), size.y), solid, walk_in_x)
	return true

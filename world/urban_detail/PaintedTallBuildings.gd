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
	# Escritórios A/B/C (pacotes de 15/10, módulo 12 m, lateral 6 m): 10 m = térreo +
	# 1 andar + topo, como a CivicTower e abaixo da ExchangeTower. Caixa antiga tinha
	# 7,5 m (só térreo + topo, sem o andar que repete). Interruptor próprio para A/B:
	# GETECO_PAINTED_OFFICES=0 devolve só estes três às caixas assadas.
	# "max_stretch": o lote tem 14,4-16,3 m e o kit esticaria o módulo de 12 m inteiro
	# (até 1,35x), levando junto a porta pintada: a de A (1,5 m) passava de 1,8 m e
	# virava porta dupla. Acima de 1,15x o prédio fica com 13,8 m (catálogo, interior e
	# fábrica usam a mesma largura, como nos prédios de PaintedHarborHouses.HARBOR).
	"BridgeCourtEast": {"style": "escritorio-a", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
	"NorthFrontage5": {"style": "escritorio-b", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
	"NorthbankFront2": {"style": "escritorio-c", "height": 10.0, "switch": "GETECO_PAINTED_OFFICES", "max_stretch": 1.15},
}


static func enabled() -> bool:
	return PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_TALL") != "0"


## Estilo alto do prédio, ou "" (piloto desligado, id sem pacote ou estilo não importado).
static func style_for(building_id: String) -> String:
	if not enabled() or not TALL.has(building_id): return ""
	if OS.get_environment(str(TALL[building_id].get("switch", ""))) == "0": return ""
	var style: String = TALL[building_id].style
	return style if PaintedFacadeKit.is_tall(style) else ""


## Largura do prédio alto com "max_stretch": no máximo o módulo da frente vezes o
## fator; os demais (e o piloto desligado) ficam com `width`.
static func footprint_width(building_id: String, width: float) -> float:
	var style := style_for(building_id)
	if style.is_empty() or not TALL[building_id].has("max_stretch"): return width
	return minf(width, PaintedFacadeKit.natural_size(style).x * float(TALL[building_id].max_stretch))


## Altura da casca pintada acima da calçada (soma exata das peças menos o que o kit
## afunda até a soleira da porta); `fallback` quando não é prédio alto.
static func height_for(building_id: String, fallback: float) -> float:
	var style := style_for(building_id)
	if style.is_empty(): return fallback
	return float(PaintedFacadeKit.tall_layout(style, float(TALL[building_id].height)).height) - PaintedFacadeKit.tall_sink(style)


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

extends RefCounted
## Costa de Harbor (mundo orgânico, etapa 3, 26/10/2026), bairro por bairro. A terra de Harbor ainda são
## os retângulos da V1 mais a terra extra (porto sul, Lago Sereno). Cada bairro desta lista transforma em
## chão natural a parte da ilha da forma (world_shape.json) que fica dentro da zona dele: a faixa entre os
## retângulos e a costa curva. Esse chão entra no fim de NativeRegion.extra_land, então o chão físico,
## o mar de Harbor, os muros da costa, o mapa e o mar do mundo seguem juntos.
##
## A zona de cada bairro termina rente a um lado dos retângulos, para a costa nova encostar na terra de
## hoje sem deixar água presa. Atenção: a curva da forma passa por cima da bacia do porto entre os
## quarteirões (onde fica o navio). Por isso as zonas contornam a bacia, e o porto ainda não entra aqui:
## precisa de cais reto e da bacia recortada no gerador.
## GETECO_HARBOR_COAST=0 volta à terra de antes (A/B no mesmo export).
const SHAPE := preload("res://world/shape/WorldShape.gd")
const GROUND_CUT := preload("res://world/urban_detail/GroundCut.gd")
const BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
## Bairro -> zona (polígono x, z). Mata a oeste: tudo a oeste do lado leste da mata (x = −80), com o
## Lago Sereno e a mata da pesca.
##
## Baía norte: ao norte da cidade, da mata até o lado oeste da cabeceira da ponte norte (x = 356). Segue as
## bordas norte dos quarteirões (z = 0,6 e −6,2; z = −150 depois da bacia). A bacia do navio
## (x 200–273,8) fecha ao norte num cais reto em z = −6,2 e continua aberta para o mar pelo sul.
const DISTRICTS := {
	"west_woods": [Vector2(-2000, -2000), Vector2(-80, -2000), Vector2(-80, 2000), Vector2(-2000, 2000)],
	"north_bay": [Vector2(-80, -2000), Vector2(356, -2000), Vector2(356, -150), Vector2(273.8, -150), Vector2(273.8, -6.2),
		Vector2(-6.2, -6.2), Vector2(-6.2, 0.6), Vector2(-80, 0.6)],
}
## Água em volta da ponte norte, da cabeceira (z = −248) para o norte.
const NORTH_BRIDGE_CLEAR := Rect2(328.75, -600, 36.55, 352)
static var _enabled := -1
static var _land: Array[PackedVector2Array] = []
static var _prepared := false

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_HARBOR_COAST") == "0" else 1
	return _enabled == 1

## Chão natural novo de todos os bairros prontos (sobrepõe os retângulos; quem monta chão subtrai a
## terra que já existe).
static func natural_land() -> Array[PackedVector2Array]:
	if not enabled(): return []
	if _prepared: return _land
	_prepared = true
	var island := PackedVector2Array()
	for item in SHAPE.islands():
		if str(item.id) == "harbor": island = item.polygon
	if island.is_empty(): return _land
	for id in DISTRICTS:
		var zone := PackedVector2Array(DISTRICTS[id])
		# Zona simples recortando polígono simples: aqui não sai buraco, só pedaços.
		var pieces: Array[PackedVector2Array] = []
		for piece in Geometry2D.intersect_polygons(island, zone):
			if absf(_area(piece)) > 1.0: pieces.append(piece)
		# As pontes são donas do chão por baixo delas (rampa e boca do ramal norte): sem chão natural ali.
		# A coluna inteira da ponte norte depois da cabeceira fica livre: recortar só a pegada (mais estreita
		# que a caixa dela) deixava um gancho de terra contornando o começo da ponte.
		var bridges: Array[PackedVector2Array] = [GROUND_CUT.rect_polygon(NORTH_BRIDGE_CLEAR)]
		if BRIDGE.enabled(): bridges.append_array([BRIDGE.east_footprint(), BRIDGE.north_footprint()])
		pieces = GROUND_CUT.subtract_exact(pieces, bridges)
		for piece in pieces:
			if absf(_area(piece)) > 1.0: _land.append(piece)
	return _land

## Zona de algum bairro pronto contém o ponto (testes e divisas).
static func in_district(point: Vector2) -> bool:
	for id in DISTRICTS:
		if Geometry2D.is_point_in_polygon(point, PackedVector2Array(DISTRICTS[id])): return true
	return false

static func is_natural(polygon: PackedVector2Array) -> bool:
	return natural_land().has(polygon)

static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size(): total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return total * .5

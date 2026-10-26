extends RefCounted
## Costa de Harbor (mundo orgânico, etapa 3, 26/10/2026), bairro por bairro. A terra de Harbor ainda são
## os retângulos da V1 mais a terra extra (porto sul, Lago Sereno). Cada bairro desta lista transforma em
## chão natural a parte da ilha da forma (world_shape.json) que fica dentro da zona dele: a faixa entre os
## retângulos e a costa curva. Esse chão entra no fim de NativeRegion.extra_land, então o chão físico,
## o mar de Harbor, os muros da costa, o mapa e o mar do mundo seguem juntos.
##
## A zona de cada bairro termina rente a um lado dos retângulos, para a costa nova encostar na terra de
## hoje sem deixar água presa. Atenção: a curva da forma passa por cima da bacia do porto entre os
## quarteirões (onde fica o navio). Por isso o porto e as ruas ainda não entram aqui: cada um precisa de
## cais reto e da bacia recortada no gerador.
## GETECO_HARBOR_COAST=0 volta à terra de antes (A/B no mesmo export).
const SHAPE := preload("res://world/shape/WorldShape.gd")
## Bairro -> zona (polígono x, z). Mata a oeste: tudo a oeste do lado leste da mata (x = −80), com o
## Lago Sereno e a mata da pesca.
const DISTRICTS := {
	"west_woods": [Vector2(-2000, -2000), Vector2(-80, -2000), Vector2(-80, 2000), Vector2(-2000, 2000)],
}
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
		# Zona convexa recortando polígono simples: não sai buraco, só pedaços.
		for piece in Geometry2D.intersect_polygons(island, zone):
			if absf(_area(piece)) > 1.0: _land.append(piece)
	return _land

static func is_natural(polygon: PackedVector2Array) -> bool:
	return natural_land().has(polygon)

static func _area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	for i in polygon.size(): total += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return total * .5

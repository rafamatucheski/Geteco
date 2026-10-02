extends RefCounted
## Seleção ampla em células de 64 m; os predicados finais são os originais.
## Pertence à região via metadata e não guarda referência à própria região.

const CELL := 64.0
const MAX_ENTRY_CELLS := 64
var _geometry: RefCounted
var _revision := -1
var _roads: Dictionary
var _junctions: Dictionary
var _buildings: Dictionary


func matches_geometry(geometry: RefCounted) -> bool:
	return _geometry == geometry and _revision == (-1 if geometry == null else int(geometry.get("context_revision")))


func configure(geometry: RefCounted, buildings: Array) -> void:
	_geometry = geometry
	_revision = -1 if geometry == null else int(geometry.get("context_revision"))
	var roads: Array = []
	var road_bounds: Array[Rect2] = []
	var junctions: Array = []
	var junction_bounds: Array[Rect2] = []
	if geometry != null:
		roads = geometry.get("_roads").duplicate()
		for road in roads:
			var points: PackedVector2Array = road.points
			var bounds := Rect2(points[0], Vector2.ZERO)
			for point in points: bounds = bounds.expand(point)
			road_bounds.append(bounds.grow(float(road.width)))
		junctions = geometry.get("_junctions").duplicate()
		for junction in junctions:
			junction_bounds.append(Rect2(junction.position, Vector2.ZERO))
	var wrappers: Array = []
	var building_bounds: Array[Rect2] = []
	for building in buildings:
		var center := Vector2(building.position.x, building.position.z)
		var footprint := Rect2(center - building.size * 0.5, building.size)
		wrappers.append({"rect": footprint, "data": building})
		building_bounds.append(footprint.grow(4.0))
	_roads = _bucket(roads, road_bounds)
	_junctions = _bucket(junctions, junction_bounds)
	_buildings = _bucket(wrappers, building_bounds)


func query(grown: Rect2) -> Dictionary:
	return {"roads": _select(_roads, grown), "junctions": _select(_junctions, grown, true), "buildings": _select(_buildings, grown, false, true)}


static func _span(bounds: Rect2) -> Rect2i:
	var first := Vector2i(floori(bounds.position.x / CELL), floori(bounds.position.y / CELL))
	var last := Vector2i(floori(bounds.end.x / CELL), floori(bounds.end.y / CELL))
	return Rect2i(first, last - first + Vector2i.ONE)


static func _bucket(values: Array, bounds: Array[Rect2]) -> Dictionary:
	var cells := {}
	var overflow: Array[int] = []
	for ordinal in values.size():
		var span := _span(bounds[ordinal])
		# Limita a memória da grade a 64 referências por entrada.
		# Não é limite de conteúdo: overflow participa de todas as consultas.
		if span.size.x * span.size.y > MAX_ENTRY_CELLS:
			overflow.append(ordinal)
			continue
		for x in range(span.position.x, span.end.x):
			for y in range(span.position.y, span.end.y):
				var cell := Vector2i(x, y)
				if not cells.has(cell): cells[cell] = []
				cells[cell].append(ordinal)
	return {"values": values, "bounds": bounds, "cells": cells, "overflow": overflow}


static func _candidate_ordinals(bucket: Dictionary, grown: Rect2) -> Array:
	var span := _span(grown)
	var ordinals: Array = []
	if span.size.x * span.size.y > bucket.values.size():
		# Consulta ampla: não percorrer milhões de células vazias.
		ordinals = range(bucket.values.size())
	else:
		var seen := {}
		for ordinal in bucket.overflow: seen[ordinal] = true
		for x in range(span.position.x, span.end.x):
			for y in range(span.position.y, span.end.y):
				for ordinal in bucket.cells.get(Vector2i(x, y), []): seen[ordinal] = true
		ordinals = seen.keys()
		ordinals.sort()
	return ordinals


static func _select(bucket: Dictionary, grown: Rect2, points := false, wrappers := false) -> Array:
	var result: Array = []
	for ordinal in _candidate_ordinals(bucket, grown):
		var bounds: Rect2 = bucket.bounds[ordinal]
		if (grown.has_point(bounds.position) if points else bounds.intersects(grown)):
			var value = bucket.values[ordinal]
			result.append(value.duplicate() if wrappers else value)
	return result

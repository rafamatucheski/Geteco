extends RefCounted
## Printed street atlas from the same world coordinates used for navigation.
## Retained vector polygons, with no raster terrain, height facets or camera capture.
const WATER := Color("91a5a8")
const COAST := Color("667c7c")
const PALETTE := {"city":Color("d3d0c4"),"forest":Color("b7c1ac"),"mountain":Color("c9cdc3"),"desert":Color("dbcdb1"),"water":WATER}
var regions := {}
var polygons: Array[Dictionary] = []

func prepare(lands: Array) -> void:
	regions.clear()
	# Union adjacent city cells once, so their internal streaming seams never look
	# like coasts. This only changes the presentation copy, never the source lands.
	polygons = preload("res://ui/hud/MapRelief.gd").new()._presentation_lands(lands)
	for row in polygons:
		var points: PackedVector2Array = row.polygon
		if points.size()<3: continue
		var id: String = {"city":"harbor","forest":"harbor","mountain":"mountain","desert":"desert"}.get(row.biome,"")
		if id.is_empty(): continue
		var bounds := Rect2(points[0],Vector2.ZERO)
		for point in points: bounds=bounds.expand(point)
		regions[id]=regions[id].merge(bounds) if regions.has(id) else bounds

func draw_land(target: CanvasItem) -> void:
	# Water polygons always cover land; collection order must not fill lakes in.
	for water_pass in [false,true]:
		for row in polygons:
			if (row.biome=="water")!=water_pass or row.polygon.size()<3: continue
			target.draw_colored_polygon(row.polygon,PALETTE.get(row.biome,PALETTE.city))

func draw_ink(target: CanvasItem, factor: float) -> void:
	for row in polygons:
		if row.polygon.size()<3: continue
		var closed: PackedVector2Array=row.polygon.duplicate()
		closed.append(closed[0])
		target.draw_polyline(closed,COAST,1.0/factor,true)

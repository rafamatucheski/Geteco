extends RefCounted
## Atlas de ruas impresso a partir das mesmas coordenadas do mundo usadas na navegação.
## Polígonos vetoriais retidos, sem terreno raster, facetas de altura nem captura de câmera.
const WATER := Color("91a5a8")
const COAST := Color("667c7c")
const PALETTE := {"city":Color("d3d0c4"),"forest":Color("b7c1ac"),"mountain":Color("c9cdc3"),"desert":Color("dbcdb1"),"water":WATER}
var regions := {}
var polygons: Array[Dictionary] = []

func prepare(lands: Array) -> void:
	regions.clear()
	# Une as células vizinhas da cidade uma vez, para que as costuras internas do streaming nunca pareçam
	# costas. Isso só muda a cópia de apresentação, nunca as terras de origem.
	polygons = preload("res://ui/hud/MapRelief.gd").new()._presentation_lands(lands)
	for row in polygons:
		var points: PackedVector2Array = row.polygon
		if points.size()<3: continue
		var id: String = {"city":"harbor","forest":"harbor","mountain":"mountain","desert":"desert"}.get(row.biome,"")
		if id.is_empty(): continue
		var bounds := Rect2(points[0],Vector2.ZERO)
		for point in points: bounds=bounds.expand(point)
		regions[id]=regions[id].merge(bounds) if regions.has(id) else bounds

const SHALLOW := Color("a3bbba")
const SHALLOW_NEAR := Color("b4c9c6")

func draw_land(target: CanvasItem) -> void:
	# Faixa rasa em volta da terra (mundo orgânico, etapa 5), como a água clara da costa no jogo. Larguras
	# em metros do mundo: acompanha o zoom. A terra por cima esconde a metade de dentro.
	for ring in [[SHALLOW, 44.0], [SHALLOW_NEAR, 18.0]]:
		for row in polygons:
			if row.biome == "water" or row.polygon.size() < 3: continue
			var closed: PackedVector2Array = row.polygon.duplicate()
			closed.append(closed[0])
			target.draw_polyline(closed, ring[0], ring[1], true)
	# Polígonos de água sempre cobrem a terra; a ordem de coleta não pode preencher lagos.
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

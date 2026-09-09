@tool
class_name LayoutV2
extends Node2D

## Blockout visual V5. Esta é a planta de Rafael convertida em geometria fixa.
## O UnifiedRoadNetwork filho publica navegação invisível sobre estes mesmos
## eixos; a geometria desenhada aqui continua sendo a fonte visual da planta.

const GRASS := Color("294129")
const WATER := Color("354bc4")
const ROAD_EDGE := Color("b9b7ab")
const ROAD := Color("11151b")
const LOT := Color("ebe9e0")
const PORT := Color("85001b")
const PARK := Color("28b54b")

@export var debug_show_route_guides := false

const MARKER_POSITIONS := {
	"PlayerSpawn": Vector2(1120, 590), "TerminalStop": Vector2(1120, 590),
	"PortApproach": Vector2(1260, 365), "MarketEntrance": Vector2(455, 385),
	"ParkEntrance": Vector2(250, 600), "GarageEntrance": Vector2(270, 970),
	"PaintSprayEntrance": Vector2(790, 1430), "CobraEntrance": Vector2(930, 1010),
	"CemeteryIMLEntrance": Vector2(1550, 670), "RailUnderpass": Vector2(1250, 1210),
	"ExitDistrict2": Vector2(2330, 910), "WarehouseEntrance": Vector2(790, 1430),
	"ExitDistrict3": Vector2(1900, 760),
}

const BUILDABLE_LOTS := [
	{"id":"market", "rect":Rect2(350, 205, 210, 150)}, {"id":"port", "rect":Rect2(1220, 15, 430, 245)},
	{"id":"central", "rect":Rect2(560, 470, 190, 210)}, {"id":"homes_north", "rect":Rect2(850, 470, 150, 210)},
	{"id":"terminal", "rect":Rect2(1060, 500, 200, 180)}, {"id":"cemetery_iml", "rect":Rect2(1510, 440, 270, 560)},
	{"id":"garage", "rect":Rect2(20, 840, 200, 240)}, {"id":"police", "rect":Rect2(20, 1110, 200, 150)},
	{"id":"fire_station", "rect":Rect2(20, 1360, 200, 200)}, {"id":"cobra", "rect":Rect2(560, 1040, 650, 170)},
	{"id":"paint_spray", "rect":Rect2(650, 1330, 230, 230)}, {"id":"favela", "rect":Rect2(1320, 1310, 280, 190)},
]

func _ready() -> void:
	add_to_group("bairro1_v2_layout")
	_ensure_markers()
	queue_redraw()

func get_buildable_lots() -> Array:
	return BUILDABLE_LOTS.duplicate(true)

func get_alley_definitions() -> Dictionary:
	return {
		"beco_mercado": {"width":60.0, "segments":[PackedVector2Array([Vector2(560,410),Vector2(560,600),Vector2(750,600)])]},
		"beco_residencial": {"width":68.0, "segments":[PackedVector2Array([Vector2(770,790),Vector2(770,950),Vector2(1000,950)])]},
		"beco_cobra": {"width":56.0, "segments":[PackedVector2Array([Vector2(760,1020),Vector2(760,1210),Vector2(1120,1210)])]},
		"beco_cemiterio": {"width":64.0, "segments":[PackedVector2Array([Vector2(1450,900),Vector2(1380,900),Vector2(1380,1110)])]},
		"beco_favela": {"width":72.0, "segments":[PackedVector2Array([Vector2(1250,1300),Vector2(1320,1300),Vector2(1320,1500)])]},
	}

func get_pedestrian_routes() -> Array:
	var routes: Array = []
	for alley in get_alley_definitions().values():
		for segment in alley["segments"]:
			routes.append(segment)
	return routes

func get_road_graph_definitions() -> Array[Dictionary]:
	# Os pontos espelham exatamente as chamadas de _road_line() em _draw().
	# render=false evita desenhar uma segunda camada de asfalto sobre o blockout.
	return [
		{"id":"market_axis", "points":PackedVector2Array([Vector2(230,400),Vector2(1720,400)]), "width":132.0, "render":false, "open_start":true, "open_end":true},
		{"id":"central_axis", "points":PackedVector2Array([Vector2(250,720),Vector2(1650,720)]), "width":132.0, "render":false, "open_start":true, "open_end":true},
		{"id":"west_spine", "points":PackedVector2Array([Vector2(250,720),Vector2(250,1560)]), "width":80.0, "render":false, "open_end":true},
		{"id":"garage_spine", "points":PackedVector2Array([Vector2(520,720),Vector2(520,1260),Vector2(650,1260),Vector2(650,1560)]), "width":80.0, "render":false, "open_end":true},
		{"id":"cobra_spine", "points":PackedVector2Array([Vector2(1050,720),Vector2(1050,1260),Vector2(1250,1260),Vector2(1250,1560)]), "width":80.0, "render":false, "open_end":true},
		{"id":"cemetery_spur", "points":PackedVector2Array([Vector2(1450,720),Vector2(1450,1060),Vector2(1780,1060)]), "width":80.0, "render":false, "open_end":true},
		{"id":"port_access", "points":PackedVector2Array([Vector2(1260,400),Vector2(1260,285)]), "width":80.0, "render":false, "open_end":true},
		{"id":"district_exit", "points":PackedVector2Array([Vector2(1650,720),Vector2(1850,720),Vector2(1850,1040),Vector2(2380,1040)]), "width":148.0, "render":false, "open_end":true},
	]

func _ensure_markers() -> void:
	var holder := Node2D.new()
	holder.name = "Markers"
	add_child(holder)
	for id in MARKER_POSITIONS:
		var marker := Marker2D.new()
		marker.name = id
		marker.position = MARKER_POSITIONS[id]
		holder.add_child(marker)

func _draw() -> void:
	draw_rect(Rect2(0,0,2400,1600), GRASS)
	draw_rect(Rect2(0,0,2400,270), WATER)
	# Vegetação principal: parque oeste e massas verdes à direita/sul.
	draw_rect(Rect2(8,400,220,420), PARK)
	for green in [Rect2(250,430,170,260),Rect2(1840,450,260,530),Rect2(1880,1040,480,520),Rect2(900,1280,320,170)]:
		draw_rect(green, PARK.darkened(0.12))
	# Ruas: somente eixos que delimitam blocos. Borda clara e asfalto escuro.
	_road_line([Vector2(230,400),Vector2(1720,400)], 156.0)
	_road_line([Vector2(250,720),Vector2(1650,720)], 156.0)
	_road_line([Vector2(250,720),Vector2(250,1560)], 104.0)
	_road_line([Vector2(520,720),Vector2(520,1260),Vector2(650,1260),Vector2(650,1560)], 104.0)
	_road_line([Vector2(1050,720),Vector2(1050,1260),Vector2(1250,1260),Vector2(1250,1560)], 104.0)
	_road_line([Vector2(1450,720),Vector2(1450,1060),Vector2(1780,1060)], 104.0)
	_road_line([Vector2(1260,400),Vector2(1260,285)], 104.0)
	_road_line([Vector2(1650,720),Vector2(1850,720),Vector2(1850,1040),Vector2(2380,1040)], 172.0)
	# Blocos fixos: os prédios serão colocados dentro deles por Antigravity.
	for lot in BUILDABLE_LOTS:
		var rect: Rect2 = lot["rect"]
		var color := PORT if lot["id"] == "port" else LOT
		draw_rect(rect, color)
	# Estacionamento do terminal e canal de saída; nenhuma curva/circuito extra.
	draw_rect(Rect2(1280,500,180,180), Color("d8d6cd"))
	for x in range(1300,1440,35):
		draw_line(Vector2(x,525),Vector2(x,655),Color("8b8a84"),2.0)
	# Trem cenográfico: túnel no sul e viaduto contornando o cemitério.
	_rail_line([Vector2(0,1580),Vector2(220,1330),Vector2(650,1280),Vector2(1100,1220)], false)
	_rail_line([Vector2(1100,1220),Vector2(1300,1100),Vector2(1320,760),Vector2(1500,350),Vector2(1730,700),Vector2(2160,800)], true)

func _road_line(points: Array[Vector2], width: float) -> void:
	draw_polyline(PackedVector2Array(points), ROAD_EDGE, width, true)
	draw_polyline(PackedVector2Array(points), ROAD, width - 24.0, true)
	for index in range(points.size()-1):
		var a := points[index]
		var b := points[index+1]
		var length := a.distance_to(b)
		var direction := a.direction_to(b)
		for distance in range(28, int(length), 42):
			draw_line(a + direction * distance, a + direction * minf(distance + 18.0, length), Color("e6c844"), 3.0)

func _rail_line(points: Array[Vector2], elevated: bool) -> void:
	var color := Color("5f5d57") if elevated else Color("3f3d39")
	draw_polyline(PackedVector2Array(points), color, 24.0, true)
	if elevated:
		for point in points:
			draw_rect(Rect2(point + Vector2(-9,0),Vector2(18,60)),Color("77736b"))

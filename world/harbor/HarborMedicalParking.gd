@tool
extends Node2D
## An off-street medical yard. Bays, access markers and paving share coordinates.
const CLINIC_POSITION := Vector2(1800, 1530)
const AMBULANCE_STOP := CLINIC_POSITION + Vector2(185, 40)
const CORONER_STOP := CLINIC_POSITION + Vector2(185, -75)
const LOT := Rect2(1910, 1375, 235, 350)
const BAY_SIZE := Vector2(106, 58)
const RESERVE_STOP := Vector2(1985, 1668)
const ROAD_EDGE := 2145.0
const WALKWAY := Rect2(2127, 1375, 18, 350)

func _ready() -> void:
	z_index = 2
	# Raised islands stay outside the swept vehicle and patient corridors.
	for rect in _islands():
		var body := StaticBody2D.new()
		body.position = rect.get_center()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)

static func bay_rect(center: Vector2) -> Rect2:
	return Rect2(center - BAY_SIZE * .5, BAY_SIZE)

static func _islands() -> Array[Rect2]:
	return [Rect2(1940, 1382, 95, 16), Rect2(1940, 1706, 95, 12)]

func _draw() -> void:
	preload("res://world/harbor/UrbanGround.gd").paint(self,LOT,Color("b3b4aa"))
	preload("res://world/harbor/UrbanGround.gd").paint(self,Rect2(1910,1405,217,295),Color("424c50"),"asphalt")
	for y in [1509.0, 1620.0]:
		draw_line(Vector2(1912, y), Vector2(2124, y), Color("394347"), 1)
	for y in [1414.0, 1690.0]:
		draw_rect(Rect2(2052, y, 48, 5), Color("2b3539"))
		for x in range(2054, 2100, 5):
			draw_line(Vector2(x, y), Vector2(x, y+5), Color("747e7e"), 1)
	# Continuous public footway, with level crossings at the service gates.
	draw_rect(WALKWAY, Color("aeb3ae"))
	for y in range(1375, 1725, 22):
		draw_line(Vector2(2128, y), Vector2(2144, y), Color("919b98"), 1)
	for center in [CORONER_STOP, AMBULANCE_STOP, RESERVE_STOP]:
		var bay := bay_rect(center)
		draw_rect(bay, Color("4d595d"))
		draw_polyline(PackedVector2Array([
			Vector2(bay.end.x, bay.position.y), bay.position,
			Vector2(bay.position.x, bay.end.y), bay.end
		]), Color("e0e1cf"), 2.0, true)
		if center != AMBULANCE_STOP:
			draw_rect(Rect2(bay.position.x+7, center.y-17, 4, 34), Color("293437"))
			draw_rect(Rect2(bay.position.x+6, center.y-18, 3, 34), Color("c2c5b7"))
	# The central aisle remains entirely unparked, over two vehicle widths wide.
	for y in [1506.0, 1622.0]:
		_arrow(Vector2(2083, y), Vector2.DOWN)
	for y in [CORONER_STOP.y, AMBULANCE_STOP.y]:
		_arrow(Vector2(2100, y), Vector2.RIGHT)
		# Yield inside the property; the nose remains behind the street edge.
		for offset in [-21.0, -7.0, 7.0, 21.0]:
			draw_line(Vector2(2121, y+offset-4), Vector2(2121, y+offset+4), Color("e1ddc2"), 2)
		for x in [2130.0, 2138.0]:
			draw_line(Vector2(x, y-34), Vector2(x, y+34), Color("c6c9be"), 2)
	for ends in [Vector2(1375, 1418), Vector2(1492, 1533), Vector2(1607, 1725)]:
		draw_line(Vector2(2143, ends.x), Vector2(2143, ends.y), Color("e0e0d1"), 3)
	# HarborDistrict owns the public reception approach (ClinicAccess). Drawing
	# another slab and tile grid here put two sidewalk finishes on the same area.
	for island in _islands():
		draw_rect(Rect2(island.position+Vector2(2, 3), island.size), Color("343f3b"))
		draw_rect(island, Color("c7c9b9"))
		draw_rect(island.grow(-3), Color("546957"))
		for x in range(int(island.position.x)+9, int(island.end.x)-5, 13):
			draw_circle(Vector2(x, island.get_center().y), 4, Color("718069"))

func _arrow(center: Vector2, direction: Vector2) -> void:
	var tip := center + direction * 11
	var normal := direction.orthogonal()
	draw_line(center-direction*11, tip, Color("bdbb93"), 1.8, true)
	draw_polyline(PackedVector2Array([tip-direction*7+normal*5, tip, tip-direction*7-normal*5]), Color("bdbb93"), 1.8, true)

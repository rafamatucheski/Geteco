@tool
extends Node2D

## Divided northern highway: local return, east branch to Mountain Pass,
## and a closed straight continuation for the future northern region.
const INBOUND := Vector2(5880, -4200)
const OUTBOUND := Vector2(6120, -4200)
const ROAD_WIDTH := 96.0
const RETURN_ID := "RoadLayout/map2_temporary_return"
const WORKS := preload("res://world/harbor/HarborGatewayWorks.gd")
const DIRECTION_SIGNS := [
	{"name": "MountainSign", "bounds": Rect2(6370, -2365, 230, 68), "title": "SERRA DA NEVASCA", "detail": "SAÍDA À DIREITA / PONTE", "direction": Vector2.RIGHT},
	{"name": "BreakwaterSign", "bounds": Rect2(5600, -2340, 164, 62), "title": "BREAKWATER", "detail": "CENTRO / PORTO", "direction": Vector2.DOWN},
	{"name": "ReturnSign", "bounds": Rect2(5948, -3996, 104, 56), "title": "RETORNO", "detail": "NORTE EM OBRAS", "direction": Vector2.DOWN, "uturn": true},
]


func _ready() -> void:
	z_index = 3
	_create_direction_sign_collisions()
	if not has_node("Works"):
		var works := WORKS.new()
		works.name = "Works"
		works.z_as_relative = false
		add_child(works)
	for definition in [{"name": "Map2Inbound", "position": INBOUND}, {"name": "Map2Outbound", "position": OUTBOUND}]:
		if not has_node(NodePath(String(definition.name))):
			var marker := Marker2D.new()
			marker.name = String(definition.name)
			marker.position = definition.position
			add_child(marker)
	if not has_node("MountainConnector"):
		var connector := preload("res://world/harbor/HarborMountainConnector.gd").new()
		connector.name = "MountainConnector"
		connector.z_as_relative = false
		add_child(connector)
	queue_redraw()


func get_map2_connection_contract() -> Dictionary:
	return {
		"destination": "mountain_pass", "connected": true,
		"status": "mountain_east_with_reserved_north",
		"inbound": {"position": to_global(INBOUND), "direction": Vector2.DOWN, "width": ROAD_WIDTH, "lane_count": 2, "road_id": "RoadLayout/map2_highway_inbound", "marker": NodePath("Map2Inbound")},
		"outbound": {"position": to_global(OUTBOUND), "direction": Vector2.UP, "width": ROAD_WIDTH, "lane_count": 2, "road_id": "RoadLayout/map2_highway_outbound", "marker": NodePath("Map2Outbound")},
		"temporary_return_road_id": RETURN_ID,
		"continuous": true,
		"seam_position": Vector2(7300,-4560),
		"transition_scene": "",
	}


func _draw() -> void:
	# Median is limited to the 144px asphalt-to-asphalt gap. It stops 180px
	# before both junction rows, keeping generated turn connectors untouched.
	var median := Rect2(5930, -4020, 140, 1840)
	draw_rect(median, Color("#687b60"))
	draw_rect(median.grow(-7), Color("#79886b"))
	for y in range(-3960, -2210, 120):
		draw_line(Vector2(5997, y), Vector2(5997, y + 40), Color("#9b9e7b"), 2)
		draw_line(Vector2(6003, y + 25), Vector2(6003, y + 60), Color("#566b59"), 2)
	for x in [5880.0, 6120.0]:
		# Replace only the inherited yellow centre dashes in this single-direction
		# carriageway's uninterrupted span; white dashes separate its two lanes.
		draw_line(Vector2(x, -4040), Vector2(x, -2160), Color("#202932"), 6.0)
		for y in range(-4025, -2175, 56):
			draw_line(Vector2(x, y), Vector2(x, y + 30), Color("#e8e5ce"), 2.2)
		for side in [-1.0, 1.0]:
			var outside_mouth: bool = (x < 6000 and side < 0) or (x > 6000 and side > 0)
			var start_y := (-3940.0 if x < 6000 else -3850.0) if outside_mouth else -4040.0
			draw_line(Vector2(x + side * 43, start_y), Vector2(x + side * 43, -2160), Color("#e8e5ce"), 2)
		for y in [-3800.0, -3350.0, -2900.0, -2450.0]:
			for offset in [-22.0, 22.0]:
				_draw_lane_arrow(Vector2(x + offset, y), Vector2.DOWN if x < 6000.0 else Vector2.UP)
	# Compact solid boards stay outside the asphalt and the return connectors.
	for definition in DIRECTION_SIGNS:
		_draw_direction_sign(definition)


func _draw_lane_arrow(center: Vector2, forward: Vector2) -> void:
	var side := forward.orthogonal()
	draw_line(center - forward * 17, center + forward * 10, Color("#ece7d1"), 3)
	draw_colored_polygon(PackedVector2Array([center + forward * 20, center + forward * 8 + side * 7, center + forward * 8 - side * 7]), Color("#ece7d1"))


func _create_direction_sign_collisions() -> void:
	for definition in DIRECTION_SIGNS:
		if has_node(NodePath(definition.name)):
			continue
		var bounds: Rect2 = definition.bounds
		var body := StaticBody2D.new()
		body.name = definition.name
		body.position = bounds.position
		body.collision_layer = 1
		body.collision_mask = 0
		# Match the visible panel and both supports; shadows remain non-solid.
		var footprints: Array[Rect2] = [Rect2(Vector2.ZERO, bounds.size)]
		for fraction in [0.2, 0.8]:
			footprints.append(Rect2(bounds.size.x * fraction - 6, bounds.size.y, 12, 15))
		for footprint in footprints:
			var shape := RectangleShape2D.new()
			shape.size = footprint.size
			var collider := CollisionShape2D.new()
			collider.position = footprint.get_center()
			collider.shape = shape
			body.add_child(collider)
		add_child(body)


func _draw_direction_sign(definition: Dictionary) -> void:
	var bounds: Rect2 = definition.bounds
	for fraction in [0.2, 0.8]:
		var foot := bounds.position + Vector2(bounds.size.x * fraction, bounds.size.y)
		draw_rect(Rect2(foot + Vector2(-6, 8), Vector2(12, 7)), Color("#555f5e"))
		draw_rect(Rect2(foot + Vector2(-3, -2), Vector2(6, 14)), Color("#85908d"))
		draw_line(foot + Vector2(-2, 0), foot + Vector2(-2, 11), Color("#bdc5bb"), 1)
	draw_rect(Rect2(bounds.position + Vector2(3, 4), bounds.size), Color(0.02, 0.05, 0.06, 0.28))
	draw_rect(bounds, Color("#414f50"))
	draw_rect(bounds.grow(-2), Color("#a4b3ac"))
	draw_rect(bounds.grow(-4), Color("#214947"))
	draw_rect(bounds.grow(-7), Color("#dde2cc"), false, 1)
	draw_line(bounds.position + Vector2(9, 9), bounds.position + Vector2(bounds.size.x - 9, 9), Color("#3a6260"), 1)
	var is_return := bool(definition.get("uturn", false))
	var text_width := bounds.size.x - (45.0 if is_return else 55.0)
	var detail_width := bounds.size.x - 26.0 if is_return else text_width
	var font := ThemeDB.fallback_font
	var title_size := 17
	while font.get_string_size(definition.title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x > text_width and title_size > 10:
		title_size -= 1
	var detail_size := 11
	while font.get_string_size(definition.detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size).x > detail_width and detail_size > 8:
		detail_size -= 1
	draw_string(font, bounds.position + Vector2(13, 28), definition.title, HORIZONTAL_ALIGNMENT_LEFT, text_width, title_size, Color("#f0efda"))
	draw_string(font, bounds.position + Vector2(13, 46), definition.detail, HORIZONTAL_ALIGNMENT_LEFT, detail_width, detail_size, Color("#cbd8c8"))
	if is_return:
		# U-turn symbol beside the heading, with the works notice below it.
		var origin := bounds.position + Vector2(bounds.size.x - 24, 18)
		draw_polyline(PackedVector2Array([origin + Vector2(12, 11), origin + Vector2(12, 3), origin + Vector2(9, 0), origin + Vector2(3, 0), origin + Vector2(0, 3), origin + Vector2(0, 8)]), Color("#f0efda"), 2, true)
		draw_colored_polygon(PackedVector2Array([origin + Vector2(0, 13), origin + Vector2(-4, 6), origin + Vector2(4, 6)]), Color("#f0efda"))
	else:
		_draw_sign_arrow(bounds, definition.direction)
	for corner in [Vector2(5, 5), Vector2(bounds.size.x - 5, 5), Vector2(5, bounds.size.y - 5), bounds.size - Vector2(5, 5)]:
		draw_circle(bounds.position + corner, 1.2, Color("#dae0d6"))


func _draw_sign_arrow(bounds: Rect2, forward: Vector2) -> void:
	var arrow_center := bounds.position + Vector2(bounds.size.x - 26, bounds.size.y * 0.5)
	var side := forward.orthogonal()
	draw_line(arrow_center - forward * 9, arrow_center + forward * 8, Color("#f0efda"), 3)
	draw_colored_polygon(PackedVector2Array([arrow_center + forward * 13, arrow_center + forward * 3 + side * 7, arrow_center + forward * 3 - side * 7]), Color("#f0efda"))


func _draw_sign(bounds: Rect2, title: String, detail: String, title_size: int, detail_size: int = 12) -> void:
	draw_rect(Rect2(bounds.position + Vector2(4, 5), bounds.size), Color(0.02, 0.08, 0.08, 0.3))
	draw_rect(bounds, Color("#244c4c"))
	draw_rect(bounds.grow(-4), Color("#ccd3bd"), false, 2)
	draw_string(ThemeDB.fallback_font, bounds.position + Vector2(12, title_size + 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color("#f4ead0"))
	draw_string(ThemeDB.fallback_font, bounds.position + Vector2(12, title_size + 36), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, Color("#d5d8bd"))

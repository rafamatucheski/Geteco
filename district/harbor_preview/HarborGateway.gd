@tool
extends Node2D

## Divided northern highway: local return, east branch to Mountain Pass,
## and a closed straight continuation for the future northern region.
const INBOUND := Vector2(5880, -4200)
const OUTBOUND := Vector2(6120, -4200)
const ROAD_WIDTH := 96.0
const RETURN_ID := "RoadLayout/map2_temporary_return"
const WORKS := preload("res://district/harbor_preview/HarborGatewayWorks.gd")


func _ready() -> void:
	z_index = 3
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
		var connector := preload("res://district/harbor_preview/HarborMountainConnector.gd").new()
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
			draw_line(Vector2(x + side * 43, -4040), Vector2(x + side * 43, -2160), Color("#e8e5ce"), 2)
		for y in [-3800.0, -3350.0, -2900.0, -2450.0]:
			for offset in [-22.0, 22.0]:
				_draw_lane_arrow(Vector2(x + offset, y), Vector2.DOWN if x < 6000.0 else Vector2.UP)
	# Sign boards remain outside asphalt and below actor z-indices. They have
	# no collision bodies and cannot block the local north-end return.
	# Construction and locked gates replace the giant board over this area.
	_draw_sign(Rect2(6300, -2390, 400, 104), "SERRA DA NEVASCA", "SAIDA A DIREITA  /  PONTE", 24)
	_draw_sign(Rect2(5550, -2350, 235, 80), "BREAKWATER", "CENTRO / PORTO", 20)
	# A north-end return sign is inside the central island, clear of both lanes.
	_draw_sign(Rect2(5940, -4000, 120, 76), "RETORNO", "NORTE EM OBRAS", 15)


func _draw_lane_arrow(center: Vector2, forward: Vector2) -> void:
	var side := forward.orthogonal()
	draw_line(center - forward * 17, center + forward * 10, Color("#ece7d1"), 3)
	draw_colored_polygon(PackedVector2Array([center + forward * 20, center + forward * 8 + side * 7, center + forward * 8 - side * 7]), Color("#ece7d1"))


func _draw_sign(bounds: Rect2, title: String, detail: String, title_size: int, detail_size: int = 12) -> void:
	draw_rect(Rect2(bounds.position + Vector2(4, 5), bounds.size), Color(0.02, 0.08, 0.08, 0.3))
	draw_rect(bounds, Color("#244c4c"))
	draw_rect(bounds.grow(-4), Color("#ccd3bd"), false, 2)
	draw_string(ThemeDB.fallback_font, bounds.position + Vector2(12, title_size + 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color("#f4ead0"))
	draw_string(ThemeDB.fallback_font, bounds.position + Vector2(12, title_size + 36), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, detail_size, Color("#d5d8bd"))

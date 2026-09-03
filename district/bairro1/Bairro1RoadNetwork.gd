@tool
class_name Bairro1RoadNetwork
extends Node2D

## Eastern and southern street expansion for Bairro 1.
##
## This is deliberately a separate module from Bairro1Expansion: the original
## lots stay fixed, while this authored road graph reserves two honest exits
## for later boroughs.  It does not publish traffic paths yet; a vehicle route
## that ends at an unopened borough would force the AI to perform a fake U-turn.

const ROAD_COLOR := Color("#202932")
const ROAD_EDGE := Color("#151c23")
const SIDEWALK := Color("#aaa9a1")
const CURB := Color("#70767a")
const LANE := Color("#dfc84d")
const VERGE := Color("#4b5555")
const ROAD_WIDTH := 164.0
const SERVICE_WIDTH := 108.0
const SIDEWALK_MARGIN := 42.0

static var COASTAL_EXIT := PackedVector2Array([
	Vector2(2450, 2140), Vector2(2700, 2140), Vector2(2950, 2180),
	Vector2(3200, 2250), Vector2(3450, 2260),
])
static var PORT_SERVICE := PackedVector2Array([
	Vector2(2450, 2950), Vector2(2650, 2900), Vector2(2880, 2820),
	Vector2(3020, 2650), Vector2(3010, 2420), Vector2(2920, 2220),
])
static var SOUTHERN_RING := PackedVector2Array([
	Vector2(2450, 3040), Vector2(2535, 3230), Vector2(2490, 3415),
	Vector2(2320, 3560), Vector2(2070, 3650), Vector2(1810, 3610),
	Vector2(1600, 3535), Vector2(1480, 3500),
])
static var WATERFRONT_SERVICE := PackedVector2Array([
	Vector2(2880, 2820), Vector2(3150, 3020), Vector2(3420, 2900),
	Vector2(3500, 2620), Vector2(3430, 2360), Vector2(3280, 2220),
])

# Pontos autorais persistidos na cena. No editor, cada ponto vira um Marker2D
# arrastável; não existe mais uma estrada "presa" em constantes de código.
@export_group("Editar ruas atuais")
@export var render_legacy_roads: bool = true:
	set(value):
		render_legacy_roads = value
		queue_redraw()
@export var coastal_exit_points: PackedVector2Array = COASTAL_EXIT
@export var port_service_points: PackedVector2Array = PORT_SERVICE
@export var southern_ring_points: PackedVector2Array = SOUTHERN_RING
@export var waterfront_service_points: PackedVector2Array = WATERFRONT_SERVICE
@export_range(48.0, 360.0, 2.0) var arterial_width: float = ROAD_WIDTH:
	set(value):
		arterial_width = value
		_build_roads()
		queue_redraw()
@export_range(32.0, 240.0, 2.0) var service_road_width: float = SERVICE_WIDTH:
	set(value):
		service_road_width = value
		_build_roads()
		queue_redraw()

var _roads: Dictionary = {}

func _ready() -> void:
	name = "Bairro1RoadNetwork"
	z_index = 1
	_build_roads()
	if Engine.is_editor_hint():
		_ensure_editor_road_points()
		queue_redraw()
		return
	_create_connection_markers()
	if not _uses_unified_junction_controls():
		_create_intersection_controls()
	# Validation must run regardless of legacy rendering: it is the graph
	# integrity check, not a visual toggle, and disabling it here previously
	# let a stale assert (port_service endpoint) go uncaught.
	_validate_network()
	queue_redraw()
	add_to_group("bairro1_road_network")
	print("BAIRRO1_ROAD_NETWORK_READY: coastal arterial, harbor service ring, 2 future borough exits")

func _uses_unified_junction_controls() -> bool:
	var composition_root := get_parent()
	if composition_root == null:
		return false
	for sibling in composition_root.get_children():
		if sibling == self:
			continue
		if sibling.is_in_group("junction_traffic_controller") or String(sibling.name) in ["UnifiedRoadNetwork", "JunctionTrafficController"]:
			return true
	return false

## The original accessor remains responsible for active ambient traffic.  New
## streets are visually and physically connected but remain reservation-only
## until District 2/3 provides a continuation past its respective marker.
func get_future_connections() -> Array[Dictionary]:
	return [
		{
			"label": "DISTRITO_2_SUL", "position": Vector2(1480, 3500),
			"forward": Vector2(0.18, 0.98).normalized(), "road_width": ROAD_WIDTH,
			"destination": "fazendas_deserto", "status": "reserved"},
		{
			"label": "DISTRITO_3_COSTA", "position": Vector2(3300, 2260),
			"forward": Vector2(0.98, -0.08).normalized(), "road_width": ROAD_WIDTH,
			"destination": "costa_floresta", "status": "reserved"},
	]

func _build_roads() -> void:
	_roads = {
		"coastal_exit": {"points": _catmull_rom(coastal_exit_points, 8), "width": arterial_width},
		"port_service": {"points": _catmull_rom(port_service_points, 7), "width": service_road_width},
		"southern_ring": {"points": _catmull_rom(southern_ring_points, 8), "width": arterial_width},
		"waterfront_service": {"points": _catmull_rom(waterfront_service_points, 7), "width": service_road_width},
	}

func _ensure_editor_road_points() -> void:
	if get_node_or_null("RoadControlPoints") != null:
		return
	var controls := Node2D.new()
	controls.name = "RoadControlPoints"
	add_child(controls)
	var edited_root := get_tree().edited_scene_root
	if edited_root != null:
		controls.owner = edited_root
	var sets := {
		"coastal_exit": coastal_exit_points, "port_service": port_service_points,
		"southern_ring": southern_ring_points, "waterfront_service": waterfront_service_points,
	}
	for road_id in sets:
		var points: PackedVector2Array = sets[road_id]
		for index in points.size():
			var marker := Marker2D.new()
			marker.name = "%s_%02d" % [String(road_id).capitalize(), index + 1]
			marker.position = points[index]
			marker.set_meta("road_id", road_id)
			marker.set_meta("point_index", index)
			controls.add_child(marker)
			if edited_root != null:
				marker.owner = edited_root

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	var controls := get_node_or_null("RoadControlPoints") as Node2D
	if controls == null:
		return
	var changed := false
	for marker in controls.get_children():
		if marker is Marker2D:
			changed = _apply_editor_point(marker as Marker2D) or changed
	if changed:
		_build_roads()
		queue_redraw()

func _apply_editor_point(marker: Marker2D) -> bool:
	var road_id := String(marker.get_meta("road_id", ""))
	var point_index := int(marker.get_meta("point_index", -1))
	var points := _get_edit_points(road_id)
	if point_index < 0 or point_index >= points.size() or points[point_index].is_equal_approx(marker.position):
		return false
	points[point_index] = marker.position
	_set_edit_points(road_id, points)
	return true

func _get_edit_points(road_id: String) -> PackedVector2Array:
	match road_id:
		"coastal_exit": return coastal_exit_points.duplicate()
		"port_service": return port_service_points.duplicate()
		"southern_ring": return southern_ring_points.duplicate()
		"waterfront_service": return waterfront_service_points.duplicate()
	return PackedVector2Array()

func _set_edit_points(road_id: String, points: PackedVector2Array) -> void:
	match road_id:
		"coastal_exit": coastal_exit_points = points
		"port_service": port_service_points = points
		"southern_ring": southern_ring_points = points
		"waterfront_service": waterfront_service_points = points

func _two_way_lane_definitions(road_width: float) -> Array[Dictionary]:
	var lane_offset := road_width * 0.25
	return [
		{"lane_id": "forward_01", "offset": lane_offset, "direction": 1, "direction_name": "forward"},
		{"lane_id": "reverse_01", "offset": -lane_offset, "direction": -1, "direction_name": "reverse"},
	]

func get_road_graph_definitions() -> Array[Dictionary]:
	var arterial_lanes := _two_way_lane_definitions(arterial_width)
	var service_lanes := _two_way_lane_definitions(service_road_width)
	return [
		{"id": "coastal_exit", "points": coastal_exit_points, "width": arterial_width, "lanes": arterial_lanes, "snap_start": "Bairro1Expansion/east_arc", "open_end": true},
		{"id": "port_service", "points": port_service_points, "width": service_road_width, "lanes": service_lanes, "snap_start": "Bairro1Expansion/east_arc", "snap_start_mode": "perpendicular", "snap_end": "Bairro1RoadNetwork/coastal_exit", "snap_end_mode": "perpendicular"},
		{"id": "southern_ring", "points": southern_ring_points, "width": arterial_width, "lanes": arterial_lanes, "snap_start": "Bairro1Expansion/east_arc", "snap_end": "Bairro1Expansion/gateway_spine", "snap_end_mode": "tangent"},
		{"id": "waterfront_service", "points": waterfront_service_points, "width": service_road_width, "lanes": service_lanes, "snap_start": "Bairro1RoadNetwork/port_service", "snap_start_mode": "perpendicular", "snap_end": "Bairro1RoadNetwork/coastal_exit", "snap_end_mode": "perpendicular"},
	]

func _create_connection_markers() -> void:
	for connection in get_future_connections():
		var marker := Marker2D.new()
		marker.name = String(connection.label)
		marker.position = connection.position
		# ProgressionConnections owns the actual gameplay hand-off markers.  This
		# visual road module exposes only its own informational reservation group.
		marker.add_to_group("bairro1_future_connection")
		marker.set_meta("from_district", 1)
		marker.set_meta("connection_label", connection.label)
		marker.set_meta("destination", connection.destination)
		marker.set_meta("reserved", true)
		add_child(marker)

func _create_intersection_controls() -> void:
	# Signals mark the two new junctions where a driver decides whether to stay
	# in Bairro 1 or take a future district exit.  They use simple built-in
	# geometry, avoiding a second traffic manager before the destinations exist.
	var controls := Node2D.new()
	controls.name = "ExpansionSignals"
	controls.z_index = 12
	add_child(controls)
	for data in [
		{"name": "CoastalSplit", "position": Vector2(2450, 2140)},
		{"name": "HarborRing", "position": Vector2(2450, 3040)},
		{"name": "ServiceJunction", "position": Vector2(2860, 2830)},
	]:
		var signal_node := _make_signal(String(data.name))
		signal_node.position = data.position
		controls.add_child(signal_node)

func _make_signal(signal_name: String) -> Node2D:
	var root := Node2D.new()
	root.name = signal_name
	for offset in [Vector2(-95, -95), Vector2(95, -95), Vector2(-95, 95), Vector2(95, 95)]:
		var post := Line2D.new()
		post.points = PackedVector2Array([offset + Vector2(0, 14), offset + Vector2(0, -15)])
		post.width = 4.0
		post.default_color = Color("#252b2c")
		root.add_child(post)
		var head := Polygon2D.new()
		head.polygon = PackedVector2Array([
			offset + Vector2(-6, -22), offset + Vector2(6, -22),
			offset + Vector2(6, -7), offset + Vector2(-6, -7),
		])
		head.color = Color("#1a2023")
		root.add_child(head)
		var lens := Polygon2D.new()
		lens.polygon = PackedVector2Array([
			offset + Vector2(-2.5, -18), offset + Vector2(2.5, -18),
			offset + Vector2(2.5, -13), offset + Vector2(-2.5, -13),
		])
		lens.color = Color("#e85845") if offset.x < 0.0 else Color("#54bb66")
		root.add_child(lens)
	return root

func _validate_network() -> void:
	# Exact shared endpoints are intentional interchanges, not visual near-misses.
	assert(_roads.coastal_exit.points[0].distance_to(Vector2(2450, 2140)) < 1.0, "Coastal exit no longer joins Bairro 1")
	assert(_roads.port_service.points[0].distance_to(Vector2(2450, 2950)) < 1.0, "Port service road no longer joins Bairro 1")
	assert(_roads.southern_ring.points[0].distance_to(Vector2(2450, 3040)) < 1.0, "Southern ring no longer joins port service")
	assert(_roads.southern_ring.points[-1].distance_to(Vector2(1480, 3500)) < 1.0, "Southern ring no longer joins highway hand-off")
	assert(get_future_connections().size() == 2, "Bairro 1 must expose exactly two future borough exits")

func _draw() -> void:
	# The outer road district is a shaped verge rather than empty grey map.
	draw_rect(Rect2(2380, 1940, 980, 1760), VERGE)
	if render_legacy_roads:
		for road in _roads.values():
			var points: PackedVector2Array = road.points
			var width: float = road.width
			draw_polyline(points, SIDEWALK, width + SIDEWALK_MARGIN * 2.0, true)
			draw_polyline(points, CURB, width + 10.0, true)
			draw_polyline(points, ROAD_EDGE, width + 4.0, true)
			draw_polyline(points, ROAD_COLOR, width, true)
			_draw_center_marks(points, width)
	_draw_exit_sign(Vector2(3165, 2170), "COSTA / DISTRITO 3", -0.08)
	_draw_exit_sign(Vector2(1645, 3570), "SUL / DISTRITO 2", 0.24)

func _draw_center_marks(points: PackedVector2Array, width: float) -> void:
	var dash_color := LANE if width >= 140.0 else Color("#c7b65a")
	for index in range(0, points.size() - 1, 2):
		draw_line(points[index], points[index + 1], dash_color, 3.0, true)

func _draw_exit_sign(at: Vector2, label: String, angle: float) -> void:
	var tangent := Vector2.RIGHT.rotated(angle)
	var normal := tangent.orthogonal()
	draw_line(at - normal * 34.0, at + normal * 34.0, Color("#374244"), 5.0, true)
	draw_rect(Rect2(at - Vector2(58, 21), Vector2(116, 30)), Color("#215245"))
	draw_rect(Rect2(at - Vector2(58, 21), Vector2(116, 30)), Color("#d9dfd6"), false, 2.0)
	draw_string(ThemeDB.fallback_font, at + Vector2(-50, -1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#f2f0dd"))

func _catmull_rom(control: PackedVector2Array, subdivisions: int) -> PackedVector2Array:
	var sampled := PackedVector2Array()
	for index in range(control.size() - 1):
		var p0 := control[maxi(0, index - 1)]
		var p1 := control[index]
		var p2 := control[index + 1]
		var p3 := control[mini(control.size() - 1, index + 2)]
		for step in subdivisions:
			var t := float(step) / float(subdivisions)
			var t2 := t * t
			var t3 := t2 * t
			sampled.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	sampled.append(control[-1])
	return sampled

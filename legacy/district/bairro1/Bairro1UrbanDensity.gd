@tool
class_name Bairro1UrbanDensity
extends Node2D

## Authored visual infill for Bairro 1.  This is intentionally a separate
## module from Bairro1Expansion: it does not own roads, traffic paths, or
## pedestrian paths.  Every solid addition is screened against the expansion's
## road ribbons, rail corridor and existing lots before it is instantiated.

const BUILDING_SCRIPT := preload("res://geodata/ProceduralBuilding.gd")
const DISTRICT_BOUNDS := Rect2(0, 1280, 2400, 2200)
static var RAIL_CORRIDOR := PackedVector2Array([
	Vector2(-260, 1620), Vector2(80, 1640), Vector2(390, 1645),
	Vector2(690, 1660), Vector2(910, 1738), Vector2(1190, 1768),
	Vector2(1490, 1740), Vector2(1760, 1662), Vector2(2020, 1618),
	Vector2(2300, 1652), Vector2(2630, 1758), Vector2(2920, 1800),
])

const INFILL_CANDIDATES: Array[Dictionary] = [
	# Small secondary lots in pockets left between the authored blocks.  Some
	# candidates are deliberately conservative; the runtime safety check makes
	# an unsuitable lot disappear rather than ever spill onto a pavement.
	{"id": "CornerKiosk", "kind": "corner_shop", "rect": Rect2(724, 1804, 104, 116), "seed": 401},
	{"id": "LedgerHouse", "kind": "office", "rect": Rect2(748, 2868, 150, 102), "seed": 402},
	{"id": "TinWorks", "kind": "warehouse", "rect": Rect2(790, 2818, 138, 84), "seed": 403},
	{"id": "CanalGarage", "kind": "garage", "rect": Rect2(1162, 3076, 92, 128), "seed": 404},
	{"id": "HarborOffice", "kind": "office", "rect": Rect2(1280, 3120, 114, 144), "seed": 405},
	{"id": "DockMarket", "kind": "corner_shop", "rect": Rect2(1492, 3024, 94, 104), "seed": 406},
	{"id": "ShedRow", "kind": "warehouse", "rect": Rect2(2135, 2832, 168, 112), "seed": 407},
	{"id": "SouthKiosk", "kind": "shop", "rect": Rect2(232, 2855, 132, 94), "seed": 408},
	# Park pavilions occupy service-free interior ground within already authored
	# plazas, so they add destinations without narrowing a public sidewalk.
	{"id": "UnionPavilion", "kind": "corner_shop", "rect": Rect2(300, 3280, 118, 72), "seed": 409, "inside_park": true},
	{"id": "HarborPavilion", "kind": "shop", "rect": Rect2(2056, 1875, 104, 60), "seed": 410, "inside_park": true},
]

var _expansion: Node2D
var _safe_infill: Array[Dictionary] = []

func _ready() -> void:
	name = "Bairro1UrbanDensity"
	z_index = 21
	if Engine.is_editor_hint():
		_expansion = get_parent().get_node_or_null("Bairro1Expansion") as Node2D
		queue_redraw()
		return
	call_deferred("_build_density")

func _build_density() -> void:
	_expansion = get_parent().get_node_or_null("Bairro1Expansion") as Node2D
	if _expansion == null:
		push_warning("Bairro1UrbanDensity needs Bairro1Expansion; density skipped")
		return
	var rejected: Array[String] = []
	for candidate in INFILL_CANDIDATES:
		var lot_rect: Rect2 = candidate.rect
		if _infill_is_clear(candidate):
			_safe_infill.append(candidate)
			_spawn_infill(candidate)
		else:
			rejected.append(String(candidate.id))
	queue_redraw()
	print("BAIRRO1_URBAN_DENSITY_READY: %d safe infill lots, detailed roofs/courts/plazas" % _safe_infill.size())
	if not rejected.is_empty():
		# A rejected lot used to vanish with zero trace, which made "a
		# building disappeared" impossible to diagnose without opening the
		# editor and eyeballing every rect against the current road curves.
		# Authored road points move (markers get dragged, snapped roads get
		# edited) more often than authored lots do, so a lot that was safe
		# yesterday can silently start failing today. Surface it instead.
		push_warning("Bairro1UrbanDensity: %d infill lot(s) skipped as unsafe (too close to a road/lot/rail, or out of bounds): %s" % [rejected.size(), ", ".join(rejected)])

func _infill_is_clear(data: Dictionary) -> bool:
	var rect: Rect2 = data.rect
	# All existing fixed lots are solid, including their surrounding service
	# setback.  This prevents a new wing from consuming a sidewalk between lots.
	var existing_lots: Array = _expansion.get("lots") as Array
	for existing in existing_lots:
		var existing_rect: Rect2 = existing.rect
		if not rect.grow(18.0).intersects(existing_rect.grow(6.0)):
			continue
		# A compact pavilion is allowed only inside a designated existing park;
		# everything else keeps the normal no-overlap rule.
		if bool(data.get("inside_park", false)) and String(existing.kind) == "park" and existing_rect.encloses(rect.grow(8.0)):
			continue
		return false
	var road_map: Dictionary = _expansion.get("_roads") as Dictionary
	for road_name in road_map:
		var road: Dictionary = road_map[road_name]
		if _rect_hits_polyline(rect, road.points, float(road.width) * 0.5 + 48.0):
			return false
	if _rect_hits_polyline(rect, RAIL_CORRIDOR, 88.0):
		return false
	return DISTRICT_BOUNDS.grow(-20.0).encloses(rect)

func _rect_hits_polyline(rect: Rect2, points: PackedVector2Array, radius: float) -> bool:
	var probes := PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y), rect.get_center(),
	])
	for index in range(points.size() - 1):
		for point in probes:
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[index], points[index + 1])) <= radius:
				return true
	return false

func _spawn_infill(data: Dictionary) -> void:
	var lot_rect: Rect2 = data.rect
	var building := BUILDING_SCRIPT.new() as ProceduralBuilding
	building.name = String(data.id)
	building.position = lot_rect.get_center()
	building.footprint = lot_rect.size
	building.building_kind = String(data.kind)
	building.variant_seed = int(data.seed)
	add_child(building)
	# ProceduralBuilding owns the solid geodata for this lot.

func _draw() -> void:
	if _expansion == null:
		return
	var source_lots: Array = _expansion.get("lots") as Array
	for index in source_lots.size():
		_draw_lot_accent(source_lots[index], index)
	for data in _safe_infill:
		_draw_service_apron(data.rect, String(data.kind), int(data.seed))

func _draw_lot_accent(data: Dictionary, index: int) -> void:
	var rect: Rect2 = data.rect
	var kind := String(data.kind)
	# Accent positions deliberately remain in the original lot, under its
	# building footprint or inside a dedicated plaza.  They have no physics.
	if "warehouse" in kind:
		_draw_warehouse_yard(rect, index)
	elif "garage" in kind:
		_draw_garage_court(rect)
	elif "park" in kind:
		_draw_civic_plaza(rect, index)
	elif "office" in kind or "hospital" in kind or "police" in kind:
		_draw_roof_services(rect, index)
	elif "rowhouse" in kind or "brownstone" in kind:
		_draw_residential_detail(rect, index)
	else:
		_draw_shopfront_detail(rect, index)

func _draw_warehouse_yard(rect: Rect2, seed: int) -> void:
	var base := rect.grow(-16)
	# Container bays behind the roof line make the block legible as a working
	# service lot, not a row of anonymous rectangles.
	for i in range(3):
		var at := Vector2(base.position.x + 16 + i * 34, base.end.y - 26)
		var cargo := Rect2(at, Vector2(26, 13))
		draw_rect(cargo, [Color("#8b6345"), Color("#526d74"), Color("#6b7657")][posmod(seed + i, 3)])
		draw_rect(cargo, Color("#242a2b"), false, 1.0)
		for x in range(int(cargo.position.x + 5), int(cargo.end.x), 7):
			draw_line(Vector2(x, cargo.position.y + 2), Vector2(x, cargo.end.y - 2), Color("#20282a"), 1.0)
	var dock_y := base.end.y - 8
	draw_line(Vector2(base.position.x + 8, dock_y), Vector2(base.end.x - 8, dock_y), Color("#d0ad51"), 3.0)

func _draw_garage_court(rect: Rect2) -> void:
	var apron := Rect2(rect.position.x + 18, rect.end.y - 30, rect.size.x - 36, 15)
	draw_rect(apron, Color("#343b3e"))
	for x in range(int(apron.position.x + 4), int(apron.end.x - 5), 18):
		draw_line(Vector2(x, apron.position.y), Vector2(x + 8, apron.end.y), Color("#c99f35"), 2.0)
	# Tool cabinets / tire stack: useful mechanic-shop silhouette at gameplay zoom.
	draw_rect(Rect2(rect.position.x + 18, rect.position.y + 16, 13, 20), Color("#49565b"))
	draw_circle(Vector2(rect.end.x - 28, rect.position.y + 27), 8, Color("#21272a"))
	draw_circle(Vector2(rect.end.x - 28, rect.position.y + 27), 4, Color("#667277"))

func _draw_civic_plaza(rect: Rect2, seed: int) -> void:
	var inner := rect.grow(-18)
	# Paved paths and a fountain/planted island make each green/public lot
	# recognisable without needing a floating text label.
	draw_line(Vector2(inner.position.x, inner.get_center().y), Vector2(inner.end.x, inner.get_center().y), Color("#b5ae92"), 7.0)
	draw_line(Vector2(inner.get_center().x, inner.position.y), Vector2(inner.get_center().x, inner.end.y), Color("#b5ae92"), 7.0)
	var center := inner.get_center()
	draw_circle(center, 16, Color("#4a6967"))
	draw_circle(center, 11, Color("#719b9b"))
	draw_circle(center + Vector2(0, -2), 4, Color("#d6e8df"))
	for i in range(4):
		var angle := float(i) * TAU / 4.0 + float(seed % 3) * 0.15
		var bench_at := center + Vector2(32, 0).rotated(angle)
		draw_rect(Rect2(bench_at - Vector2(9, 3), Vector2(18, 6)), Color("#78523a"))

func _draw_roof_services(rect: Rect2, seed: int) -> void:
	# Offset antennas, tanks and HVAC provide tall-building scale without adding
	# physical obstacles around the facade.
	var top := rect.position + Vector2(30 + seed % 25, 29)
	draw_line(top, top + Vector2(0, -20), Color("#273439"), 2.0)
	draw_line(top + Vector2(-5, -14), top + Vector2(5, -14), Color("#8caeb0"), 1.5)
	var unit := Rect2(rect.end.x - 52, rect.position.y + 24, 26, 17)
	draw_rect(unit, Color("#48585b"))
	draw_rect(unit.grow(-3), Color("#75898b"), false, 1.0)

func _draw_residential_detail(rect: Rect2, seed: int) -> void:
	# Water tanks and fire escapes distinguish residential rows from commercial
	# blocks and give the skyline irregularity.
	var x := rect.position.x + 28 + float(seed % 3) * 26.0
	var tank := Vector2(x, rect.position.y + 28)
	draw_circle(tank, 9, Color("#5a6e6f"))
	draw_rect(Rect2(tank - Vector2(9, 0), Vector2(18, 11)), Color("#425255"))
	for rung in range(3):
		var y := rect.position.y + 62 + rung * 8
		draw_line(Vector2(rect.end.x - 26, y), Vector2(rect.end.x - 10, y), Color("#303b3d"), 2.0)

func _draw_shopfront_detail(rect: Rect2, seed: int) -> void:
	var canopy := Rect2(rect.position.x + 18, rect.end.y - 33, rect.size.x - 36, 7)
	draw_rect(canopy, [Color("#d9a346"), Color("#54a095"), Color("#be6252")][seed % 3])
	for x in range(int(canopy.position.x + 4), int(canopy.end.x), 12):
		draw_line(Vector2(x, canopy.position.y), Vector2(x, canopy.end.y), Color("#f0dfb7"), 1.0)

func _draw_service_apron(rect: Rect2, kind: String, seed: int) -> void:
	# A slim painted edge beneath each new infill building ties it to the ground;
	# this is inside the lot rectangle, never in public walking space.
	var line_color := Color("#c69c3f") if "garage" in kind else Color("#657a7c")
	var y := rect.end.y - 8
	draw_line(Vector2(rect.position.x + 8, y), Vector2(rect.end.x - 8, y), line_color, 2.0)

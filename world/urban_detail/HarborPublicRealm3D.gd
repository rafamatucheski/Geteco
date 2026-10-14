extends Node3D
class_name HarborPublicRealm3D

## Recognizable public-realm sets reconstructed from HarborDistrict and
## HarborEastDistrict. Coordinates below are local metres after NativeRegion
## places each set at its exact V1 anchor.

var zone_id := ""
var materials := {}
const INSTANCING := preload("res://world/urban_detail/HarborPropInstancing.gd")
var _furniture_built := false

static func records() -> Array[Dictionary]:
	return [
		{"zone_id":"union_plaza", "point":Vector2(1675, 1810)},
		{"zone_id":"foundry_courtyard", "point":Vector2(845, 850)},
		{"zone_id":"northbank_promenade_west", "point":Vector2(5150, 2400)},
		{"zone_id":"northbank_promenade_east", "point":Vector2(6210, 2400)},
		{"zone_id":"museum_compass", "point":Vector2(6080, 1000)},
	]

func _ready() -> void:
	set_meta("source_id", "world/harbor/HarborDistrict.gd" if zone_id in ["union_plaza", "foundry_courtyard"] else "world/harbor/HarborEastDistrict.gd")
	match zone_id:
		"union_plaza": _build_union_plaza()
		"foundry_courtyard": _build_foundry_courtyard()
		"northbank_promenade_west": _build_promenade(false)
		"northbank_promenade_east": _build_promenade(true)
		"museum_compass": _build_compass()
	_furniture_built = true
	INSTANCING.schedule_furniture(self)

func _enter_tree() -> void:
	if _furniture_built: INSTANCING.schedule_furniture(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE: INSTANCING.restore_furniture(self)

func _material(hex: String, roughness := 0.86) -> StandardMaterial3D:
	var key := hex + ":" + str(roughness)
	if materials.has(key): return materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = roughness
	materials[key] = material
	return material

func _box(label: String, center: Vector3, size: Vector3, hex: String) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.position = center
	item.material_override = _material(hex)
	add_child(item)
	return item

func _disc(label: String, center: Vector3, radius: float, height: float, hex: String, solid := false) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	item.mesh = mesh
	item.position = center
	item.material_override = _material(hex)
	add_child(item)
	if solid:
		var body := StaticBody3D.new()
		body.name = label + "Solid"
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collider.shape = shape
		body.add_child(collider)
		item.add_child(body)
	return item

func _build_union_plaza() -> void:
	# HarborUrbanSurface3D owns the entire court and its aligned joints.
	# V1 radii 60/51/40/13 px converted by 16 px/m.
	_disc("UnionFountainBasin", Vector3(0, 0.30, 0), 3.75, 0.60, "7b8078", true)
	_disc("UnionFountainPedestal", Vector3(0, 0.93, 0), 0.81, 0.62, "c4c4ad", true)
	# Água, taça e jato: antes eram dois discos pintados (água e anel claro da V1 2D).
	add_child(preload("res://world/urban_detail/fountain/UnionFountain3D.gd").new())
	var piano := preload("res://activities/UnionPiano.gd").new()
	piano.position = Vector3(10.0, 0, -.8)
	add_child(piano)

func _build_foundry_courtyard() -> void:
	# Garden and courtyard share the district's single surface, including edging.
	_bench(Vector3(-17.5, 0.08, -4.69), 0.0)
	_bench(Vector3(-9.38, 0.08, -4.69), 0.0)
	_disc("FoundryBirdbathBase", Vector3(-11.75, 0.28, -3.125), 0.44, 0.50, "8c8577")
	_disc("FoundryBirdbathWater", Vector3(-11.75, 0.55, -3.125), 0.31, 0.04, "48818a")
	_service_box("FoundryDumpsterGreen", Vector3(5.75, 0.55, 2.38), Vector3(2.75, 1.1, 1.63), "3d5e4a")
	_service_box("FoundryDumpsterBlue", Vector3(8.94, 0.55, 2.38), Vector3(2.5, 1.1, 1.63), "385369")
	_service_box("FoundryHVAC0", Vector3(11.75, 0.42, 2.31), Vector3(1.63, 0.84, 1.38), "8b9390")
	_service_box("FoundryHVAC1", Vector3(13.75, 0.42, 2.31), Vector3(1.63, 0.84, 1.38), "8b9390")
	_service_box("FoundryPallets", Vector3(2.44, 0.24, 2.56), Vector3(1.75, 0.48, 1.63), "765139")
	_box("FoundryDrain", Vector3(-3.44, 0.055, 4.56), Vector3(1.25, 0.05, 1.0), "181a1c")
	_box("AnchorCafePlanterWest", Vector3(-18.5, 0.24, 18.56), Vector3(3.38, 0.48, 0.38), "497552")
	_box("AnchorCafePlanterEast", Vector3(-9.75, 0.24, 18.56), Vector3(3.38, 0.48, 0.38), "497552")

func _service_box(label: String, center: Vector3, size: Vector3, hex: String) -> void:
	var prop := _box(label, center, size, hex)
	if "Dumpster" in label or "Pallet" in label:
		preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("dumpster" if "Dumpster" in label else "pallet",prop,self)

func _build_promenade(east: bool) -> void:
	# No independent promenade plate: the district pavement reaches the quay.
	if not east:
		_planter(Vector3(-39.06, 0.22, 0), Vector2(7.81, 4.06), 0)
		_planter(Vector3(-5.78, 0.22, 0), Vector2(9.69, 3.88), 1)
		_bench(Vector3(-30.31, 0.08, 0), 0.0)
		_bench(Vector3(8.75, 0.08, 0.31), 0.0)
	else:
		_planter(Vector3(-16.88, 0.22, 0), Vector2(5.94, 3.63), 2)
		_planter(Vector3(20.94, 0.22, 0), Vector2(8.13, 4.5), 3)
		_bench(Vector3(-8.13, 0.08, 0), 0.0)
		_bench(Vector3(10.63, 0.08, 0), 0.0)

func _planter(center: Vector3, size: Vector2, variant: int) -> void:
	_box("PromenadePlanterCurb", center, Vector3(size.x, 0.44, size.y), "9d9685")
	_box("PromenadePlanterBed", center + Vector3(0, 0.24, 0), Vector3(size.x - 0.38, 0.10, size.y - 0.38), ["3d463a", "464b38", "3b4740", "444a37"][variant])
	for side in [-1.0, 1.0]:
		_box("PlanterRim", center + Vector3(0,.24,side*(size.y*.5-.09)), Vector3(size.x,.10,.18), "b5ae9a")
		_box("PlanterRim", center + Vector3(side*(size.x*.5-.09),.24,0), Vector3(.18,.10,size.y-.36), "b5ae9a")
	for i in 5:
		var px := -size.x * 0.34 + float(i) * size.x * 0.17
		var shrub := MeshInstance3D.new()
		shrub.name = "PromenadeShrub"
		shrub.mesh = preload("res://world/urban_detail/CoastalFoliage.gd").mesh(i + variant)
		var radius := 0.52 + float((i + variant) % 3) * 0.10
		shrub.scale = Vector3(radius, .48 + float(i % 2) * .08, radius * .92)
		shrub.position = center + Vector3(px, .68, (-.18 if i % 2 == 0 else .18) * size.y)
		shrub.rotation.y = float(i + variant) * 1.37
		shrub.material_override = _material(["557252", "617a50", "48694f"][(i + variant) % 3])
		(shrub.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
		add_child(shrub)

func _bench(point: Vector3, angle: float) -> void:
	var root := Node3D.new()
	root.name = "PublicBench"
	root.position = point
	root.rotation.y = angle
	add_child(root)
	root.add_child(preload("res://world/urban_detail/StreetBench.gd").create(2.8,.62))
	var body := StaticBody3D.new()
	body.name = "BenchSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8,1.12,.72)
	collider.shape = shape
	collider.position = Vector3(0,.56,0)
	body.add_child(collider)
	root.add_child(body)
	preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("bench_seat",root,self)

func _build_compass() -> void:
	_disc("MuseumCompassOuter", Vector3(0, 0.07, 0), 2.875, 0.14, "8c9589")
	_disc("MuseumCompassInner", Vector3(0, 0.15, 0), 2.25, 0.05, "597984")
	for index in 4:
		var arm := _box("MuseumCompassPoint", Vector3(0, 0.20, -1.7), Vector3(0.62, 0.08, 3.4), "e1c892" if index % 2 == 0 else "b9c4be")
		arm.rotation.y = float(index) * PI * 0.5

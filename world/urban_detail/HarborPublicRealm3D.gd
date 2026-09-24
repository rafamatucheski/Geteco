extends Node3D
class_name HarborPublicRealm3D

## Recognizable public-realm sets reconstructed from HarborDistrict and
## HarborEastDistrict. Coordinates below are local metres after NativeRegion
## places each set at its exact V1 anchor.

var zone_id := ""
var materials := {}

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
	# Rect2(1440,1740,620,330), centred around the fountain anchor.
	_box("UnionPlazaPaving", Vector3(0, 0.018, 4.375), Vector3(38.75, 0.036, 20.625), "aaa9a1")
	for x in range(-18, 19, 3):
		_box("UnionPlazaJoint", Vector3(float(x), 0.041, 4.375), Vector3(0.025, 0.012, 20.2), "8e8d86")
	for z in range(-5, 15, 3):
		_box("UnionPlazaJoint", Vector3(0, 0.041, float(z)), Vector3(38.3, 0.012, 0.025), "8e8d86")
	# V1 radii 60/51/40/13 px converted by 16 px/m.
	_disc("UnionFountainBasin", Vector3(0, 0.30, 0), 3.75, 0.60, "7b8078", true)
	_disc("UnionFountainWater", Vector3(0, 0.615, 0), 3.19, 0.03, "397d86")
	_disc("UnionFountainInnerRing", Vector3(0, 0.65, 0), 2.50, 0.06, "92c3be")
	_disc("UnionFountainPedestal", Vector3(0, 0.93, 0), 0.81, 0.62, "c4c4ad", true)

func _build_foundry_courtyard() -> void:
	# Anchor is the shared courtyard centre; preserve the V1 stone/garden split.
	_box("FoundryCourtyardStone", Vector3(-0.94, 0.018, -2.97), Vector3(28.125, 0.036, 6.25), "b5ad9a")
	_box("FoundryGardenBed", Vector3(-5.94, 0.055, -2.81), Vector3(13.75, 0.11, 4.375), "445d4b")
	_box("FoundryGardenPath", Vector3(-11.72, 0.075, -2.97), Vector3(0.94, 0.05, 5.31), "c5bcab")
	_bench(Vector3(-17.5, 0.08, -4.69), 0.0)
	_bench(Vector3(-9.38, 0.08, -4.69), 0.0)
	_disc("FoundryBirdbathBase", Vector3(-11.75, 0.28, -3.125), 0.44, 0.50, "8c8577")
	_disc("FoundryBirdbathWater", Vector3(-11.75, 0.55, -3.125), 0.31, 0.04, "48818a")
	_box("FoundryPassage", Vector3(-6.69, 0.018, -13.91), Vector3(1.5, 0.036, 14.69), "a8a18e")
	_box("FoundryServiceYard", Vector3(7.69, 0.018, 3.59), Vector3(25.25, 0.036, 6.56), "5c605f")
	_service_box("FoundryDumpsterGreen", Vector3(5.75, 0.55, 2.38), Vector3(2.75, 1.1, 1.63), "3d5e4a")
	_service_box("FoundryDumpsterBlue", Vector3(8.94, 0.55, 2.38), Vector3(2.5, 1.1, 1.63), "385369")
	_service_box("FoundryHVAC0", Vector3(11.75, 0.42, 2.31), Vector3(1.63, 0.84, 1.38), "8b9390")
	_service_box("FoundryHVAC1", Vector3(13.75, 0.42, 2.31), Vector3(1.63, 0.84, 1.38), "8b9390")
	_service_box("FoundryPallets", Vector3(2.44, 0.24, 2.56), Vector3(1.75, 0.48, 1.63), "765139")
	_box("FoundryDrain", Vector3(-3.44, 0.055, 4.56), Vector3(1.25, 0.05, 1.0), "181a1c")
	_box("AnchorCafeTerrace", Vector3(-14.0, 0.025, 17.75), Vector3(13.125, 0.05, 1.75), "a97155")
	_box("AnchorCafePlanterWest", Vector3(-18.5, 0.24, 18.56), Vector3(3.38, 0.48, 0.38), "497552")
	_box("AnchorCafePlanterEast", Vector3(-9.75, 0.24, 18.56), Vector3(3.38, 0.48, 0.38), "497552")

func _service_box(label: String, center: Vector3, size: Vector3, hex: String) -> void:
	_box(label, center, size, hex)

func _build_promenade(east: bool) -> void:
	var span_center_x := -1.25 if not east else -2.5
	_box("NorthbankPromenade", Vector3(span_center_x, 0.018, 0), Vector3(66.25, 0.036, 10.625), "d0c4a7")
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
	for i in 5:
		var px := -size.x * 0.34 + float(i) * size.x * 0.17
		_disc("PromenadeShrub", center + Vector3(px, 0.55 + float(i % 2) * 0.08, (-0.18 if i % 2 == 0 else 0.18) * size.y), 0.42 + float((i + variant) % 3) * 0.10, 0.7, "557252")

func _bench(point: Vector3, angle: float) -> void:
	var root := Node3D.new()
	root.name = "PublicBench"
	root.position = point
	root.rotation.y = angle
	add_child(root)
	var seat := _box("BenchSeat", Vector3.ZERO, Vector3(2.8, 0.16, 0.48), "765139")
	seat.reparent(root, true)
	seat.position = Vector3(0, 0.55, 0)
	var back := _box("BenchBack", Vector3.ZERO, Vector3(2.8, 0.75, 0.14), "765139")
	back.reparent(root, true)
	back.position = Vector3(0, 0.90, -0.22)
	for side in [-1.1, 1.1]:
		var leg := _box("BenchLeg", Vector3.ZERO, Vector3(0.14, 0.55, 0.32), "343d42")
		leg.reparent(root, true)
		leg.position = Vector3(side, 0.28, 0)

func _build_compass() -> void:
	_disc("MuseumCompassOuter", Vector3(0, 0.07, 0), 2.875, 0.14, "8c9589")
	_disc("MuseumCompassInner", Vector3(0, 0.15, 0), 2.25, 0.05, "597984")
	for index in 4:
		var arm := _box("MuseumCompassPoint", Vector3(0, 0.20, -1.7), Vector3(0.62, 0.08, 3.4), "e1c892" if index % 2 == 0 else "b9c4be")
		arm.rotation.y = float(index) * PI * 0.5

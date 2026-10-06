extends Node3D
## Authored native cutaway: the near walls stay physically full-height.
## Static gravel/sleepers/coal share MultiMeshes; only the one-shot reveal animates.
const RELIC_HIDDEN_Y := .4
var solid_bodies: Array[StaticBody3D] = []
var solid_bounds: Array[AABB] = []
var _materials: Dictionary = {}
var _lid: Node3D
var _lever: Node3D
var _relic: Node3D
var _relic_light: OmniLight3D
var _reveal_tween: Tween
var _secret := false
var _wall_rocks: Array[Transform3D] = []
var raid_loot_available := true
var _raid_loot: Node3D

func _ready() -> void:
	name = "CoalGallery"
	_build_floor_and_walls()
	_build_supports()
	_build_tracks()
	_build_work_corner()
	_build_secret_cart()
	_build_lamps()
	_build_scatter()
	_build_clandestine_gallery()
	reveal_secret(false, false)

func _mat(key: String, color: Color, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .88 if metallic < .5 else .59
	material.metallic = metallic
	if emission > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	_materials[key] = material
	return material

func _box(parent: Node3D, id: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var shape := BoxMesh.new()
	shape.size = size
	node.mesh = shape
	node.material_override = material
	node.position = center
	parent.add_child(node)
	return node

func _sphere(parent: Node3D, id: String, center: Vector3, scale_value: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var shape := SphereMesh.new()
	shape.radius = .5
	shape.height = 1
	shape.radial_segments = 8
	shape.rings = 4
	node.mesh = shape
	node.material_override = material
	node.position = center
	node.scale = scale_value
	parent.add_child(node)
	return node

func _solid(id: String, center: Vector3, size: Vector3, obstacle := true) -> void:
	var body := StaticBody3D.new()
	body.name = id + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)
	var bounds := AABB(center - size * .5, size)
	body.set_meta("bounds", bounds)
	body.set_meta("interior_solid_id", id)
	add_child(body)
	solid_bodies.append(body)
	if obstacle: solid_bounds.append(bounds)

func _wall(id: String, center: Vector3, size: Vector3, cutaway := false) -> void:
	_solid(id, center, size)
	var visual_size := size
	var visual_center := center
	if cutaway:
		visual_size.y = .6
		visual_center.y = .3
	# Recess the flat core; exposed faceted strata stay entirely inside the
	# existing physical wall. The gameplay aisle and its capsule clearance stay put.
	if size.x >= size.z: visual_size.z *= .6
	else: visual_size.x *= .6
	visual_size.y *= .82
	visual_center.y = visual_size.y * .5
	_box(self, id, visual_center, visual_size, _mat("rock", Color("343638")))
	var seam := visual_size
	seam.y = .15
	_box(self, id + "CoalSeam", visual_center + Vector3(0, .12, -.012), seam * Vector3(1.004, 1, 1.004), _mat("coal", Color("101517"), .23))
	_append_wall_rocks(center, size, cutaway)

func _append_wall_rocks(center: Vector3, size: Vector3, cutaway: bool) -> void:
	var along_x := size.x >= size.z
	var length_value := size.x if along_x else size.z
	var thickness := size.z if along_x else size.x
	var height := .6 if cutaway else size.y
	var count := maxi(2, int(ceil(length_value / 1.2)))
	var rows := 1 if cutaway else 3
	var random := RandomNumberGenerator.new()
	random.seed = int(absf(center.x * 137 + center.z * 619)) + 7163
	for row in rows:
		for index in count:
			var width := minf(length_value, length_value / count * random.randf_range(1.03, 1.25))
			var chunk_height := minf(height, height / rows * random.randf_range(1.02, 1.18))
			var along := clampf(-length_value * .5 + (index + .5) * length_value / count, -length_value * .5 + width * .5, length_value * .5 - width * .5)
			var y := clampf((row + .5) * height / rows + random.randf_range(-.07, .07), chunk_height * .5, height - chunk_height * .5)
			var extent := Vector3(width, chunk_height, thickness * .99) if along_x else Vector3(thickness * .99, chunk_height, width)
			var point := Vector3(center.x + along, y, center.z) if along_x else Vector3(center.x, y, center.z + along)
			_wall_rocks.append(Transform3D(Basis.IDENTITY.scaled(extent), point))

func _rough_rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1
	sphere.radial_segments = 7
	sphere.rings = 3
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in vertices.size():
		var point := vertices[index]
		# Only contract vertices: the mesh is guaranteed inside the unit AABB.
		vertices[index] *= .88 + .12 * absf(sin(point.x * 29.7 + point.y * 17.3 + point.z * 41.5))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(0, indices.size(), 3):
		var a := vertices[indices[index]]
		var b := vertices[indices[index + 1]]
		var c := vertices[indices[index + 2]]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(a + b + c) < 0: normal = -normal
		for point in [a, b, c]:
			surface.set_normal(normal)
			surface.add_vertex(point)
	return surface.commit()

func _build_rock_faces() -> void:
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = _rough_rock_mesh()
	batch.instance_count = _wall_rocks.size()
	for index in _wall_rocks.size():
		batch.set_instance_transform(index, _wall_rocks[index])
		var soot := .82 + float(index % 7) * .03
		batch.set_instance_color(index, Color(soot, soot, soot, 1))
	var material := _mat("raw_strata", Color("414340"))
	material.vertex_color_use_as_albedo = true
	var node := MultiMeshInstance3D.new()
	node.name = "RawRockFaces"
	node.multimesh = batch
	node.material_override = material
	add_child(node)

func _build_floor_and_walls() -> void:
	var floor_material := _mat("floor", Color("292b29"))
	for item in [
		["GalleryFloor", Vector3(-5, -.14, -4.5), Vector3(18, .28, 15)],
		["AccessFloor", Vector3(9, -.14, 3), Vector3(5.2, .28, 19)],
		["BendFloor", Vector3(5.2, -.14, -4), Vector3(5.6, .28, 4.4)],
		["RaidConnectorFloor", Vector3(13.5, -.14, 3.1), Vector3(6, .28, 4.4)],
		["ClandestineFloor", Vector3(23, -.14, 2), Vector3(17, .28, 17)]]:
		_box(self, item[0], item[1], item[2], floor_material)
		_solid(item[0], item[1], item[2], false)
	_wall("GalleryWest", Vector3(-13.6, 1.9, -4.5), Vector3(1.2, 3.8, 16))
	_wall("GalleryNorth", Vector3(-5, 2.1, -11.6), Vector3(18, 4.2, 1.2))
	_wall("GallerySouth", Vector3(-5, 1.9, 2.5), Vector3(18, 3.8, 1), true)
	_wall("GalleryEastUpper", Vector3(3.45, 1.9, -8.75), Vector3(.9, 3.8, 5.7))
	_wall("GalleryEastLower", Vector3(3.45, 1.9, .05), Vector3(.9, 3.8, 4.1), true)
	_wall("BendNorth", Vector3(5.2, 1.9, -6.45), Vector3(4.5, 3.8, .9))
	_wall("TunnelWest", Vector3(6.5, 1.9, 5.1), Vector3(1, 3.8, 14.2), true)
	_wall("TunnelEastNorth", Vector3(11.5, 1.9, -2.8), Vector3(1, 3.8, 7.4))
	_wall("TunnelEastSouth", Vector3(11.5, 1.9, 8.9), Vector3(1, 3.8, 7.2))
	_wall("TunnelNorth", Vector3(9.2, 1.9, -6.45), Vector3(5.5, 3.8, .9))
	_wall("TunnelExit", Vector3(9, 1.9, 12.4), Vector3(5.6, 3.8, .8), true)
	_wall("RaidConnectorNorth", Vector3(13.5, 1.9, .45), Vector3(5, 3.8, 1))
	_wall("RaidConnectorSouth", Vector3(13.5, 1.9, 5.8), Vector3(5, 3.8, 1), true)
	_wall("RaidWestNorth", Vector3(15, 1.9, -2.6), Vector3(1, 3.8, 7.4))
	_wall("RaidWestSouth", Vector3(15, 1.9, 7.9), Vector3(1, 3.8, 5.2))
	_wall("RaidNorth", Vector3(23, 1.9, -6.5), Vector3(17, 3.8, 1))
	_wall("RaidEast", Vector3(31.5, 1.9, 2), Vector3(1, 3.8, 17))
	_wall("RaidSouth", Vector3(23, 1.9, 10.5), Vector3(18, 3.8, 1), true)
	_build_rock_faces()
	# Short drainage channels, flush enough for the actor capsule to cross.
	var water := _mat("water", Color("142021"), .28)
	_box(self, "GalleryDrain", Vector3(-11.8, .009, -4.5), Vector3(.22, .012, 12.5), water)
	_box(self, "TunnelDrain", Vector3(10.7, .009, 3), Vector3(.17, .012, 17), water)

func _post(center: Vector3, id: String) -> void:
	var timber := _mat("timber", Color("5b4938"))
	_box(self, id, center, Vector3(.28, 3.25, .33), timber)
	_solid(id, center, Vector3(.28, 3.25, .33))
	for height in [.25, 2.55]:
		_box(self, id + "Band", Vector3(center.x, height, center.z), Vector3(.31, .1, .36), _mat("iron", Color("3a4547"), .65))

func _build_supports() -> void:
	var timber := _mat("timber", Color("5b4938"))
	for index in 4:
		var z := 10.3 - index * 4.5
		for x in [7.1, 10.9]: _post(Vector3(x, 1.625, z), "TunnelPost%d_%d" % [index, int(x)])
		_box(self, "TunnelBeam%d" % index, Vector3(9, 3.2, z), Vector3(4.35, .26, .34), timber)
		_solid("TunnelBeam%d" % index, Vector3(9, 3.2, z), Vector3(4.35, .26, .34), false)
	for z in [-8.8, -3.0]:
		for x in [-12.55, 2.5]: _post(Vector3(x, 1.625, z), "GalleryPost%d_%d" % [int(x), int(z)])
		# Broken upper members leave the chamber readable from the fixed camera.
		for x in [-10.8, .75]:
			_box(self, "GalleryBeam", Vector3(x, 3.26, z), Vector3(4.0, .28, .35), timber)
			_solid("GalleryBeam", Vector3(x, 3.26, z), Vector3(4.0, .28, .35), false)
	_box(self, "PowerCable", Vector3(10.94, 2.45, 3), Vector3(.035, .035, 17), _mat("cable", Color("1c2223")))
	_box(self, "ChamberCable", Vector3(-4.6, 2.72, -11.02), Vector3(15.4, .035, .035), _mat("cable", Color("1c2223")))

func _multibox(id: String, centers: Array[Vector3], size: Vector3, material: Material) -> void:
	var shape := BoxMesh.new()
	shape.size = size
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = shape
	batch.instance_count = centers.size()
	for index in centers.size(): batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, centers[index]))
	var node := MultiMeshInstance3D.new()
	node.name = id
	node.multimesh = batch
	node.material_override = material
	add_child(node)

func _build_tracks() -> void:
	var sleepers: Array[Vector3] = []
	for index in 24: sleepers.append(Vector3(-7.5, .025, -10.1 + index * .47))
	_multibox("RailSleepers", sleepers, Vector3(2.05, .05, .2), _mat("old_wood", Color("3d342b")))
	for x in [-8.14, -6.86]:
		_box(self, "Rail", Vector3(x, .065, -4.8), Vector3(.075, .08, 11.5), _mat("rail", Color("6b655b"), .75))
	var tunnel_sleepers: Array[Vector3] = []
	for index in 30: tunnel_sleepers.append(Vector3(9.0, .025, -3.7 + index * .48))
	_multibox("AccessSleepers", tunnel_sleepers, Vector3(1.8, .05, .19), _mat("old_wood", Color("3d342b")))
	for x in [8.43, 9.57]:
		_box(self, "AccessRail", Vector3(x, .065, 3.5), Vector3(.065, .08, 14.8), _mat("rail", Color("6b655b"), .75))

func _build_work_corner() -> void:
	var wood := _mat("crate", Color("65513c"))
	for item in [[Vector3(.65, .4, -9.4), Vector3(1.2, .8, 1.1)], [Vector3(-.65, .28, -9.5), Vector3(.9, .56, 1)], [Vector3(.8, 1.02, -9.4), Vector3(.85, .45, .8)]]:
		_box(self, "Supplies", item[0], item[1], wood)
		# Solid coverage includes stacked supplies down to floor level.
		_solid("Supplies", Vector3(item[0].x, (item[0].y + item[1].y * .5) * .5, item[0].z), Vector3(item[1].x, item[0].y + item[1].y * .5, item[1].z))
	_box(self, "RestBench", Vector3(-11.6, .5, .65), Vector3(2.3, .15, .6), wood)
	_solid("RestBench", Vector3(-11.6, .3, .65), Vector3(2.3, .6, .6))
	for x in [-12.35, -10.85]: _box(self, "BenchLeg", Vector3(x, .24, .65), Vector3(.15, .48, .48), wood)
	# Abandoned lamp, boots and enamel cup; clutter is confined to the bench.
	_sphere(self, "OldHardhat", Vector3(-11.5, .74, .65), Vector3(.42, .25, .36), _mat("helmet", Color("b78933")))
	_box(self, "LunchTin", Vector3(-12.05, .67, .62), Vector3(.32, .25, .24), _mat("tin", Color("74807e"), .6))
	# Pickaxe propped against the rear wall; its entire footprint blocks actors.
	var pick := _box(self, "PickHandle", Vector3(-3, .85, -10.6), Vector3(.07, 1.7, .09), wood)
	pick.rotation.z = -.18
	_box(self, "PickHead", Vector3(-2.85, 1.53, -10.6), Vector3(.9, .1, .12), _mat("iron", Color("3a4547"), .65))
	_solid("Pickaxe", Vector3(-2.92, .87, -10.6), Vector3(1.12, 1.74, .18))
	# Lever sits in the open aisle, reachable south of the secret wagon.
	_box(self, "LeverBase", Vector3(-10.65, .36, -4.05), Vector3(.6, .72, .6), _mat("iron", Color("3a4547"), .65))
	_solid("LeverBase", Vector3(-10.65, .75, -4.05), Vector3(1.2, 1.5, .72))
	_lever = Node3D.new()
	_lever.name = "LeverPivot"
	_lever.position = Vector3(-10.65, .7, -4.05)
	add_child(_lever)
	_box(_lever, "LeverStem", Vector3(0, .32, 0), Vector3(.065, .64, .065), _mat("rail", Color("6b655b"), .75))
	_box(_lever, "LeverGrip", Vector3(0, .68, 0), Vector3(.31, .1, .11), _mat("handle", Color("a56035")))

func _build_secret_cart() -> void:
	var iron := _mat("wagon", Color("55423a"), .55)
	var rust := _mat("rust", Color("72432c"), .4)
	var cart := Node3D.new()
	cart.name = "BuriedWagon"
	cart.position = Vector3(-7.5, 0, -7.8)
	add_child(cart)
	_box(cart, "WagonBed", Vector3(0, .48, 0), Vector3(2.05, .25, 2.75), iron)
	for side in [-1, 1]:
		_box(cart, "WagonSide", Vector3(side * 1.02, 1.02, 0), Vector3(.13, .9, 2.8), rust)
		_box(cart, "WagonEnd", Vector3(0, .98, side * 1.33), Vector3(2.05, .83, .13), iron)
		for z in [-.95, .95]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .27
			cylinder.bottom_radius = .27
			cylinder.height = .15
			cylinder.radial_segments = 12
			wheel.mesh = cylinder
			wheel.material_override = iron
			wheel.rotation.z = PI * .5
			wheel.position = Vector3(side * 1.05, .29, z)
			cart.add_child(wheel)
	_solid("SecretWagon", Vector3(-7.5, .77, -7.8), Vector3(2.35, 1.54, 2.85))
	_lid = Node3D.new()
	_lid.name = "WagonLidPivot"
	_lid.position = Vector3(0, 1.5, -1.33)
	cart.add_child(_lid)
	_box(_lid, "DustyWagonCover", Vector3(0, 0, 1.33), Vector3(2.16, .13, 2.78), _mat("cover", Color("46443a")))
	var lid_body := StaticBody3D.new()
	lid_body.name = "CoverCollision"
	lid_body.collision_layer = 1
	lid_body.collision_mask = 0
	var lid_shape := CollisionShape3D.new()
	var lid_box := BoxShape3D.new()
	lid_box.size = Vector3(2.16, .13, 2.78)
	lid_shape.shape = lid_box
	lid_shape.position = Vector3(0, 0, 1.33)
	lid_body.add_child(lid_shape)
	_lid.add_child(lid_body)
	solid_bodies.append(lid_body)
	for x in [-.65, .65]: _box(_lid, "CoverStrap", Vector3(x, .08, 1.33), Vector3(.065, .035, 2.78), iron)
	_relic = Node3D.new()
	_relic.name = "AmberMeteorite"
	_relic.position = Vector3(-7.5, RELIC_HIDDEN_Y, -7.8)
	add_child(_relic)
	var amber := _mat("amber", Color("ec9b3d"), .25, .8)
	var stone := _mat("meteorite", Color("162428"), .47)
	_sphere(_relic, "BrokenMeteorite", Vector3.ZERO, Vector3(1.5, 1.9, 1.45), stone)
	_sphere(_relic, "AmberHeart", Vector3(0, .06, .47), Vector3(.96, 1.35, .44), amber)
	# A tiny absurd passenger inside the meteorite rewards close inspection.
	var gold := _mat("duck", Color("ffd668"), .1, .16)
	_sphere(_relic, "DuckBody", Vector3(0, -.08, .74), Vector3(.48, .34, .29), gold)
	_sphere(_relic, "DuckHead", Vector3(.1, .15, .76), Vector3(.24, .25, .24), gold)
	_box(_relic, "DuckBeak", Vector3(.17, .11, .9), Vector3(.18, .065, .15), _mat("beak", Color("dc682c")))
	for x in [.04, .17]: _sphere(_relic, "DuckEye", Vector3(x, .19, .862), Vector3(.04, .045, .025), _mat("eye", Color("192022")))
	for index in 7:
		var angle := index * TAU / 7
		# Keep the whole orbit inside the closed lid/side silhouette at birth.
		_sphere(_relic, "SuspendedCoal", Vector3(cos(angle) * .90, .2 + sin(angle * 2) * .32, sin(angle) * .88), Vector3(.23, .29, .22), stone)
	_relic_light = OmniLight3D.new()
	_relic_light.name = "MeteoriteGlow"
	_relic_light.position = Vector3(-7.5, 2.35, -7.5)
	_relic_light.light_color = Color("ffb755")
	_relic_light.light_energy = 0
	_relic_light.omni_range = 5.5
	_relic_light.shadow_enabled = false
	add_child(_relic_light)

func _lamp(id: String, position_value: Vector3, color: Color, range_value: float, energy: float) -> void:
	_box(self, id + "Cage", position_value, Vector3(.28, .38, .23), _mat("iron", Color("3a4547"), .65))
	_box(self, id + "Glass", position_value + Vector3(0, -.035, .13), Vector3(.2, .21, .04), _mat("lamp_" + id, color, 0, 1.0))
	var light := OmniLight3D.new()
	light.name = id
	light.position = position_value + Vector3(0, -.18, .35)
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_value
	light.shadow_enabled = id in ["GalleryLamp", "RaidLamp19"]
	add_child(light)

func _build_lamps() -> void:
	_lamp("EntranceLamp", Vector3(10.85, 2.35, 8.0), Color("f1ba76"), 8.5, 2.6)
	_lamp("BendLamp", Vector3(9.8, 2.35, -3.6), Color("f1ba76"), 9.0, 2.8)
	_lamp("GalleryLamp", Vector3(-1.5, 2.5, -10.95), Color("f1ba76"), 12, 3.2)
	_lamp("OldWorkLamp", Vector3(-11.7, 2.4, -3.0), Color("84b8bd"), 10, 2.6)
	# A caged work lamp hangs from a cross-wire above the central walking aisle.
	# It fills the route to the lever without relying on daytime exterior sun.
	_box(self, "CenterLampCable", Vector3(-4, 3.55, -3), Vector3(12.5, .035, .035), _mat("cable", Color("1c2223")))
	_box(self, "CenterLampDrop", Vector3(-4, 3.2, -3), Vector3(.035, .7, .035), _mat("cable", Color("1c2223")))
	_lamp("CenterWorkLamp", Vector3(-4, 2.86, -3), Color("e8bf8b"), 10.5, 3.1)

func _build_scatter() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 671093
	var shape := SphereMesh.new()
	shape.radius = .5
	shape.height = 1
	shape.radial_segments = 7
	shape.rings = 3
	var transforms: Array[Transform3D] = []
	# Low fragments remain below foot clearance. Large heaps have explicit bodies.
	for index in 110:
		var x := random.randf_range(-12.75, 2.7)
		var z := random.randf_range(-10.85, 1.65)
		var size := Vector3(random.randf_range(.09, .3), random.randf_range(.025, .075), random.randf_range(.08, .24))
		transforms.append(Transform3D(Basis.from_euler(Vector3(0, random.randf() * TAU, 0)).scaled(size), Vector3(x, size.y * .35, z)))
	for index in 48:
		var x := -13.05 + random.randf_range(-.08, .15)
		var z := random.randf_range(-10.6, 1.3)
		var y := random.randf_range(.12, 2.85)
		transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.5, .28, .65)), Vector3(x, y, z)))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = shape
	batch.instance_count = transforms.size()
	for index in transforms.size(): batch.set_instance_transform(index, transforms[index])
	var node := MultiMeshInstance3D.new()
	node.name = "CoalFragmentsAndSeams"
	node.multimesh = batch
	node.material_override = _mat("coal", Color("101517"), .23)
	add_child(node)
	# Faceted exposed seams protrude from the flat rock face and need coverage too.
	_solid("WestCoalVein", Vector3(-13.06, 1.65, -4.65), Vector3(.88, 3.3, 12.8))
	for point in [Vector3(-11.2, .45, -9.95), Vector3(.85, .55, -.3), Vector3(-3.15, .35, -10.45)]:
		_sphere(self, "CoalHeap", point, Vector3(1.6, 1.15, 1.45), _mat("coal", Color("101517"), .23))
		_solid("CoalHeap", Vector3(point.x, .6, point.z), Vector3(1.6, 1.2, 1.45))

func _build_clandestine_gallery() -> void:
	var crate := _mat("raid_crate", Color("62533f"))
	var iron := _mat("iron", Color("3a4547"), .65)
	# Three divided stacks provide actual ballistic and movement cover, with
	# a clear northern aisle and enough room to flank each stack.
	for item in [
		["WestCover", Vector3(19, .66, 3.5), Vector3(2.6, 1.32, 1.2)],
		["CenterCover", Vector3(24, .64, 1), Vector3(3, 1.28, 1.3)],
		["SouthCover", Vector3(27, .72, 7.7), Vector3(2.8, 1.44, 1.4)]]:
		_box(self, item[0], item[1], item[2], crate)
		_solid(item[0], item[1], item[2])
		for x_offset in [-.9, .9]:
			_box(self, "CrateStrap", item[1] + Vector3(x_offset, 0, item[2].z * .5 + .005), Vector3(.075, item[2].y, .02), iron)
	# Pallet of taped white packages: an occupied contraband store, no signs or
	# expository labels. The pallet reserves the complete stack footprint.
	_box(self, "ContrabandPallet", Vector3(19.2, .1, -4.7), Vector3(3.2, .2, 1.35), crate)
	_solid("ContrabandPallet", Vector3(19.2, .63, -4.7), Vector3(3.2, 1.26, 1.35))
	var packages: Array[Vector3] = []
	var tapes: Array[Vector3] = []
	for row in 3:
		for column in 6:
			for tier in 3:
				var position_value := Vector3(17.94 + column * .49, .33 + tier * .29, -5.08 + row * .37)
				packages.append(position_value)
				tapes.append(position_value)
	_multibox("WrappedPackages", packages, Vector3(.45, .27, .33), _mat("wrapping", Color("cbc9ad")))
	_multibox("PackageTape", tapes, Vector3(.085, .278, .339), _mat("black_tape", Color("242925")))
	# Packing table and scales, with a full-volume blocker below the tabletop.
	_box(self, "PackingTable", Vector3(24.5, .87, -4.6), Vector3(2.6, .15, 1.2), iron)
	_solid("PackingTable", Vector3(24.5, .66, -4.6), Vector3(2.6, 1.32, 1.2))
	for x in [23.5, 25.5]:
		_box(self, "PackingTableLeg", Vector3(x, .41, -4.6), Vector3(.08, .82, .85), iron)
	_box(self, "ScalesBase", Vector3(24.1, 1.01, -4.55), Vector3(.56, .13, .48), _mat("scale", Color("afb2a6"), .4))
	_box(self, "ScalesTray", Vector3(24.1, 1.15, -4.55), Vector3(.62, .06, .48), iron)
	_box(self, "PackingRoll", Vector3(25.15, 1.01, -4.55), Vector3(.33, .18, .25), _mat("black_tape", Color("242925")))
	# Cash sits on its own table; the functional approach remains clear at
	# RAID_LOOT (28,-3), a metre in front of the solid furniture.
	_box(self, "CashTable", Vector3(28.5, .91, -4.6), Vector3(3, .18, 1.2), crate)
	_solid("CashTable", Vector3(28.5, .72, -4.6), Vector3(3, 1.44, 1.2))
	for x in [27.25, 29.75]: _box(self, "CashTableLeg", Vector3(x, .41, -4.6), Vector3(.14, .82, .85), crate)
	_raid_loot = Node3D.new()
	_raid_loot.name = "RaidCashBag"
	_raid_loot.position = Vector3(28, 1.02, -4.5)
	add_child(_raid_loot)
	var cloth := _mat("bag", Color("283e35"))
	_box(_raid_loot, "DuffelBody", Vector3.ZERO, Vector3(1.03, .35, .62), cloth)
	for x in [-.32, .32]:
		_box(_raid_loot, "DuffelHandle", Vector3(x, .29, 0), Vector3(.07, .37, .08), _mat("black_tape", Color("242925")))
	var note := _mat("banknote", Color("95a46e"))
	var band := _mat("cash_band", Color("e6dab3"))
	for index in 7:
		var position_value := Vector3((index % 4) * .22 - .34, .24 + (index / 4) * .10, .14)
		_box(_raid_loot, "CashBundle", position_value, Vector3(.19, .085, .32), note)
		_box(_raid_loot, "BundleBand", position_value + Vector3(0, .044, 0), Vector3(.045, .006, .323), band)
	# Empty canisters and a rolled tarp stay at the rear east wall, away from
	# authored guards, loot access and the flanking route.
	for z in [-2.9, -1.55]:
		_box(self, "SupplyCanister", Vector3(30.35, .53, z), Vector3(.65, 1.06, .72), _mat("canister", Color("596256")))
		_solid("SupplyCanister", Vector3(30.35, .53, z), Vector3(.65, 1.06, .72))
	for x in [16.1, 30.8]:
		_post(Vector3(x, 1.625, -5.4), "RaidRearPost%d" % int(x))
		_post(Vector3(x, 1.625, 9.65), "RaidFrontPost%d" % int(x))
	_box(self, "RaidPowerCable", Vector3(23.3, 3.25, 2.4), Vector3(14.7, .035, .035), _mat("cable", Color("1c2223")))
	for x in [19.1, 28.0]:
		_box(self, "RaidLampDrop", Vector3(x, 2.95, 2.4), Vector3(.035, .6, .035), _mat("cable", Color("1c2223")))
		_lamp("RaidLamp%d" % int(x), Vector3(x, 2.63, 2.4), Color("d0ded2"), 11.5, 3.1)
	set_raid_loot_available(raid_loot_available)

func set_raid_loot_available(value: bool) -> void:
	raid_loot_available = value
	if is_instance_valid(_raid_loot): _raid_loot.visible = value

func reveal_secret(animate: bool, revealed := true) -> void:
	_secret = revealed
	if is_instance_valid(_reveal_tween): _reveal_tween.kill()
	_relic.visible = revealed
	_relic_light.visible = revealed
	if not animate:
		_lid.rotation.x = -1.65 if revealed else 0.0
		_lever.rotation.z = -.65 if revealed else .3
		_relic.position.y = 2.0 if revealed else RELIC_HIDDEN_Y
		_relic_light.light_energy = 1.75 if revealed else 0.0
		return
	# Radius .95 leaves the top at 1.35, below the lid underside at 1.435.
	_relic.position.y = RELIC_HIDDEN_Y
	_relic_light.light_energy = 0
	_reveal_tween = create_tween().set_parallel(true)
	_reveal_tween.tween_property(_lever, "rotation:z", -.65, .35).set_trans(Tween.TRANS_SINE)
	_reveal_tween.tween_property(_lid, "rotation:x", -1.65, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_reveal_tween.tween_property(_relic, "position:y", 2.0, 2.0).set_delay(.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_relic_light, "light_energy", 1.75, 1.7).set_delay(.4)

func set_active(value: bool) -> void:
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if not value and is_instance_valid(_reveal_tween):
		_reveal_tween.kill()
		reveal_secret(false, _secret)

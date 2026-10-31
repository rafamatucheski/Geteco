extends Node3D
## Parque de pesca ao ar livre no bosque oeste, acessado por uma estrada de terra local.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const LOCATION := preload("res://runtime/FishingLocation.gd")
const ANCHOR := LOCATION.ANCHOR
const LOT := LOCATION.GROUNDS
const DRIVEWAY := LOCATION.DRIVEWAY
const ANGLER := preload("res://world/places/fishing/FishingAngler.gd")
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
const FINISH := preload("res://world/places/fishing/FishingGround.gd")
const NAMES := ["Lia", "Rui", "Nina", "Beto", "Celso"]
const PLAYER_ANGLES := [.76, 1.15, 1.70, 2.12]
const NPC_ANGLES := [-.08, .35, 2.66, 3.37, 4.60]
const WATER_Y := .055
var anglers: Array[CharacterBody3D] = []
var complete := false
var pond_polygon := PackedVector2Array()
var solid_inventory: Array[Dictionary] = []
var _materials: Dictionary = {}
var _surfaces: Dictionary = {}
static var _box_meshes: Dictionary = {}
var _solids: StaticBody3D
var _focus := Vector3.INF
var _near := true
var _clock := 0.0
var _gameplay: Node
var gameplay: Node:
	get: return _gameplay
var _spawn_index := 0
var water_dynamics: RefCounted

static func reserved(point: Vector2, margin := 0.0) -> bool:
	return LOCATION.reserved(point,margin)

func _ready() -> void:
	name = "LagoSereno"
	position = ANCHOR
	add_to_group("fishing_site")
	add_to_group("native_water_surface")
	build()

func build() -> void:
	if complete: return
	_solids = StaticBody3D.new()
	_solids.name = "FishingParkSolids"
	_solids.collision_layer = 1
	_solids.collision_mask = 0
	add_child(_solids)
	_build_materials()
	_build_pond()
	water_dynamics = preload("res://world/places/fishing/FishingWaterDynamics.gd").new(pond_polygon)
	_materials.water.set_shader_parameter("rain_height", water_dynamics.texture)
	preload("res://world/places/fishing/FishingLakeDetail.gd").build(self)
	_build_entrance()
	_build_furniture()
	_flush()
	complete = true

func finish_build() -> void:
	build()
	while _spawn_index < NAMES.size(): _spawn_angler()

func entry_position() -> Vector3:
	return to_global(Vector3(10, .08, 24))

func reception_position() -> Vector3:
	return entry_position()

func is_angler_available(index: int) -> bool:
	return index >= 0 and index < anglers.size() and is_instance_valid(anglers[index]) and not anglers[index].dead and anglers[index]._fear <= 0

func show_rival_catch(index: int,fish: Dictionary) -> void:
	if is_angler_available(index): anglers[index].show_catch(fish)

func entrance_position() -> Vector3:
	return to_global(Vector3(0, .05, 30))

func approach_waypoints(index: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	if index < 0 or index >= PLAYER_ANGLES.size(): return result
	# Sai do balcão pelo oeste e depois segue o caminho livre da margem.
	for point in [Vector3(3,.08,24),Vector3(0,.08,21)]: result.append(to_global(point))
	var target: float = PLAYER_ANGLES[index]
	for step in range(1,7):
		var angle := lerpf(PI*.5,target,float(step)/6.0)
		result.append(to_global(_shore(angle)+_outward(angle)*2.65+Vector3.UP*.08))
	result.append(fishing_spots()[index].position)
	return result

func fishing_spots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in PLAYER_ANGLES.size():
		var angle: float = PLAYER_ANGLES[index]
		var shore := _shore(angle)
		var out := _outward(angle)
		result.append({"id":"sereno_%d" % index,
			"position":to_global(shore + out * 1.65 + Vector3.UP * .085),
			"water":to_global(shore - out * 5.0 + Vector3.UP * WATER_Y)})
	return result

func contains_water(world_position: Vector3) -> bool:
	var point := to_local(world_position)
	return Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), pond_polygon)

func rain_surface_height_at(point: Vector3) -> float:
	var local := to_local(point)
	return global_position.y + WATER_Y + water_dynamics.height_at(Vector2(local.x, local.z))

func receive_rain_impact(point: Vector3, strength: float, delay: float) -> void:
	if not _near or not contains_water(point): return
	var local := to_local(point)
	water_dynamics.impact(Vector2(local.x, local.z), strength, delay)

func set_focus(point: Vector3) -> void:
	_focus = point
	_update_budget()

func bind_gameplay(gameplay_node: Node) -> void:
	if _gameplay == gameplay_node: return
	_gameplay = gameplay_node
	for angler in anglers:
		if is_instance_valid(angler): angler.bind_gameplay(gameplay_node)

func _process(delta: float) -> void:
	if water_dynamics != null: water_dynamics.update(delta)
	# Só um rig nativo novo por quadro na primeira admissão.
	if _spawn_index < NAMES.size(): _spawn_angler()
	_clock -= delta
	if _clock > 0: return
	_clock = .25
	_update_budget()

func _update_budget() -> void:
	var focus := _focus
	if not focus.is_finite():
		var camera := get_viewport().get_camera_3d()
		if camera != null: focus = camera.global_position
	var near := not focus.is_finite() or focus.distance_squared_to(global_position) < 110.0 * 110.0
	if near == _near: return
	_near = near
	for angler in anglers:
		if is_instance_valid(angler): angler.set_active(near)

func _spawn_angler() -> void:
	var index := _spawn_index
	_spawn_index += 1
	var angle: float = NPC_ANGLES[index]
	var shore := _shore(angle)
	var outward := _outward(angle)
	var angler := ANGLER.new()
	angler.name = NAMES[index]
	angler.identity = 600 + index
	angler.position = shore + outward * 1.6 + Vector3.UP * .09
	angler.water_target = to_global(shore - outward * 4.5 + Vector3.UP * WATER_Y)
	angler.set_meta("region_id", "harbor")
	add_child(angler)
	anglers.append(angler)
	angler.bind_gameplay(_gameplay)
	angler.set_active(_near)

func _build_materials() -> void:
	for row in [["wood","796347","wood"],["darkwood","493d2e","wood"],
		["gravel","928675","gravel"],["earth","756449","gravel"],
		["stone","777e70","concrete"],["metal","3a4943",""],
		["roof","466454",""],["cream","c0b7a0",""],["leaf","465f3e",""],
		["leaf_dark","364b32",""],["terracotta","a27855",""]]:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(row[1])
		material.roughness = .91
		if not str(row[2]).is_empty() and str(row[2]) != "wood":
			GROUND.bind(material, row[2])
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * .55
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[row[0]] = material
		if str(row[2]) == "wood":
			var wood := ShaderMaterial.new()
			wood.shader = preload("res://world/places/fishing/fishing_wood.gdshader")
			wood.set_shader_parameter("base_color",Color(row[1]))
			_materials[row[0]] = wood
	_materials.grass = GRASS.ground_material()
	var water := ShaderMaterial.new()
	water.shader = preload("res://world/places/fishing/fishing_water.gdshader")
	_materials.water = water

func _shore(angle: float, extra := 0.0) -> Vector3:
	var lobe := 1.0 + .045 * sin(angle * 3.0 + .6) + .025 * cos(angle * 5.0)
	return Vector3(cos(angle) * (27 * lobe + extra), 0, -4 + sin(angle) * (18 * lobe + extra))

func _outward(angle: float) -> Vector3:
	return Vector3(cos(angle) / 27.0, 0, sin(angle) / 18.0).normalized()

func _build_pond() -> void:
	const SEGMENTS := 72
	for i in SEGMENTS:
		var angle := TAU * float(i) / SEGMENTS
		var next := TAU * float(i + 1) / SEGMENTS
		var a := _shore(angle)
		var b := _shore(next)
		pond_polygon.append(Vector2(a.x, a.z))
		# Faixas concêntricas deixam o campo de altura compartilhado deformar a superfície real.
		var water_center := Vector3(0, WATER_Y, -4)
		for radial in 24:
			var inner := float(radial) / 24.0
			var outer := float(radial + 1) / 24.0
			var ai := water_center.lerp(a + Vector3.UP * WATER_Y, inner)
			var bi := water_center.lerp(b + Vector3.UP * WATER_Y, inner)
			var ao := water_center.lerp(a + Vector3.UP * WATER_Y, outer)
			var bo := water_center.lerp(b + Vector3.UP * WATER_Y, outer)
			_triangle("water", ai, bo, ao)
			if radial > 0: _triangle("water", ai, bi, bo)
		# Every shore band shares its contour, without coplanar duplicate layers.
		_ring_quad("stone", a, b, _shore(angle, .4), _shore(next, .4), .075)
		if FINISH.previous_finish():
			_ring_quad("gravel", _shore(angle, .4), _shore(next, .4), _shore(angle, 3.7), _shore(next, 3.7), .065)
			_ring_quad("earth", _shore(angle, 3.7), _shore(next, 3.7), _shore(angle, 4.15), _shore(next, 4.15), .035)
			_ring_quad("grass", _shore(angle, 4.15), _shore(next, 4.15), _shore(angle, 5.2 + .4 * sin(angle * 7)), _shore(next, 5.2 + .4 * sin(next * 7)), .018)
		# O guarda-corpo visível contínuo mantém pedestres e veículos fora da água.
		var side := b - a
		var plank_basis := Basis(Vector3.UP, atan2(side.x, side.z))
		var center := (a + b) * .5
		_box("wood", center + Vector3.UP * .94, Vector3(.11, .13, side.length() + .08), false, plank_basis)
		_box("darkwood", center + Vector3.UP * .44, Vector3(.075, .08, side.length() + .05), false, plank_basis)
		_add_solid("PondGuard_%02d" % i, center + Vector3.UP * .52, Vector3(.17, 1.04, side.length() + .1), plank_basis)
		if i % 2 == 0: _box("darkwood", a + Vector3.UP * .53, Vector3(.16, 1.06, .16))
	for angle in PLAYER_ANGLES + NPC_ANGLES:
		var a := float(angle)
		var outward := _outward(a)
		var platform_basis := Basis(Vector3.UP, atan2(outward.x, outward.z))
		var center := _shore(a) + outward * 1.82
		_box("darkwood", center + Vector3.UP * .025, Vector3(3.9, .06, 3.2), false, platform_basis)
		for plank in 13:
			_box("wood", center + platform_basis.x * (-1.8 + plank * .30) + Vector3.UP * .069, Vector3(.284, .02, 3.2), false, platform_basis)
		_add_solid("FishingPlatform", center + Vector3.UP * .015, Vector3(3.9, .12, 3.2), platform_basis)

func _build_entrance() -> void:
	var paving := PackedVector2Array([Vector2(-18, 22),Vector2(-15,19),Vector2(-4,19),Vector2(4,20),Vector2(16,20),Vector2(20,23),Vector2(19,31),Vector2(4,32),Vector2(4,32.5),Vector2(-4,32.5),Vector2(-4,32),Vector2(-18,31)])
	if FINISH.previous_finish(): _polygon("gravel", paving, .04)
	# O portal fica de frente para a aproximação final da estrada, não para a grade do estacionamento.
	var road_outward: Vector2 = (LOCATION.ROAD_POINTS[-2] - LOCATION.ROAD_POINTS[-1]).normalized()
	var portal_basis := Basis(Vector3.UP, atan2(road_outward.x, road_outward.y))
	var portal_center := Vector3(0, 0, 30)
	for x in [-5.0, 5.0]:
		_box("darkwood", portal_center + portal_basis * Vector3(x,1.95,0), Vector3(.28,3.9,.28), true, portal_basis)
	_box("darkwood", portal_center + Vector3(0,3.55,0), Vector3(10.4,.7,.22), false, portal_basis)
	var entrance_label := Label3D.new()
	entrance_label.name = "LagoSerenoName"
	entrance_label.text = "Lago Sereno"
	entrance_label.font_size = 72
	entrance_label.pixel_size = .009
	entrance_label.modulate = Color("eee8cd")
	entrance_label.outline_size = 0
	entrance_label.transform = Transform3D(portal_basis, portal_center + portal_basis * Vector3(0,3.56,.125))
	add_child(entrance_label)
	# Three vehicle bays and a wide pedestrian approach.
	var marking_height := .058 if FINISH.previous_finish() else .009
	for x in [-15.0,-10.4,-5.8]:
		for edge in [-2.0,2.0]: _box("cream",Vector3(x+edge,marking_height,27),Vector3(.08,.012,5.3))
		_box("wood",Vector3(x,.13,24.2),Vector3(3.2,.26,.18),true)
	# Balcão aberto ao ar livre: este local não tem transição de interior.
	for x in [7.5,12.5]:
		for z in [19.8,23.5]: _box("darkwood",Vector3(x,1.55,z),Vector3(.16,3.1,.16),true)
	_box("roof",Vector3(10,3.12,21.65),Vector3(5.8,.18,4.5))
	_box("wood",Vector3(10,.51,22.5),Vector3(4.2,1.02,.72),true)
	_box("darkwood",Vector3(10,1.05,22.5),Vector3(4.4,.08,.90))
	_box("metal",Vector3(9.1,1.12,22.45),Vector3(.58,.08,.45),true)
	_box("cream",Vector3(9.1,1.2,22.45),Vector3(.46,.05,.32))
	_cylinder("terracotta",Vector3(11.1,1.22,22.45),.14,.24)
	_cylinder("cream",Vector3(11.1,1.4,22.45),.22,.14)
	for x in [8.0,8.3,8.6]: _beam("darkwood",Vector3(x,.08,20.25),Vector3(x+.12,2.35,20.12),.027)
	_add_solid("RodRack",Vector3(8.25,1.05,20.15),Vector3(.85,2.1,.38))

func _build_furniture() -> void:
	for angle in NPC_ANGLES:
		var a := float(angle)
		var outward := _outward(a)
		var bench_basis := Basis(Vector3.UP, atan2(outward.x,outward.z))
		var shore := _shore(a)
		var bench := shore + outward * 3.45
		_box("wood",bench+Vector3.UP*.44,Vector3(1.65,.11,.50),false,bench_basis)
		_box("wood",bench+outward*.2+Vector3.UP*.83,Vector3(1.65,.48,.08),false,bench_basis)
		for side in [-.64,.64]: _box("metal",bench+bench_basis.x*side+Vector3.UP*.22,Vector3(.10,.44,.42),false,bench_basis)
		_add_solid("AnglerBench",bench+Vector3.UP*.50,Vector3(1.72,1,.58),bench_basis)
		var bucket := shore + outward * 1.8 + bench_basis.x * 1.10
		_cylinder("metal",bucket+Vector3.UP*.23,.22,.44)
		_add_solid("FishBucket",bucket+Vector3.UP*.22,Vector3(.44,.44,.44))
	# Os postos do sul ficam livres na câmera normal: as antigas copas em primeiro
	# plano escondiam a pose de vara do Dante. Essas três árvores sombreiam a margem norte,
	# com as copas dentro do terreno e sem contato com o terreno do motocross.
	for index in 7:
		var angle := -.40 + float(index)*.62
		var point := _shore(angle,7.0)
		if index == 2: point = Vector3(-23,0,-21)
		elif index == 3: point = Vector3(-16,0,-24)
		elif index == 4: point = Vector3(18,0,-24)
		_tree(point,index)
	for point in [Vector3(-23,0,17),Vector3(25,0,17)]:
		_box("wood",point+Vector3.UP*.78,Vector3(2.5,.11,1.3),true)
		for z in [-1.0,1.0]: _box("wood",point+Vector3(0,.43,z),Vector3(2.8,.12,.40),true)
		for x in [-.86,.86]: _box("darkwood",point+Vector3(x,.36,0),Vector3(.16,.72,1.8),false)
		_add_solid("PicnicTable",point+Vector3.UP*.42,Vector3(2.55,.84,1.32))
	for index in 18:
		var angle := TAU*float(index)/18.0
		if sin(angle) > .62: continue
		var point := _shore(angle,4.4)
		for stem in 3:
			var offset := Vector3(float(stem-1)*.14,0,sin(float(index+stem))*.18)
			_beam("leaf_dark",point+offset,point+offset+Vector3(.04,.55+float(stem%2)*.25,.03),.045)

func _tree(point: Vector3,index: int) -> void:
	_cylinder("darkwood",point+Vector3.UP*1.75,.18,3.5)
	_add_solid("TreeTrunk",point+Vector3.UP*1.7,Vector3(.40,3.4,.40))
	for lobe in 4:
		var mesh := SphereMesh.new()
		mesh.radius = 1.2 + .12*float((index+lobe)%3)
		mesh.height = mesh.radius*1.65
		mesh.radial_segments = 10
		mesh.rings = 4
		var angle := float(lobe)*TAU/4
		_append_mesh("leaf" if lobe%2 else "leaf_dark",mesh,Transform3D(Basis.IDENTITY,point+Vector3(cos(angle)*.7,3.5+float(lobe%2)*.45,sin(angle)*.7)))

func _ring_quad(material: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3,height: float) -> void:
	var up := Vector3.UP*height
	_triangle(material,a+up,b+up,c+up)
	_triangle(material,b+up,d+up,c+up)

func _polygon(material: String,points: PackedVector2Array,height: float) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for i in range(0,indices.size(),3):
		var a := points[indices[i]]
		var b := points[indices[i+1]]
		var c := points[indices[i+2]]
		_triangle(material,Vector3(a.x,height,a.y),Vector3(c.x,height,c.y),Vector3(b.x,height,b.y))

func _surface(material: String) -> SurfaceTool:
	if not _surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[material] = surface
	return _surfaces[material]

func _triangle(material: String,a: Vector3,b: Vector3,c: Vector3) -> void:
	var surface := _surface(material)
	# Godot front faces use clockwise winding. All these surfaces face upwards.
	var points := [a,b,c] if (b-a).cross(c-a).y <= 0 else [a,c,b]
	for point in points:
		surface.set_normal(Vector3.UP)
		surface.set_uv(Vector2(point.x,point.z))
		surface.add_vertex(point)

func _append_mesh(material: String,mesh: Mesh,mesh_transform: Transform3D) -> void:
	var arrays := MESH_ARRAYS.arrays_of(mesh, 0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var surface := _surface(material)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in count:
		var index := indices[i] if not indices.is_empty() else i
		surface.set_normal((mesh_transform.basis*normals[index]).normalized())
		surface.set_uv(uv[index] if index < uv.size() else Vector2.ZERO)
		surface.add_vertex(mesh_transform*vertices[index])

func _box(material: String,point: Vector3,size: Vector3,solid := false,orientation := Basis.IDENTITY) -> void:
	if not _box_meshes.has(size):
		var box := BoxMesh.new()
		box.size = size
		_box_meshes[size] = box
	var mesh: BoxMesh = _box_meshes[size]
	_append_mesh(material,mesh,Transform3D(orientation,point))
	if solid: _add_solid(material.capitalize()+"Furniture",point,size,orientation)

func _cylinder(material: String,point: Vector3,radius: float,height: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	_append_mesh(material,mesh,Transform3D(Basis.IDENTITY,point))

func _beam(material: String,a: Vector3,b: Vector3,radius: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius*.75
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	_append_mesh(material,mesh,Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5))

func _add_solid(id: String,point: Vector3,size: Vector3,orientation := Basis.IDENTITY) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.name = id
	collision.shape = shape
	collision.transform = Transform3D(orientation,point)
	_solids.add_child(collision)
	solid_inventory.append({"id":id,"position":point,"size":size,"basis":orientation})

func _flush() -> void:
	for key in _surfaces:
		var mesh := MeshInstance3D.new()
		mesh.name = "LagoSereno_"+str(key)
		mesh.mesh = _surfaces[key].commit()
		mesh.material_override = _materials[key]
		if key in ["water","earth","gravel","grass"]: mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
	_surfaces.clear()

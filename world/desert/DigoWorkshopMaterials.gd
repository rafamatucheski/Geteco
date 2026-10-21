extends RefCounted
## Digo-only finishes. Imported mipmapped tiles, one cached architectural batch,
## the two authored shadowless lights, and no frame processing or extra viewport.
const SHOP := preload("res://world/places/ShopInteriorMaterials.gd")
const SURFACE_KINDS := ["steel","steel_dark","steel_brushed","enamel_red","enamel_green","wood","rubber","plastic","screen","paper"]
static var _materials: Dictionary = {}
static var _architecture: ArrayMesh

static func material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind): return _materials[kind]
	var result := StandardMaterial3D.new()
	result.resource_name = "digo_workshop_"+kind
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match kind:
		"epoxy":
			result.albedo_texture = preload("res://assets/materials/digo_workshop/epoxy_albedo.png")
			result.roughness_texture = preload("res://assets/materials/digo_workshop/epoxy_roughness.png")
			result.normal_texture = preload("res://assets/materials/digo_workshop/epoxy_normal.png")
			result.normal_enabled = true
			result.normal_scale = .26
			result.roughness = 1.0
			result.metallic_specular = .32
			_triplanar(result,4.0)
		"block":
			result.albedo_texture = preload("res://assets/materials/digo_workshop/block_albedo.png")
			result.roughness_texture = preload("res://assets/materials/digo_workshop/block_roughness.png")
			result.normal_texture = preload("res://assets/materials/digo_workshop/block_normal.png")
			result.normal_enabled = true
			result.normal_scale = .45
			result.roughness = 1.0
			result.metallic_specular = .15
			_triplanar(result,1.6)
		"steel","steel_brushed":
			result.albedo_color = Color("7a858b" if kind == "steel_brushed" else "566169")
			result.metallic = .62
			result.roughness = .44 if kind == "steel_brushed" else .57
		"steel_dark":
			result.albedo_color = Color("303c43")
			result.metallic = .5
			result.roughness = .64
		"enamel_red","enamel_green":
			result.albedo_color = Color("913f37" if kind == "enamel_red" else "3f5952")
			result.metallic = .16
			result.roughness = .48
		"wood":
			result = SHOP.material("wood",Color("79644c")).duplicate() as StandardMaterial3D
			result.resource_name = "digo_workshop_wood"
			result.roughness = .72
		"rubber":
			result.albedo_color = Color("22282b")
			result.roughness = .94
		"plastic":
			result.albedo_color = Color("3c474a")
			result.roughness = .61
		"screen":
			result.albedo_color = Color("284f58")
			result.roughness = .4
			result.emission_enabled = true
			result.emission = Color("67939a")
			result.emission_energy_multiplier = .22
		"paper":
			result.albedo_color = Color("c0bba7")
			result.roughness = .88
		"safety":
			result.albedo_color = Color("c5a452")
			result.roughness = .82
		"emitter":
			result.albedo_color = Color("e8e4d6")
			result.roughness = .45
			result.emission_enabled = true
			result.emission = Color("fff1dc")
			result.emission_energy_multiplier = .9
		_:
			result.albedo_color = Color("747c7d")
			result.roughness = .8
	_materials[kind] = result
	return result

static func _triplanar(result: StandardMaterial3D, metres: float) -> void:
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	result.uv1_scale = Vector3.ONE/metres

static func apply(room: Node3D) -> void:
	if room.has_meta("digo_workshop_materials"): return
	room.set_meta("digo_workshop_materials",true)
	for mesh: MeshInstance3D in room.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null: continue
		var id := str(mesh.name)
		if id == "ConcreteFloor": mesh.material_override = material("epoxy")
		elif "Wall" in id: mesh.material_override = material("block")
		elif id.begins_with("BayPaint"): mesh.material_override = material("safety")
		elif id.begins_with("LiftPost") or id.begins_with("ToolChest"): mesh.material_override = material("enamel_red")
		elif id.begins_with("RoofTruss") or id.begins_with("PartsShelf") or id.begins_with("LiftFoot"): mesh.material_override = material("steel_dark")
		elif id.begins_with("PartsCrate") or id in ["Workbench","TuningDesk"]: mesh.material_override = material("wood")
		elif id in ["Computer","TuningKeyboard"]: mesh.material_override = material("plastic")
		elif id.begins_with("Drawer") or id.begins_with("SocketTool"): mesh.material_override = material("steel_brushed")
		if mesh.mesh is ArrayMesh:
			for surface in mesh.mesh.get_surface_count():
				var kind: String = mesh.mesh.surface_get_name(surface)
				if kind in SURFACE_KINDS: mesh.set_surface_override_material(surface,material(kind))
	# Keep the authored sources and their range. There is no additional light or
	# shadow pass: the visible fluorescent housings below only motivate them.
	var fixtures: Array[OmniLight3D] = []
	for light: OmniLight3D in room.find_children("*","OmniLight3D",true,false):
		light.light_color = Color("fff1dc")
		light.light_energy = .85
		light.shadow_enabled = false
		fixtures.append(light)
	room.set_meta("digo_workshop_lights",fixtures)
	var details := MeshInstance3D.new()
	details.name = "DigoArchitecturalFinish"
	details.mesh = _architectural_mesh()
	details.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	room.add_child(details)

static func update_lighting(room: Node3D, night: float) -> void:
	# The existing weather curve gradually brings up the same two fittings.
	# Daylight keeps its authored finish; nighttime tuning keeps colors readable.
	if not is_instance_valid(room) or not room.has_meta("digo_workshop_lights"): return
	var energy := lerpf(.85,2.0,clampf(night,0.0,1.0))
	for light: OmniLight3D in room.get_meta("digo_workshop_lights"):
		if is_instance_valid(light) and not is_equal_approx(light.light_energy,energy): light.light_energy = energy

static func _architectural_mesh() -> ArrayMesh:
	if _architecture != null: return _architecture
	var batches := {}
	for kind in ["steel_dark","steel_brushed","emitter"]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[kind] = surface
	# Luminaires sit above standing height and do not enter the service camera's
	# free corridor. Their two real sources already belong to this room.
	for z in [-4.0,3.0]:
		_box(batches.steel_dark,Vector3(0,4.27,z),Vector3(3.6,.15,.42))
		_box(batches.emitter,Vector3(0,4.184,z),Vector3(3.26,.018,.22))
		_box(batches.steel_brushed,Vector3(0,4.17,z),Vector3(.055,.035,.24))
	# Inset drainage reads through alternating open/recessed strips. All tops
	# remain at floor level, outside the lift markings and away from spawn points.
	_box(batches.steel_dark,Vector3(0,-.005,6.2),Vector3(4.8,.006,.24))
	for i in 60:
		_box(batches.steel_brushed,Vector3(-2.36+float(i)*.08,.001,6.2),Vector3(.025,.006,.2))
	for side in [-1.0,1.0]:
		_box(batches.steel_dark,Vector3(side*12.27,.12,0),Vector3(.025,.24,17.5))
	_box(batches.steel_dark,Vector3(0,.12,-8.76),Vector3(24.5,.24,.025))
	# Conduits follow the rear wall above furniture rather than floating across
	# the room or changing the clear route around the car.
	for y in [3.18,3.4]:
		_pipe(batches.steel_brushed,Vector3(0,y,-8.735),24.0,.024,true)
	_pipe(batches.steel_brushed,Vector3(-11.7,2.45,-8.735),1.9,.024,false)
	for i in 11:
		_box(batches.steel_dark,Vector3(-11.7+float(i)*2.34,3.29,-8.715),Vector3(.06,.32,.055))
	_architecture = ArrayMesh.new()
	for kind in batches:
		batches[kind].commit(_architecture)
		var index := _architecture.get_surface_count()-1
		_architecture.surface_set_name(index,kind)
		_architecture.surface_set_material(index,material(kind))
	return _architecture

static func _box(surface: SurfaceTool, at: Vector3, size: Vector3) -> void:
	var primitive := BoxMesh.new()
	primitive.size = size
	surface.append_from(primitive,0,Transform3D(Basis.IDENTITY,at))

static func _pipe(surface: SurfaceTool, at: Vector3, length: float, radius: float, horizontal: bool) -> void:
	var primitive := CylinderMesh.new()
	primitive.top_radius = radius
	primitive.bottom_radius = radius
	primitive.height = length
	primitive.radial_segments = 10
	var basis := Basis(Vector3.FORWARD,PI*.5) if horizontal else Basis.IDENTITY
	surface.append_from(primitive,0,Transform3D(basis,at))

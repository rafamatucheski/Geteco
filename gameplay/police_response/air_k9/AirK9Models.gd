extends RefCounted
## Native geometry, sharing materials. No private viewports or transparent rotor discs.
static var _materials: Dictionary = {}

static func material(color: Color) -> StandardMaterial3D:
	if _materials.has(color): return _materials[color]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.76
	_materials[color] = result
	return result

static func part(parent: Node3D, label: String, mesh: Mesh, point: Vector3, color: Color) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.position = point
	result.material_override = material(color)
	parent.add_child(result)
	return result

static func box(parent: Node3D, label: String, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return part(parent, label, mesh, point, color)

static func ellipsoid(parent: Node3D, label: String, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var result := part(parent, label, mesh, point, color)
	result.scale = size
	return result

static func helicopter(parent: Node3D) -> Dictionary:
	var navy := Color("182c3b")
	var ivory := Color("d2d9d5")
	var glass := Color("23414d")
	var black := Color("172025")
	ellipsoid(parent, "Cabin", Vector3(0, 0, -0.3), Vector3(2.4, 2.0, 4.8), ivory)
	ellipsoid(parent, "Belly", Vector3(0, -0.48, 0), Vector3(2.3, 1.1, 4.1), navy)
	ellipsoid(parent, "CockpitGlass", Vector3(0, 0.28, -1.68), Vector3(2.05, 1.37, 1.65), glass)
	box(parent, "WindshieldDivider", Vector3(0, 0.37, -2.32), Vector3(0.085, 1.12, 0.06), ivory)
	for side in [-1.0, 1.0]:
		box(parent, "SlidingDoor", Vector3(side * 1.14, 0, 0.45), Vector3(0.085, 1.33, 1.84), navy)
		box(parent, "DoorWindow", Vector3(side * 1.2, 0.36, 0.32), Vector3(0.045, 0.54, 1.32), glass)
		box(parent, "DoorHandle", Vector3(side * 1.23, -0.13, 0.02), Vector3(0.06, 0.055, 0.24), ivory)
		box(parent, "PoliceStripe", Vector3(side * 1.205, -0.32, 0.45), Vector3(0.04, 0.16, 1.8), ivory)
		box(parent, "Skid", Vector3(side * 1.42, -1.45, -0.05), Vector3(0.13, 0.13, 4.3), black)
		for z in [-1.15, 1.0]:
			var strut := box(parent, "SkidStrut", Vector3(side * 1.1, -1.05, z), Vector3(0.105, 0.85, 0.11), black)
			strut.rotation.z = side * -0.5
	var tail := box(parent, "TailBoom", Vector3(0, 0.28, 3.65), Vector3(0.49, 0.54, 4.5), navy)
	tail.rotation.x = -0.1
	box(parent, "TailFin", Vector3(0, 1.0, 5.6), Vector3(0.14, 1.9, 0.9), ivory).rotation.x = -0.25
	box(parent, "TailStabilizer", Vector3(0, 0.32, 4.95), Vector3(2.5, 0.1, 0.58), ivory)
	box(parent, "EngineHousing", Vector3(0, 1.05, 0.4), Vector3(1.5, 0.55, 2.0), navy)
	box(parent, "RotorMast", Vector3(0, 1.64, 0), Vector3(0.18, 0.75, 0.18), black)
	var rotor := Node3D.new()
	rotor.name = "MainRotor"
	rotor.position.y = 2.03
	parent.add_child(rotor)
	for angle in [0.0, PI * 0.5]:
		var blade := box(rotor, "Blade", Vector3.ZERO, Vector3(8.7, 0.045, 0.2), black)
		blade.rotation.y = angle
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tail_rotor := Node3D.new()
	tail_rotor.name = "TailRotor"
	tail_rotor.position = Vector3(-0.3, 0.9, 5.65)
	parent.add_child(tail_rotor)
	for angle in [0.0, PI * 0.5]:
		var blade := box(tail_rotor, "TailBlade", Vector3.ZERO, Vector3(0.055, 1.65, 0.12), black)
		blade.rotation.x = angle
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"rotor": rotor, "tail_rotor": tail_rotor}

static func dog_scale(variant: int) -> float:
	return preload("res://gameplay/police_response/air_k9/PoliceDogArt.gd").variant_scale(variant)

static func dog(parent: Node3D, variant: int = 0) -> Dictionary:
	return preload("res://gameplay/police_response/air_k9/PoliceDogArt.gd").build(parent, variant)

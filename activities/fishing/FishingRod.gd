extends Node3D
## One reusable rod, float and caught-fish mesh; no particles or render viewport.
const RULES := preload("res://activities/fishing/FishingRules.gd")
var _segments: Array[MeshInstance3D] = []
var _line: MeshInstance3D
var _float: MeshInstance3D
var _reel: MeshInstance3D
var _fish: Node3D
var _fish_body: MeshInstance3D
var _fish_material: StandardMaterial3D
var _fish_belly: MeshInstance3D
var _fish_belly_material: StandardMaterial3D
var _fish_fins: MeshInstance3D
var _fish_tail: Node3D
var _fish_tail_mesh: MeshInstance3D
var _fish_fin_material: StandardMaterial3D
var _fish_details: MeshInstance3D
var _fish_gills: Array[MeshInstance3D] = []
var _fish_detail_material: StandardMaterial3D
var _fish_eye_material: StandardMaterial3D
var _fish_mouth_material: StandardMaterial3D
var _fish_mouth: MeshInstance3D
var _fish_species := ""
var _fish_strength := 0.5
var _ripple: MeshInstance3D
var _age := 0.0
var right_grip := Vector3(.17, 1.02, -.33)
var left_grip := Vector3(-.02, .98, -.43)

func _ready() -> void:
	var carbon := _material(Color("35434a"))
	var cork := _material(Color("b69667"))
	for i in 7:
		var mesh := CylinderMesh.new()
		mesh.top_radius = .018 if i == 0 else maxf(.005, .015 - i * .0015)
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1.0
		mesh.radial_segments = 6
		var segment := _mesh(mesh, cork if i == 0 else carbon)
		_segments.append(segment)
	var line_mesh := CylinderMesh.new()
	line_mesh.top_radius = .004
	line_mesh.bottom_radius = .004
	line_mesh.height = 1.0
	line_mesh.radial_segments = 3
	_line = _mesh(line_mesh, _material(Color("d9e2d3")))
	_float = _mesh(_sphere(.07), _material(Color("ec6c43")))
	_reel = _mesh(_sphere(.075), carbon)
	_reel.scale = Vector3(1, .65, 1)
	var ring := TorusMesh.new()
	ring.inner_radius = .94
	ring.outer_radius = 1.0
	ring.rings = 16
	ring.ring_segments = 4
	_ripple = _mesh(ring, _material(Color("adccc2")))
	_ripple.scale = Vector3(.16, .006, .16)
	_fish = Node3D.new()
	_fish.name = "CaughtFish"
	add_child(_fish)
	_fish_material = _material(Color("a3a89a"))
	_fish_body = _mesh(_sphere(.16), _fish_material, _fish)
	_fish_body.name = "FishBody"
	_fish_body.scale = Vector3(.90, .66, 2.15)
	_fish_belly_material = _material(Color("c5c9b0"))
	_fish_belly = _mesh(_sphere(.16), _fish_belly_material, _fish)
	_fish_belly.name = "FishBelly"
	_fish_belly.position = Vector3(0, -.035, .015)
	_fish_belly.scale = Vector3(.77, .31, 1.48)
	_fish_fin_material = _material(Color("7a8174"))
	_fish_fin_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fish_fins = _mesh(_fish_fin_mesh(), _fish_fin_material, _fish)
	_fish_fins.name = "FishFins"
	_fish_tail = Node3D.new()
	_fish_tail.name = "FishTail"
	_fish_tail.position.z = .265
	_fish.add_child(_fish_tail)
	_fish_tail_mesh = _mesh(_fish_tail_mesh_for("rounded"), _fish_fin_material, _fish_tail)
	_fish_tail_mesh.name = "CaudalFin"
	_fish_detail_material = _material(Color("596253"))
	_fish_detail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fish_details = _mesh(_fish_detail_mesh("plain"), _fish_detail_material, _fish)
	_fish_details.name = "FishMarkings"
	var gill_material := _material(Color("596253"))
	for side in [-1.0, 1.0]:
		var gill := _mesh(_sphere(.025), gill_material, _fish)
		gill.name = "GillPlate"
		gill.position = Vector3(side * .112, .004, -.105)
		gill.scale = Vector3(.27, 1.4, .24)
		_fish_gills.append(gill)
	_fish_mouth_material = _material(Color("596253"))
	_fish_mouth = _mesh(_sphere(.018), _fish_mouth_material, _fish)
	_fish_mouth.name = "Mouth"
	_fish_mouth.position = Vector3(0, -.002, -.35)
	_fish_mouth.scale = Vector3(.45, .48, .62)
	_fish_eye_material = _material(Color("101b1a"))
	var eye_glint_material := _material(Color("e8e4d4"))
	for side in [-1, 1]:
		var eye := _mesh(_sphere(.024), _fish_eye_material, _fish)
		eye.name = "FishEye"
		eye.position = Vector3(float(side) * .092, .027, -.228)
		eye.scale = Vector3(.78, .78, .82)
		var glint := _mesh(_sphere(.007), eye_glint_material, _fish)
		glint.name = "FishEyeGlint"
		glint.position = Vector3(float(side) * .107, .036, -.237)
	_fish.hide()

func present(actor, target: Vector3, phase: String, tension: float, progress: float, charge: float, fish: Dictionary, delta: float) -> void:
	_age += delta
	var direction: Vector3 = (target - actor.global_position).normalized()
	direction.y = 0
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP)
	var grip: Vector3 = actor.global_position + Vector3.UP * 1.04 + direction * .34 + right * .16
	var pitch := .48
	if phase == "charging": pitch = lerpf(.48, 1.3, charge)
	elif phase == "reeling": pitch = .54 + tension * .32
	elif phase == "caught": pitch = 1.0
	var previous := grip - direction * .18
	for i in _segments.size():
		var t := float(i + 1) / float(_segments.size())
		var reach := t * 2.5
		var bend := tension * t * t * .42 if phase == "reeling" else 0.0
		var point := grip + direction * (reach * cos(pitch) + bend) + Vector3.UP * (reach * sin(pitch) - bend)
		_between(_segments[i], previous, point)
		previous = point
	_reel.global_position = grip + Vector3.DOWN * .06
	var bobber := target + Vector3.UP * (.05 + sin(_age * 3) * .018)
	if phase == "bite": bobber.y -= .07 + sin(_age * 20) * .06
	if phase == "reeling":
		bobber = bobber.lerp(grip + direction * 1.6 - Vector3.UP * .82, progress)
		bobber += right * sin(_age * 7) * (1.0 - progress) * .3
	var floating := phase in ["waiting", "bite", "reeling", "casting"]
	_float.visible = floating
	_ripple.visible = floating
	_line.visible = floating or phase == "caught"
	if phase == "casting": bobber = previous.lerp(target, clampf(charge, 0, 1)) + Vector3.UP * sin(charge * PI) * 1.5
	_float.global_position = bobber
	_ripple.global_position = Vector3(bobber.x, target.y + .025, bobber.z)
	var ripple_scale := .1 + fmod(_age * .24, .42)
	_ripple.scale = Vector3(ripple_scale, .005, ripple_scale)
	if floating: _between(_line, previous, bobber)
	_fish.visible = phase == "caught"
	if _fish.visible:
		_fish.global_position = grip + direction * .65 + Vector3.DOWN * .15 + Vector3.UP * sin(_age * 8.0) * .025
		var twitch := .65 + _fish_strength * .55
		_fish.rotation = Vector3(sin(_age * 3.7) * .045, sin(_age * 2.2) * .20, sin(_age * 7.4) * .10)
		_fish_tail.rotation = Vector3(sin(_age * 8.5) * .06, sin(_age * 11.5) * .30 * twitch, sin(_age * 6.0) * .08)
		if not fish.is_empty():
			var definition := RULES.definition(str(fish.get("id", "")))
			if not definition.is_empty(): _configure_fish(definition)
			_fish.scale = Vector3.ONE * clampf(sqrt(float(fish.grams) / 2500.0), .6, 1.5)
		_between(_line, previous, _fish_mouth.global_position)
	var pose := {"right":right_grip, "left":left_grip, "basis":Basis.IDENTITY, "right_grip":true, "left_grip":true, "right_solve":true, "left_solve":true, "armed":true, "lean":-.035, "support_locked":false}
	actor.set_combat_weapon_pose("fishing", pose)
	actor._apply_combat_weapon_pose()

func _between(node: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var direction := b - a
	node.global_position = (a + b) * .5
	var y_axis := direction.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < .0001: x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	node.global_basis = Basis(x_axis, y_axis, x_axis.cross(y_axis)).scaled(Vector3(1, direction.length(), 1))

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	return mesh

func _configure_fish(definition: Dictionary) -> void:
	var species := str(definition.get("id", ""))
	if species == _fish_species: return
	_fish_species = species
	var color: Color = definition.get("color", Color("a3a89a"))
	_fish_strength = float(definition.get("strength", .5))
	_fish_material.albedo_color = color
	_fish_belly_material.albedo_color = color.lightened(.30)
	_fish_fin_material.albedo_color = color.darkened(.18)
	_fish_detail_material.albedo_color = color.darkened(.34)
	_fish_mouth_material.albedo_color = color.darkened(.48)
	var body_shape := str(definition.get("body_shape", "")).to_lower()
	var body_scale := Vector3(.90, .66, 2.15)
	match body_shape:
		"deep": body_scale = Vector3(.98, .84, 1.86)
		"slender": body_scale = Vector3(.76, .59, 2.38)
		"long": body_scale = Vector3(.78, .61, 2.60)
	_fish_body.scale = body_scale
	_fish_belly.scale = Vector3(body_scale.x * .78, .30, body_scale.z * .68)
	_fish_mouth.position.z = -(.16 * body_scale.z + .003)
	var gill_z := -.105
	var gill_surface := _fish_surface_x(body_scale, .004, gill_z)
	for i in _fish_gills.size():
		_fish_gills[i].position.x = (-1.0 if i == 0 else 1.0) * (gill_surface + .002)
	var pattern := str(definition.get("pattern", "plain")).to_lower()
	var markings := _fish_detail_mesh(pattern, body_scale)
	_fish_details.mesh = markings
	_fish_details.visible = markings.get_surface_count() > 0
	var tail_shape := str(definition.get("tail_shape", "rounded")).to_lower()
	_fish_tail_mesh.mesh = _fish_tail_mesh_for(tail_shape)

func _fish_fin_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	# Dorsal and anal fins follow the back and belly; pectoral and pelvic fins
	# flare from both sides of the body. They are flat, low-poly silhouettes.
	_push_triangle(vertices, normals, indices, Vector3(0, .065, -.16), Vector3(0, .16, -.015), Vector3(0, .07, .12))
	_push_triangle(vertices, normals, indices, Vector3(0, -.065, .08), Vector3(0, -.13, .20), Vector3(0, -.07, .25))
	for side in [-1.0, 1.0]:
		_push_triangle(vertices, normals, indices, Vector3(side * .105, -.005, -.10), Vector3(side * .22, -.035, .06), Vector3(side * .105, -.055, .035))
		_push_triangle(vertices, normals, indices, Vector3(side * .065, -.058, .07), Vector3(side * .145, -.10, .18), Vector3(side * .065, -.085, .16))
	return _triangle_mesh(vertices, normals, indices)

func _fish_tail_mesh_for(shape: String) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	match shape:
		"forked":
			# Two lobes with a clear central notch.
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, .14, .18), Vector3(0, .035, .10))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, -.035, .10), Vector3(0, -.14, .18))
		"fan":
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, .13, .16), Vector3(0, .07, .12))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, .07, .12), Vector3(0, 0, .15))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, 0, .15), Vector3(0, -.07, .12))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, -.07, .12), Vector3(0, -.13, .16))
		_:
			# A compact rounded fan is the safe fallback for unknown definitions.
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, .12, .13), Vector3(0, .06, .15))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, .06, .15), Vector3(0, 0, .16))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, 0, .16), Vector3(0, -.06, .15))
			_push_triangle(vertices, normals, indices, Vector3(0, 0, .008), Vector3(0, -.06, .15), Vector3(0, -.12, .13))
	return _triangle_mesh(vertices, normals, indices)

func _fish_detail_mesh(pattern: String, body_scale: Vector3) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	match pattern:
		"stripes", "striped", "bars":
			for side in [-1.0, 1.0]:
				for z in [-.13, -.025, .08, .17]:
					var x0 := side * _fish_surface_x(body_scale, -.047, z - .013)
					var x1 := side * _fish_surface_x(body_scale, .047, z - .013)
					var x2 := side * _fish_surface_x(body_scale, .047, z + .013)
					var x3 := side * _fish_surface_x(body_scale, -.047, z + .013)
					_push_quad(vertices, normals, indices,
						Vector3(x0, -.047, z - .013), Vector3(x1, .047, z - .013),
						Vector3(x2, .047, z + .013), Vector3(x3, -.047, z + .013))
		"spots", "spotted", "speckles":
			for side in [-1.0, 1.0]:
				for mark in [[-.105, .032], [-.035, -.012], [.045, .035], [.13, -.012]]:
					var z := float(mark[0])
					var y := float(mark[1])
					var radius := .013
					_push_quad(vertices, normals, indices,
						Vector3(side * _fish_surface_x(body_scale, y, z - radius), y, z - radius),
						Vector3(side * _fish_surface_x(body_scale, y + radius, z), y + radius, z),
						Vector3(side * _fish_surface_x(body_scale, y, z + radius), y, z + radius),
						Vector3(side * _fish_surface_x(body_scale, y - radius, z), y - radius, z))
	return _triangle_mesh(vertices, normals, indices)

static func _fish_surface_x(body_scale: Vector3, y: float, z: float) -> float:
	var radius_x := .16 * body_scale.x
	var radius_y := .16 * body_scale.y
	var radius_z := .16 * body_scale.z
	var remaining := 1.0 - pow(y / radius_y, 2.0) - pow(z / radius_z, 2.0)
	return radius_x * sqrt(maxf(remaining, .05)) + .0015

static func _push_quad(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_push_triangle(vertices, normals, indices, a, b, c)
	_push_triangle(vertices, normals, indices, a, c, d)

static func _push_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var first := vertices.size()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	indices.append(first)
	indices.append(first + 1)
	indices.append(first + 2)

static func _triangle_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if vertices.is_empty(): return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	return material

func _mesh(mesh: Mesh, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(node)
	return node

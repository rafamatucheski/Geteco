extends RefCounted
## Authored nodachi silhouette: curved steel, hamon, brass fittings and wrapped long grip.
## The energy conversion is emissive geometry, with no additional dynamic lights.
const TIP := Vector3(0.08, 0.0, -1.12)
const GRIP := Vector3(0.0, 0.0, 0.04)

static func create(saber := false, color := Color("68cfff")) -> Node3D:
	var root := Node3D.new()
	root.name = "TakeshiKatana"
	build(root, saber, color)
	return root

static func build(root: Node3D, saber := false, color := Color("68cfff")) -> Vector3:
	var black := _material(Color("141820"), 0.08, 0.75)
	var gold := _material(Color("bda15f"), 0.85, 0.32)
	var steel := _material(Color("abbcca"), 0.92, 0.23)
	var edge := _material(Color("e8f0f4"), 0.85, 0.17)
	_box(root, "GripCore", Vector3(0.038, 0.027, 0.30), Vector3(0, 0, 0.09), black)
	for i in 12:
		var silk_wrap := _box(root, "SilkWrap", Vector3(0.041, 0.034, 0.012), Vector3(0, 0, -0.045 + i * 0.024), black)
		silk_wrap.rotation.z = -0.5 if i % 2 else 0.5
	_box(root, "Pommel", Vector3(0.048, 0.036, 0.026), Vector3(0, 0, 0.245), gold)
	_box(root, "Habaki", Vector3(0.050, 0.015, 0.055), Vector3(0, 0, -0.102), gold)
	var guard := _box(root, "Tsuba", Vector3(0.125, 0.095, 0.016), Vector3(0, 0, -0.063), gold)
	guard.rotation.z = PI / 4.0
	if saber:
		var glow := _material(color, 0.0, 0.5)
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.emission_enabled = true
		glow.emission = color
		glow.emission_energy_multiplier = 1.5
		var core := _material(color.lerp(Color.WHITE, 0.8), 0.0, 0.4)
		core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blade(root, "EnergyBlade", glow, 0.033)
		_blade(root, "EnergyCore", core, 0.009, 0.006)
	else:
		_blade(root, "ForgedSteel", steel, 0.027)
		_blade(root, "Hamon", edge, 0.006, 0.006)
	return TIP

static func _blade(root: Node3D, label: String, material: Material, width: float, raised := 0.0) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Slight curve and a real tapered kissaki; each face gets generated normals.
	for i in 16:
		var t0 := float(i) / 16.0
		var t1 := float(i + 1) / 16.0
		var p0 := Vector3(0.08 * t0 * t0, raised, -0.12 - t0)
		var p1 := Vector3(0.08 * t1 * t1, raised, -0.12 - t1)
		var w0 := width * (1.0 - maxf(0.0, (t0 - 0.88) / 0.12))
		var w1 := width * (1.0 - maxf(0.0, (t1 - 0.88) / 0.12))
		for sign_y in [-1.0, 1.0]:
			var a := p0 + Vector3(-w0, sign_y * 0.004, 0)
			var b := p0 + Vector3(w0, sign_y * 0.004, 0)
			var c := p1 + Vector3(w1, sign_y * 0.004, 0)
			var d := p1 + Vector3(-w1, sign_y * 0.004, 0)
			for point in ([a, c, b, a, d, c] if sign_y > 0.0 else [a, b, c, a, c, d]): surface.add_vertex(point)
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = surface.commit()
	mesh.material_override = material
	root.add_child(mesh)

static func _box(root: Node3D, label: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = position
	root.add_child(mesh)
	return mesh

static func _material(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metal
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

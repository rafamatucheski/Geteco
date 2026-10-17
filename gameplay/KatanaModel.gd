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
	var underwrap := _material(Color("8d8878"), 0.0, 0.94)
	_oval(root, "GripCore", 0.019, 0.30, 0.72, Vector3(0, 0, 0.09), underwrap)
	_wrapping(root, black)
	_oval(root, "Pommel", 0.024, 0.026, 0.75, Vector3(0, 0, 0.245), gold)
	_oval(root, "Habaki", 0.025, 0.062, 0.30, Vector3(0, 0, -0.102), gold)
	_oval(root, "Tsuba", 0.0625, 0.016, 0.76, Vector3(0, 0, -0.063), gold)
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
		_steel_blade(root, steel, edge)
	return TIP

static func _oval(root: Node3D, label: String, radius: float, length: float, flatten: float, position: Vector3, material: Material) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = 16
	shape.rings = 1
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = shape
	mesh.material_override = material
	mesh.position = position
	mesh.rotation.x = PI * .5
	mesh.scale.z = flatten
	root.add_child(mesh)

static func _wrapping(root: Node3D, material: Material) -> void:
	# Two counterwound silk ribbons reveal the underwrap between the crossings.
	# All twelve turns share one surface instead of twelve independent boxes.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for turn in 12:
		var center_z := -0.039 + turn * .024
		for handedness in [-1.0, 1.0]:
			for segment in 8:
				var angle0 := float(segment) * TAU / 8.0
				var angle1 := float(segment + 1) * TAU / 8.0
				var z0: float = center_z + float(handedness) * (float(segment) / 8.0 - .5) * .024
				var z1: float = center_z + float(handedness) * (float(segment + 1) / 8.0 - .5) * .024
				var a := Vector3(cos(angle0) * .0205, sin(angle0) * .0157, z0 - .0045)
				var b := Vector3(cos(angle1) * .0205, sin(angle1) * .0157, z1 - .0045)
				var c := b + Vector3(0, 0, .009)
				var d := a + Vector3(0, 0, .009)
				var outward := Vector3(cos((angle0 + angle1) * .5), sin((angle0 + angle1) * .5), 0)
				_quad(surface, a, b, c, d, outward)
	_add_mesh(root, "SilkWrap", surface, material)

static func _steel_blade(root: Node3D, steel: Material, edge: Material) -> void:
	var body := SurfaceTool.new()
	var hamon := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	hamon.begin(Mesh.PRIMITIVE_TRIANGLES)
	# A closed five-facet section has a spine, shinogi ridge and a real cutting edge.
	# The polished edge and body share their boundary; neither floats over the other.
	for segment in 12:
		var section0 := _section(float(segment) / 12.0)
		var section1 := _section(float(segment + 1) / 12.0)
		for face in [[0, 1], [1, 2], [2, 3], [5, 6], [6, 0]]:
			var a: Vector3 = section0[face[0]]
			var b: Vector3 = section0[face[1]]
			var side := Vector3(-(b.y-a.y), b.x-a.x, 0)
			_quad(body, a, b, section1[face[1]], section1[face[0]], side)
		for face in [[3, 4], [4, 5]]:
			var a: Vector3 = section0[face[0]]
			var b: Vector3 = section0[face[1]]
			var side := Vector3(-(b.y-a.y), b.x-a.x, 0)
			_quad(hamon, a, b, section1[face[1]], section1[face[0]], side)
	var base := _section(0.0)
	var cap := [0, 1, 2, 3, 5, 6]
	for i in range(1, cap.size()-1):
		_triangle(body, base[cap[0]], base[cap[i]], base[cap[i+1]], Vector3.BACK)
	_triangle(hamon, base[3], base[4], base[5], Vector3.BACK)
	_add_mesh(root, "ForgedSteel", body, steel)
	_add_mesh(root, "Hamon", hamon, edge)

static func _section(t: float) -> PackedVector3Array:
	var center := Vector3(.08 * t * t, 0, -.12 - t)
	var taper := clampf((1.0-t) / .12, 0.0, 1.0)
	var width := .027 * taper
	var thickness := .004 * taper
	var boundary := .48 + sin(t * 37.0) * .025
	var boundary_height := thickness * (1.0 - (boundary+.15) / 1.15)
	var section := PackedVector3Array()
	for p in [Vector2(-width,-thickness*.65), Vector2(-width,thickness*.65), Vector2(-width*.15,thickness), Vector2(width*boundary,boundary_height), Vector2(width,0), Vector2(width*boundary,-boundary_height), Vector2(-width*.15,-thickness)]:
		section.append(center + Vector3(p.x,p.y,0))
	return section

static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	_triangle(surface, a, b, c, outward)
	_triangle(surface, a, c, d, outward)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (b-a).cross(c-a)
	if normal.length_squared() < .0000000000000001: return
	normal = normal.normalized()
	if normal.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	surface.set_normal(normal)
	# Godot front faces are clockwise; normal is supplied explicitly.
	for point in [a, c, b]: surface.add_vertex(point)

static func _add_mesh(root: Node3D, label: String, surface: SurfaceTool, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = surface.commit()
	mesh.material_override = material
	root.add_child(mesh)

static func _blade(root: Node3D, label: String, material: Material, width: float, raised := 0.0) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Close the existing energy volume without changing its authored bounds or glow.
	for i in 16:
		var t0 := float(i) / 16.0
		var t1 := float(i + 1) / 16.0
		var p0 := Vector3(0.08 * t0 * t0, raised, -0.12 - t0)
		var p1 := Vector3(0.08 * t1 * t1, raised, -0.12 - t1)
		var w0 := width * (1.0 - maxf(0.0, (t0 - 0.88) / 0.12))
		var w1 := width * (1.0 - maxf(0.0, (t1 - 0.88) / 0.12))
		var ring0 := PackedVector3Array([p0+Vector3(-w0,-.004,0), p0+Vector3(-w0,.004,0), p0+Vector3(w0,.004,0), p0+Vector3(w0,-.004,0)])
		var ring1 := PackedVector3Array([p1+Vector3(-w1,-.004,0), p1+Vector3(-w1,.004,0), p1+Vector3(w1,.004,0), p1+Vector3(w1,-.004,0)])
		for face in 4:
			var next := (face+1)%4
			var edge := ring0[next]-ring0[face]
			var outward := Vector3(-edge.y,edge.x,0)
			_quad(surface,ring0[face],ring0[next],ring1[next],ring1[face],outward)
		if i == 0: _quad(surface,ring0[0],ring0[1],ring0[2],ring0[3],Vector3.BACK)
	_add_mesh(root, label, surface, material)

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

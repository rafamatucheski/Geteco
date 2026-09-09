@tool
extends Node3D

## Original procedural study inspired by the 911 silhouette, not an official asset.
## Coordinates in approximate metres, nose = -Z. No gameplay dependencies.
var materials: Dictionary = {}
var paint: StandardMaterial3D

func _ready() -> void:
	if get_child_count() == 0: build()

func mat(key: String, color: String, metallic := 0.0, roughness := 0.6, glow := 0.0) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.metallic = metallic
	m.roughness = roughness
	if glow > 0:
		m.emission_enabled = true
		m.emission = Color(color)
		m.emission_energy_multiplier = glow
	materials[key] = m
	return m

func mesh_node(mesh: Mesh, position_value: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position_value
	node.material_override = material
	add_child(node)
	return node

func box(pos: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	return mesh_node(mesh, pos, material)

func ell(pos: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var node := mesh_node(mesh, pos, material)
	node.scale = size_value
	return node

func cylinder(pos: Vector3, radius: float, depth: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 32
	return mesh_node(mesh, pos, material)

func tube(points: Array[Vector3], radius: float, material: Material) -> void:
	for i in range(points.size() - 1):
		var direction := points[i + 1] - points[i]
		var node := cylinder((points[i] + points[i + 1]) * 0.5, radius, direction.length(), material)
		node.quaternion = Quaternion(Vector3.UP, direction.normalized())

func surface(points: Array[Vector3], material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size() - 1):
		for point in [points[0], points[i], points[i + 1]]: tool.add_vertex(point)
	tool.generate_normals()
	mesh_node(tool.commit(), Vector3.ZERO, material)

func width_at(z: float) -> float:
	var ends := pow(absf(z) / 2.23, 8)
	return 0.83 + 0.10 * exp(-pow((z - 1.15) / 0.7, 2)) + 0.08 * exp(-pow((z + 1.28) / 0.7, 2)) - 0.16 * ends

func top_at(x_ratio: float, z: float) -> float:
	var nose := exp(-pow((z + 2.25) / 0.37, 2))
	var crown := 0.035 * (1 - x_ratio * x_ratio)
	var fender := 0.18 * (exp(-pow((z + 1.28) / 0.6, 2)) + exp(-pow((z - 1.22) / 0.6, 2))) * pow(absf(x_ratio), 2)
	return 0.75 - nose * 0.20 + crown + fender

func arch_bottom(z: float) -> float:
	var bottom := 0.25
	for wheel_z in [-1.28, 1.22]:
		var dz: float = absf(z - wheel_z)
		if dz < 0.405: bottom = maxf(bottom, 0.36 + sqrt(0.405 * 0.405 - dz * dz))
	return bottom

func build_shell() -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Crown and fenders: one continuous authored surface, not overlapping boxes.
	for j in 80:
		var z0 := lerpf(-2.23, 2.23, j / 80.0)
		var z1 := lerpf(-2.23, 2.23, (j + 1) / 80.0)
		for i in 16:
			var x0 := lerpf(-1, 1, i / 16.0)
			var x1 := lerpf(-1, 1, (i + 1) / 16.0)
			var a := Vector3(x0 * width_at(z0), top_at(x0,z0), z0)
			var b := Vector3(x0 * width_at(z1), top_at(x0,z1), z1)
			var c := Vector3(x1 * width_at(z1), top_at(x1,z1), z1)
			var d := Vector3(x1 * width_at(z0), top_at(x1,z0), z0)
			for v in [a,c,b,a,d,c]: tool.add_vertex(v)
		for side in [-1.0, 1.0]:
			var a := Vector3(side * width_at(z0), top_at(side,z0), z0)
			var b := Vector3(side * width_at(z1), top_at(side,z1), z1)
			var c := Vector3(side * (width_at(z1)-0.035), arch_bottom(z1), z1)
			var d := Vector3(side * (width_at(z0)-0.035), arch_bottom(z0), z0)
			var vertices := [a,b,c,a,c,d] if side < 0 else [a,c,b,a,d,c]
			for v in vertices: tool.add_vertex(v)
	tool.generate_normals()
	mesh_node(tool.commit(), Vector3.ZERO, paint)
	for z in [-2.23, 2.23]:
		var w := width_at(z)
		var points: Array[Vector3] = [Vector3(-w,0.25,z),Vector3(w,0.25,z),Vector3(w,top_at(1,z),z),Vector3(-w,top_at(-1,z),z)]
		if z > 0: points.reverse()
		surface(points,paint)

func build() -> void:
	paint = mat("paint", "b83632", 0.25, 0.24)
	var black := mat("rubber", "171b20", 0, 0.9)
	var trim := mat("trim", "30373d", 0.15, 0.45)
	var glass := mat("glass", "243a47", 0.35, 0.17)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rim := mat("alloy", "b5bdc3", 0.72, 0.24)
	var lens := mat("headlight", "e6f0ed", 0.15, 0.16, 0.3)
	var brake := mat("brake", "cd6133", 0.2, 0.4)
	build_shell()
	box(Vector3(0,0.245,0),Vector3(1.55,0.08,3.8),black)
	# Low roof and sloping front/rear glass form the recognizable fastback arc.
	var roof_tool := SurfaceTool.new()
	roof_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 12:
		for i in 16:
			var points: Array[Vector3] = []
			for ij in [Vector2(i,j),Vector2(i,j+1),Vector2(i+1,j+1),Vector2(i+1,j)]:
				var u: float = ij.x / 16 * 2 - 1
				var z: float = -0.30 + ij.y / 12 * 0.94
				points.append(Vector3(u * 0.60, 1.25 + 0.075 * (1-u*u) + 0.025 * sin(ij.y / 12 * PI), z))
			for k in [0,2,1,0,3,2]: roof_tool.add_vertex(points[k])
	roof_tool.generate_normals()
	mesh_node(roof_tool.commit(),Vector3.ZERO,paint)
	for i in 16:
		var u0 := -1.0 + i / 8.0
		var u1 := -1.0 + (i + 1) / 8.0
		var y0 := 1.25 + 0.075 * (1-u0*u0)
		var y1 := 1.25 + 0.075 * (1-u1*u1)
		surface([Vector3(u0*0.70,0.82,-0.88),Vector3(u1*0.70,0.82,-0.88),Vector3(u1*0.60,y1,-0.30),Vector3(u0*0.60,y0,-0.30)],glass)
		surface([Vector3(u0*0.60,y0,0.64),Vector3(u1*0.60,y1,0.64),Vector3(u1*0.73,0.82,1.42),Vector3(u0*0.73,0.82,1.42)],glass)
	for side in [-1.0,1.0]:
		var lower_front := Vector3(side*0.75,0.81,-0.73)
		var upper_front := Vector3(side*0.60,1.25,-0.30)
		var upper_rear := Vector3(side*0.60,1.25,0.64)
		var lower_rear := Vector3(side*0.78,0.82,1.17)
		surface([lower_front,upper_front,upper_rear,lower_rear],glass)
		tube([lower_front,upper_front,upper_rear,lower_rear,lower_front],0.025,paint)
		tube([Vector3(side*0.60,1.25,0.24),Vector3(side*0.765,0.815,0.32)],0.020,trim)
		# Painted rear haunch and C pillar, tapering toward the engine cover.
		surface([upper_rear,lower_rear,Vector3(side*0.86,0.85,1.55),Vector3(side*0.73,0.82,1.42)],paint)
		# Door shut line and flush handle.
		tube([Vector3(side*0.892,0.75,-0.70),Vector3(side*0.862,0.34,-0.57),Vector3(side*0.882,0.34,0.70),Vector3(side*0.912,0.76,0.83)],0.005,trim)
		box(Vector3(side*0.899,0.70,0.52),Vector3(0.023,0.025,0.15),trim)
		ell(Vector3(side*0.91,0.88,-0.54),Vector3(0.25,0.095,0.18),paint)
		ell(Vector3(side*0.935,0.88,-0.475),Vector3(0.15,0.06,0.018),rim)
		# Four wheels, real circular rims, brake discs and five split-spoke pairs.
		for wheel_z in [-1.28,1.22]:
			var first_wheel_part := get_child_count()
			var wheel := cylinder(Vector3(side*0.86,0.36,wheel_z),0.355,0.22,black)
			wheel.rotation.z = PI/2
			var disc := cylinder(Vector3(side*0.977,0.36,wheel_z),0.265,0.015,trim)
			disc.rotation.z = PI/2
			var rotor := cylinder(Vector3(side*0.988,0.36,wheel_z),0.21,0.016,mat("rotor","515963",0.55,0.55))
			rotor.rotation.z = PI/2
			var caliper := box(Vector3(side*1.001,0.38,wheel_z+0.145),Vector3(0.026,0.12,0.06),brake)
			var torus := TorusMesh.new()
			torus.inner_radius = 0.245
			torus.outer_radius = 0.273
			var ring := mesh_node(torus,Vector3(side*1.002,0.36,wheel_z),rim)
			ring.rotation.z = PI/2
			for spoke in 5:
				for split in [-0.10,0.10]:
					var angle: float = spoke * TAU / 5 + split
					var a := Vector3(side*1.007,0.36+cos(angle)*0.065,wheel_z+sin(angle)*0.065)
					var b := Vector3(side*1.007,0.36+cos(angle+0.12)*0.242,wheel_z+sin(angle+0.12)*0.242)
					tube([a,b],0.016,rim)
			var hub := cylinder(Vector3(side*1.016,0.36,wheel_z),0.063,0.022,rim)
			hub.rotation.z = PI/2
			# Explicit rig membership: body trim must never be guessed into a wheel
			# assembly by position. Brake calipers steer but do not spin.
			for part_index in range(first_wheel_part, get_child_count()):
				var part := get_child(part_index)
				part.set_meta("wheel_center", Vector3(side * 0.86, 0.36, wheel_z))
				part.set_meta("wheel_spins", part != caliper)
		# Oval headlight lenses inset into the raised front fenders.
		var lamp_pos := Vector3(side*0.67,0.815,-1.80)
		var bezel := cylinder(lamp_pos,0.154,0.023,trim)
		bezel.rotation.x = -PI*0.32
		var lamp := cylinder(lamp_pos+Vector3(0,0.009,-0.014),0.134,0.012,mat("smoked_lens","293b44",0.35,0.16))
		lamp.rotation.x = -PI*0.32
		# Four compact LED modules instead of a bright ring and dark pupil.
		for dx in [-0.060,0.060]:
			for dy in [-0.06,0.06]:
				var led := box(lamp_pos+Vector3(dx,0.019+dy*0.84,-0.030+dy*0.54),Vector3(0.036,0.008,0.022),lens)
				led.rotation.x = -PI*0.32
		box(Vector3(side*0.57,0.43,-2.235),Vector3(0.37,0.095,0.023),black)
		for slat in 3:
			box(Vector3(side*0.57,0.402+slat*0.027,-2.252),Vector3(0.33,0.009,0.018),trim)
		# Hood edges, no badge/logo.
		tube([Vector3(side*0.46,0.65,-2.01),Vector3(side*0.44,0.78,-1.40),Vector3(side*0.53,0.79,-0.94)],0.004,trim)
		var exhaust := cylinder(Vector3(side*0.55,0.29,2.23),0.065,0.12,rim)
		exhaust.rotation.x = PI/2
		var opening := cylinder(Vector3(side*0.55,0.29,2.295),0.049,0.005,black)
		opening.rotation.x = PI/2
	box(Vector3(0,0.41,-2.241),Vector3(0.55,0.095,0.025),black)
	box(Vector3(0,0.28,2.22),Vector3(1.35,0.12,0.04),trim)
	var tail := mat("tail", "eb3832", 0.1, 0.25, 0.65)
	tube([Vector3(-0.84,0.72,2.06),Vector3(-0.69,0.73,2.24),Vector3(0.69,0.73,2.24),Vector3(0.84,0.72,2.06)],0.030,trim)
	tube([Vector3(-0.84,0.72,2.06),Vector3(-0.69,0.73,2.238),Vector3(0.69,0.73,2.238),Vector3(0.84,0.72,2.06)],0.018,tail)
	for i in 9:
		box(Vector3(-0.35+i*0.0875,0.79,1.72),Vector3(0.035,0.018,0.34),black)
	box(Vector3(0,0.80,2.00),Vector3(1.46,0.035,0.13),paint)

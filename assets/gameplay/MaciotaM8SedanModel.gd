extends Node3D

## Gran cupê preto do Maciota, com proporções e detalhes inspirados no M8.
##
## A malha é autoral e não inclui marcas ou emblemas reais. O modelo mantém
## quatro portas funcionais para a missão e usa -Z como frente do veículo.
var doors: Array[Node3D] = []
var wheels: Array[Node3D] = []
var occupants: Array[Node3D] = []


func material(color: String, metal := 0.0, rough := .4, glow := 0.0) -> StandardMaterial3D:
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color(color)
	finish.metallic = metal
	finish.roughness = rough
	finish.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		finish.emission_enabled = true
		finish.emission = Color(color)
		finish.emission_energy_multiplier = glow
	return finish


func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, finish: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = finish
	node.position = at
	parent.add_child(node)
	return node


func box(parent: Node3D, size: Vector3, at: Vector3, finish: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return mesh_node(parent, shape, at, finish)


func ell(parent: Node3D, size: Vector3, at: Vector3, finish: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = .5
	shape.height = 1.0
	shape.radial_segments = 24
	shape.rings = 12
	var node := mesh_node(parent, shape, at, finish)
	node.scale = size
	return node


func cylinder(
	parent: Node3D,
	radius: float,
	height: float,
	at: Vector3,
	finish: Material,
	rot := Vector3.ZERO
) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = 24
	var node := mesh_node(parent, shape, at, finish)
	node.rotation = rot
	return node


func tube(parent: Node3D, points: Array[Vector3], radius: float, finish: Material) -> void:
	for index in points.size() - 1:
		var start := points[index]
		var end := points[index + 1]
		var direction := end - start
		var node := cylinder(parent, radius, direction.length(), (start + end) * .5, finish)
		node.quaternion = Quaternion(Vector3.UP, direction.normalized())


func add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, reverse := false) -> void:
	if reverse:
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(b)
		tool.add_vertex(a)
		tool.add_vertex(d)
		tool.add_vertex(c)
	else:
		tool.add_vertex(a)
		tool.add_vertex(b)
		tool.add_vertex(c)
		tool.add_vertex(a)
		tool.add_vertex(c)
		tool.add_vertex(d)


func surface(parent: Node3D, points: Array[Vector3], finish: Material) -> MeshInstance3D:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, points.size() - 1):
		tool.add_vertex(points[0])
		tool.add_vertex(points[index])
		tool.add_vertex(points[index + 1])
	tool.index()
	tool.generate_normals()
	var node := mesh_node(parent, tool.commit(), Vector3.ZERO, finish)
	return node


func width_at(z: float) -> float:
	var front_fender := .10 * exp(-pow((z + 1.46) / .52, 2))
	var rear_haunch := .135 * exp(-pow((z - 1.40) / .62, 2))
	var end_taper := .115 * pow(absf(z) / 2.48, 8)
	return .915 + front_fender + rear_haunch - end_taper


func deck_at(z: float) -> float:
	var nose_drop := .145 * pow(clampf((-z - 1.55) / .93, 0.0, 1.0), 1.35)
	var tail_drop := .075 * pow(clampf((z - 1.64) / .81, 0.0, 1.0), 1.25)
	return .715 - nose_drop - tail_drop


func top_at(x_ratio: float, z: float) -> Vector3:
	var half_width := width_at(z)
	var crown := .052 * (1.0 - x_ratio * x_ratio)
	var axle_swell := exp(-pow((z + 1.46) / .58, 2)) + exp(-pow((z - 1.40) / .62, 2))
	var fender := .135 * axle_swell * pow(absf(x_ratio), 3)
	var rounded_z := z - signf(z) * .085 * x_ratio * x_ratio * pow(absf(z) / 2.48, 7)
	return Vector3(x_ratio * half_width, deck_at(z) + crown + fender, rounded_z)


func arch_bottom(z: float) -> float:
	var bottom := .185
	for axle in [-1.46, 1.40]:
		var delta := absf(z - axle)
		if delta < .47:
			bottom = maxf(bottom, .365 + sqrt(.47 * .47 - delta * delta))
	return bottom


func roof_ratio(z: float) -> float:
	return clampf((z + .43) / 1.49, 0.0, 1.0)


func roof_y_at(z: float) -> float:
	var ratio := roof_ratio(z)
	return 1.17 + .078 * sin(ratio * PI) - .040 * ratio


func roof_width_at(z: float) -> float:
	return .61 + .025 * sin(roof_ratio(z) * PI)


func build_windshield(front: bool, glass: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_z := -.43 if front else 1.06
	var belt_z := -1.15 if front else 1.70
	var roof_width := roof_width_at(roof_z)
	var belt_width := .77 if front else .80
	const CROSS_SECTIONS := 14
	for cross in CROSS_SECTIONS:
		var u0 := lerpf(-1.0, 1.0, float(cross) / CROSS_SECTIONS)
		var u1 := lerpf(-1.0, 1.0, float(cross + 1) / CROSS_SECTIONS)
		var roof0 := Vector3(
			u0 * roof_width,
			roof_y_at(roof_z) + .060 * (1.0 - u0 * u0),
			roof_z
		)
		var roof1 := Vector3(
			u1 * roof_width,
			roof_y_at(roof_z) + .060 * (1.0 - u1 * u1),
			roof_z
		)
		var belt0 := Vector3(
			u0 * belt_width,
			.765 + .018 * (1.0 - u0 * u0),
			belt_z
		)
		var belt1 := Vector3(
			u1 * belt_width,
			.765 + .018 * (1.0 - u1 * u1),
			belt_z
		)
		if front:
			add_quad(tool, belt0, belt1, roof1, roof0)
		else:
			add_quad(tool, roof0, roof1, belt1, belt0)
	tool.index()
	tool.generate_normals()
	mesh_node(self, tool.commit(), Vector3.ZERO, glass)


func build_shell(paint: Material, highlight: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const LENGTH_SECTIONS := 96
	const CROSS_SECTIONS := 18
	for longitudinal in LENGTH_SECTIONS:
		var z0 := lerpf(-2.48, 2.45, float(longitudinal) / LENGTH_SECTIONS)
		var z1 := lerpf(-2.48, 2.45, float(longitudinal + 1) / LENGTH_SECTIONS)
		for cross in CROSS_SECTIONS:
			var x0 := lerpf(-1.0, 1.0, float(cross) / CROSS_SECTIONS)
			var x1 := lerpf(-1.0, 1.0, float(cross + 1) / CROSS_SECTIONS)
			add_quad(tool, top_at(x0, z0), top_at(x1, z0), top_at(x1, z1), top_at(x0, z1))
		for side in [-1, 1]:
			for vertical in 7:
				var v0 := float(vertical) / 7.0
				var v1 := float(vertical + 1) / 7.0
				var bottom0 := arch_bottom(z0)
				var bottom1 := arch_bottom(z1)
				var y00 := lerpf(bottom0, top_at(side, z0).y, v0)
				var y01 := lerpf(bottom0, top_at(side, z0).y, v1)
				var y10 := lerpf(bottom1, top_at(side, z1).y, v0)
				var y11 := lerpf(bottom1, top_at(side, z1).y, v1)
				var swell0 := .015 * sin(v0 * PI)
				var swell1 := .015 * sin(v1 * PI)
				var p00 := Vector3(side * (width_at(z0) + swell0), y00, top_at(side, z0).z)
				var p01 := Vector3(side * (width_at(z0) + swell1), y01, top_at(side, z0).z)
				var p10 := Vector3(side * (width_at(z1) + swell0), y10, top_at(side, z1).z)
				var p11 := Vector3(side * (width_at(z1) + swell1), y11, top_at(side, z1).z)
				add_quad(tool, p00, p10, p11, p01, side < 0)
	tool.index()
	tool.generate_normals()
	mesh_node(self, tool.commit(), Vector3.ZERO, paint)
	# Fecha para-choques e elimina vazios vistos em ângulos altos da missão.
	for z in [-2.48, 2.45]:
		var half_width := width_at(z)
		var cap: Array[Vector3] = [
			Vector3(-half_width, .185, z),
			Vector3(half_width, .185, z),
			Vector3(half_width, deck_at(z), z),
			Vector3(-half_width, deck_at(z), z)
		]
		if z > 0.0:
			cap.reverse()
		surface(self, cap, paint)

	# Painel central do capô: muda apenas a leitura dos reflexos.
	var hood_tool := SurfaceTool.new()
	hood_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for longitudinal in 30:
		var z0 := lerpf(-2.28, -.72, float(longitudinal) / 30.0)
		var z1 := lerpf(-2.28, -.72, float(longitudinal + 1) / 30.0)
		add_quad(
			hood_tool,
			top_at(-.43, z0) + Vector3(0, .004, 0),
			top_at(.43, z0) + Vector3(0, .004, 0),
			top_at(.43, z1) + Vector3(0, .004, 0),
			top_at(-.43, z1) + Vector3(0, .004, 0)
		)
	hood_tool.index()
	hood_tool.generate_normals()
	mesh_node(self, hood_tool.commit(), Vector3.ZERO, highlight)


func build_greenhouse(paint: Material, glass: Material, trim: Material) -> void:
	# Teto abaulado com arco longitudinal, sem volumes atravessando os vidros.
	var roof_tool := SurfaceTool.new()
	roof_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ROOF_Z_SECTIONS := 16
	const ROOF_X_SECTIONS := 14
	for longitudinal in ROOF_Z_SECTIONS:
		var z0 := lerpf(-.43, 1.06, float(longitudinal) / ROOF_Z_SECTIONS)
		var z1 := lerpf(-.43, 1.06, float(longitudinal + 1) / ROOF_Z_SECTIONS)
		for cross in ROOF_X_SECTIONS:
			var x0 := lerpf(-1.0, 1.0, float(cross) / ROOF_X_SECTIONS)
			var x1 := lerpf(-1.0, 1.0, float(cross + 1) / ROOF_X_SECTIONS)
			var roof_y0 := roof_y_at(z0)
			var roof_y1 := roof_y_at(z1)
			var width0 := roof_width_at(z0)
			var width1 := roof_width_at(z1)
			var p00 := Vector3(x0 * width0, roof_y0 + .060 * (1.0 - x0 * x0), z0)
			var p01 := Vector3(x1 * width0, roof_y0 + .060 * (1.0 - x1 * x1), z0)
			var p10 := Vector3(x0 * width1, roof_y1 + .060 * (1.0 - x0 * x0), z1)
			var p11 := Vector3(x1 * width1, roof_y1 + .060 * (1.0 - x1 * x1), z1)
			add_quad(roof_tool, p00, p01, p11, p10)
	roof_tool.index()
	roof_tool.generate_normals()
	mesh_node(self, roof_tool.commit(), Vector3.ZERO, paint)

	# Para-brisas compartilham a mesma curvatura transversal do teto.
	build_windshield(true, glass)
	build_windshield(false, glass)

	for side in [-1, 1]:
		var outward := float(side)
		# Cada segmento usa os mesmos vértices da borda do teto.
		var side_tool := SurfaceTool.new()
		side_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for section in ROOF_Z_SECTIONS:
			var t0 := float(section) / ROOF_Z_SECTIONS
			var t1 := float(section + 1) / ROOF_Z_SECTIONS
			var z0 := lerpf(-.43, 1.06, t0)
			var z1 := lerpf(-.43, 1.06, t1)
			var a := Vector3(outward * roof_width_at(z0), roof_y_at(z0), z0)
			var b := Vector3(outward * roof_width_at(z1), roof_y_at(z1), z1)
			var c := Vector3(outward * lerpf(.77, .80, t1), .765, lerpf(-1.15, 1.70, t1))
			var d := Vector3(outward * lerpf(.77, .80, t0), .765, lerpf(-1.15, 1.70, t0))
			add_quad(side_tool, a, b, c, d)
		side_tool.index()
		side_tool.generate_normals()
		mesh_node(self, side_tool.commit(), Vector3.ZERO, glass)
		for station in [0, 8, 16]:
			var t := float(station) / ROOF_Z_SECTIONS
			var z := lerpf(-.43, 1.06, t)
			tube(self, [
				Vector3(outward * roof_width_at(z), roof_y_at(z), z),
				Vector3(outward * lerpf(.77, .80, t), .765, lerpf(-1.15, 1.70, t))
			], .012, trim)


func build_door(rear: bool, side: int, paint: Material, trim: Material) -> void:
	var hinge := Node3D.new()
	hinge.name = ("RearDoor" if rear else "FrontDoor") + ("L" if side < 0 else "R")
	var center_z := .78 if rear else -.51
	hinge.position = Vector3(float(side) * .925, 0.0, center_z)
	hinge.set_meta("door_side", float(side))
	hinge.set_meta("door_index", doors.size())
	add_child(hinge)
	doors.append(hinge)

	# Uma lâmina fina sobre a casca mantém a porta visualmente integrada.
	var length := .55 if rear else .85
	box(hinge, Vector3(.018, .46, length), Vector3(0, .49, 0), paint)
	box(hinge, Vector3(.026, .035, length - .08), Vector3(float(side) * .01, .255, 0), trim)
	box(hinge, Vector3(.034, .025, .15), Vector3(float(side) * .018, .665, .30), trim)


func build_wheel(side: int, axle: float, rubber: Material, alloy: Material, rotor: Material, brake: Material) -> void:
	var pivot := Node3D.new()
	pivot.name = ("Front" if axle < 0 else "Rear") + ("L" if side < 0 else "R") + "Wheel"
	pivot.position = Vector3(float(side) * .95, .385, axle)
	add_child(pivot)
	wheels.append(pivot)

	var tire_shape := TorusMesh.new()
	tire_shape.inner_radius = .30
	tire_shape.outer_radius = .39
	tire_shape.rings = 32
	tire_shape.ring_segments = 12
	var tire_node := mesh_node(pivot, tire_shape, Vector3.ZERO, rubber)
	tire_node.rotation.z = PI / 2.0
	tire_node.scale.y = 1.42

	var face_x := float(side) * .105
	cylinder(pivot, .265, .022, Vector3(face_x * .55, 0, 0), rotor, Vector3(0, 0, PI / 2.0))
	var rim_shape := TorusMesh.new()
	rim_shape.inner_radius = .255
	rim_shape.outer_radius = .30
	rim_shape.rings = 32
	rim_shape.ring_segments = 10
	var rim_node := mesh_node(pivot, rim_shape, Vector3(face_x, 0, 0), alloy)
	rim_node.rotation.z = PI / 2.0

	for spoke_index in 10:
		var angle := float(spoke_index) * TAU / 10.0
		var spoke := box(
			pivot,
			Vector3(.025, .205, .032),
			Vector3(face_x * 1.05, cos(angle) * .115, sin(angle) * .115),
			alloy
		)
		spoke.rotation.x = angle
	cylinder(pivot, .055, .035, Vector3(face_x * 1.12, 0, 0), alloy, Vector3(0, 0, PI / 2.0))
	box(pivot, Vector3(.032, .12, .055), Vector3(face_x * 1.18, .02, -.18), brake)


func build_wheel_well(side: int, axle: float, finish: Material) -> void:
	# Fundo escuro e contorno apoiado exatamente na borda da carroceria.
	var well := cylinder(
		self,
		.36,
		.035,
		Vector3(float(side) * .79, .385, axle),
		finish,
		Vector3(0, 0, PI / 2.0)
	)
	well.set_meta("wheel_well", true)
	var lip: Array[Vector3] = []
	for step in 15:
		var angle := PI - float(step) / 14.0 * PI
		var z := axle + cos(angle) * .47
		var y := .365 + sin(angle) * .47
		lip.append(Vector3(float(side) * (width_at(z) + .004), y, z))
	tube(self, lip, .012, finish)


func build_front(grille: Material, chrome_dark: Material, headlight: Material) -> void:
	# Rins duplos verticais: principal assinatura visual do M8.
	for side in [-1, 1]:
		var center_x := float(side) * .285
		var inner_x := .035 * float(side)
		var outer_x := .505 * float(side)
		surface(self, [
			Vector3(inner_x, .61, -2.482),
			Vector3(outer_x, .59, -2.445),
			Vector3(outer_x, .39, -2.472),
			Vector3(inner_x, .37, -2.505)
		], grille)
		tube(self, [
			Vector3(inner_x, .61, -2.50),
			Vector3(outer_x, .59, -2.463),
			Vector3(outer_x, .39, -2.49),
			Vector3(inner_x, .37, -2.523),
			Vector3(inner_x, .61, -2.50)
		], .018, chrome_dark)
		for slat_index in 5:
			var offset := lerpf(-.175, .175, float(slat_index) / 4.0)
			box(self, Vector3(.014, .17, .025), Vector3(center_x + offset, .49, -2.522), chrome_dark)

		# Faróis estreitos, puxados para os para-lamas.
		var lamp_points: Array[Vector3] = [
			Vector3(float(side) * .42, .575, -2.445),
			Vector3(float(side) * .88, .555, -2.375),
			Vector3(float(side) * .92, .49, -2.395),
			Vector3(float(side) * .48, .50, -2.47)
		]
		if side < 0:
			lamp_points.reverse()
		surface(self, lamp_points, headlight)

		# Entrada lateral escura integrada à face do para-choque.
		surface(self, [
			Vector3(float(side) * .57, .405, -2.49),
			Vector3(float(side) * .91, .385, -2.42),
			Vector3(float(side) * .88, .205, -2.43),
			Vector3(float(side) * .50, .225, -2.52)
		], grille)
func build_rear(_paint: Material, trim: Material, chrome: Material, grille: Material, taillight: Material) -> void:
	# Lanternas horizontais com ponta afilada para o centro.
	for side in [-1, 1]:
		tube(self, [
			Vector3(float(side) * .87, .555, 2.435),
			Vector3(float(side) * .64, .585, 2.455),
			Vector3(float(side) * .31, .575, 2.465),
			Vector3(float(side) * .18, .55, 2.47)
		], .032, taillight)
		tube(self, [
			Vector3(float(side) * .82, .52, 2.445),
			Vector3(float(side) * .56, .54, 2.475)
		], .014, taillight)

	# Difusor e quatro saídas circulares em pares.
	surface(self, [
		Vector3(-.82, .26, 2.445),
		Vector3(.82, .26, 2.445),
		Vector3(.67, .13, 2.41),
		Vector3(-.67, .13, 2.41)
	], trim)
	# Rebaixo central e placa quebram a face traseira e seguem a referência.
	box(self, Vector3(.64, .22, .025), Vector3(0, .47, 2.468), grille)
	box(self, Vector3(.38, .105, .018), Vector3(0, .475, 2.485), chrome)
	for x in [-.72, -.51, .51, .72]:
		cylinder(self, .086, .055, Vector3(x, .25, 2.465), chrome, Vector3(PI / 2.0, 0, 0))
		cylinder(self, .059, .060, Vector3(x, .25, 2.495), grille, Vector3(PI / 2.0, 0, 0))


func _ready() -> void:
	set_meta("vehicle_kind", "car")
	set_meta("vehicle_name", "Maciota M8 Competition")
	set_meta("paint", "full_black")
	set_meta("wheelbase", 2.86)
	set_meta("silhouette", "m8_gran_coupe")

	# Preto automotivo preserva reflexos azulados para a forma continuar legível.
	var paint := material("171a1f", .42, .21)
	var carbon := material("050709", .66, .24)
	var grille := material("020304", .32, .35)
	var glass := material("0b202d", .58, .10)
	var rubber := material("08090a", .04, .62)
	var alloy := material("15191d", .88, .18)
	var rotor := material("51575c", .74, .26)
	var brake := material("8f1b22", .46, .25)
	var chrome_dark := material("4f565c", .92, .16)
	var chrome := material("899197", .92, .12)
	var headlight := material("cde9f4", .48, .10, .36)
	var taillight := material("c61f32", .44, .16, .72)

	build_shell(paint, paint)
	build_greenhouse(paint, glass, carbon)
	box(self, Vector3(1.66, .08, 3.68), Vector3(0, .15, .04), carbon)

	# Ordem esperada pela missão: dianteira esquerda, dianteira direita,
	# traseira esquerda, traseira direita.
	for rear in [false, true]:
		for side in [-1, 1]:
			build_door(rear, side, paint, carbon)

	for side in [-1, 1]:
		# Espelhos compactos presos à base das janelas.
		box(self, Vector3(.075, .040, .11), Vector3(float(side) * .955, .815, -.99), carbon)
		var mirror := ell(self, Vector3(.145, .065, .17), Vector3(float(side) * .995, .84, -1.00), paint)
		mirror.rotation.y = float(side) * .10
		# Saia e respiro ficam embutidos no plano lateral.
		box(self, Vector3(.032, .065, 2.82), Vector3(float(side) * .948, .21, .08), carbon)
		surface(self, [
			Vector3(float(side) * 1.007, .67, -.98),
			Vector3(float(side) * 1.012, .58, -.70),
			Vector3(float(side) * 1.012, .51, -.72)
		], carbon)

	build_front(grille, chrome_dark, headlight)
	build_rear(paint, carbon, chrome, grille, taillight)

	for side in [-1, 1]:
		for axle in [-1.46, 1.40]:
			build_wheel_well(side, axle, carbon)
			build_wheel(side, axle, rubber, alloy, rotor, brake)

	# Os ocupantes aparecem apenas quando o embarque termina.
	for side in [-1, 1]:
		var person := Node3D.new()
		person.name = "Occupant" + ("L" if side < 0 else "R")
		person.position = Vector3(float(side) * .36, .72, -.12)
		add_child(person)
		ell(person, Vector3(.28, .32, .24), Vector3.ZERO, material("171a1e" if side < 0 else "20262c"))
		ell(person, Vector3(.18, .20, .18), Vector3(0, .25, 0), material("986953"))
		person.hide()
		occupants.append(person)


func door(index: int, opened: bool) -> void:
	if index < 0 or index >= doors.size():
		return
	var side: float = doors[index].get_meta("door_side", -1.0)
	var amount := side * .56 if opened else 0.0
	create_tween().tween_property(doors[index], "rotation:y", amount, .28)


func roll(distance: float) -> void:
	for wheel_node in wheels:
		wheel_node.rotation.x += distance / .39


func steer(angle: float) -> void:
	for wheel_node in wheels:
		if wheel_node.position.z < 0.0:
			wheel_node.rotation.y = -angle

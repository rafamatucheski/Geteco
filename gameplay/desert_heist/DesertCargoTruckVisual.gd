extends RefCounted
## Malhas consolidadas por acabamento e compartilhadas entre todas as viagens.
## A construção inicial deve acontecer sob a cortina, antes de admitir a região.
const ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static var _template: PackedScene
static var _materials: Dictionary = {}
static var _box: BoxMesh
static var _cylinder: CylinderMesh
var _batches: Dictionary = {}

static func spec() -> Dictionary:
	return {"id":"desert_cargo_truck", "label":"Caminhão de carga", "bounds_size":[2.7,3.8,11.6],
		"bounds_center":[0,1.9,0], "colors":["583d35ff"], "durability":900.0,
		"damage_resistance":.3, "mass":12.0, "max_speed":250.0, "acceleration":330.0,
		"braking":1100.0, "turn_speed":.82, "drift_factor":.75, "drivetrain":"rwd",
		"engine_family":"diesel", "engine_pitch":.62, "vehicle_kind":"truck", "roof_prop":"none"}

static func prewarm() -> void:
	if _template != null: return
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_cylinder = CylinderMesh.new()
	_cylinder.top_radius = 1.0
	_cylinder.bottom_radius = 1.0
	_cylinder.height = 1.0
	_cylinder.radial_segments = 20
	_cylinder.rings = 1
	var builder := new()
	var root: Node3D = builder._build()
	_assign_owner(root, root)
	_template = PackedScene.new()
	_template.pack(root)
	root.free()

static func _assign_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_assign_owner(child, root)

static func create() -> Node3D:
	prewarm()
	return _template.instantiate() as Node3D

static func set_cargo_open(root: Node3D, opened: bool, immediate: bool = false) -> void:
	var old: Variant = root.get_meta("cargo_door_tween") if root.has_meta("cargo_door_tween") else null
	if old is Tween and old.is_valid(): old.kill()
	var tween: Tween
	if not immediate and root.is_inside_tree():
		tween = root.create_tween().set_parallel(true)
		tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		root.set_meta("cargo_door_tween", tween)
	for side in [-1, 1]:
		var hinge := root.get_node_or_null("CargoDoorLeft" if side < 0 else "CargoDoorRight") as Node3D
		if hinge == null: continue
		var angle: float = side * 2.35 if opened else 0.0
		if tween != null: tween.tween_property(hinge, "rotation:y", angle, 1.15)
		else: hinge.rotation.y = angle
	root.set_meta("cargo_open", opened)

static func set_loot_visible(root: Node3D, shown: bool) -> void:
	var cargo := root.get_node_or_null("CargoLoot") as Node3D
	if cargo != null: cargo.visible = shown

func _build() -> Node3D:
	var root := Node3D.new()
	root.name = "DesertCargoTruck"
	# A cabine alta não usa o piso de sedã nem a largura dos espelhos externos.
	root.set_meta("vehicle_interior_spec", {"kind":"truck", "floor":1.15,
		"belt":2.14, "roof":3.02, "hw":1.02, "wz0":-4.18, "wz1":-4.06,
		"rear":-2.78, "rear_top":-2.78, "sz":-3.35, "sx":-.55, "roof_liner":false})
	# Chassi longitudinal, travessas e diferencial ficam separados do baú.
	for side in [-1, 1]:
		box(Vector3(side*.73,.76,0),Vector3(.18,.28,10.8),"chassis")
	for z in [-4.5,-2.4,0,2.5,4.5]:
		box(Vector3(0,.76,z),Vector3(2.15,.14,.18),"chassis")
	box(Vector3(0,1.0,1.75),Vector3(2.46,.22,7.85),"steel")
	# O baú é oco: portas abertas revelam assoalho e carga, nunca uma caixa sólida.
	box(Vector3(0,1.15,1.8),Vector3(2.35,.12,7.7),"wood")
	box(Vector3(0,3.67,1.8),Vector3(2.58,.13,7.82),"container")
	box(Vector3(0,2.42,-2.06),Vector3(2.56,2.5,.12),"container")
	for side in [-1,1]:
		box(Vector3(side*1.24,2.42,1.8),Vector3(.10,2.5,7.8),"container")
		for index in 26:
			box(Vector3(side*1.305,2.42,-1.86+index*.295),Vector3(.055,2.30,.075),"rib")
		for y in [1.24,3.56]:
			box(Vector3(side*1.28,y,1.8),Vector3(.13,.12,7.8),"frame")
		for z in [-2.04,5.64]:
			box(Vector3(side*1.25,2.42,z),Vector3(.18,2.6,.18),"frame")
			for y in [1.24,3.57]:
				box(Vector3(side*1.26,y,z),Vector3(.22,.20,.22),"steel")
		for z in [-1.7,.2,2.0,3.8,5.35]:
			box(Vector3(side*1.35,1.28,z),Vector3(.025,.10,.16),"amber")
			box(Vector3(side*1.35,1.13,z),Vector3(.025,.055,.38),"reflector")
		# Caixa de ferramentas, degrau, tanque e escapamento de inox.
		box(Vector3(side*1.03,.85,-1.7),Vector3(.48,.55,.72),"chassis")
		cylinder(Vector3(side*1.04,.83,-2.65),.34,.96,"steel",Vector3(PI*.5,0,0))
		for z in [-3.0,-2.3]: box(Vector3(side*1.04,.85,z),Vector3(.64,.07,.055),"chassis")
		for y in [.48,.73]: box(Vector3(side*1.12,y,-3.47),Vector3(.42,.10,.75),"steel")
		cylinder(Vector3(side*1.08,2.57,-2.15),.075,2.18,"steel")
		cylinder(Vector3(side*1.08,3.68,-2.15),.096,.06,"chassis")
		box(Vector3(side*1.15,.39,4.91),Vector3(.42,.55,.065),"rubber")
	# Cabine recuada com capô comprido, para-brisa bipartido e quebra-sol.
	box(Vector3(0,1.47,-3.23),Vector3(2.22,1.32,1.75),"paint")
	box(Vector3(0,2.55,-2.53),Vector3(2.2,1.05,.35),"paint")
	box(Vector3(0,3.12,-3.18),Vector3(2.29,.20,1.83),"paint")
	box(Vector3(0,1.54,-4.77),Vector3(1.65,.86,1.38),"paint")
	box(Vector3(0,2.00,-4.74),Vector3(1.72,.16,1.5),"paint",Vector3(-.06,0,0))
	box(Vector3(0,2.53,-4.02),Vector3(2.16,.93,.12),"chassis",Vector3(-.13,0,0))
	for side in [-1,1]:
		box(Vector3(side*.53,2.57,-4.10),Vector3(.96,.68,.035),"glass",Vector3(-.13,0,0))
		box(Vector3(side*.52,2.26,-4.17),Vector3(.70,.025,.025),"rubber",Vector3(0,0,-side*.12))
		box(Vector3(side*1.12,2.53,-3.37),Vector3(.035,.77,1.09),"glass")
		for z in [-3.98,-2.78]: box(Vector3(side*1.12,2.54,z),Vector3(.12,1.04,.12),"paint")
		box(Vector3(side*1.15,2.04,-3.34),Vector3(.05,.075,1.20),"steel")
		box(Vector3(side*1.15,1.90,-2.91),Vector3(.055,.055,.23),"steel")
		box(Vector3(side*1.29,2.52,-3.92),Vector3(.37,.045,.045),"steel")
		box(Vector3(side*1.44,2.51,-3.90),Vector3(.12,.44,.21),"chassis")
		box(Vector3(side*1.51,2.51,-3.89),Vector3(.016,.36,.16),"glass")
		box(Vector3(side*1.07,1.52,-4.65),Vector3(.44,.22,1.75),"paint")
		box(Vector3(side*1.05,1.32,-5.47),Vector3(.43,.30,.10),"steel")
		box(Vector3(side*1.05,1.34,-5.53),Vector3(.33,.19,.03),"headlight_left" if side < 0 else "headlight_right")
		box(Vector3(side*1.05,1.08,-5.53),Vector3(.30,.085,.03),"amber")
		box(Vector3(side*1.02,1.06,5.73),Vector3(.30,.19,.055),"tail")
		box(Vector3(side*.70,1.06,5.73),Vector3(.18,.19,.055),"amber")
	box(Vector3(0,3.01,-4.13),Vector3(2.34,.12,.38),"paint",Vector3(-.10,0,0))
	# Os cinco gabaritos da cabine são instalados e acesos por VehicleEquipment.
	# O projetor único do trânsito nasce entre as lentes: grade recuada evita
	# que a própria chapa bloqueie esse facho com a sombra do caminhão.
	box(Vector3(0,1.48,-5.40),Vector3(1.45,.90,.12),"steel")
	box(Vector3(0,1.48,-5.47),Vector3(1.22,.73,.035),"chassis")
	for x in 11: box(Vector3(-.54+x*.108,1.48,-5.50),Vector3(.035,.70,.035),"steel")
	box(Vector3(0,.84,-5.58),Vector3(2.58,.30,.22),"steel")
	box(Vector3(0,.62,5.59),Vector3(2.42,.15,.30),"steel")
	for side in [-1,1]: box(Vector3(side*.83,.81,5.59),Vector3(.12,.42,.13),"chassis")
	flush(root)
	for side in [-1,1]:
		for z in [-4.63,3.20,4.52]:
			var center := Vector3(side*1.07,.61,z)
			cylinder(center,.61,.42,"rubber",Vector3(0,0,PI*.5))
			cylinder(center+Vector3(side*.22,0,0),.37,.035,"steel",Vector3(0,0,PI*.5))
			cylinder(center+Vector3(side*.25,0,0),.17,.10,"chassis",Vector3(0,0,PI*.5))
			for bolt in 8:
				var angle := TAU*bolt/8.0
				cylinder(center+Vector3(side*.245,sin(angle)*.27,cos(angle)*.27),.032,.035,"chassis",Vector3(0,0,PI*.5))
			for part in flush(root): part.set_meta("wheel_center",center)
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.name = "CargoDoorLeft" if side < 0 else "CargoDoorRight"
		hinge.position = Vector3(side*1.2,2.42,5.65)
		root.add_child(hinge)
		box(Vector3(-side*.60,0,0),Vector3(1.18,2.34,.12),"container")
		for offset in [.2,.43,.66,.89,1.12]: box(Vector3(-side*offset,0,.07),Vector3(.065,2.15,.04),"rib")
		for offset in [.27,.93]:
			cylinder(Vector3(-side*offset,0,.13),.027,2.18,"steel")
			box(Vector3(-side*offset,-.10,.18),Vector3(.24,.045,.045),"steel")
		for y in [-.92,0,.92]: box(Vector3(-side*.06,y,.1),Vector3(.23,.10,.09),"steel")
		box(Vector3(-side*.60,-.95,.10),Vector3(1.10,.08,.025),"reflector")
		flush(hinge)
	var cargo := Node3D.new()
	cargo.name = "CargoLoot"
	root.add_child(cargo)
	for z in [2.0,3.35,4.65]:
		for side in [-1,1]:
			var x: float = side*.59
			for offset in [-.34,0,.34]: box(Vector3(x+offset,1.28,z),Vector3(.13,.16,.98),"wood")
			box(Vector3(x,1.40,z),Vector3(.96,.08,1.02),"wood")
			box(Vector3(x,1.73,z),Vector3(.84,.57,.86),"case")
			box(Vector3(x,2.04,z),Vector3(.88,.06,.90),"steel")
			for offset in [-.27,.27]: box(Vector3(x+offset,1.74,z),Vector3(.045,.61,.91),"chassis")
			box(Vector3(x,1.76,z+.45),Vector3(.24,.07,.035),"steel")
	flush(cargo)
	return root

func box(at: Vector3, size: Vector3, finish: String, rotation := Vector3.ZERO) -> void:
	append(_box,Transform3D(Basis.from_euler(rotation).scaled_local(size),at),finish)

func cylinder(at: Vector3, radius: float, height: float, finish: String, rotation := Vector3.ZERO) -> void:
	append(_cylinder,Transform3D(Basis.from_euler(rotation).scaled_local(Vector3(radius,height,radius)),at),finish)

func append(mesh: Mesh, transform: Transform3D, finish: String) -> void:
	if not _batches.has(finish):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[finish] = surface
	var surface: SurfaceTool = _batches[finish]
	var arrays: Array = ARRAYS.arrays_of(mesh,0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_basis := transform.basis.inverse().transposed()
	for index in indices:
		surface.set_normal((normal_basis*normals[index]).normalized())
		surface.add_vertex(transform*vertices[index])

func flush(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for finish: String in _batches:
		var part := MeshInstance3D.new()
		part.name = "Freight_"+finish
		part.mesh = _batches[finish].commit()
		part.material_override = material(finish)
		part.set_meta("coupe_damage_material_key",finish)
		parent.add_child(part)
		result.append(part)
	_batches.clear()
	return result

static func material(finish: String) -> StandardMaterial3D:
	if _materials.has(finish): return _materials[finish]
	var palette := {"paint":"583d35", "container":"3a5559", "rib":"476367", "frame":"293b3e",
		"chassis":"24272a", "steel":"a4aaa8", "wood":"776249", "rubber":"17191b",
		"glass":"26383f", "case":"414b43", "reflector":"d9c6a0", "amber":"c5893a",
		"tail":"942e29", "headlight":"e3dcc4"}
	var key := "headlight" if finish.begins_with("headlight_") else finish
	var mat := StandardMaterial3D.new()
	mat.resource_name = finish
	mat.albedo_color = Color(palette.get(key,"ffffff"))
	mat.metallic = .70 if finish == "steel" else (.30 if finish in ["paint","container","rib","frame"] else .0)
	mat.roughness = .28 if finish == "glass" else (.38 if finish == "steel" else .76)
	_materials[finish] = mat
	return mat

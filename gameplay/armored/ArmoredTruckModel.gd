extends RefCounted
## Purpose-built cash carrier. Static panels share one mesh per finish; only
## wheels and the two vault leaves move. No per-frame script or extra lights.
static var _materials: Dictionary = {}
var _batches: Dictionary = {}

static func spec() -> Dictionary:
	return {"id":"armored_truck", "label":"Carro-forte", "bounds_size":[2.5,2.9,6.0],
		"bounds_center":[0,1.45,0], "colors":["64736dff"], "durability":1200.0,
		"damage_resistance":.25, "mass":8.5, "max_speed":208.0, "acceleration":480.0,
		"braking":1400.0, "turn_speed":1.35, "drift_factor":.8, "drivetrain":"rwd",
		"engine_family":"diesel", "engine_pitch":.72, "vehicle_kind":"truck", "roof_prop":"none"}

static func create() -> Node3D:
	var builder := new()
	return builder._build()

func _build() -> Node3D:
	var root := Node3D.new()
	root.name = "ArmoredTruck"
	box(Vector3(0,.56,0),Vector3(1.84,.3,5.6),"trim")
	box(Vector3(0,.8,-2.86),Vector3(2.4,.34,.28),"trim")
	box(Vector3(0,.63,2.79),Vector3(2.4,.2,.42),"steel")
	box(Vector3(0,.8,.57),Vector3(2.18,.2,4.48),"paint")
	# Hollow armored vault; opening the leaves exposes actual cargo.
	box(Vector3(0,2.8,.8),Vector3(2.32,.2,3.94),"paint")
	box(Vector3(0,1.81,-1.07),Vector3(2.32,1.86,.18),"paint")
	box(Vector3(0,.94,.79),Vector3(2.13,.13,3.63),"interior")
	for side in [-1,1]:
		# Skirt is broken around each rear wheel, never overlapping the tire.
		box(Vector3(side*1.11,2.04,.8),Vector3(.2,1.34,3.94),"paint")
		box(Vector3(side*1.11,1.13,-.07),Vector3(.2,.47,2.16),"paint")
		box(Vector3(side*1.11,1.13,2.46),Vector3(.2,.47,.57),"paint")
		box(Vector3(side*1.218,1.52,.79),Vector3(.03,.09,3.93),"stripe")
		box(Vector3(side*1.224,1.66,.79),Vector3(.024,.035,3.93),"steel")
		box(Vector3(side*1.17,1.36,1.58),Vector3(.13,.12,1.22),"trim")
		box(Vector3(side*1.16,.92,1.00),Vector3(.13,.76,.12),"trim")
		box(Vector3(side*1.16,.92,2.17),Vector3(.13,.76,.12),"trim")
		box(Vector3(side*1.12,.67,-1.59),Vector3(.21,.12,.72),"steel")
		box(Vector3(side*1.10,1.45,-1.51),Vector3(.12,1.17,1.05),"paint")
		box(Vector3(side*1.112,2.24,-1.55),Vector3(.12,.48,.94),"glass")
		box(Vector3(side*1.19,1.78,-1.17),Vector3(.045,.06,.2),"steel")
		box(Vector3(side*1.10,2.57,-1.55),Vector3(.19,.18,1.06),"paint")
		for z in [-2.06,-1.04]: box(Vector3(side*1.12,2.18,z),Vector3(.17,.67,.14),"paint")
		box(Vector3(side*1.21,2.04,-2.08),Vector3(.08,.09,.48),"trim")
		box(Vector3(side*1.22,2.15,-2.28),Vector3(.06,.3,.2),"trim")
		box(Vector3(side*1.252,2.15,-2.28),Vector3(.015,.25,.15),"glass")
		for z in [-.9,.35,2.6]:
			box(Vector3(side*1.216,2.14,z),Vector3(.014,1.09,.024),"trim")
			for y in [1.74,2.55]: cylinder(Vector3(side*1.23,y,z+.08),.025,.027,"steel",Vector3(0,0,PI*.5))
		box(Vector3(side*1.225,2.16,1.30),Vector3(.04,.23,.4),"trim")
		box(Vector3(side*1.25,2.16,1.30),Vector3(.018,.055,.19),"glass")
		# Embossed shield motif, no explanatory/decorative text.
		box(Vector3(side*1.235,2.12,-.34),Vector3(.025,.4,.38),"stripe")
		box(Vector3(side*1.25,2.12,-.34),Vector3(.018,.23,.21),"steel")
		box(Vector3(side*.99,1.38,2.82),Vector3(.2,.27,.065),"tail")
		box(Vector3(side*.99,1.13,2.82),Vector3(.2,.13,.066),"amber")
	# Short armored snout, narrow split windshield and protected front grille.
	box(Vector3(0,1.32,-2.43),Vector3(2.16,.66,.74),"paint")
	box(Vector3(0,1.68,-2.4),Vector3(2.19,.16,.8),"paint",Vector3(.1,0,0))
	box(Vector3(0,2.20,-2.04),Vector3(2.03,.69,.18),"paint",Vector3(-.14,0,0))
	for side in [-1,1]:
		box(Vector3(side*.50,2.22,-2.15),Vector3(.83,.36,.035),"glass",Vector3(-.14,0,0))
		box(Vector3(side*.49,2.05,-2.18),Vector3(.53,.025,.028),"trim",Vector3(0,0,side*.08))
		# Equipment discovers each lamp from its surface centroid. Keeping the
		# lenses separate preserves independent left/right damage and projectors.
		box(Vector3(side*.84,1.29,-2.811),Vector3(.35,.24,.04),"headlight_left" if side < 0 else "headlight_right")
		box(Vector3(side*.84,1.11,-2.821),Vector3(.35,.085,.04),"amber")
		box(Vector3(side*.96,1.09,-2.96),Vector3(.10,.58,.1),"trim")
	box(Vector3(0,2.64,-1.54),Vector3(2.29,.18,1.19),"paint")
	box(Vector3(0,1.22,-2.824),Vector3(.99,.34,.055),"trim")
	for y in [1.1,1.21,1.32]: box(Vector3(0,y,-2.86),Vector3(.86,.026,.035),"steel")
	box(Vector3(0,.97,-3.0),Vector3(2.1,.10,.10),"trim")
	box(Vector3(0,1.44,-2.91),Vector3(1.98,.07,.07),"trim")
	box(Vector3(0,2.92,.13),Vector3(.65,.1,.52),"trim")
	for z in [-.03,.10,.23]: box(Vector3(0,2.976,z),Vector3(.5,.013,.045),"steel")
	flush(root)
	for side in [-1,1]:
		for z in [-2.16,1.58]:
			var center := Vector3(side*1.08,.59,z)
			cylinder(center,.57,.3,"rubber",Vector3(0,0,PI*.5))
			cylinder(center+Vector3(side*.157,0,0),.335,.02,"steel",Vector3(0,0,PI*.5))
			cylinder(center+Vector3(side*.174,0,0),.13,.06,"trim",Vector3(0,0,PI*.5))
			for index in 8:
				var angle := TAU*index/8.0
				cylinder(center+Vector3(side*.18,sin(angle)*.245,cos(angle)*.245),.032,.026,"trim",Vector3(0,0,PI*.5))
			for part in flush(root): part.set_meta("wheel_center",center)
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.name = "VaultDoorLeft" if side == -1 else "VaultDoorRight"
		hinge.position = Vector3(side*1.01,1.8,2.75)
		root.add_child(hinge)
		box(Vector3(-side*.5,0,0),Vector3(.98,1.70,.14),"paint")
		box(Vector3(-side*.5,0,-.09),Vector3(.86,1.57,.05),"interior")
		box(Vector3(-side*.80,0,.11),Vector3(.048,1.45,.06),"steel")
		box(Vector3(-side*.78,-.1,.16),Vector3(.21,.055,.05),"steel")
		box(Vector3(-side*.53,-.28,.08),Vector3(.9,.09,.025),"stripe")
		for y in [-.65,.65]:
			box(Vector3(-side*.025,y,.085),Vector3(.15,.19,.09),"steel")
			box(Vector3(-side*.8,y,.10),Vector3(.14,.10,.09),"trim")
		flush(hinge)
	var cargo := Node3D.new()
	cargo.name = "VaultCargo"
	root.add_child(cargo)
	for side in [-1,1]:
		for z in [1.59,2.25]:
			box(Vector3(side*.43,1.14,z),Vector3(.65,.29,.48),"case")
			box(Vector3(side*.43,1.31,z),Vector3(.59,.05,.43),"steel")
			for x in [-.23,.23]: box(Vector3(side*.43+x,1.15,z),Vector3(.035,.3,.49),"trim")
			box(Vector3(side*.43,1.18,z+.25),Vector3(.19,.055,.04),"steel")
	flush(cargo)
	cargo.visible = false
	return root

func box(at: Vector3, size: Vector3, finish: String, rotation := Vector3.ZERO) -> void:
	var primitive := BoxMesh.new()
	primitive.size = size
	append(primitive,Transform3D(Basis.from_euler(rotation),at),finish)

func cylinder(at: Vector3, radius: float, height: float, finish: String, rotation := Vector3.ZERO) -> void:
	var primitive := CylinderMesh.new()
	primitive.top_radius = radius
	primitive.bottom_radius = radius
	primitive.height = height
	primitive.radial_segments = 16
	primitive.rings = 1
	append(primitive,Transform3D(Basis.from_euler(rotation),at),finish)

func append(mesh: Mesh, transform: Transform3D, finish: String) -> void:
	if not _batches.has(finish):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[finish] = surface
	_batches[finish].append_from(mesh,0,transform)

func flush(parent: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for finish: String in _batches:
		var part := MeshInstance3D.new()
		part.name = "Armor_"+finish
		part.mesh = _batches[finish].commit()
		part.material_override = material(finish)
		part.set_meta("coupe_damage_material_key",finish)
		parent.add_child(part)
		result.append(part)
	_batches.clear()
	return result

static func material(finish: String) -> StandardMaterial3D:
	if _materials.has(finish): return _materials[finish]
	var color_key := "headlight" if finish.begins_with("headlight_") else finish
	var palette := {"paint":"64736d", "trim":"242a2b", "rubber":"171a1b", "glass":"243941",
		"steel":"a6ada9", "stripe":"d4b565", "interior":"343c3b", "case":"566559",
		"headlight":"dbe1d6", "tail":"af2925", "amber":"d99236"}
	var mat := StandardMaterial3D.new()
	mat.resource_name = finish
	mat.albedo_color = Color(palette.get(color_key,"ffffff"))
	mat.metallic = .55 if finish in ["paint","steel"] else .12
	mat.roughness = .23 if finish == "glass" else .62
	_materials[finish] = mat
	return mat

extends RefCounted
## Static presentation set, not a walkable room. One material batch per finish;
## the real workshop, actors and collision remain in the session's world.
var _groups := {}
var _materials := {}

func build() -> Node3D:
	var room := Node3D.new()
	room.name = "WorkshopBay"
	_materials = {
		"floor": _material("484e4c",.91), "wall": _material("394447",.94),
		"steel": _material("252e32",.56,.5), "edge": _material("86908f",.35,.65),
		"cabinet": _material("596964",.63,.3), "wood": _material("95724d",.85),
		"mark": _material("bba063",.85), "rubber": _material("1c2427",.92),
		"light": _material("e7e2ca",.4), "red": _material("a44b3b",.65,.2)
	}
	_materials.light.emission_enabled = true
	_materials.light.emission = Color("e7e2ca")
	_materials.light.emission_energy_multiplier = .7
	_box("floor",Vector3(0,-.105,0),Vector3(24,.2,24))
	_box("wall",Vector3(0,2.2,-6.1),Vector3(24,4.4,.2))
	_box("steel",Vector3(0,.38,-5.98),Vector3(24,.76,.04))
	for x in [-8.0,-4.0,0.0,4.0,8.0]:
		_box("steel",Vector3(x,2.3,-5.93),Vector3(.13,4.6,.14))
		_box("rubber",Vector3(x,.002,1),Vector3(.012,.006,20))
	for z in [-4.0,0.0,4.0,8.0]: _box("rubber",Vector3(0,.002,z),Vector3(24,.006,.012))
	# Low painted bay marks and a flush drain. No luminous turntable.
	for x in [-1.85,1.85]:
		_box("mark",Vector3(x,.008,0),Vector3(.06,.012,6.3))
		for z in [-3.15,3.15]: _box("mark",Vector3(x-signf(x)*.24,.009,z),Vector3(.54,.014,.065))
	_box("steel",Vector3(0,.012,-3.65),Vector3(3.4,.025,.19))
	for x in 34: _box("edge",Vector3(-1.65+x*.10,.029,-3.65),Vector3(.025,.015,.17))
	# Back bench in human scale: 0.95m worktop, toe recess and drawer handles.
	_box("wood",Vector3(.8,.96,-4.94),Vector3(4.5,.10,.84))
	for x in [-.65,2.3]:
		_box("steel",Vector3(x,.45,-4.97),Vector3(1.14,.82,.69))
		for y in [.26,.48,.70]:
			_box("cabinet",Vector3(x,y,-4.61),Vector3(1.04,.19,.045))
			_box("edge",Vector3(x,y+.035,-4.565),Vector3(.38,.028,.035))
	_box("steel",Vector3(.8,1.86,-5.84),Vector3(4.6,1.35,.08))
	# A tidy pegboard, recognisable wrenches and socket rail.
	for x in 18:
		for y in 5: _box("rubber",Vector3(-1.24+x*.24,1.40+y*.23,-5.791),Vector3(.024,.024,.008))
	for i in 7:
		var x := -.95+i*.29
		var length := .22+i*.023
		_box("edge",Vector3(x,1.94,-5.75),Vector3(.032,length,.033))
		for side in [-1.0,1.0]: _box("edge",Vector3(x+side*.024,1.94+length*.5,-5.75),Vector3(.025,.065,.034))
	_box("red",Vector3(2.35,1.075,-4.92),Vector3(.66,.17,.35))
	_box("steel",Vector3(2.35,1.20,-4.92),Vector3(.30,.065,.045))
	_box("edge",Vector3(-.50,1.1,-4.85),Vector3(.24,.22,.24))
	_box("steel",Vector3(-.50,1.23,-4.85),Vector3(.39,.09,.15))
	# Cabinets and a compact rolling chest, kept outside the central vehicle bay.
	for x in [-4.45,-3.57]:
		_box("steel",Vector3(x,1.12,-5.30),Vector3(.85,2.20,.9))
		_box("cabinet",Vector3(x,1.17,-4.84),Vector3(.77,2.02,.035))
		_box("edge",Vector3(x+.24,1.16,-4.79),Vector3(.032,.29,.04))
	_box("red",Vector3(3.7,.56,-2.9),Vector3(.85,.88,.57))
	_box("steel",Vector3(3.7,1.04,-2.9),Vector3(.93,.07,.63))
	for i in 4: _box("edge",Vector3(3.7,.30+i*.18,-2.60),Vector3(.69,.026,.025))
	for x in [3.39,4.01]:
		for z in [-3.10,-2.70]: _box("rubber",Vector3(x,.12,z),Vector3(.11,.18,.12))
	# Authored visible fixtures; illumination is provided by the showroom rig.
	for x in [-3.0,2.4]:
		_box("steel",Vector3(x,3.55,-5.72),Vector3(2.4,.15,.23))
		_box("light",Vector3(x,3.49,-5.57),Vector3(2.22,.06,.08))
	for finish in _groups:
		var transforms: Array = _groups[finish]
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = mesh
		batch.instance_count = transforms.size()
		for i in transforms.size(): batch.set_instance_transform(i,transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Bay_"+finish
		instance.multimesh = batch
		instance.material_override = _materials[finish]
		room.add_child(instance)
	_groups.clear()
	return room

func _box(finish: String, at: Vector3, size: Vector3) -> void:
	if not _groups.has(finish): _groups[finish] = []
	_groups[finish].append(Transform3D(Basis.from_scale(size),at))

func _material(color: String, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	return material

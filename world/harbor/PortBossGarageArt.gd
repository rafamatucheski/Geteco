extends Node3D
var gate: MeshInstance3D
var materials := {}

func material(color: String) -> StandardMaterial3D:
	if materials.has(color): return materials[color]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = .82
	materials[color] = m
	return m

func box(id: String, center: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	n.mesh = mesh
	n.position = center
	n.material_override = material(color)
	if not id.is_empty(): n.set_meta("interior_solid_id",StringName(id))
	add_child(n)
	return n

func _ready() -> void:
	box("",Vector3(0,-.12,0),Vector3(22,.24,17),"525c60")
	box("NorthWall",Vector3(0,1.6,-8),Vector3(22,.0+3.2,.35),"777e7b")
	box("WestWall",Vector3(-10.8,1.6,0),Vector3(.35,3.2,16),"737b78")
	box("EastWallNorth",Vector3(10.8,1.6,-5.25),Vector3(.35,3.2,5.5),"737b78")
	box("EastWallSouth",Vector3(10.8,1.6,5.25),Vector3(.35,3.2,5.5),"737b78")
	for side in [-1.0,1.0]:
		box("SouthWall%s" % side,Vector3(side*5.4,1.6,8),Vector3(10.8,3.2,.35),"858c87")
		box("RampSide%s" % side,Vector3(12.3,.35,side*2.35),Vector3(2.8,.7,.3),"777e7b")
	box("",Vector3(12.3,-.06,0),Vector3(2.9,.12,4.4),"626a69")
	for x in [-8.0,-4.0,0.0,4.0,8.0]:
		for side in [-1.0,1.0]:
			box("",Vector3(x+side*1.6,.008,-4.5),Vector3(.07,.015,5.4),"d1c5a4")
		box("",Vector3(x,.008,-7.12),Vector3(3.2,.015,.08),"d1c5a4")
		box("Stop%s" % x,Vector3(x,.095,-6.85),Vector3(1.5,.19,.20),"bfa450")
		box("",Vector3(x,1.1,-7.80),Vector3(3.8,.32,.06),"b6a252")
	for x in [-9.7,9.7]:
		for z in [-1.2,4.8]:
			var id := "Pillar%s_%s" % [x,z]
			box(id,Vector3(x,1.5,z),Vector3(.65,3,.65),"89918e")
			box(id,Vector3(x,.55,z),Vector3(.69,.25,.69),"c4a14a")
			box(id,Vector3(x,.25,z),Vector3(.69,.18,.69),"242c31")
	box("GuardDesk",Vector3(8.6,.43,6.8),Vector3(2.2,.86,.85),"3a474c")
	box("GuardDesk",Vector3(8.6,1.08,6.8),Vector3(.55,.44,.18),"19242c")
	for x in [-7.0,0.0,7.0]:
		box("",Vector3(x,2.9,-7.65),Vector3(2.0,.08,.16),"e3e8cf")
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,2.7,-4)
		lamp.light_color = Color("d8e2c5")
		lamp.light_energy = .65
		lamp.omni_range = 9
		lamp.shadow_enabled = false
		add_child(lamp)
	# Thin concrete joints and irregular aggregate keep the floor in scale.
	for x in range(-10,11,2):
		box("",Vector3(x,.006,0),Vector3(.014,.009,15.7),"454e52")
	for z in range(-6,8,2):
		box("",Vector3(0,.006,z),Vector3(21,.009,.014),"454e52")
	var rng := RandomNumberGenerator.new()
	rng.seed = 91266
	for i in 150:
		box("",Vector3(rng.randf_range(-10,10),.012,rng.randf_range(-7.5,7.5)),Vector3(rng.randf_range(.02,.12),.006,rng.randf_range(.02,.09)),"596265")
	batch_static_geometry()

func batch_static_geometry() -> void:
	# Keep each solid's identity while sharing one draw call per material.
	# The resulting rendered mesh is still the source of collision bounds.
	var groups := {}
	for child in get_children():
		if not child is MeshInstance3D: continue
		var key := "%s:%s" % [child.get_meta("interior_solid_id",""),child.material_override.get_instance_id()]
		if not groups.has(key): groups[key] = []
		groups[key].append(child)
	for group in groups.values():
		if group.size()<2: continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node in group: tool.append_from(node.mesh,0,node.transform)
		var merged := MeshInstance3D.new()
		merged.mesh = tool.commit()
		merged.material_override = group[0].material_override
		if group[0].has_meta("interior_solid_id"):
			merged.set_meta("interior_solid_id",group[0].get_meta("interior_solid_id"))
		add_child(merged)
		for node in group: node.free()

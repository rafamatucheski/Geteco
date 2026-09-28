extends RefCounted
## Metric three-section low-floor bus; shared materials and separate sliding doors.
static var materials: Dictionary = {}
static func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color({"body":"b92732","cream":"dedbd1","glass":"203640","rubber":"24272a","metal":"727b80","light":"fff0cb","tail":"f43333","floor":"44494b"}[key])
	m.roughness = .32 if key=="glass" else .72
	if key in ["light","tail"]: m.emission_enabled = true; m.emission = m.albedo_color; m.emission_energy_multiplier = 1.2
	materials[key] = m
	return m

static func box(parent: Node3D, at: Vector3, size: Vector3, key: String) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material(key)
	part.position = at
	parent.add_child(part)
	return part

static func build(parent: Node3D, length: float, section: int) -> Dictionary:
	var model := Node3D.new()
	model.name = "BiarticulatedSection%d" % section
	parent.add_child(model)
	box(model,Vector3(0,.27,0),Vector3(2.42,.18,length),"body")
	box(model,Vector3(0,2.95,0),Vector3(2.5,.24,length),"cream")
	box(model,Vector3(0,3.16,.3),Vector3(1.5,.22,2.4),"cream")
	box(model,Vector3(0,.39,0),Vector3(2.3,.06,length-.15),"floor")
	var door_z := -length*.5+1.2
	var wheels: Array[Node3D] = []
	for side in [-1,1]:
		var intervals := [[-length*.5,length*.5]] if side<0 else [[-length*.5,door_z-.7],[door_z+.7,length*.5]]
		for span in intervals:
			var middle: float = (span[0]+span[1])*.5
			var span_length: float = span[1]-span[0]
			box(model,Vector3(side*1.23,1.14,middle),Vector3(.08,.84,span_length),"body")
			box(model,Vector3(side*1.23,2.17,middle),Vector3(.07,1.12,maxf(.05,span_length-.1)),"glass")
		for z in range(ceili(length/1.2)):
			if side>0 and absf(-length*.5+.1+z*1.2-door_z)<.7: continue
			box(model,Vector3(side*1.27,2.15,-length*.5+.1+z*1.2),Vector3(.055,1.23,.06),"metal")
		for span in intervals: box(model,Vector3(side*1.28,1.5,(span[0]+span[1])*.5),Vector3(.04,.10,span[1]-span[0]),"cream")
		var axles := [-length*.3,length*.31] if section==0 else [length*.26]
		for z in axles:
			var wheel := MeshInstance3D.new()
			var tire := CylinderMesh.new()
			tire.top_radius = .48; tire.bottom_radius = .48; tire.height = .21
			tire.radial_segments = 12
			wheel.mesh = tire
			wheel.material_override = material("rubber")
			wheel.rotation.z = PI*.5
			wheel.position = Vector3(side*1.24,.49,z)
			model.add_child(wheel)
			wheels.append(wheel)
			var hub := wheel.duplicate()
			hub.scale = Vector3(.52,1.08,.52)
			hub.material_override = material("metal")
			model.add_child(hub)
			wheels.append(hub)
	box(model,Vector3(0,1.55,-length*.5),Vector3(2.44,2.55,.08),"body")
	box(model,Vector3(0,1.55,length*.5),Vector3(2.44,2.55,.08),"body")
	if section==0:
		box(model,Vector3(0,2.1,-length*.5-.05),Vector3(2.22,1.1,.04),"glass")
		box(model,Vector3(0,2.78,-length*.5-.06),Vector3(2,.22,.04),"rubber")
		var sign := Label3D.new()
		sign.text = "510  CIRCULAR"
		sign.font_size = 36; sign.pixel_size = .004
		sign.position = Vector3(0,2.78,-length*.5-.09)
		sign.rotation.y = PI
		sign.modulate = Color("ffd275")
		model.add_child(sign)
	for side in [-1,1]:
		if section==0:
			box(model,Vector3(side*.87,.94,-length*.5-.06),Vector3(.42,.19,.06),"light")
			box(model,Vector3(side*1.4,2.35,-length*.5+.1),Vector3(.15,.35,.3),"rubber")
		if section==2: box(model,Vector3(side*.95,1,length*.5+.06),Vector3(.18,.5,.06),"tail")
	var doors: Array[Node3D] = []
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(1.31,0,door_z+side*.32)
		model.add_child(leaf)
		box(leaf,Vector3(0,1.54,0),Vector3(.08,2.4,.62),"rubber")
		box(leaf,Vector3(.05,1.92,0),Vector3(.025,1.57,.49),"glass")
		doors.append(leaf)
	# Bake static parts by material once. Door leaves and wheel transforms remain movable.
	var batches := {}
	for child in model.get_children():
		if not child is MeshInstance3D or child in wheels: continue
		var mat: Material = child.material_override
		if not batches.has(mat):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[mat]=surface
		for index in child.mesh.get_surface_count(): batches[mat].append_from(child.mesh,index,child.transform)
		child.free()
	for mat in batches:
		var part := MeshInstance3D.new()
		part.mesh=batches[mat].commit(); part.material_override=mat
		model.add_child(part)
	return {"model":model,"doors":doors,"door_z":door_z,"wheels":wheels}

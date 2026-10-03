extends Node3D
## Repeated groceries share mesh/material and are submitted in MultiMesh batches.
var batches: Dictionary = {}
var materials: Dictionary = {}
var product_count := 0

func material(color: String, metal := false, glow := false) -> StandardMaterial3D:
	var key := color+str(metal)+str(glow)
	if materials.has(key): return materials[key]
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(color)
	surface.roughness = .38 if metal else .78
	surface.metallic = .55 if metal else 0.0
	if glow:
		surface.emission_enabled = true
		surface.emission = Color(color)
		surface.emission_energy_multiplier = .65
	materials[key] = surface
	return surface

func box(label: String, point: Vector3, size: Vector3, color: String, solid := false, metal := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material(color,metal)
	if solid: node.set_meta("interior_solid_id",label)
	add_child(node)
	return node

func piece(shape: String, point: Vector3, size: Vector3, color: String) -> void:
	var key := shape+color
	if not batches.has(key): batches[key] = {"shape":shape,"color":color,"transforms":[]}
	batches[key].transforms.append(Transform3D(Basis.from_scale(size),point))

func product(kind: int, point: Vector3, color: String) -> void:
	product_count += 1
	match kind % 5:
		0: # Carton, contrasting sleeve, folded top.
			piece("box",point+Vector3(0,.14,0),Vector3(.17,.28,.12),color)
			piece("box",point+Vector3(0,.16,.063),Vector3(.12,.085,.01),"eee8d7")
			piece("box",point+Vector3(0,.29,0),Vector3(.14,.025,.085),"eee8d7")
		1: # Bottle, shoulder and screw cap.
			piece("round",point+Vector3(0,.13,0),Vector3(.13,.26,.13),color)
			piece("round",point+Vector3(0,.28,0),Vector3(.07,.07,.07),color)
			piece("round",point+Vector3(0,.325,0),Vector3(.075,.035,.075),"e5d5a6")
			piece("round",point+Vector3(0,.14,0),Vector3(.134,.09,.134),"eee8d7")
		2: # Tin with rolled silver rim.
			piece("round",point+Vector3(0,.10,0),Vector3(.15,.20,.15),color)
			for y in [.015,.195]: piece("round",point+Vector3(0,y,0),Vector3(.16,.018,.16),"b7beb8")
		3: # Coffee, rice or snack packet.
			piece("box",point+Vector3(0,.12,0),Vector3(.20,.24,.12),color)
			piece("box",point+Vector3(0,.24,0),Vector3(.22,.025,.09),color)
			piece("box",point+Vector3(0,.13,.065),Vector3(.12,.10,.009),"dfcc92")
		4: # Fruit / rolls.
			piece("fruit",point+Vector3(0,.065,0),Vector3(.15,.13,.15),color)
			piece("box",point+Vector3(0,.14,0),Vector3(.018,.045,.018),"5e6c32")

func flush_batches() -> void:
	for key in batches:
		var row: Dictionary = batches[key]
		var mesh: PrimitiveMesh
		if row.shape == "round":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .5; cylinder.bottom_radius = .5; cylinder.height = 1
			cylinder.radial_segments = 10; cylinder.rings = 1
			mesh = cylinder
		elif row.shape == "fruit":
			var sphere := SphereMesh.new()
			sphere.radius = .5; sphere.height = 1; sphere.radial_segments = 10; sphere.rings = 5
			mesh = sphere
		else: mesh = BoxMesh.new(); mesh.size = Vector3.ONE
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = row.transforms.size()
		for i in row.transforms.size(): multi.set_instance_transform(i,row.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Stock_"+key
		instance.multimesh = multi
		instance.material_override = material(row.color)
		add_child(instance)
	batches.clear()

extends RefCounted
## Shared materials and a small set of articulated nodes; no decorative scripts.
static var materials: Dictionary = {}

static func material(key: String, color: Color) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = color
	m.roughness = .88
	if key in ["metal", "hydraulic"]: m.metallic = .6
	if key == "glass":
		m.albedo_color = Color(.19,.28,.29,.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[key] = m
	return m

static func box(root: Node3D, label: String, size: Vector3, at: Vector3, key: String, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material(key,color)
	node.set_meta("mining_material_key", "paint" if key.begins_with("paint") else key)
	root.add_child(node)
	return node

static func beam(root: Node3D, label: String, a: Vector3, b: Vector3, width: float, key: String, color: Color) -> MeshInstance3D:
	var part := box(root,label,Vector3(width,a.distance_to(b),width),(a+b)*.5,key,color)
	part.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return part

static func wheel(root: Node3D, at: Vector3, radius: float, width: float) -> void:
	var tire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 16
	tire.mesh = mesh
	tire.rotation.z = PI*.5
	tire.position = at
	tire.material_override = material("rubber",Color("252521"))
	tire.set_meta("wheel_center",at)
	root.add_child(tire)
	for side in [-1,1]:
		var hub := MeshInstance3D.new()
		var hub_mesh := CylinderMesh.new()
		hub_mesh.top_radius = radius*.48
		hub_mesh.bottom_radius = radius*.48
		hub_mesh.height = .07
		hub_mesh.radial_segments = 12
		hub.mesh = hub_mesh
		hub.rotation.z = PI*.5
		hub.position = at+Vector3(side*(width*.5+.01),0,0)
		hub.material_override = material("metal",Color("787466"))
		hub.set_meta("wheel_center",at)
		root.add_child(hub)
	# Wide diagonal tread blocks remain attached to the wheel pivot.
	for i in 12:
		var angle := TAU*float(i)/12.0
		var tread := box(root,"Tread",Vector3(width+.04,.10,radius*.24),at+Vector3(0,cos(angle)*radius,sin(angle)*radius),"mud",Color("514937"))
		tread.rotation.x = angle
		tread.set_meta("wheel_center",at)

static func create(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "MiningMachineModel"
	var truck := id == "mining_haul_truck"
	var tractor := id == "mining_tractor"
	var paint := Color("d1a24a") if not tractor else Color("698051")
	var key := "paint_"+id
	if truck: _truck(root,key,paint)
	else: _loader(root,key,paint,tractor)
	_batch(root)
	return root

static func _batch(root: Node3D) -> void:
	var batches: Dictionary = {}
	for child in root.get_children():
		if not child is MeshInstance3D:
			if child is Node3D: _batch(child)
			continue
		var signature := str(child.material_override.get_instance_id())+str(child.get_meta("wheel_center",Vector3.INF))
		if not batches.has(signature): batches[signature] = []
		batches[signature].append(child)
	for signature in batches:
		var parts: Array = batches[signature]
		if parts.size() < 2: continue
		var first: MeshInstance3D = parts[0]
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in parts: tool.append_from(part.mesh,0,part.transform)
		var batch := MeshInstance3D.new()
		batch.name = "Batch_"+str(first.material_override.resource_name)
		batch.mesh = tool.commit()
		batch.material_override = first.material_override
		batch.set_meta("mining_material_key",first.get_meta("mining_material_key",""))
		if first.has_meta("wheel_center"): batch.set_meta("wheel_center",first.get_meta("wheel_center"))
		root.add_child(batch)
		for part in parts: part.free()

static func _cabin(root: Node3D, center_z: float, floor_y: float, roof: float, key: String, paint: Color) -> void:
	box(root,"CabFloor",Vector3(1.86,.20,1.7),Vector3(0,floor_y-.1,center_z),key,paint)
	box(root,"CabRoof",Vector3(2.0,.16,1.9),Vector3(0,roof,center_z),key,paint)
	for x in [-.88,.88]:
		for z in [-.8,.8]: box(root,"CabPillar",Vector3(.09,roof-floor_y,.10),Vector3(x,(roof+floor_y)*.5,center_z+z),"metal",Color("373b36"))
	box(root,"Windshield",Vector3(1.70,1.10,.04),Vector3(0,roof-.66,center_z-.79),"glass",Color.WHITE)
	box(root,"RearGlass",Vector3(1.70,1.10,.04),Vector3(0,roof-.66,center_z+.79),"glass",Color.WHITE)
	for x in [-.90,.90]:
		box(root,"DoorPanel",Vector3(.08,.62,1.52),Vector3(x,floor_y+.30,center_z),key,paint)
		box(root,"SideGlass",Vector3(.035,1.10,1.48),Vector3(x,roof-.66,center_z),"glass",Color.WHITE)
		box(root,"Handle",Vector3(.10,.05,.22),Vector3(x*1.06,floor_y+.74,center_z+.35),"metal",Color("393e39"))
		for step in 3: box(root,"EntryStep",Vector3(.38,.09,.56),Vector3(signf(x)*1.13,.27+step*.29,center_z+.35),"metal",Color("4a4b43"))
	root.set_meta("vehicle_interior_spec",{"kind":"truck","floor":floor_y,"roof":roof-.10,"belt":floor_y+.70,"hw":.83,"wz0":center_z-.72,"wz1":center_z-.72,"rear":center_z+.72,"rear_top":center_z+.72,"sx":-.30,"sz":center_z+.04,"roof_liner":false,"rows":false})

static func _loader(root: Node3D, key: String, paint: Color, tractor: bool) -> void:
	box(root,"Chassis",Vector3(1.95,.43,3.80),Vector3(0,.73,0),"metal",Color("46483e"))
	box(root,"EngineHood",Vector3(1.60,.85,1.6),Vector3(0,1.27,-1.27),key,paint)
	box(root,"Grille",Vector3(1.42,.46,.07),Vector3(0,1.24,-2.10),"rubber",Color("222820"))
	for i in 7: box(root,"GrilleSlat",Vector3(.09,.40,.04),Vector3(-.57+i*.19,1.24,-2.15),"metal",Color("5c5c4a"))
	_cabin(root,.10,.98,2.93,key,paint)
	for x in [-1.10,1.10]:
		wheel(root,Vector3(x,.76,1.30),.76,.53)
		wheel(root,Vector3(x,.60,-1.35),.60,.48)
		box(root,"RearFender",Vector3(.65,.12,1.65),Vector3(x,1.61,1.30),key,paint)
	box(root,"Exhaust",Vector3(.11,1.35,.11),Vector3(.68,2.02,-.90),"rubber",Color("34362e"))
	var arm := Node3D.new()
	arm.name = "LoaderArm"
	arm.position = Vector3(0,1.18,-.50)
	root.add_child(arm)
	for x in [-1.0,1.0]:
		beam(arm,"LiftArm",Vector3(x,0,0),Vector3(x,-.71,-2.70),.19,key,paint)
		beam(arm,"HydraulicCylinder",Vector3(x,-.40,-.05),Vector3(x,-.40,-1.25),.16,"metal",Color("41483f"))
		beam(arm,"HydraulicRod",Vector3(x,-.40,-1.25),Vector3(x,-.57,-2.2),.065,"hydraulic",Color("afb6b0"))
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	bucket.position = Vector3(0,-.82,-2.92)
	arm.add_child(bucket)
	box(bucket,"BucketFloor",Vector3(2.76,.15,1.35),Vector3(0,0,-.20),"metal",Color("716c53"))
	box(bucket,"BucketBack",Vector3(2.76,.68,.12),Vector3(0,.34,.39),key,paint)
	for x in [-1.31,1.31]: box(bucket,"BucketSide",Vector3(.12,.48,1.25),Vector3(x,.24,-.20),key,paint)
	for x in [-1.08,-.54,0,.54,1.08]: box(bucket,"Tooth",Vector3(.15,.11,.43),Vector3(x,-.015,-.98),"hydraulic",Color("a7a18c"))
	# Attachment points make the heavy load sit above the scoop, never at cab height.
	var anchor := Marker3D.new()
	anchor.name = "LoadAnchor"
	anchor.position = Vector3(0,.13,-.38)
	bucket.add_child(anchor)
	if not tractor:
		var rear := Node3D.new()
		rear.name = "RearExcavator"
		root.add_child(rear)
		beam(rear,"BackhoeBoom",Vector3(0,1.10,1.55),Vector3(0,2.9,2.35),.30,key,paint)
		beam(rear,"BackhoeDipper",Vector3(0,2.9,2.35),Vector3(0,1.1,2.9),.23,key,paint)
		beam(rear,"BackhoeRam",Vector3(.19,1.35,1.6),Vector3(.19,2.6,2.25),.08,"hydraulic",Color("bbc0b6"))
		box(rear,"DiggingBucket",Vector3(.85,.60,.70),Vector3(0,.94,2.80),"metal",Color("595749"))
		for x in [-.3,0,.3]: box(rear,"BackTooth",Vector3(.13,.24,.22),Vector3(x,.55,2.5),"hydraulic",Color("aaa48b"))

static func _truck(root: Node3D, key: String, paint: Color) -> void:
	box(root,"HaulChassis",Vector3(3.35,.64,7.20),Vector3(0,1.02,0),"metal",Color("41433a"))
	box(root,"FrontDeck",Vector3(3.2,.25,2.4),Vector3(0,1.05,-2.4),key,paint)
	_cabin(root,-2.65,1.18,3.6,key,paint)
	box(root,"EngineBlock",Vector3(2.8,.9,1.5),Vector3(0,1.73,-.90),key,paint)
	for x in [-1.91,1.91]:
		for z in [-2.30,2.20]: wheel(root,Vector3(x,1.05,z),1.05,.79)
		for z in [-3.4,-2.65,-1.9]: box(root,"SafetyRail",Vector3(.055,.70,.055),Vector3(signf(x)*1.48,1.52,z),"metal",Color("5b5e51"))
		box(root,"Handrail",Vector3(.06,.06,1.7),Vector3(signf(x)*1.48,1.88,-2.65),"metal",Color("5b5e51"))
	var bed := Node3D.new()
	bed.name = "DumpBed"
	bed.position = Vector3(0,1.55,3.1)
	root.add_child(bed)
	box(bed,"BedFloor",Vector3(4.3,.22,5.0),Vector3(0,.33,-2.0),"metal",Color("625e4b"))
	for x in [-2.04,2.04]:
		box(bed,"BedSide",Vector3(.20,1.70,5.0),Vector3(x,1.25,-2),key,paint)
		for z in [-4.2,-3.2,-2.2,-1.2,-.2]: box(bed,"BedRib",Vector3(.10,1.8,.15),Vector3(x*1.07,1.25,z),"metal",Color("85764a"))
	box(bed,"BedFront",Vector3(4.3,1.7,.18),Vector3(0,1.25,-4.4),key,paint)
	box(bed,"Canopy",Vector3(4.4,.19,1.9),Vector3(0,2.2,-4.6),key,paint)

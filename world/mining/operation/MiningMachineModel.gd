extends RefCounted
## Shared materials and a small set of articulated nodes; no decorative scripts.
static var materials: Dictionary = {}

static func material(key: String, color: Color) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = color
	m.roughness = .86
	if key.begins_with("paint"):
		m.metallic = .18
		m.roughness = .61
	if key in ["metal", "hydraulic", "worn_steel"]:
		m.metallic = .6
		m.roughness = .42 if key == "hydraulic" else .72
	if key == "glass":
		m.albedo_color = Color(.19,.28,.29,.64)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = .19
	# Cor lisa lia como plano chapado: relevo e rugosidade em espaço de mundo, mesmo tom.
	if color.a >= 1.0 and not m.emission_enabled and key != "glass":
		preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(m, "metal" if m.metallic > 0.1 else "plaster", 2.0, .7)
		m.albedo_color = Color(minf(color.r * m.albedo_color.r, 1.0), minf(color.g * m.albedo_color.g, 1.0), minf(color.b * m.albedo_color.b, 1.0))
		m.roughness = 1.0
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

static func tapered_box(root: Node3D, label: String, size: Vector3, at: Vector3, key: String, color: Color, taper := .82) -> MeshInstance3D:
	var part := box(root,label,size,at,key,color)
	var half := size*.5
	var vertices: Array[Vector3] = []
	for i in 8:
		var top := bool(i & 2)
		vertices.append(Vector3((half.x if i & 1 else -half.x)*(taper if top else 1.0),half.y if top else -half.y,(half.z if i & 4 else -half.z)*(taper if top else 1.0)))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:
		for index in [0,1,2,0,2,3]: tool.add_vertex(vertices[face[index]])
	tool.generate_normals()
	part.mesh = tool.commit()
	return part

static func glazing(root: Node3D, label: String, size: Vector2, at: Vector3, yaw := 0.0) -> void:
	# A pane has one surface. Thin double-sided boxes drew both front/back faces
	# on top of one another and produced unstable dark seams during steering.
	var part := MeshInstance3D.new()
	part.name = label
	var pane := QuadMesh.new()
	pane.size = size
	part.mesh = pane
	part.material_override = material("glass",Color.WHITE)
	part.set_meta("mining_material_key","glass")
	part.position = at
	part.rotation.y = yaw
	root.add_child(part)

static func beam(root: Node3D, label: String, a: Vector3, b: Vector3, width: float, key: String, color: Color) -> MeshInstance3D:
	var part := box(root,label,Vector3(width,a.distance_to(b),width),(a+b)*.5,key,color)
	part.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return part

static func pin(root: Node3D, at: Vector3, radius := .10, width := .12) -> void:
	var part := MeshInstance3D.new()
	part.name = "HexPivotPin"
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = width
	shape.radial_segments = 6
	part.mesh = shape
	part.rotation.z = PI*.5
	part.position = at
	part.material_override = material("worn_steel",Color("7f837d"))
	part.set_meta("mining_material_key","worn_steel")
	root.add_child(part)

static func tread_plate(root: Node3D, at: Vector3, width: float, length: float) -> void:
	# Thick raised chevrons, grouped into the existing steel batch. The geometry
	# sits above the plate; no coplanar decals or runtime material animation.
	for row in 3:
		for column in 3:
			var mark := box(root,"RaisedDeckGrip",Vector3(width*.19,.023,length*.12),at+Vector3((column-1)*width*.28,.012,(row-1)*length*.27),"worn_steel",Color("7f837d"))
			mark.rotation.y = .65 if row%2==0 else -.65

static func bucket_finish(bucket: Node3D) -> void:
	box(bucket,"ScoopCuttingEdge",Vector3(2.72,.10,.17),Vector3(0,-.02,-.89),"worn_steel",Color("7f837d"))
	for side in [-1,1]:
		box(bucket,"ScoopWearCheek",Vector3(.13,.26,1.1),Vector3(side*1.32,.15,-.20),"worn_steel",Color("7f837d"))
		for z in [-.58,.11]: pin(bucket,Vector3(side*1.405,.23,z),.054,.055)
	# Long scrape channels follow the loading direction and leave the bright
	# cutting edge exposed. Angular residue remains within the working scoop.
	for index in 7:
		var x := -.99+index*.33
		box(bucket,"ScrapedScoopFloor",Vector3(.075,.027,.83),Vector3(x,.091,-.18),"worn_steel",Color("7f837d"))
	for index in 4:
		var fragment := tapered_box(bucket,"PackedOreResidue",Vector3(.38,.055,.35),Vector3(-.86+index*.55,.115,.12),"grime",Color("45443a"),.60)
		fragment.rotation.y = index*.71

static func wheel(root: Node3D, at: Vector3, radius: float, width: float) -> void:
	var tire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 24
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
	# Recessed black rim and a small axle cap read as wheels instead of grey discs.
	for side in [-1,1]:
		var cap := box(root,"AxleCap",Vector3(.08,radius*.28,radius*.28),at+Vector3(side*(width*.5+.06),0,0),"metal",Color("787466"))
		cap.set_meta("wheel_center",at)

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
		# Only cabin skin belongs to the door leaf. Previously a door also cut
		# loader arms, exhausts, handrails and the dump bed out of their pivots.
		if root.name != "Cabin": child.set_meta("door_cut_exempt",true)
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
		if first.get_meta("door_cut_exempt",false): batch.set_meta("door_cut_exempt",true)
		if first.has_meta("wheel_center"): batch.set_meta("wheel_center",first.get_meta("wheel_center"))
		root.add_child(batch)
		for part in parts: part.free()

static func _cabin(root: Node3D, center_z: float, floor_y: float, roof: float, key: String, paint: Color) -> void:
	var cabin := Node3D.new()
	cabin.name = "Cabin"
	root.add_child(cabin)
	box(cabin,"CabFloor",Vector3(1.86,.20,1.7),Vector3(0,floor_y-.1,center_z),key,paint)
	tapered_box(cabin,"CabRoof",Vector3(2.0,.16,1.9),Vector3(0,roof,center_z),key,paint,.94)
	for x in [-.88,.88]:
		for z in [-.8,.8]: box(cabin,"CabPillar",Vector3(.09,roof-floor_y,.10),Vector3(x,(roof+floor_y)*.5,center_z+z),"metal",Color("373b36"))
	var glass_height := roof-floor_y-.84
	var glass_y := floor_y+.72+glass_height*.5
	for z in [-.8,.8]:
		box(cabin,"CabLowerPanel",Vector3(1.76,.70,.08),Vector3(0,floor_y+.35,center_z+z),key,paint)
		box(cabin,"WindowSeal",Vector3(1.76,.045,.085),Vector3(0,floor_y+.71,center_z+z),"rubber",Color("222820"))
		box(cabin,"WindowHeader",Vector3(1.76,.08,.085),Vector3(0,roof-.10,center_z+z),"metal",Color("373b36"))
	glazing(cabin,"Windshield",Vector2(1.70,glass_height),Vector3(0,glass_y,center_z-.80))
	glazing(cabin,"RearGlass",Vector2(1.70,glass_height),Vector3(0,glass_y,center_z+.80))
	for x in [-.90,.90]:
		box(cabin,"DoorPanel",Vector3(.08,.70,1.52),Vector3(x,floor_y+.35,center_z),key,paint)
		box(cabin,"DoorWindowSeal",Vector3(.085,.045,1.52),Vector3(x,floor_y+.71,center_z),"rubber",Color("222820"))
		glazing(cabin,"SideGlass",Vector2(1.48,glass_height),Vector3(x,glass_y,center_z),PI*.5)
		box(cabin,"Handle",Vector3(.10,.05,.22),Vector3(x*1.06,floor_y+.74,center_z+.35),"metal",Color("393e39"))
		for step in 3: box(root,"EntryStep",Vector3(.38,.09,.56),Vector3(signf(x)*1.13,.27+step*.29,center_z+.35),"metal",Color("4a4b43"))
		tread_plate(root,Vector3(signf(x)*1.13,.896,center_z+.35),.38,.56)
		beam(root,"MirrorStay",Vector3(x,roof-.45,center_z-.75),Vector3(signf(x)*1.21,roof-.53,center_z-.81),.045,"metal",Color("373b36"))
		box(root,"MirrorHousing",Vector3(.12,.30,.21),Vector3(signf(x)*1.23,roof-.55,center_z-.81),"rubber",Color("222820"))
	box(root,"Wiper",Vector3(.04,.61,.035),Vector3(-.34,roof-.67,center_z-.83),"rubber",Color("222820")).rotation.z = -.25
	root.set_meta("vehicle_interior_spec",{"kind":"truck","floor":floor_y,"roof":roof-.10,"belt":floor_y+.70,"hw":.83,"wz0":center_z-.72,"wz1":center_z-.72,"rear":center_z+.72,"rear_top":center_z+.72,"sx":-.30,"sz":center_z+.04,"roof_liner":false,"rows":false})

static func _loader(root: Node3D, key: String, paint: Color, tractor: bool) -> void:
	box(root,"Chassis",Vector3(1.95,.43,3.80),Vector3(0,.73,0),"metal",Color("46483e"))
	tapered_box(root,"EngineHood",Vector3(1.60,.85,1.6),Vector3(0,1.27,-1.27),key,paint)
	box(root,"Grille",Vector3(1.42,.46,.07),Vector3(0,1.24,-2.10),"rubber",Color("222820"))
	for i in 7: box(root,"GrilleSlat",Vector3(.09,.40,.04),Vector3(-.57+i*.19,1.24,-2.15),"metal",Color("5c5c4a"))
	for x in [-.57,.57]:
		box(root,"FrontLampRim",Vector3(.37,.25,.10),Vector3(x,1.61,-2.06),"rubber",Color("222820"))
		box(root,"FrontLampLens",Vector3(.28,.16,.025),Vector3(x,1.61,-2.12),"lens",Color("dbd8bf"))
	for side in [-1,1]:
		box(root,"EngineVent",Vector3(.025,.28,.78),Vector3(side*.81,1.26,-1.33),"rubber",Color("222820"))
		for index in 5: box(root,"VentSlat",Vector3(.035,.025,.73),Vector3(side*.832,1.15+index*.052,-1.33),"metal",Color("5c5c4a"))
		# Service covers and a separate frame keep the hood from reading as one
		# painted block; the running gear remains visible below the panels.
		box(root,"HoodLowerSeam",Vector3(.035,.055,1.32),Vector3(side*.81,.91,-1.27),"rubber",Color("222820"))
		box(root,"ServiceLatch",Vector3(.045,.13,.12),Vector3(side*.834,1.19,-.70),"worn_steel",Color("7f837d"))
		box(root,"RearMudflap",Vector3(.56,.43,.09),Vector3(side*1.10,.51,1.98),"rubber",Color("222820"))
		box(root,"FenderWornEdge",Vector3(.07,.028,1.52),Vector3(side*1.41,1.687,1.3),"worn_steel",Color("7f837d"))
		box(root,"SideTransmission",Vector3(.21,.29,1.18),Vector3(side*.94,.60,.12),"metal",Color("46483e"))
		pin(root,Vector3(side*1.075,.60,.43),.13,.08)
	for z in [-1.35,1.30]:
		box(root,"ExposedAxle",Vector3(2.07,.19,.23),Vector3(0,.57,z),"metal",Color("46483e"))
	box(root,"RearCounterweight",Vector3(1.58,.44,.34),Vector3(0,.94,1.84),key,paint)
	box(root,"RearTowSocket",Vector3(.36,.18,.32),Vector3(0,.52,2.02),"metal",Color("46483e"))
	for x in [-.63,.63]:
		box(root,"RearLampRim",Vector3(.25,.16,.07),Vector3(x,1.07,2.027),"rubber",Color("222820"))
		box(root,"RearLampLens",Vector3(.18,.105,.024),Vector3(x,1.07,2.078),"tail_lens",Color("973e2e"))
	for i in 4:
		var stripe := box(root,"CounterweightStripe",Vector3(.075,.35,.024),Vector3(-.48+i*.31,.95,2.025),"rubber",Color("222820"))
		stripe.rotation.z = -.40
	_cabin(root,.10,.98,2.93,key,paint)
	for x in [-1.10,1.10]:
		wheel(root,Vector3(x,.76,1.30),.76,.53)
		wheel(root,Vector3(x,.60,-1.35),.60,.48)
		box(root,"RearFender",Vector3(.65,.12,1.65),Vector3(x,1.61,1.30),key,paint)
	box(root,"Exhaust",Vector3(.11,1.35,.11),Vector3(.68,2.02,-.90),"rubber",Color("34362e"))
	box(root,"ExhaustShield",Vector3(.16,.63,.16),Vector3(.68,1.79,-.90),"metal",Color("787466"))
	var arm := Node3D.new()
	arm.name = "LoaderArm"
	arm.position = Vector3(0,1.18,-.50)
	root.add_child(arm)
	for x in [-1.0,1.0]:
		beam(arm,"LiftArm",Vector3(x,0,0),Vector3(x,-.71,-2.70),.19,key,paint)
		beam(arm,"HydraulicCylinder",Vector3(x,-.40,-.05),Vector3(x,-.40,-1.25),.16,"metal",Color("41483f"))
		beam(arm,"HydraulicRod",Vector3(x,-.40,-1.25),Vector3(x,-.57,-2.2),.065,"hydraulic",Color("afb6b0"))
		for point in [Vector3(x*1.09,0,0),Vector3(x*1.09,-.71,-2.70)]: pin(arm,point,.115,.09)
		beam(arm,"HydraulicHose",Vector3(x*.94,.08,-.12),Vector3(x*.94,-.22,-.76),.045,"rubber",Color("222820"))
		beam(arm,"HydraulicHose",Vector3(x*.94,-.22,-.76),Vector3(x*.94,-.31,-1.18),.045,"rubber",Color("222820"))
		box(arm,"ArmEdgeWear",Vector3(.035,.075,1.15),Vector3(x*1.09,-.32,-1.24),"worn_steel",Color("7f837d")).rotation.x = -.24
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	bucket.position = Vector3(0,-.82,-2.92)
	arm.add_child(bucket)
	box(bucket,"BucketFloor",Vector3(2.76,.15,1.35),Vector3(0,0,-.20),"metal",Color("716c53"))
	box(bucket,"BucketBack",Vector3(2.76,.68,.12),Vector3(0,.34,.39),key,paint)
	for x in [-1.31,1.31]: box(bucket,"BucketSide",Vector3(.12,.48,1.25),Vector3(x,.24,-.20),key,paint)
	for x in [-1.08,-.54,0,.54,1.08]: box(bucket,"Tooth",Vector3(.15,.11,.43),Vector3(x,-.015,-.98),"hydraulic",Color("a7a18c"))
	bucket_finish(bucket)
	# Attachment points make the heavy load sit above the scoop, never at cab height.
	var anchor := Marker3D.new()
	anchor.name = "LoadAnchor"
	anchor.position = Vector3(0,.13,-.38)
	bucket.add_child(anchor)
	if not tractor:
		preload("res://world/mining/operation/BackhoeModel.gd").create(root,load("res://world/mining/operation/MiningMachineModel.gd"),key,paint)

static func _truck(root: Node3D, key: String, paint: Color) -> void:
	box(root,"HaulChassis",Vector3(3.35,.64,7.20),Vector3(0,1.02,0),"metal",Color("41433a"))
	box(root,"FrontDeck",Vector3(3.2,.25,2.4),Vector3(0,1.05,-2.4),key,paint)
	_cabin(root,-2.65,1.18,3.6,key,paint)
	tapered_box(root,"EngineBlock",Vector3(2.8,.9,1.5),Vector3(0,1.73,-.90),key,paint,.9)
	box(root,"FrontBumper",Vector3(3.42,.34,.32),Vector3(0,.91,-3.55),"metal",Color("41433a"))
	box(root,"FrontGrille",Vector3(1.53,.37,.045),Vector3(0,1.42,-3.54),"rubber",Color("222820"))
	for index in 9: box(root,"GrilleSlat",Vector3(.055,.31,.035),Vector3(-.66+index*.165,1.42,-3.58),"metal",Color("787466"))
	for side in [-1,1]:
		box(root,"LampHousing",Vector3(.44,.29,.12),Vector3(side*1.22,1.42,-3.48),"rubber",Color("222820"))
		box(root,"LampLens",Vector3(.33,.19,.025),Vector3(side*1.22,1.42,-3.56),"lens",Color("dbd8bf"))
		box(root,"Mudguard",Vector3(.89,.12,2.18),Vector3(side*1.82,2.17,-2.30),key,paint)
		box(root,"AccessStep",Vector3(.65,.12,.68),Vector3(side*1.78,.52,-3.11),"metal",Color("41433a"))
		box(root,"ExhaustStack",Vector3(.16,1.51,.16),Vector3(side*1.27,2.51,-1.52),"metal",Color("787466"))
		box(root,"TailLens",Vector3(.34,.17,.07),Vector3(side*1.48,1.22,3.64),"tail_lens",Color("973e2e"))
		box(root,"FuelTank",Vector3(.57,.60,1.16),Vector3(side*1.49,.83,-.12),"metal",Color("41433a"))
		for z in [-.46,.25]: box(root,"TankStrap",Vector3(.60,.08,.12),Vector3(side*1.49,1.17,z),"worn_steel",Color("7f837d"))
		box(root,"HaulMudflap",Vector3(.82,.61,.10),Vector3(side*1.89,.67,3.26),"rubber",Color("222820"))
		beam(root,"BedLiftCylinder",Vector3(side*.65,1.25,-.72),Vector3(side*.65,2.13,.55),.19,"metal",Color("41433a"))
		beam(root,"BedLiftRod",Vector3(side*.65,2.13,.55),Vector3(side*.65,2.45,1.00),.09,"hydraulic",Color("afb6b0"))
		tread_plate(root,Vector3(side*1.21,1.19,-3.03),.54,.68)
	for x in [-1.91,1.91]:
		for z in [-2.30,2.20]: wheel(root,Vector3(x,1.05,z),1.05,.79)
		box(root,"SafetyRail",Vector3(.055,.70,.055),Vector3(signf(x)*1.48,1.52,-3.63),"metal",Color("5b5e51"))
	# The front deck has a guardrail; the two cabin approaches stay open.
	# Continuous side rails previously ran straight through the boarding route.
	box(root,"Handrail",Vector3(3.02,.06,.06),Vector3(0,1.88,-3.63),"metal",Color("5b5e51"))
	var bed := Node3D.new()
	bed.name = "DumpBed"
	bed.position = Vector3(0,1.55,3.1)
	root.add_child(bed)
	box(bed,"BedFloor",Vector3(4.3,.22,5.0),Vector3(0,.33,-2.0),"metal",Color("625e4b"))
	for side in [-1,1]:
		box(bed,"BedSide",Vector3(.20,1.70,5.0),Vector3(side*2.04,1.25,-2),key,paint).rotation.z = -side*.12
		box(bed,"BedLowerRail",Vector3(.20,.18,5.03),Vector3(side*1.99,.41,-2),"metal",Color("625e4b"))
		box(bed,"BedTopRail",Vector3(.22,.16,5.09),Vector3(side*2.15,2.12,-2),key,paint)
		for z in [-4.2,-3.2,-2.2,-1.2,-.2]:
			beam(bed,"BedRib",Vector3(side*2.04,.48,z),Vector3(side*2.26,2.02,z),.13,"metal",Color("85764a"))
			for y in [.58,1.91]: pin(bed,Vector3(side*(2.08+(y-.48)*.14),y,z),.051,.065)
		# Uneven scraped edges and repaired patches create a working vehicle;
		# every plate stays proud of its host panel to avoid z-fighting.
		for index in 5:
			box(bed,"RimBareMetal",Vector3(.225,.028,.21+float(index%3)*.11),Vector3(side*2.15,2.215,-4.05+index*.83),"worn_steel",Color("7f837d"))
		for index in 3:
			var patch := box(bed,"WornBedPanel",Vector3(.026,.16+index*.07,.34+index*.12),Vector3(side*(2.05+index*.035),.84+index*.30,-3.73+index*1.39),"grime",Color("595445"))
			patch.rotation.z = -side*.12
		pin(bed,Vector3(side*1.72,.12,.06),.21,.22)
	box(bed,"BedFront",Vector3(4.3,1.7,.18),Vector3(0,1.25,-4.4),key,paint)
	box(bed,"Canopy",Vector3(4.4,.19,1.9),Vector3(0,2.2,-4.6),key,paint)
	box(bed,"TailWearEdge",Vector3(4.25,.16,.17),Vector3(0,.44,.51),"worn_steel",Color("7f837d"))
	for index in 9:
		var scrape := box(bed,"BedFloorScrape",Vector3(.07,.024,1.55+float(index%3)*.31),Vector3(-1.69+index*.42,.452,-1.18-float(index%2)*.42),"worn_steel",Color("7f837d"))
		scrape.rotation.y = -.025+index*.006
	for side in [-1,1]:
		beam(bed,"CanopyBrace",Vector3(side*1.65,1.33,-4.37),Vector3(side*1.65,2.06,-5.31),.14,"metal",Color("625e4b"))

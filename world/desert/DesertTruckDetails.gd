extends RefCounted
## Static, batched truck-stop life: service equipment, sheltered tables and usable forecourt lanes.
const G := preload("res://world/desert/DesertGeometry.gd")
const M := preload("res://world/desert/DesertTownMaterials.gd")
const T := preload("res://world/desert/DesertTownDetails.gd")

static func truck_stop() -> Node3D:
	var root := Node3D.new()
	root.name="MiragemWorkingForecourt"
	var canopy := Vector3(10,0,4)
	for x in [-5.0,5.0]:
		var roof := Node3D.new()
		roof.name="PumpIslandRoof"
		roof.position=canopy+Vector3(x,0,0)
		roof.set_meta("desert_roof_occluder",true)
		root.add_child(roof)
		T._piece(roof,"SmallIslandCanopy",Vector3(0,4.2,0),Vector3(5.6,.18,5.8),"roof")
		T._piece(roof,"CanopyFascia",Vector3(0,4.2,2.92),Vector3(5.64,.33,.1),"rust")
		for side in [-1.0,1.0]:
			T._piece(root,"IslandRoofPost",roof.position+Vector3(side*2.3,2.04,2.2),Vector3(.15,4.08,.15),"steel",true)
			T._piece(roof,"CanopyGirder",Vector3(side*2.3,4.02,0),Vector3(.13,.2,5.5),"steel")
			_pipe(roof,"CanopyBrace",Vector3(side*2.3,3.18,2.2),Vector3(side*2.3,4.02,.75),.055,"steel")
		for seam in [-2.0,-1.0,0,1.0,2.0]: T._piece(roof,"CanopySeam",Vector3(seam,4.31,0),Vector3(.04,.035,5.8),"steel")
		G.sign_name(roof,"Miragem",Vector3(0,4.21,2.99),31)
		M.batch_visuals(roof)
	for x in [-5.0,5.0]:
		var pump := canopy+Vector3(x,0,0)
		for side in [-1.0,1.0]:
			# Thick loops, nozzle and guards communicate the pump without explanatory signs.
			var path := PackedVector3Array([pump+Vector3(side*.49,1.7,0),pump+Vector3(side*.87,1.36,.05),pump+Vector3(side*.96,.58,.12),pump+Vector3(side*.68,.31,.17),pump+Vector3(side*.46,.63,.2),pump+Vector3(side*.47,1.33,.23)])
			for i in range(1,path.size()): _pipe(root,"PumpHose",path[i-1],path[i],.043,"rubber")
			_pipe(root,"PumpNozzle",pump+Vector3(side*.47,1.33,.23),pump+Vector3(side*.61,1.51,.23),.052,"steel")
			for z in [-.5,.9]: G.cylinder(root,"PumpBollard",pump+Vector3(side*.78,.46,z),.09,.92,Color("b5914f"),true)
		T._piece(root,"PumpKeypad",pump+Vector3(0,1.29,.53),Vector3(.35,.21,.035),"steel")
		for side in [-1.0,1.0]: T._piece(root,"PumpMeter",pump+Vector3(side*.2,1.79,.53),Vector3(.25,.13,.035),"glass")
		T._piece(root,"PumpBaseTrim",pump+Vector3(0,.27,0),Vector3(.92,.17,1.07),"steel")
	# Air/water station sits clear of the x290 entry and Raul/manifest to the west.
	var air := Vector3(28,0,12)
	T._piece(root,"AirCabinet",air+Vector3(0,.82,0),Vector3(.82,1.64,.68),"rust",true)
	G.cylinder(root,"AirGauge",air+Vector3(0,1.35,.38),.17,.065,Color("ddd0af")).rotation.x=PI*.5
	for i in 8:
		var a := float(i)*TAU/8
		var b := float(i+1)*TAU/8
		_pipe(root,"CoiledAirLine",air+Vector3(.5+cos(a)*.3,.66+sin(a)*.3,.1),air+Vector3(.5+cos(b)*.3,.66+sin(b)*.3,.1),.035,"rubber")
	T._bin(root,Vector3(24,0,11))
	_shelter(root,Vector3(27,0,-27))
	for i in 3: T._pallet(root,Vector3(-47+float(i)*1.4,0,-39))
	T._barrel(root,Vector3(-42.5,0,-39),"rust")
	T._barrel(root,Vector3(-41.4,0,-39),"steel")
	# Individual wheel stops are only on parked trailer rear bays, never across through lanes.
	for i in 4:
		var x := -26.0-float(i)*6.4
		T._piece(root,"TruckWheelStop",Vector3(x,.11,17.3),Vector3(2.7,.22,.36),"stone",true)
	M.batch_visuals(root)
	return root

static func _shelter(root: Node3D,at: Vector3) -> void:
	T._piece(root,"DriverShadeRoof",at+Vector3(0,3.05,0),Vector3(8.3,.16,6.4),"rust")
	for x in [-3.7,3.7]:
		for z in [-2.7,2.7]: T._piece(root,"DriverShadePost",at+Vector3(x,1.5,z),Vector3(.16,3,.16),"wood",true)
	for x in [-2.1,2.1]: T._table(root,at+Vector3(x,0,0))
	for i in range(-3,4): T._piece(root,"ShadeRoofBatten",at+Vector3(i,3.15,0),Vector3(.065,.065,6.4),"steel")
	T._bin(root,at+Vector3(3.2,0,2.2))
	for x in [-3.0,3.0]: T._planter(root,at+Vector3(x,0,-2.1))

static func bitrem() -> Node3D:
	var root := Node3D.new()
	root.name="RoadTrainDetails"
	# Cab doors and steps establish a believable driver-sized tractor.
	for side in [-1.0,1.0]:
		T._piece(root,"CabSideWindow",Vector3(side*1.267,2.62,-11.18),Vector3(.035,.79,1.32),"glass")
		T._piece(root,"WindowDivider",Vector3(side*1.292,2.63,-11.12),Vector3(.032,.86,.043),"steel")
		T._piece(root,"DoorLowerPanel",Vector3(side*1.272,1.76,-11.05),Vector3(.04,.77,1.32),"steel")
		T._piece(root,"TruckDoorHandle",Vector3(side*1.313,2.12,-10.54),Vector3(.05,.07,.3),"chalk")
		for step in 2: T._piece(root,"CabAccessStep",Vector3(side*1.39,.63+float(step)*.29,-10.93),Vector3(.3,.12,.85),"steel")
		T._piece(root,"SleeperVent",Vector3(side*1.22,2.47,-8.95),Vector3(.035,.51,.62),"rubber")
		for i in 4: T._piece(root,"SleeperGrille",Vector3(side*1.25,2.28+float(i)*.12,-8.95),Vector3(.035,.028,.6),"steel")
		# Fuel tanks, chassis equipment and mudguards fill the silhouette below the trailer.
		var tank := G.cylinder(root,"DieselTank",Vector3(side*1.02,1.02,-5.5),.38,1.5,Color("92958d"))
		tank.rotation.x=PI*.5
		for z in [-5.95,-5.05]: T._piece(root,"TankStrap",Vector3(side*1.36,1.04,z),Vector3(.05,.64,.08),"steel")
		for z in [-11.0,-7.0,1.6,11.7]: T._piece(root,"WheelMudguard",Vector3(side*1.30,1.26,z),Vector3(.55,.1,1.85 if z==-11.0 else 2.9),"rubber")
		for z in [-5.7,3.4,13.0]: T._piece(root,"MudFlap",Vector3(side*1.27,.61,z),Vector3(.48,.83,.055),"rubber")
	for z in [-11.0,-7.5,-6.35,.5,1.65,2.8,11.1,12.25]:
		_pipe(root,"TruckAxle",Vector3(-1.30,.60,z),Vector3(1.30,.60,z),.085,"steel")
	var deflector := T._piece(root,"CabWindDeflector",Vector3(0,3.64,-9.25),Vector3(2.35,.16,1.5),"steel")
	deflector.rotation.x=-.2
	for trailer in 2:
		var z := -2.3+float(trailer)*10.5
		for side in [-1.0,1.0]:
			T._piece(root,"LandingLeg",Vector3(side*.81,.72,z-3.2),Vector3(.15,1.13,.15),"steel")
			T._piece(root,"LandingFoot",Vector3(side*.81,.15,z-3.2),Vector3(.38,.1,.4),"steel")
			for i in 5: T._piece(root,"TrailerReflector",Vector3(side*1.373,1.12,z-3.6+float(i)*1.8),Vector3(.018,.09,.37),"chalk")
		var rear := z+4.77
		T._piece(root,"TrailerRearDoorSeam",Vector3(0,2.15,rear),Vector3(.045,2.5,.035),"steel")
		for x in [-.86,.86]:
			T._piece(root,"DoorLockRod",Vector3(x,2.12,rear+.055),Vector3(.037,2.32,.04),"steel")
			T._piece(root,"DoorLockLatch",Vector3(x,1.46,rear+.09),Vector3(.26,.05,.04),"steel")
		T._piece(root,"TrailerRearRail",Vector3(0,.6,rear+.12),Vector3(2.5,.13,.13),"steel")
	M.batch_visuals(root)
	return root

static func _pipe(root: Node3D,id: String,a: Vector3,b: Vector3,radius: float,kind: String) -> void:
	var node := G.cylinder(root,id,(a+b)*.5,radius,a.distance_to(b),Color.WHITE)
	node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	node.material_override=M.material(kind)

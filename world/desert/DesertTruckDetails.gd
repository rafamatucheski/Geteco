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

static func _pipe(root: Node3D,id: String,a: Vector3,b: Vector3,radius: float,kind: String) -> void:
	var node := G.cylinder(root,id,(a+b)*.5,radius,a.distance_to(b),Color.WHITE)
	node.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	node.material_override=M.material(kind)

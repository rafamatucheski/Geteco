extends RefCounted
## Authored exterior objects stay near their building; shared player/NPC approaches stay open.
const G := preload("res://world/desert/DesertGeometry.gd")
const M := preload("res://world/desert/DesertTownMaterials.gd")

static func building(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name="AuthoredTownDetails"
	var size: Vector3=data.size
	var kind: String=data.kind
	var front := size.z*.5
	var half := size.x*.5
	# Continuous plinth, cornice and corner piers articulate wall thickness at human scale.
	for side in [-1.0,1.0]:
		_piece(root,"StonePlinth",Vector3(side*half,.29,0),Vector3(.46,.58,size.z+.2),"stone")
		_piece(root,"CornerPier",Vector3(side*(half-.28),size.y*.5,front+.23),Vector3(.46,size.y,.2),"cream")
		_piece(root,"Cornice",Vector3(side*half,size.y-.14,0),Vector3(.55,.22,size.z+.4),"cream")
		var segment := half-1.5
		_piece(root,"FrontPlinth",Vector3(side*(1.5+segment*.5),.29,front+.23),Vector3(segment,.58,.25),"stone")
		if kind!="workshop": _window(root,Vector3(side*size.x*.30,1.65,front+.34),2.1)
	_piece(root,"FrontCornice",Vector3(0,size.y-.13,front+.33),Vector3(size.x,.22,.25),"cream")
	# A real narrow pedestrian threshold, not an empty paved city block.
	for x in range(-floori(half)+1,floori(half),2):
		var slab := _piece(root,"WalkSlab",Vector3(x,.04,front+1.25),Vector3(1.93,.08,2.15),"stone")
		slab.rotation.y=sin(float(x)*2.3)*.006
	_door(root,Vector3(0,0,front+.02),2.1 if kind!="workshop" else 2.5)
	_rooftop(root,size)
	match kind:
		"bank": _bank(root,size)
		"workshop": _workshop(root,size)
		"motel": _motel(root,size)
		"fuel": _fuel_shop(root,size)
		"diner", "shop": _shopfront(root,size,kind=="diner")
		_: _home(root,size)
	M.batch_visuals(root)
	return root

static func finish_shell(root: Node3D, data: Dictionary) -> void:
	var wall_kind := "cream" if data.kind in ["bank","fuel"] else "adobe"
	if data.kind=="workshop": wall_kind="chalk"
	for child in root.get_children():
		if not child is MeshInstance3D: continue
		var id := str(child.get_meta("desert_part_id",child.name))
		if "Wall" in id or "Parapet" in id: child.material_override=M.material(wall_kind)
		elif id in ["RoofSlab","Foundation","Portico","CoveredWalk"]: child.material_override=M.material("roof" if id=="RoofSlab" else "stone")
		elif id in ["SignBacking","WindowShade"]: child.material_override=M.material("wood")
		elif id in ["Shutter","CoolingUnit"]: child.material_override=M.material("steel")
		elif id=="WindowGlass": child.material_override=M.material("glass")

static func _piece(root: Node3D,id: String,at: Vector3,size: Vector3,kind: String,solid := false) -> MeshInstance3D:
	var node := G.box(root,id,at,size,Color.WHITE,solid)
	node.material_override=M.material(kind)
	return node

static func _window(root: Node3D,at: Vector3,width: float) -> void:
	_piece(root,"WindowRecess",at+Vector3(0,0,.015),Vector3(width+.16,1.22,.12),"steel")
	_piece(root,"GlassPane",at+Vector3(0,0,.083),Vector3(width,1.05,.025),"glass")
	for x in [-width*.5,0,width*.5]: _piece(root,"WindowMullion",at+Vector3(x,0,.11),Vector3(.055,1.15,.045),"cream")
	_piece(root,"WindowSill",at+Vector3(0,-.65,.19),Vector3(width+.4,.12,.48),"stone")
	_piece(root,"WindowReflection",at+Vector3(-width*.18,.22,.102),Vector3(.065,.5,.012),"chalk")

static func _door(root: Node3D,at: Vector3,width: float) -> void:
	for side in [-1.0,1.0]: _piece(root,"DoorJamb",at+Vector3(side*(width*.5+.04),1.19,.06),Vector3(.09,2.38,.14),"steel")
	_piece(root,"DoorTop",at+Vector3(0,2.4,.06),Vector3(width+.17,.12,.14),"steel")
	_piece(root,"DoorGlass",at+Vector3(0,1.5,.025),Vector3(width-.1,1.52,.055),"glass")
	_piece(root,"DoorKickplate",at+Vector3(0,.35,.055),Vector3(width-.1,.53,.06),"steel")
	for side in [-1.0,1.0]: _piece(root,"DoorHandle",at+Vector3(side*.14,1.08,.14),Vector3(.035,.36,.055),"steel")

static func _rooftop(root: Node3D,size: Vector3) -> void:
	var at := Vector3(size.x*.28,size.y+.61,-size.z*.24)
	# AC has louvres, supply duct, service curb and visible drainpipe rather than an anonymous cube.
	_piece(root,"ACServiceCurb",at+Vector3(0,-.42,0),Vector3(1.7,.12,1.65),"steel")
	for i in 6: _piece(root,"ACLouvre",at+Vector3(0,-.27+float(i)*.105,.665),Vector3(1.25,.035,.07),"rubber")
	_piece(root,"ACDuct",at+Vector3(-1.1,-.23,0),Vector3(.9,.42,.6),"steel")
	for side in [-1.0,1.0]:
		var drain := Vector3(side*(size.x*.5+.24),size.y*.5,-size.z*.5+.65)
		G.cylinder(root,"Downpipe",drain,.065,size.y,Color("81715a"))
		_piece(root,"Scupper",drain+Vector3(0,size.y*.5-.16,.12),Vector3(.23,.17,.5),"steel")
	_piece(root,"RoofHatch",Vector3(-size.x*.28,size.y+.26,-size.z*.19),Vector3(1.3,.08,1.1),"steel")
	for i in 3:
		_piece(root,"RoofRepair",Vector3(-size.x*.31+float(i)*1.2,size.y+.246,size.z*.18),Vector3(1.0,.012,2.4),"stone")
	var meter := Vector3(size.x*.5+.3,1.3,size.z*.18)
	_piece(root,"PowerMeter",meter,Vector3(.2,.62,.43),"steel")
	_piece(root,"MeterFace",meter+Vector3(.11,.08,0),Vector3(.012,.22,.22),"glass")
	G.cylinder(root,"ServiceConduit",meter+Vector3(0,-.55,0),.025,1.1,Color("77776a"))

static func _bank(root: Node3D,size: Vector3) -> void:
	var front := size.z*.5
	for side in [-1.0,1.0]:
		_bench(root,Vector3(side*6.7,0,front+1.15))
		_planter(root,Vector3(side*8.8,0,front+1.1))
		for i in 5: _piece(root,"SecurityBar",Vector3(side*size.x*.30-.82+float(i)*.41,1.65,front+.54),Vector3(.028,1.12,.028),"steel")
	_bin(root,Vector3(size.x*.5+1,0,front-1))

static func _workshop(root: Node3D,size: Vector3) -> void:
	var at := Vector3(-size.x*.5-2.1,0,-1)
	_piece(root,"WorkCanopy",at+Vector3(0,3,0),Vector3(3.8,.12,6.3),"rust")
	for z in [-2.6,2.6]: _piece(root,"CanopyLeg",at+Vector3(-1.55,1.46,z),Vector3(.12,2.92,.12),"steel",true)
	_piece(root,"OutdoorWorkbench",at+Vector3(0,.91,-1.8),Vector3(2.4,.12,.85),"wood",true)
	for x in [-.94,.94]: _piece(root,"BenchFrame",at+Vector3(x,.44,-1.8),Vector3(.08,.88,.68),"steel")
	for i in 3:
		_piece(root,"ToolDrawer",at+Vector3(-.75+float(i)*.75,.62,-1.8),Vector3(.66,.38,.76),"steel")
		_piece(root,"DrawerHandle",at+Vector3(-.75+float(i)*.75,.68,-1.395),Vector3(.2,.025,.025),"chalk")
	_barrel(root,at+Vector3(-.8,0,1.1),"rust")
	_barrel(root,at+Vector3(.25,0,1.3),"steel")
	_pallet(root,at+Vector3(.65,0,-3.5))
	_bin(root,Vector3(size.x*.5+1.6,0,-size.z*.5+1))
	# The roadside car delivery and Bia's front-left waiting area remain clear.
	for side in [-1.0,1.0]:
		var at_front := Vector3(side*8,0,size.z*.5+.38)
		_piece(root,"WorkshopBayFrame",at_front+Vector3(-2.33,1.6,0),Vector3(.13,3.3,.18),"rust")
		_piece(root,"WorkshopBayFrame",at_front+Vector3(2.33,1.6,0),Vector3(.13,3.3,.18),"rust")
	# The normal southeast camera sees this service cart against a pier, clear of all three doors.
	var cart := Vector3(3.9,0,size.z*.5+1.25)
	_piece(root,"RollingToolCabinet",cart+Vector3(0,.60,0),Vector3(1.14,.88,.66),"rust",true)
	_piece(root,"ToolCabinetTop",cart+Vector3(0,1.06,0),Vector3(1.2,.055,.72),"steel")
	for i in 4:
		_piece(root,"ToolDrawerFace",cart+Vector3(0,.29+float(i)*.19,.345),Vector3(1.04,.15,.025),"rust")
		_piece(root,"ToolDrawerPull",cart+Vector3(0,.3+float(i)*.19,.371),Vector3(.4,.026,.025),"steel")
	for x in [-.43,.43]:
		for z in [-.23,.23]:
			var wheel := G.cylinder(root,"ToolCartWheel",cart+Vector3(x,.13,z),.11,.07,Color("292c29"))
			wheel.rotation.z=PI*.5
	_barrel(root,Vector3(-3.9,0,size.z*.5+1.1),"steel")

static func _motel(root: Node3D,size: Vector3) -> void:
	var front := size.z*.5
	for i in 6:
		var x := -14.0+float(i)*5.5
		_piece(root,"PorchSupport",Vector3(x-1.8,1.38,front+2.4),Vector3(.14,2.76,.14),"wood",true)
		_piece(root,"RoomThreshold",Vector3(x,.05,front+.8),Vector3(1.35,.1,1.1),"stone")
		_piece(root,"MotelDoorPanel",Vector3(x,1.12,front+.33),Vector3(.92,2.06,.08),"wood")
		_piece(root,"RoomDoorHandle",Vector3(x+.31,1.06,front+.42),Vector3(.12,.04,.06),"steel")
		_chair(root,Vector3(x+1.6,0,front+1.25))
		_piece(root,"RoomAC",Vector3(x+2.65,.92,front+.45),Vector3(.7,.52,.48),"steel")
		for y in 4: _piece(root,"RoomACLouvre",Vector3(x+2.65,.75+float(y)*.1,front+.71),Vector3(.57,.025,.025),"rubber")
	# Vicente x=-327,z=-913 and the existing rest bench x=-315,z=-914.2 remain outside this porch.
	_bin(root,Vector3(-size.x*.5-1,0,front))

static func _fuel_shop(root: Node3D,size: Vector3) -> void:
	var front := size.z*.5
	_piece(root,"IceCabinet",Vector3(-size.x*.5+2,.94,front+.84),Vector3(1.7,1.88,.82),"chalk",true)
	_piece(root,"CabinetDoor",Vector3(-size.x*.5+2,.99,front+1.26),Vector3(1.48,1.51,.045),"steel")
	_bin(root,Vector3(size.x*.5-1.6,0,front+1.1))
	for i in 2: _pallet(root,Vector3(-size.x*.5-1.8,0,-size.z*.5+1.5+float(i)*1.3))

static func _shopfront(root: Node3D,size: Vector3,diner: bool) -> void:
	var front := size.z*.5
	if diner:
		for x in [-5.0,5.0]:
			_piece(root,"ShortDinerAwning",Vector3(x,2.8,front+.72),Vector3(4.1,.11,1.65),"rust")
			for side in [-1.0,1.0]:
				var brace := _piece(root,"AwningBracket",Vector3(x+side*1.8,2.54,front+.58),Vector3(.07,.08,1.1),"steel")
				brace.rotation.x=-.48
		# Side terrace remains readable from the fixed gameplay camera while the entrance faces its street.
		var patio := Vector3(-size.x*.5-3.1,0,0)
		for x in [-.98,.98]:
			for z in [-2.7,-.9,.9,2.7]: _piece(root,"TerracePaving",patio+Vector3(x,.035,z),Vector3(1.92,.07,1.73),"stone")
		for z in [-2.15,2.15]: _table(root,patio+Vector3(0,0,z))
		for x in [-1.7,1.7]:
			for z in [-3.65,3.65]: _piece(root,"PergolaPost",patio+Vector3(x,1.46,z),Vector3(.14,2.92,.14),"wood",true)
			_piece(root,"PergolaRail",patio+Vector3(x,2.93,0),Vector3(.16,.18,7.6),"wood")
		for i in range(-4,5): _piece(root,"OpenShadeSlat",patio+Vector3(0,3.05,float(i)*.83),Vector3(3.7,.12,.12),"wood")
		var side_sign := Node3D.new()
		side_sign.position=Vector3(-size.x*.5-.23,2.45,0)
		side_sign.rotation.y=-PI*.5
		root.add_child(side_sign)
		_piece(side_sign,"SideNameBoard",Vector3.ZERO,Vector3(3.2,.7,.1),"wood")
		G.sign_name(side_sign,"Solana",Vector3(0,0,.065),39)
	else:
		for x in [-5.0,5.0]:
			_piece(root,"ProduceCrate",Vector3(x,.4,front+1.0),Vector3(1.2,.8,.82),"wood",true)
			for i in 4: G.cylinder(root,"ClayJar",Vector3(x-.4+float(i)*.26,.92,front+1),.095,.25,Color("bd9270"))
	_bin(root,Vector3(size.x*.5+1,0,front))

static func _home(root: Node3D,size: Vector3) -> void:
	_planter(root,Vector3(-size.x*.5+1.1,0,size.z*.5+1))
	_chair(root,Vector3(size.x*.5-1.1,0,size.z*.5+1))
	for z in [-1.8,1.8]: _piece(root,"YardPost",Vector3(-size.x*.5-1.6,.62,z),Vector3(.12,1.24,.12),"wood",true)
	for y in [.4,.9]: _piece(root,"YardRail",Vector3(-size.x*.5-1.6,y,0),Vector3(.08,.1,3.6),"wood")

static func _bench(root: Node3D,at: Vector3) -> void:
	_piece(root,"BenchSeat",at+Vector3(0,.47,0),Vector3(1.8,.1,.52),"wood",true)
	_piece(root,"BenchBack",at+Vector3(0,.83,-.23),Vector3(1.8,.56,.08),"wood",true)
	for side in [-1.0,1.0]: _piece(root,"BenchLeg",at+Vector3(side*.68,.23,0),Vector3(.065,.46,.42),"steel")

static func _chair(root: Node3D,at: Vector3) -> void:
	_piece(root,"ChairSeat",at+Vector3(0,.46,0),Vector3(.55,.09,.55),"wood",true)
	_piece(root,"ChairBack",at+Vector3(0,.76,-.23),Vector3(.55,.54,.07),"wood")
	for x in [-.22,.22]:
		for z in [-.22,.22]: _piece(root,"ChairLeg",at+Vector3(x,.23,z),Vector3(.055,.46,.055),"steel")

static func _table(root: Node3D,at: Vector3) -> void:
	G.cylinder(root,"TableTop",at+Vector3(0,.77,0),.68,.08,Color("8d7255"),true)
	G.cylinder(root,"TableStem",at+Vector3(0,.37,0),.075,.74,Color("657067"))
	for x in [-1.0,1.0]: _chair(root,at+Vector3(x,0,0))

static func _planter(root: Node3D,at: Vector3) -> void:
	G.cylinder(root,"ClayPot",at+Vector3(0,.28,0),.35,.56,Color("a77454"),true)
	G.cylinder(root,"PotSoil",at+Vector3(0,.57,0),.30,.025,Color("78674e"))
	for i in 5:
		var angle := float(i)*TAU/5
		var leaf := _piece(root,"DryAgave",at+Vector3(sin(angle)*.19,.88,cos(angle)*.19),Vector3(.1,.6,.055),"steel")
		leaf.rotation=Vector3(cos(angle)*.45,angle,sin(angle)*.45)

static func _bin(root: Node3D,at: Vector3) -> void:
	_piece(root,"RubbishBin",at+Vector3(0,.49,0),Vector3(.66,.98,.64),"steel",true)
	_piece(root,"BinLid",at+Vector3(0,1,0),Vector3(.72,.08,.7),"rubber")

static func _barrel(root: Node3D,at: Vector3,kind: String) -> void:
	var body := G.cylinder(root,"ServiceDrum",at+Vector3(0,.47,0),.31,.94,Color.WHITE,true)
	body.material_override=M.material(kind)
	for y in [.15,.75]: G.cylinder(root,"DrumBand",at+Vector3(0,y,0),.322,.04,Color("545d57"))

static func _pallet(root: Node3D,at: Vector3) -> void:
	for z in [-.45,0,.45]: _piece(root,"PalletRunner",at+Vector3(0,.085,z),Vector3(1.2,.17,.12),"wood")
	for i in 5: _piece(root,"PalletSlat",at+Vector3(-.5+float(i)*.25,.19,0),Vector3(.20,.08,1.12),"wood")
	_piece(root,"CargoBox",at+Vector3(0,.5,0),Vector3(.96,.55,.86),"wood",true)

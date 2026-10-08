extends "res://world/places/amusement_park/ParkGeometry.gd"
## Umbra is a harmless walk-through attraction. Frights are mechanical props.
var variant := 0
var puppet: Node3D
var _scare_amount := 0.0
var _visited := false

func _ready() -> void:
	name = "UmbraInterior"
	_shell()
	_displays()
	_lights()
	flush()
	set_process(false)
	set_physics_process(false)

func _shell() -> void:
	box("FloorBoards",Vector3(0,-.025,0),Vector3(18,.05,15),"55434a",false,"wood")
	for i in 30: box("FloorJoin",Vector3(0,.004,-7.25+i*.5),Vector3(17.7,.007,.015),"322e39")
	box("RearWall",Vector3(0,1.65,-7.36),Vector3(18,3.3,.28),"3f3747",true,"wood")
	for side in [-1,1]:
		box("SideWall%d"%side,Vector3(side*8.86,1.65,0),Vector3(.28,3.3,15),"453c4d",true,"wood")
		box("FrontWall%d"%side,Vector3(side*5.12,1.65,7.36),Vector3(7.75,3.3,.28),"3e3546",true,"wood")
		for z in [-6,-2,2,6]:
			box("WallPilaster",Vector3(side*8.65,1.6,z),Vector3(.15,3.2,.16),"80705c")
		box("Cornice",Vector3(side*8.60,3.07,0),Vector3(.28,.20,14.7),"847560")
	box("Roof",Vector3(0,3.4,0),Vector3(18,.2,15),"272833",false,"wood")
	for x in [-6,-2,2,6]: box("RoofBeam",Vector3(x,3.18,0),Vector3(.18,.25,14.7),"56473e")
	box("EntranceCarpet",Vector3(0,.014,5.2),Vector3(2.15,.02,4.1),"70414e",false,"cloth")
	# Front return wall is physical even when viewed in first person.
	box("DoorHeader",Vector3(0,2.98,7.36),Vector3(2.5,.64,.28),"80705c")
	box("ExitDoorPanel",Vector3(0,1.35,7.36),Vector3(2.35,2.7,.16),"645140",true,"wood")
	box("ExitDoorInset",Vector3(0,1.45,7.267),Vector3(1.97,2.02,.018),"493c35",false,"wood")
	box("ExitHandlePlate",Vector3(-.82,1.15,7.242),Vector3(.09,.28,.035),"b69757",false,"metal")
	box("ExitHandle",Vector3(-.70,1.15,7.19),Vector3(.27,.055,.075),"c9af71",false,"metal")
	for side in [-1,1]: box("DoorJamb%d"%side,Vector3(side*1.27,1.4,7.32),Vector3(.16,2.8,.30),"80705c",true)
	# Tall scenery forms a loop with >=2.1 m side aisles and an open rear gallery.
	box("WestDisplayWall",Vector3(-3.7,1.35,-.6),Vector3(.24,2.7,7.1),"443b43",true,"wood")
	box("EastDisplayWall",Vector3(3.7,1.35,-.6),Vector3(.24,2.7,7.1),"443b43",true,"wood")
	box("CentralStageFront",Vector3(0,.44,2.8),Vector3(7.45,.88,.28),"65544a",true,"wood")
	box("CentralStageFloor",Vector3(0,.16,-.4),Vector3(7.2,.32,6.1),"45363c",true,"wood")
	# The stage stays behind a visible front railing. It is never a walkable shelf.
	for x in [-3,-2,-1,0,1,2,3]: box("StageBaluster",Vector3(x,1.0,2.8),Vector3(.045,.35,.045),"b69c70",false,"metal")
	box("StageRail",Vector3(0,1.2,2.8),Vector3(7.4,.07,.09),"b69c70",false,"metal")

func _displays() -> void:
	for side in [-1,1]:
		var base := Vector3(side*8.22,0,-.5)
		box("PortraitCase%d"%side,base+Vector3(0,1.12,0),Vector3(.90,2.24,2.05),"58493f",true,"wood")
		box("PortraitVelvet",base+Vector3(-side*.47,1.43,0),Vector3(.018,1.43,1.36),"2d323b",false,"cloth")
		ball(base+Vector3(-side*.51,1.5,0),Vector3(.10,.52,.34),"beaa86")
		for z in [-.09,.09]: ball(base+Vector3(-side*.57,1.60,z),Vector3(.045,.055,.055),"cba985", "glow")
		# Low coffers fit the outer bays without pinching the 6.4 m circulation line.
		box("SecretCoffer%d"%side,Vector3(side*7.8,.32,-5.9),Vector3(1.05,.64,1.15),"655244",true,"wood")
		for y in [.12,.54]: box("CofferBand",Vector3(side*7.8,y,-5.9),Vector3(1.08,.08,1.18),"917a56",false,"metal")
		box("SecretTray",Vector3(side*6.4,.028,-5.2),Vector3(.60,.05,.48),"8f734e",false,"wood")
		var stand := Vector3(side*7.8,0,4.9)
		box("StatuePedestal%d"%side,stand+Vector3.UP*.22,Vector3(1.05,.44,1.05),"716661",true,"stone")
		ball(stand+Vector3.UP*1.10,Vector3(.56,1.36,.46),"6e7975")
		ball(stand+Vector3.UP*1.94,Vector3(.38,.47,.36),"c0bca5")
		for x in [-.28,.28]: beam(stand+Vector3(x,1.55,0),stand+Vector3(x*1.5,1.0,-.18),.12,.12,"6e7975")
	# A coffin, a raised puppet and mechanical arms are clearly theatrical props.
	box("Coffin",Vector3(-1.55,.69,-.9),Vector3(1.35,.82,2.5),"493833",true,"wood")
	box("CoffinLid",Vector3(-1.55,1.10,-.9),Vector3(1.37,.10,2.53),"78614a")
	for z in [-1.7,-.2]: box("CoffinClasp",Vector3(-.845,.87,z),Vector3(.10,.16,.24),"ad8e56",false,"metal")
	box("PuppetBase",Vector3(1.50,.61,-1.8),Vector3(1.4,.9,1.5),"49493f",true,"wood")
	puppet = Node3D.new()
	puppet.name = "MechanicalGhost"
	puppet.position = Vector3(1.5,1.10,-1.8)
	add_child(puppet)
	var model := preload("res://world/places/amusement_park/ParkGeometry.gd").new()
	puppet.add_child(model)
	model.ball(Vector3(0,.49,0),Vector3(.63,1.04,.46),"c7ccb7","cloth")
	model.ball(Vector3(0,1.03,0),Vector3(.43,.47,.38),"d8d6bc")
	for side in [-1,1]:
		model.ball(Vector3(side*.095,1.07,.18),Vector3(.074,.11,.04),"292c35")
		model.beam(Vector3(side*.27,.78,0),Vector3(side*.65,.52,.09),.17,.18,"c7ccb7","cloth")
	model.ball(Vector3(0,.94,.187),Vector3(.095,.11,.035),"292c35")
	model.flush()
	box("RearCurtain",Vector3(0,1.5,-7.13),Vector3(4.3,2.9,.11),"603341",false,"cloth")
	for x in [-1.8,-1.2,-.6,0,.6,1.2,1.8]: box("CurtainFold",Vector3(x,1.5,-7.03),Vector3(.14,2.9,.10),"79424e",false,"cloth")
	# Hanging cobweb threads remain high enough for a standing actor to pass.
	for side in [-1,1]:
		var corner := Vector3(side*8.6,3.1,-7.1)
		for i in 6:
			var target := corner+Vector3(-side*(.25+i*.3),-.15-i*.07,.6+i*.17)
			beam(corner,target,.014,.014,"9c9c8e")

func _lights() -> void:
	# Steady motivated sconces; no strobe or exposure changes during frights.
	lantern(Vector3(-6.9,2.55,3.5),"ddbb8a",9.5,1.8)
	lantern(Vector3(6.9,2.55,-3.5),"b8bbda",10.0,2.0)
	lantern(Vector3(0,2.8,-6.85),"d6b28c",8.0,1.45)

func update_visitor(local_point: Vector3, delta: float) -> void:
	if not is_instance_valid(puppet): return
	var near := local_point.distance_to(Vector3(0,0,4.4)) < 4.0
	var target := 1.0 if near else 0.0
	_scare_amount = move_toward(_scare_amount,target,maxf(delta,0)*1.4)
	puppet.position.y = 1.10+sin(_scare_amount*PI*.5)*.62
	puppet.rotation.y = sin(_scare_amount*PI)*.18
	_visited = _visited or near

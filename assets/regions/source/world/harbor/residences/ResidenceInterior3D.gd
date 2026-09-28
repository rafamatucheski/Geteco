extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

var variant_index := 0
var solid_rects: Dictionary = {}
var station_points: Dictionary = {}
var furniture: Node3D

func _ready() -> void:
	var wood: String = ["947354","857566","615749"][variant_index]
	var fabric: String = ["647c72","49717e","8b8474"][variant_index]
	var wall: String = ["d4c9b4","c4d4d2","dfddd1"][variant_index]
	box("Foundation",Vector3(14.4,.22,10.4),Vector3(0,-.15,0),"505852")
	for row in 24:
		for col in 4:
			box("OakFloorboard",Vector3(3.47,.035,.407),Vector3(-5.25+col*3.5,-.01,-4.79+row*.416),wood)
	_wall("BackWall",Rect2(-7,-5.1,14,.2),2.75,wall)
	_wall("LeftWall",Rect2(-7.1,-5,.2,10),2.75,wall)
	_wall("RightCutaway",Rect2(6.9,-5,.2,10),.6,wall)
	_wall("SouthLeft",Rect2(-7,4.9,5.9,.2),.45,wall)
	_wall("SouthRight",Rect2(1.1,4.9,5.9,.2),.45,wall)
	# A doorway in the cutaway is still solid at the far edge: E performs exit.
	solid_rects["DoorBoundary"] = Rect2(-1.1,5.05,2.2,.2)
	box("Skirting",Vector3(13.85,.16,.09),Vector3(0,.08,-4.87),"ebe4d3")
	for x in [-4.4,.3,4.8]:
		box("WindowSurround",Vector3(2.1,1.4,.1),Vector3(x,1.85,-4.83),"eeeadc")
		box("Glass",Vector3(1.87,1.17,.04),Vector3(x,1.85,-4.75),"88b3bc")
		box("WindowCross",Vector3(.06,1.2,.05),Vector3(x,1.85,-4.7),"e8e0ce")
		for side in [-1,1]: box("Curtain",Vector3(.3,1.65,.16),Vector3(x+side*1.03,1.77,-4.62),fabric)
	furniture = Node3D.new()
	furniture.name = "Furnishings"
	add_child(furniture)
	# Variants use different room arrangements, not just recoloured walls.
	var kitchen: Vector2 = [Vector2(4.65,-3.8),Vector2(4.3,2.5),Vector2(-4.3,-3.8)][variant_index]
	var bedroom: Vector2 = [Vector2(4.55,2),Vector2(-4.4,-2.6),Vector2(4.5,2.2)][variant_index]
	var wardrobe: Vector2 = [Vector2(-5.95,-3.25),Vector2(5.9,-3),Vector2(5.95,-3.25)][variant_index]
	var armory: Vector2 = [Vector2(-2.7,-4.2),Vector2(.2,-4.2),Vector2(1.1,-4.2)][variant_index]
	var lounge: Vector2 = [Vector2(-3.5,1.2),Vector2(-3.8,1.7),Vector2(-3.7,.4)][variant_index]
	_kitchen(kitchen,fabric)
	_bedroom(bedroom,fabric)
	_wardrobe(wardrobe,wood)
	_armory(armory,wood)
	_lounge(lounge,fabric,wood)
	_home_storage([Vector2(.5,-4.2),Vector2(.2,-2.1),Vector2(-.7,-4.2)][variant_index],wood)
	if variant_index == 2:
		box("OfficeDesk",Vector3(2.1,.12,.85),Vector3(.1,.79,-1.7),wood)
		for x in [-.8,1]: box("DeskLeg",Vector3(.07,.75,.65),Vector3(x,.37,-1.7),"454e4b")
		box("Laptop",Vector3(.7,.03,.44),Vector3(.1,.88,-1.6),"303c43")
		var screen := box("LaptopScreen",Vector3(.7,.43,.025),Vector3(.1,1.1,-1.8),"678c91")
		screen.rotation.x = -.12
		solid_rects["Desk"] = Rect2(-.95,-2.13,2.1,.85)
	box("EntryMat",Vector3(2.0,.015,1.0),Vector3(0,.02,4.25),"47544e")
	station_points["exit"] = Vector2(0,4.3)
	for point in [Vector3(-6.25,0,3.9),Vector3(6.35,0,-.4)]:
		cylinder("CeramicPot",.3,.46,point+Vector3.UP*.23,"b4a78c")
		solid_rects["Plant"+str(point.x)] = Rect2(Vector2(point.x,point.z)-Vector2(.32,.32),Vector2(.64,.64))
		for i in 5:
			beam("PlantStem",point+Vector3.UP*.4,point+Vector3(sin(i*1.5)*.35,1.15+sin(i)*.2,cos(i*1.5)*.3),.04,"486447")
			var leaf := box("PlantLeaf",Vector3(.23,.055,.48),point+Vector3(sin(i*1.5)*.3,1.0+sin(i)*.2,cos(i*1.5)*.25),"5b7a50")
			leaf.rotation.y = i*1.5
	var lamp_point := lounge+Vector2(-1.75,-.3)
	cylinder("ReadingLampBase",.16,.055,Vector3(lamp_point.x,.035,lamp_point.y),"685d46")
	cylinder("ReadingLampStem",.025,1.15,Vector3(lamp_point.x,.62,lamp_point.y),"ae9975")
	cylinder("ReadingLampShade",.24,.34,Vector3(lamp_point.x,1.36,lamp_point.y),"ddd1b6")
	solid_rects["ReadingLamp"] = Rect2(lamp_point-Vector2(.17,.17),Vector2(.34,.34))
	for point in [bedroom+Vector2(-1.6,-1.05),lamp_point]:
		var light := OmniLight3D.new()
		light.position = Vector3(point.x,1.5,point.y)
		light.light_color = Color("ffd6a0")
		light.light_energy = .65
		light.omni_range = 4.2
		add_child(light)

func _wall(id: String,r: Rect2,height: float,color: String) -> void:
	box(id,Vector3(r.size.x,height,r.size.y),Vector3(r.get_center().x,height*.5,r.get_center().y),color)
	solid_rects[id] = r

func _kitchen(p: Vector2,color: String) -> void:
	box("KitchenCabinets",Vector3(3.25,.88,1.15),Vector3(p.x,.44,p.y),color)
	box("StoneCounter",Vector3(3.4,.09,1.25),Vector3(p.x,.925,p.y),"e2ddcc")
	for x in [-1.1,0,1.1]:
		box("CabinetDoor",Vector3(1.02,.73,.045),Vector3(p.x+x,.44,p.y+.59),color)
		box("BrassPull",Vector3(.25,.035,.06),Vector3(p.x+x,.76,p.y+.63),"b5a782")
	box("SinkInset",Vector3(.76,.035,.67),Vector3(p.x-.9,.978,p.y),"738783")
	box("SinkBowl",Vector3(.57,.038,.48),Vector3(p.x-.9,1,p.y),"394c54")
	beam("Tap",Vector3(p.x-.9,1,p.y-.35),Vector3(p.x-.9,1.42,p.y-.35),.045,"b7c5c3")
	beam("TapSpout",Vector3(p.x-.9,1.4,p.y-.35),Vector3(p.x-.9,1.4,p.y-.08),.045,"b7c5c3")
	box("Hob",Vector3(.72,.035,.72),Vector3(p.x+.8,.98,p.y),"303b3b")
	for x in [.57,1.03]:
		for z in [-.22,.22]: cylinder("Burner",.12,.02,Vector3(p.x+x,1.01,p.y+z),"71817d")
	cylinder("Plate",.22,.025,Vector3(p.x-.05,1,p.y+.2),"f0e6cf")
	cylinder("Meal",.13,.06,Vector3(p.x-.05,1.04,p.y+.2),"be824b")
	var fridge_x := p.x+signf(p.x)*1.75
	box("Refrigerator",Vector3(.8,1.9,.88),Vector3(fridge_x,.95,p.y),"c7cfc8")
	box("FreezerDoor",Vector3(.74,.55,.04),Vector3(fridge_x,1.55,p.y+.46),"e2e5dc")
	box("FridgeDoor",Vector3(.74,1.16,.04),Vector3(fridge_x,.65,p.y+.46),"dce0d7")
	box("FridgeHandle",Vector3(.055,.38,.07),Vector3(fridge_x-.27,1.01,p.y+.51),"788783")
	solid_rects["Kitchen"] = Rect2(p-Vector2(2.2,.65),Vector2(4.4,1.3))
	station_points["food"] = Vector2(fridge_x,p.y+1.25)

func _home_storage(p: Vector2,wood: String) -> void:
	box("StorageChest",Vector3(1.2,.65,.75),Vector3(p.x,.325,p.y),wood)
	box("ChestLid",Vector3(1.26,.09,.8),Vector3(p.x,.695,p.y),"76614e")
	for x in [-.43,.43]: box("ChestStrap",Vector3(.07,.73,.81),Vector3(p.x+x,.37,p.y),"505951")
	box("ChestLatch",Vector3(.13,.18,.04),Vector3(p.x,.56,p.y+.43),"b2a077")
	solid_rects["StorageChest"] = Rect2(p-Vector2(.63,.43),Vector2(1.26,.86))
	station_points["chest"] = p+Vector2(0,1.05)
	box("SaveDesk",Vector3(1.05,.76,.55),Vector3(1.85,.38,4.5),wood)
	box("SaveNotebook",Vector3(.4,.04,.3),Vector3(1.68,.79,4.47),"e9dfc6")
	box("SavePen",Vector3(.02,.025,.21),Vector3(1.97,.795,4.46),"344c59")
	solid_rects["SaveDesk"] = Rect2(1.325,4.225,1.05,.55)
	station_points["save"] = Vector2(1.85,3.55)

func _bedroom(p: Vector2,color: String) -> void:
	box("BedroomRug",Vector3(3.55,.018,3.65),Vector3(p.x,.025,p.y),"b9b29b")
	box("BedBase",Vector3(2.2,.36,2.9),Vector3(p.x,.26,p.y),"6c5846")
	box("Mattress",Vector3(2.15,.27,2.8),Vector3(p.x,.56,p.y),"e5dfcd")
	box("Duvet",Vector3(2.19,.18,2.0),Vector3(p.x,.77,p.y+.4),color)
	box("Throw",Vector3(2.2,.025,.6),Vector3(p.x,.88,p.y+1.1),"bcac89")
	for x in [-.55,.55]: box("Pillow",Vector3(.87,.19,.52),Vector3(p.x+x,.78,p.y-.98),"efe8d6")
	box("Headboard",Vector3(2.35,1.1,.13),Vector3(p.x,.58,p.y-1.5),"74624e")
	for x in [-1.6,1.6]:
		box("BedsideCabinet",Vector3(.64,.57,.65),Vector3(p.x+x,.285,p.y-1.05),"8e7e65")
		cylinder("LampStem",.06,.3,Vector3(p.x+x,.75,p.y-1.05),"ad9c7a")
		cylinder("LinenShade",.21,.3,Vector3(p.x+x,1,p.y-1.05),"ded2b4")
	solid_rects["Bed"] = Rect2(p-Vector2(1.175,1.565),Vector2(2.35,3.065))
	for side in [-1,1]: solid_rects["Bedside%d"%side] = Rect2(p+Vector2(side*1.6-.32,-1.375),Vector2(.64,.65))
	station_points["time"] = p+Vector2(-signf(p.x)*1.9,.25)

func _wardrobe(p: Vector2,color: String) -> void:
	box("Wardrobe",Vector3(1.35,2.35,2.45),Vector3(p.x,1.175,p.y),color)
	var front := p.x-signf(p.x)*.7
	for z in [-.77,0,.77]:
		box("WardrobePanel",Vector3(.05,2.17,.72),Vector3(front,1.18,p.y+z),"b8ae97")
		box("WardrobeHandle",Vector3(.07,.2,.04),Vector3(front-signf(p.x)*.04,1.12,p.y+z+.2),"8d8062")
	solid_rects["Wardrobe"] = Rect2(p-Vector2(.8,1.25),Vector2(1.6,2.5))
	station_points["wardrobe"] = p+Vector2(-signf(p.x)*1.45,0)

func _armory(p: Vector2,color: String) -> void:
	box("ArmoryBench",Vector3(2.6,.85,.85),Vector3(p.x,.425,p.y),color)
	box("Pegboard",Vector3(2.7,1.4,.12),Vector3(p.x,1.72,p.y-.4),"374948")
	for row in 4:
		for col in 9: cylinder("Peg",.018,.04,Vector3(p.x-1.15+col*.28,1.15+row*.3,p.y-.29),"84958a").rotation.x=PI*.5
	for y in [1.45,2.05]:
		box("RifleStock",Vector3(.47,.16,.08),Vector3(p.x-.75,y,p.y-.23),"765b3c")
		box("RifleReceiver",Vector3(.68,.1,.075),Vector3(p.x-.22,y+.02,p.y-.23),"26343b")
		box("RifleBarrel",Vector3(.86,.045,.045),Vector3(p.x+.49,y+.045,p.y-.23),"596767")
		var grip := box("RifleGrip",Vector3(.11,.22,.07),Vector3(p.x-.38,y-.12,p.y-.23),"344044")
		grip.rotation.z = -.3
	box("AmmoBox",Vector3(.6,.21,.36),Vector3(p.x+.55,.98,p.y+.05),"657353")
	solid_rects["Armory"] = Rect2(p-Vector2(1.35,.46),Vector2(2.7,.92))
	station_points["arsenal"] = p+Vector2(0,1.15)

func _lounge(p: Vector2,color: String,wood: String) -> void:
	box("LoungeRug",Vector3(4.5,.02,4.8),Vector3(p.x,.035,p.y+.6),"b1a789")
	box("SofaBase",Vector3(3.0,.4,1.05),Vector3(p.x,.37,p.y),color)
	box("SofaBack",Vector3(3.05,.75,.22),Vector3(p.x,.78,p.y-.46),color)
	for x in [-1.45,1.45]: box("SofaArm",Vector3(.21,.56,1.12),Vector3(p.x+x,.62,p.y),color)
	for x in [-.92,0,.92]: box("SeatCushion",Vector3(.85,.18,.76),Vector3(p.x+x,.65,p.y+.06),color)
	box("CoffeeTable",Vector3(1.8,.12,.9),Vector3(p.x,.46,p.y+1.65),wood)
	for x in [-.72,.72]:
		for z in [-.3,.3]: box("TableLeg",Vector3(.06,.43,.06),Vector3(p.x+x,.22,p.y+1.65+z),"424c47")
	box("Book",Vector3(.44,.05,.32),Vector3(p.x+.3,.56,p.y+1.65),"486577")
	cylinder("CoffeeMug",.075,.14,Vector3(p.x-.32,.59,p.y+1.67),"e3d8be")
	solid_rects["Sofa"] = Rect2(p-Vector2(1.6,.6),Vector2(3.2,1.2))
	solid_rects["CoffeeTable"] = Rect2(p+Vector2(-.9,1.2),Vector2(1.8,.9))

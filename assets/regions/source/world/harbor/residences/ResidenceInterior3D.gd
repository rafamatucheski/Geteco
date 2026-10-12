extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"
const WEAPON_MODEL := preload("res://gameplay/ArsenalWeapon3D.gd")
const FINISH := preload("res://gameplay/WeaponFinish3D.gd")

var variant_index := 0
var solid_rects: Dictionary = {}
var station_points: Dictionary = {}
var furniture: Node3D
var presentation_points: Dictionary = {}
var fridge_hinge: Node3D
var mirror_mesh: MeshInstance3D
var backpack_prop: Node3D
var bench_light: SpotLight3D
var roof_access_point := Vector3.ZERO

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
	# A wall-backed roof ladder occupies the gap between the authored furniture.
	roof_access_point = Vector3([1.95,2.9,3.0][variant_index],0,-4.05)
	station_points["roof"] = Vector2(roof_access_point.x,roof_access_point.z)
	_kitchen(kitchen,fabric)
	_bedroom(bedroom,fabric)
	_wardrobe(wardrobe,wood)
	_armory(armory,wood)
	_lounge(lounge,fabric,wood)
	_home_storage([Vector2(.5,-4.2),Vector2(.2,-2.1),Vector2(-.7,-4.2)][variant_index],wood)
	_backpack()
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
	# A hollow cabinet exposes the food when the real hinged door opens.
	box("RefrigeratorBack",Vector3(.8,1.9,.08),Vector3(fridge_x,.95,p.y-.4),"c7cfc8")
	for side in [-1,1]: box("RefrigeratorSide",Vector3(.055,1.9,.88),Vector3(fridge_x+side*.3725,.95,p.y),"dce0d7")
	for shelf_y in [.055,.49,.91,1.3,1.86]:
		box("FridgeShelf",Vector3(.71,.055,.79),Vector3(fridge_x,shelf_y,p.y+.015),"ecede3")
	for bottle_x in [-.2,.04,.22]:
		cylinder("JuiceBottle",.066,.25,Vector3(fridge_x+bottle_x,.65,p.y+.11),"dfb05b")
		cylinder("BottleNeck",.027,.085,Vector3(fridge_x+bottle_x,.82,p.y+.11),"e6d4a5")
		cylinder("BottleCap",.031,.022,Vector3(fridge_x+bottle_x,.87,p.y+.11),"708969")
	for shelf_y in [1.0,1.4]:
		box("FoodContainer",Vector3(.44,.12,.38),Vector3(fridge_x-.08,shelf_y,p.y+.04),"a4b6a0")
		box("FoodContainerLid",Vector3(.46,.025,.4),Vector3(fridge_x-.08,shelf_y+.073,p.y+.04),"e5e2d0")
	fridge_hinge = Node3D.new()
	fridge_hinge.name = "FridgeHinge"
	fridge_hinge.position = Vector3(fridge_x-.39,0,p.y+.47)
	add_child(fridge_hinge)
	box("FreezerDoor",Vector3(.76,.55,.07),Vector3(.39,1.58,0),"e2e5dc",fridge_hinge)
	box("FridgeDoor",Vector3(.76,1.23,.07),Vector3(.39,.66,0),"dce0d7",fridge_hinge)
	box("FridgeHandle",Vector3(.055,.4,.07),Vector3(.67,1.01,.07),"788783",fridge_hinge)
	box("DoorInnerShelf",Vector3(.59,.12,.12),Vector3(.39,.44,-.09),"ecebdf",fridge_hinge)
	solid_rects["Kitchen"] = Rect2(p-Vector2(2.2,.65),Vector2(4.4,1.3))
	station_points["food"] = Vector2(fridge_x,p.y+1.25)
	presentation_points["food"] = Vector3(fridge_x,.99,p.y+.13)

func _home_storage(p: Vector2,wood: String) -> void:
	box("StorageChest",Vector3(1.2,.65,.75),Vector3(p.x,.325,p.y),wood)
	box("ChestLid",Vector3(1.26,.09,.8),Vector3(p.x,.695,p.y),"76614e")
	for x in [-.43,.43]: box("ChestStrap",Vector3(.07,.73,.81),Vector3(p.x+x,.37,p.y),"505951")
	box("ChestLatch",Vector3(.13,.18,.04),Vector3(p.x,.56,p.y+.43),"b2a077")
	solid_rects["StorageChest"] = Rect2(p-Vector2(.63,.43),Vector2(1.26,.86))
	station_points["chest"] = p+Vector2(0,1.05)
	presentation_points["chest"] = Vector3(p.x,.4,p.y)
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
	presentation_points["time"] = Vector3(p.x,0,p.y)

func _wardrobe(p: Vector2,color: String) -> void:
	box("Wardrobe",Vector3(1.35,2.35,2.45),Vector3(p.x,1.175,p.y),color)
	var front := p.x-signf(p.x)*.7
	for z in [-.77,0,.77]:
		box("WardrobePanel",Vector3(.05,2.17,.72),Vector3(front,1.18,p.y+z),"b8ae97")
		box("WardrobeHandle",Vector3(.07,.2,.04),Vector3(front-signf(p.x)*.04,1.12,p.y+z+.2),"8d8062")
	solid_rects["Wardrobe"] = Rect2(p-Vector2(.8,1.25),Vector2(1.6,2.5))
	station_points["wardrobe"] = p+Vector2(-signf(p.x)*1.45,0)
	var normal := Vector3(-signf(p.x),0,0)
	var mirror_center := Vector3(front,1.18,p.y+.61)+normal*.045
	box("MirrorFrame",Vector3(.075,1.98,.82),mirror_center,"484d43")
	mirror_mesh = MeshInstance3D.new()
	mirror_mesh.name = "WardrobeMirrorSurface"
	var glass := QuadMesh.new()
	glass.size = Vector2(.73,1.87)
	mirror_mesh.mesh = glass
	mirror_mesh.position = mirror_center+normal*.044
	mirror_mesh.rotation.y = normal.x*PI*.5
	var mirror_surface := material("a2b7bd",.85).duplicate() as StandardMaterial3D
	mirror_surface.roughness = .15
	mirror_mesh.material_override = mirror_surface
	add_child(mirror_mesh)
	presentation_points["wardrobe"] = Vector3(p.x,1.15,p.y)
	presentation_points["wardrobe_normal"] = normal

func _armory(p: Vector2,color: String) -> void:
	var cabinet := box("ArmoryBench",Vector3(2.55,.74,.78),Vector3(p.x,.37,p.y),"615449")
	cabinet.mesh = FINISH._beveled_box(Vector3(2.55,.74,.78))
	var top := box("OiledBenchTop",Vector3(2.66,.11,.91),Vector3(p.x,.795,p.y),color)
	top.mesh = FINISH._beveled_box(Vector3(2.66,.11,.91))
	for x in [-.87,0,.87]:
		box("ToolDrawer",Vector3(.81,.23,.035),Vector3(p.x+x,.59,p.y+.405),"80664e")
		box("DrawerPull",Vector3(.26,.035,.055),Vector3(p.x+x,.61,p.y+.443),"3f4641")
	for x in [-1.24,1.24]:
		box("BenchCornerSteel",Vector3(.075,.72,.06),Vector3(p.x+x,.36,p.y+.397),"444c47")
	# The window curtains end at z=-4.54; keep the entire rack in front of them.
	box("Pegboard",Vector3(2.7,1.4,.12),Vector3(p.x,1.72,p.y-.26),"374948")
	for row in 4:
		for col in 9: cylinder("PegboardHole",.014,.001,Vector3(p.x-1.15+col*.28,1.15+row*.3,p.y-.198),"1b2928").rotation.x=PI*.5
	# Keep the mounted weapons above the lamp housing and inside the close view.
	for spec in [["shotgun",-.48,2.12],["ak47",.55,2.12]]:
		var weapon := Node3D.new()
		weapon.name = "Rack_"+str(spec[0])
		# Side profile parallel to the wall, with 4 mm behind the deepest mesh.
		weapon.position = Vector3(p.x+float(spec[1]),float(spec[2]),p.y-.169)
		weapon.rotation.y = -PI*.5
		add_child(weapon)
		WEAPON_MODEL.build_cached(weapon,str(spec[0]))
		# Each cradle meets the underside of the stock and the wooden fore-end.
		var supports := [Vector2(-.18,-.0825),Vector2(.16,-.036)] if spec[0] == "shotgun" else [Vector2(-.25,-.0575),Vector2(.16,-.02)]
		for support in supports:
			var mount := Node3D.new()
			mount.name = "WallCradle"
			mount.position = Vector3(weapon.position.x+support.x,weapon.position.y+support.y,p.y-.20)
			add_child(mount)
			box("MountPlate",Vector3(.034,.07,.006),Vector3(0,-.024,.003),"657a71",mount)
			box("PaddedSeat",Vector3(.034,.016,.079),Vector3(0,-.009,.0425),"293a35",mount)
			box("RetainingLip",Vector3(.034,.038,.009),Vector3(0,.002,.078),"657a71",mount)
	box("WeaponCleaningMatBorder",Vector3(1.99,.013,.65),Vector3(p.x,.858,p.y+.015),"6a6454")
	box("WeaponCleaningMat",Vector3(1.94,.012,.6),Vector3(p.x,.869,p.y+.015),"667978")
	_bench_tools(p)
	_bench_lamp(p)
	solid_rects["Armory"] = Rect2(p-Vector2(1.35,.46),Vector2(2.7,.92))
	station_points["arsenal"] = p+Vector2(0,1.15)
	presentation_points["arsenal"] = Vector3(p.x,.877,p.y+.015)

func _bench_tools(p: Vector2) -> void:
	var tools := Node3D.new()
	tools.name = "WorkbenchTools"
	tools.position = Vector3(p.x,.86,p.y)
	add_child(tools)
	# The smaller tools sit on the mat edges inside the close camera's view.
	# The centre remains clear for the same weapon meshes used in gameplay.
	for side in [-1,1]:
		beam("PliersHandle",Vector3(-.78+side*.055,.031,.25),Vector3(-.78+side*.018,.031,.08),.03,"aa6547",tools)
		beam("PliersJaw",Vector3(-.78+side*.018,.031,.08),Vector3(-.78+side*.026,.031,-.015),.018,"9da9a5",tools)
	cylinder("PliersPivot",.025,.021,Vector3(-.78,.041,.08),"b7b9ab",tools)
	var handle := cylinder("ScrewdriverHandle",.036,.15,Vector3(.65,.052,.17),"a88335",tools)
	handle.rotation.x = PI*.5
	beam("ScrewdriverShaft",Vector3(.65,.052,.09),Vector3(.65,.052,-.115),.011,"b8c0bc",tools)
	box("ScrewdriverTip",Vector3(.021,.006,.03),Vector3(.65,.052,-.12),"909b95",tools)
	beam("CleaningRod",Vector3(-.35,.022,.387),Vector3(.85,.022,.387),.012,"a2aca5",tools)
	beam("RodHandle",Vector3(-.5,.027,.387),Vector3(-.35,.027,.387),.037,"654330",tools)
	box("CleaningBrush",Vector3(.2,.028,.043),Vector3(.30,.035,-.36),"b89964",tools)
	for x in 8:
		box("BrushBristles",Vector3(.01,.021,.037),Vector3(.24+x*.017,.011,-.36),"656252",tools)
	cylinder("GunOilBottle",.063,.15,Vector3(-.75,.091,-.20),"bb923f",tools)
	cylinder("OilCap",.035,.043,Vector3(-.75,.187,-.20),"38483f",tools)
	beam("OilNozzle",Vector3(-.75,.207,-.20),Vector3(-.75,.270,-.20),.015,"a4ada2",tools)
	box("PartsTray",Vector3(.29,.015,.13),Vector3(.55,.024,-.25),"697b75",tools)
	for z in [-.313,-.187]: box("TrayRim",Vector3(.3,.03,.012),Vector3(.55,.038,z),"9baaa2",tools)
	for x in [.405,.695]: box("TrayRim",Vector3(.012,.03,.13),Vector3(x,.038,-.25),"9baaa2",tools)
	for index in 4:
		cylinder("SpareScrewHead",.014,.012,Vector3(.46+index*.054,.040,-.265+sin(index)*.025),"c3c5ae",tools)
	box("FoldedCleaningCloth",Vector3(.19,.021,.1),Vector3(.83,.024,.275),"d7c9a9",tools)
	for index in 3: box("ClothFold",Vector3(.18,.009,.013),Vector3(.83,.04,.25+index*.025),"bdb39b",tools)

func _bench_lamp(p: Vector2) -> void:
	cylinder("TaskLampBase",.095,.032,Vector3(p.x-1.1,.881,p.y+.05),"394841")
	beam("TaskLampLowerArm",Vector3(p.x-1.1,.90,p.y+.05),Vector3(p.x-1.08,1.52,p.y-.02),.034,"54655b")
	beam("TaskLampUpperArm",Vector3(p.x-1.08,1.52,p.y-.02),Vector3(p.x-.62,1.7,p.y+.08),.031,"54655b")
	var head := Node3D.new()
	head.name = "TaskLampHead"
	head.position = Vector3(p.x-.62,1.7,p.y+.08)
	add_child(head)
	head.look_at(to_global(Vector3(p.x,.89,p.y+.04)))
	box("LampHousing",Vector3(.3,.12,.18),Vector3.ZERO,"34483e",head)
	box("LampLens",Vector3(.25,.07,.014),Vector3(0,0,-.098),"f0dfb3",head)
	bench_light = SpotLight3D.new()
	bench_light.name = "WorkbenchTaskLight"
	bench_light.position = head.position+Vector3(0,-.025,0)
	bench_light.light_color = Color("fff0d5")
	bench_light.light_energy = .65
	bench_light.spot_range = 2.4
	bench_light.spot_angle = 61
	bench_light.spot_attenuation = .7
	bench_light.shadow_enabled = false
	bench_light.visible = false
	add_child(bench_light)
	bench_light.look_at(to_global(Vector3(p.x,.88,p.y+.035)))

func _backpack() -> void:
	box("BackpackStand",Vector3(.54,.13,.46),Vector3(6.35,.065,4.4),"685a49")
	backpack_prop = Node3D.new()
	backpack_prop.name = "HomeBackpack"
	backpack_prop.position = Vector3(6.35,.11,4.4)
	add_child(backpack_prop)
	var body := MeshInstance3D.new()
	body.name = "CanvasBag"
	var mesh := CapsuleMesh.new()
	mesh.radius = .22
	mesh.height = .58
	body.mesh = mesh
	body.scale.z = .6
	body.position.y = .31
	body.material_override = material("9c8156")
	backpack_prop.add_child(body)
	box("FrontPocket",Vector3(.32,.22,.08),Vector3(0,.23,.145),"776846",backpack_prop)
	box("PocketZip",Vector3(.28,.018,.018),Vector3(0,.34,.192),"c9b98b",backpack_prop)
	for side in [-1,1]:
		box("BagStrap",Vector3(.045,.4,.035),Vector3(side*.13,.33,-.145),"394641",backpack_prop)
		box("SidePocket",Vector3(.09,.23,.18),Vector3(side*.215,.25,0),"7f7250",backpack_prop)
	beam("HandleLeft",Vector3(-.085,.56,0),Vector3(-.085,.67,0),.035,"394641",backpack_prop)
	beam("HandleRight",Vector3(.085,.56,0),Vector3(.085,.67,0),.035,"394641",backpack_prop)
	beam("HandleTop",Vector3(-.085,.67,0),Vector3(.085,.67,0),.035,"394641",backpack_prop)
	solid_rects["BackpackStand"] = Rect2(6.08,4.17,.54,.46)
	station_points["backpack"] = Vector2(5.5,4.3)
	presentation_points["backpack"] = Vector3(6.35,.3,4.4)

func _lounge(p: Vector2,color: String,wood: String) -> void:
	# The previous 60 cm gap exactly matched Dante's capsule diameter and
	# wedged it between sofa and table. Keep one metre of walkable floor.
	var table := p+Vector2(0,2.05)
	box("LoungeRug",Vector3(4.5,.02,4.8),Vector3(p.x,.035,p.y+.6),"b1a789")
	box("SofaBase",Vector3(3.0,.4,1.05),Vector3(p.x,.37,p.y),color)
	box("SofaBack",Vector3(3.05,.75,.22),Vector3(p.x,.78,p.y-.46),color)
	for x in [-1.45,1.45]: box("SofaArm",Vector3(.21,.56,1.12),Vector3(p.x+x,.62,p.y),color)
	for x in [-.92,0,.92]: box("SeatCushion",Vector3(.85,.18,.76),Vector3(p.x+x,.65,p.y+.06),color)
	box("CoffeeTable",Vector3(1.8,.12,.9),Vector3(table.x,.46,table.y),wood)
	for x in [-.72,.72]:
		for z in [-.3,.3]: box("TableLeg",Vector3(.06,.43,.06),Vector3(table.x+x,.22,table.y+z),"424c47")
	box("Book",Vector3(.44,.05,.32),Vector3(table.x+.3,.56,table.y),"486577")
	cylinder("CoffeeMug",.075,.14,Vector3(table.x-.32,.59,table.y+.02),"e3d8be")
	solid_rects["Sofa"] = Rect2(p-Vector2(1.6,.6),Vector2(3.2,1.2))
	solid_rects["CoffeeTable"] = Rect2(table-Vector2(.9,.45),Vector2(1.8,.9))

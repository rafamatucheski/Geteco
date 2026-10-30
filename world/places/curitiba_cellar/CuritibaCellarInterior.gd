extends "res://world/places/curitiba_cellar/CellarGeometry.gd"
const SHELL_FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const SHELL_RECIPES := {
	"wood": ["745540", "71503b", "7c5940", "856044", "684837", "402d26", "624536", "95764b", "513b2e"],
	"stone": ["c3b99f", "c7bba4", "baaf98"],
	"cloth": ["532c3c", "b69b65"],
}
const SHELL_KINDS := {"wood": "wood", "stone": "cast", "cloth": "fabric"}

static func painted_enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_CELLAR_INTERIOR") != "0"

static func prewarm_materials() -> Array[Material]:
	var result: Array[Material] = []
	if not painted_enabled(): return result
	for kind in SHELL_RECIPES:
		for color in SHELL_RECIPES[kind]:
			result.append(SHELL_FINISH.material(SHELL_KINDS[kind], Color(color), .9))
	return result

func surface(color: String, kind := "wood") -> StandardMaterial3D:
	if kind.begins_with("shell_"):
		var original := kind.trim_prefix("shell_")
		if painted_enabled():
			return SHELL_FINISH.material(SHELL_KINDS[original], Color(color), .9)
		return super.surface(color, original)
	return super.surface(color, kind)

## Curitiba Cellar: native 14 x 11 metre shop, composed for the Maciota camera.
## NativePlace builds the physical volumes before admitting player/residents.
const ROOM_SIZE := Vector2(14,11)
const ENTRY := Vector3(0,0,4.0)
const EXIT := Vector3(0,0,4.95)
const NELSON := Vector3(-1.8,0,-3.62)
const LUISA := Vector3(4.65,0,-3.92)
const SERVICE := Vector3(-1.8,0,-1.35)
const LUISA_INTERACTION := Vector3(3.05,0,-2.15)
var station_points := {"service":Vector2(-1.8,-1.35),"nelson":Vector2(-1.8,-1.35),"luisa":Vector2(3.05,-2.15)}
var variant := 0

func _ready() -> void:
	name = "CuritibaCellarInterior"
	_shell()
	_wine_library()
	_tasting_counter()
	_financial_office()
	_display_islands()
	_greek_details()
	_lighting()
	anchor("Entry",ENTRY)
	anchor("Exit",EXIT)
	anchor("Nelson",NELSON)
	anchor("Luisa",LUISA)
	anchor("Service",SERVICE)
	anchor("LuisaInteraction",LUISA_INTERACTION)
	flush_batches()
	set_process(false)
	set_physics_process(false)

func _shell() -> void:
	box("OakFloor",Vector3(0,-.033,0),Vector3(14,.06,11),"745540","","shell_wood")
	for row in 22:
		for col in 7:
			var x := -6.01+col*2.0
			var z := -5.25+row*.5
			piece("box",Vector3(x,.002,z),Vector3(1.983,.008,.483),["71503b","7c5940","856044"][(row+col*2)%3],"shell_wood")
	# The light stone aisle remains unobstructed from the entrance to Nelson.
	box("StoneRunner",Vector3(.25,.01,.85),Vector3(2.8,.016,8.55),"c3b99f","","shell_stone")
	for x in [-1.175,1.675]: piece("box",Vector3(x,.021,.85),Vector3(.025,.008,8.55),"ad8c50","metal")
	box("BackWall",Vector3(0,1.6,-5.38),Vector3(14,3.2,.24),"c7bba4","BackWall","shell_stone")
	for side in [-1,1]:
		box("SideWall%d"%side,Vector3(side*6.88,1.6,0),Vector3(.24,3.2,11),"baaf98","SideWall%d"%side,"shell_stone")
		box("SouthWall%d"%side,Vector3(side*4.05,.22,5.38),Vector3(5.9,.44,.24),"684837","SouthWall%d"%side,"shell_wood")
		piece("box",Vector3(side*6.72,.13,0),Vector3(.07,.26,10.65),"402d26","shell_wood")
		piece("box",Vector3(side*6.72,2.98,0),Vector3(.08,.16,10.65),"624536","shell_wood")
		box("EntryJamb%d"%side,Vector3(side*1.065,.58,5.31),Vector3(.13,1.16,.20),"95764b","EntryJamb%d"%side,"shell_wood")
	box("RearCrown",Vector3(0,3.03,-5.20),Vector3(13.55,.20,.13),"513b2e","","shell_wood")
	box("EntranceMat",Vector3(0,.027,4.58),Vector3(1.86,.025,1.03),"532c3c","","shell_cloth")
	for side in [-1,1]: piece("box",Vector3(side*.88,.042,4.58),Vector3(.028,.006,.9),"b69b65","shell_cloth")

func _wine_library() -> void:
	# Four distinct selections use bottle/foil colors; country names stay in the
	# functional buying UI, never on decorative explanatory signs.
	var labels := ["eee5c4","e4d2a1","d6c3a9","e4dcc5"]
	var foils := ["274f70","487046","762f3a","9b573c"]
	for index in 4:
		var x := -5.35+index*2.65
		var id := "RearLibrary%d"%index
		box(id,Vector3(x,1.22,-5.17),Vector3(2.43,2.44,.13),"4c352b",id)
		box("LibraryInset",Vector3(x,1.27,-5.096),Vector3(2.19,2.12,.025),"292b28")
		for edge in [-1,1]:
			box("LibraryUpright",Vector3(x+edge*1.175,1.22,-4.87),Vector3(.08,2.44,.68),"705039",id)
		for level in 4:
			var y := .40+level*.49
			box("LibraryShelf",Vector3(x,y,-4.81),Vector3(2.27,.055,.76),"936c48",id)
			for item in 12:
				bottle(Vector3(x-1.0+item*.181,y+.034,-4.55),labels[index],"253a2a" if index%2 == 0 else "313524",foils[index])
			piece("box",Vector3(x,y+.415,-4.56),Vector3(2.13,.02,.025),"f0c68b","glow")
		for edge in [-1,1]: piece("box",Vector3(x+edge*1.105,1.25,-4.52),Vector3(.035,2.14,.032),"ae8c51","metal")
	# Wine cubbies on the left, a shorter display on the right leaving the
	# financial workspace open to the room and keeping the service path clear.
	for side in [-1,1]:
		for bay in (3 if side < 0 else 2):
			var z := -.95+bay*1.65
			var id := "SideRack%d_%d"%[side,bay]
			box(id,Vector3(side*6.67,1.05,z),Vector3(.14,2.1,1.54),"51382c",id)
			for edge in [-1,1]:
				box("SideRackUpright",Vector3(side*6.28,1.05,z+edge*.74),Vector3(.89,2.1,.06),"79543b",id)
			for level in 4:
				var y := .30+level*.46
				box("SideRackShelf",Vector3(side*6.27,y,z),Vector3(.88,.055,1.39),"9c744c",id)
				for item in 7:
					bottle(Vector3(side*5.97,y+.035,z-.56+item*.18),labels[(bay+2)%4],"2e3c29",foils[(bay+2)%4],Vector3(0,side*-PI*.5,0))
			box("RackCornice",Vector3(side*6.3,2.15,z),Vector3(.89,.12,1.53),"7c5638")

func _tasting_counter() -> void:
	var center := Vector3(-1.80,0,-2.47)
	box("TastingCounter",center+Vector3(0,.51,0),Vector3(5.25,1.02,.80),"543b2d","TastingCounter")
	box("TastingCounterTop",center+Vector3(0,1.075,0),Vector3(5.45,.13,1.03),"d6c8a8","TastingCounter","stone")
	for i in 27: piece("box",center+Vector3(-2.5+i*.19,.54,.409),Vector3(.035,.81,.035),"a17a50")
	piece("box",center+Vector3(0,.13,.435),Vector3(5.15,.05,.05),"a98950","metal")
	piece("box",center+Vector3(0,.935,.435),Vector3(5.15,.03,.035),"c0a26d","metal")
	# Tools, tasting flight, folded cloth, water jug and corkscrew.
	box("TastingBoard",center+Vector3(-.1,1.153,.05),Vector3(1.25,.032,.53),"8c603f")
	for i in 4:
		glass(center+Vector3(-.53+i*.29,1.176,.12),i<3)
		bottle(center+Vector3(-1.90+i*.27,1.143,-.12),["eee5c4","e4d2a1","d6c3a9","e4dcc5"][i],"2b3c2a",["274f70","487046","762f3a","9b573c"][i])
	box("FoldedLinen",center+Vector3(.93,1.157,.05),Vector3(.39,.039,.31),"e7ddc4","","cloth")
	piece("box",center+Vector3(1.32,1.159,.02),Vector3(.16,.03,.035),"303232","metal",Vector3(0,.5,0))
	piece("round",center+Vector3(1.40,1.155,.18),Vector3(.02,.07,.02),"ae9c72","metal",Vector3(0,0,PI*.5))
	piece("round",center+Vector3(1.76,1.28,-.13),Vector3(.15,.28,.15),"899b98","bottle")
	piece("cup",center+Vector3(1.76,1.44,-.13),Vector3(.15,.07,.15),"a3b2a9","bottle")
	box("CardTerminal",center+Vector3(2.10,1.21,.17),Vector3(.14,.13,.24),"303a37","","metal")
	box("TerminalScreen",center+Vector3(2.10,1.278,.12),Vector3(.106,.008,.11),"9aac8c","","glow")
	# Two stools occupy a side bay, leaving Nelson's customer position free.
	for x in [-4.65,-3.55]:
		var id := "TastingStool"+str(x)
		box(id,Vector3(x,.37,-.90),Vector3(.43,.74,.43),"473830",id)
		box("StoolLeather",Vector3(x,.76,-.90),Vector3(.49,.10,.51),"5b2c3c",id,"cloth")
		for side in [-1,1]: piece("box",Vector3(x+side*.22,.44,-.665),Vector3(.035,.04,.035),"a89570","metal")

func _financial_office() -> void:
	# Half-height screens keep Luisa visible and the office reachable from the
	# right aisle. The inhabited chair belongs to her native actor model.
	box("OfficeCredenza",Vector3(5.86,.40,-3.84),Vector3(.81,.8,1.09),"684933","OfficeCredenza")
	box("OfficeDesk",Vector3(4.65,.645,-2.94),Vector3(2.25,.25,1.0),"755139","OfficeDesk")
	box("OfficeDrawers",Vector3(5.48,.34,-2.94),Vector3(.49,.68,.91),"664732","OfficeDesk")
	box("OfficeDeskLeg",Vector3(3.59,.385,-2.94),Vector3(.10,.77,.93),"604633","OfficeDesk")
	box("OfficeDesktop",Vector3(4.65,.807,-2.94),Vector3(2.35,.075,1.06),"b39061","OfficeDesk")
	for row in 3:
		piece("box",Vector3(5.48,.14+row*.20,-3.402),Vector3(.40,.008,.01),"392c23")
		piece("box",Vector3(5.48,.18+row*.20,-3.415),Vector3(.11,.018,.025),"b69b69","metal")
	for side in [-1,1]: piece("box",Vector3(4.65+side*.99,.37,-2.412),Vector3(.032,.7,.019),"b99a65","metal")
	box("MonitorStand",Vector3(4.64,.87,-2.80),Vector3(.30,.035,.19),"3f4441","","metal")
	box("MonitorStem",Vector3(4.64,1.01,-2.80),Vector3(.055,.27,.065),"404641","","metal")
	box("FinancialMonitor",Vector3(4.64,1.22,-2.78),Vector3(.68,.40,.055),"293735","","metal")
	box("SpreadsheetScreen",Vector3(4.64,1.22,-2.813),Vector3(.62,.34,.010),"a9c6ba","","glow")
	# A visible spreadsheet has cells and bars, no decorative exposition text.
	for row in 6:
		piece("box",Vector3(4.64,1.075+row*.053,-2.820),Vector3(.58,.003,.003),"6b9485","paper")
	for col in 5:
		piece("box",Vector3(4.37+col*.134,1.22,-2.821),Vector3(.003,.30,.003),"6b9485","paper")
	for row in 4: piece("box",Vector3(4.50+row*.065,1.11+row*.053,-2.824),Vector3(.11+row*.025,.024,.004),"365e55","paper")
	box("Keyboard",Vector3(4.59,.864,-3.38),Vector3(.48,.025,.14),"e0dccc","","metal")
	for row in 3:
		for col in 12: piece("box",Vector3(4.39+col*.036,.882,-3.423+row*.043),Vector3(.026,.009,.030),"595f56","paper")
	piece("leaf",Vector3(4.98,.877,-3.28),Vector3(.065,.036,.095),"ccc9bc","metal")
	box("MousePad",Vector3(5.00,.853,-3.25),Vector3(.23,.009,.25),"57313b","","cloth")
	box("Ledger",Vector3(5.40,.884,-2.87),Vector3(.34,.064,.45),"473d33")
	box("LedgerPages",Vector3(5.40,.890,-2.865),Vector3(.327,.044,.43),"e9ddbc","","paper")
	piece("round",Vector3(5.40,.933,-2.87),Vector3(.012,.30,.012),"2d3534","metal",Vector3(PI*.5,0,.3))
	for i in 3:
		box("InvoiceStack",Vector3(5.87,.83+i*.035,-3.96),Vector3(.33,.025,.39),"e1d9bf","","paper")
	box("Printer",Vector3(5.88,.90,-3.62),Vector3(.46,.20,.32),"777e74","","metal")
	box("PrinterPaper",Vector3(5.88,.98,-3.45),Vector3(.29,.012,.26),"e5dfcb","","paper")
	box("OfficeRug",Vector3(4.8,.017,-3.85),Vector3(2.15,.025,1.82),"5b4241","","cloth")

func _display_islands() -> void:
	for side in [-1,1]:
		var x: float = side*3.7
		var id := "WineIsland%d"%side
		box(id,Vector3(x,.46,2.07),Vector3(1.65,.92,1.85),"5a3f30",id)
		box("IslandTop",Vector3(x,.97,2.07),Vector3(1.78,.10,1.98),"b29668",id)
		for side_z in [-1,1]:
			piece("box",Vector3(x,.52,2.07+side_z*.938),Vector3(1.46,.62,.022),"3a3029")
			for line in 3: piece("box",Vector3(x,.28+line*.235,2.07+side_z*.96),Vector3(1.45,.035,.05),"987348")
		for row in 3:
			for col in 5:
				bottle(Vector3(x-.56+col*.28,1.026,1.57+row*.47),"e0d3ad","283c2b","6c2c3b" if side<0 else "947743")
		# A wooden gift box and linen wrapping make the premium offer readable.
		box("GiftBox",Vector3(x+.46,1.05,2.75),Vector3(.42,.08,.41),"c6aa7a")
		piece("box",Vector3(x+.46,1.092,2.75),Vector3(.035,.009,.41),"732e40","cloth")
	box("WaterSideboard",Vector3(3.98,.43,.10),Vector3(1.45,.86,.64),"705039","WaterSideboard")
	box("StoneSideboardTop",Vector3(3.98,.90,.10),Vector3(1.53,.09,.72),"c6b899","WaterSideboard","stone")
	for x in [3.55,3.79,4.03]: glass(Vector3(x,.951,.05))
	piece("round",Vector3(4.39,1.09,.07),Vector3(.16,.29,.16),"91a79d","bottle")
	_planter(Vector3(-5.93,0,-3.72),"RearOlive")
	_planter(Vector3(2.2,0,4.44),"EntranceOlive")

func _planter(at: Vector3, id: String) -> void:
	box(id,at+Vector3(0,.27,0),Vector3(.52,.54,.52),"b39a72",id,"stone")
	piece("round",at+Vector3(0,.87,0),Vector3(.07,.98,.07),"7c6143")
	for i in 10:
		var angle := i*2.4
		piece("leaf",at+Vector3(sin(angle)*.22,1.14+sin(i*1.7)*.16,cos(angle)*.18),Vector3(.34,.24,.30),"5c6b42","cloth")

func _greek_details() -> void:
	# Aegean architecture and a small classical amphora express Nelson's
	# interest in Greece through objects, without wall paragraphs or slogans.
	box("AegeanFrame",Vector3(-1.35,2.76,-5.21),Vector3(2.9,.69,.065),"a78a57","","metal")
	box("AegeanSky",Vector3(-1.35,2.76,-5.167),Vector3(2.78,.58,.023),"708e9a","","paper")
	box("AegeanSea",Vector3(-1.35,2.57,-5.146),Vector3(2.78,.18,.01),"335d78","","paper")
	for i in 8:
		piece("box",Vector3(-2.49+i*.31,2.71+sin(i*.9)*.06,-5.129),Vector3(.27,.23+i%3*.035,.016),"e6dfcb","paper")
		piece("box",Vector3(-2.49+i*.31,2.71,-5.117),Vector3(.045,.09,.009),"4c7693","paper")
	for side in [-1,1]:
		var x: float = side*5.85
		box("AmphoraPedestal",Vector3(x,.56,4.2),Vector3(.48,1.12,.5),"b5a082","AmphoraPedestal%d"%side,"stone")
		piece("cup",Vector3(x,1.32,4.2),Vector3(.29,.4,.29),"b2754c","stone")
		piece("round",Vector3(x,1.57,4.2),Vector3(.13,.15,.13),"b2754c","stone")
		piece("round",Vector3(x,1.65,4.2),Vector3(.17,.035,.17),"6b4836","stone")
		for handle_side in [-1,1]:
			piece("leaf",Vector3(x+handle_side*.16,1.46,4.2),Vector3(.075,.19,.065),"9b603e","stone")

func _lighting() -> void:
	# The office pendant is offset from Luisa's head in the fixed gameplay
	# camera, so the occupied workstation stays readable while she types.
	for at: Vector3 in [Vector3(-3.6,0,-1.2),Vector3(.1,0,-1.2),Vector3(3.45,0,-2.5)]:
		piece("round",at+Vector3(0,2.86,0),Vector3(.025,.55,.025),"45413a","metal")
		piece("cup",at+Vector3(0,2.55,0),Vector3(.56,.27,.56),"ac8650","metal")
		piece("round",at+Vector3(0,2.416,0),Vector3(.42,.018,.42),"f7d4a0","glow")
	# Broad stable sources, no animated flicker or individual bottle lights.
	for data in [[Vector3(-2.7,2.72,-1.0),8.0,.65],[Vector3(3.45,2.75,-2.5),5.5,.48]]:
		var light := OmniLight3D.new()
		light.name = "CellarPendantLight"
		light.position = data[0]
		light.omni_range = data[1]
		light.light_energy = data[2]
		light.light_color = Color("ffdfaf")
		light.shadow_enabled = false
		add_child(light)

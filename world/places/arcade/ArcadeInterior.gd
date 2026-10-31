extends "res://world/places/arcade/ArcadeGeometry.gd"
const SHELL_FINISH := preload("res://world/mountain_detail/MountainInteriorFinish.gd")
const SHELL_RECIPES := {
	"stone": ["54505a", "393a48", "56515a", "42383f"],
	"cloth": ["44374e", "745468", "56697d", "977959", "262730", "b78a55"],
	"wood": ["49392f"],
	"paint": ["201f2b"],
}
const SHELL_KINDS := {"stone": "cast", "cloth": "fabric", "wood": "wood", "paint": "plaster"}

static func painted_enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_ARCADE_INTERIOR") != "0"

static func prewarm_materials() -> Array[Material]:
	var result: Array[Material] = []
	if not painted_enabled(): return result
	for kind in SHELL_RECIPES:
		for color in SHELL_RECIPES[kind]:
			result.append(SHELL_FINISH.material(SHELL_KINDS[kind], Color(color), .9))
	return result

func material(color: String, kind := "paint") -> StandardMaterial3D:
	if kind.begins_with("shell_"):
		var original := kind.trim_prefix("shell_")
		if painted_enabled():
			return SHELL_FINISH.material(SHELL_KINDS[original], Color(color), .9)
		return super.material(color, original)
	return super.material(color, kind)

## Native 12 x 10 m room. Four different cabinets plus two occupied stations.
var variant := 0
var cabinet_bounds: Dictionary = {}
var station_points := {
	"arcade_pinball":Vector2(-4.25,-1.85),"arcade_blocks":Vector2(-1.45,-2.1),
	"arcade_racer":Vector2(1.4,-1.28),"arcade_fighter":Vector2(4.05,-2.1),
}

func _ready() -> void:
	name = "FagulhaInterior"
	_shell()
	_pinball(Vector3(-4.25,0,-3.65))
	_upright("BlocksCabinet",Vector3(-1.45,0,-3.85),0.0,"43b6ad",0)
	_racer(Vector3(1.4,0,-3.85))
	_upright("FighterCabinet",Vector3(4.05,0,-3.85),0.0,"cf5868",2,1.3)
	_upright("LiaCabinet",Vector3(5.15,0,.35),-PI*.5,"be934e",0)
	_upright("IvoCabinet",Vector3(5.15,0,2.9),-PI*.5,"778bc1",2)
	_lounge()
	_wall_details()
	_wall_lighting()
	flush()
	set_process(false)
	set_physics_process(false)

func _wall_lighting() -> void:
	# Duas luminárias fixas de parede iluminam o corredor e os rigs reais dos atores à noite.
	# O NativePlace é dono da visibilidade/tempo de vida delas; as telas continuam arte emissiva.
	for side in [-1,1]:
		var x: float = side*5.56
		box("WallLampBack%d"%side,Vector3(side*5.69,2.74,0),Vector3(.10,.40,1.04),"37343e","","metal")
		box("WallLampArm%d"%side,Vector3(side*5.45,2.85,0),Vector3(.45,.07,.11),"aa885a","","metal")
		box("WallLampDiffuser%d"%side,Vector3(x,2.69,0),Vector3(.19,.24,.82),"dfc8a8" if side<0 else "bcd8df","","screen")
		var light := OmniLight3D.new()
		light.name = "ArcadeWallLightWest" if side<0 else "ArcadeWallLightEast"
		light.position = Vector3(side*5.2,2.7,0)
		light.light_color = Color("efdfc8") if side<0 else Color("d6e5ed")
		light.light_energy = 1.3
		light.light_specular = .35
		light.omni_range = 10.0
		light.omni_attenuation = .7
		light.shadow_enabled = false
		add_child(light)

func _shell() -> void:
	box("FloorSurface",Vector3(0,-.026,0),Vector3(12,.05,10),"54505a","","shell_stone")
	box("Carpet",Vector3(0,.012,-.45),Vector3(9.70,.021,7.4),"44374e","","shell_cloth")
	# Fitas curtas repetidas dão ao carpete identidade de fliperama sem placas.
	for row in 10:
		for col in 12:
			var x := -4.45+col*.8
			var z := -3.7+row*.73
			var color: String = ["745468","56697d","977959"][(row+col)%3]
			detail(Vector3(x,.025,z),Vector3(.18,.006,.035),color,"shell_cloth",Vector3(0,.45 if col%2==0 else -.45,0))
			detail(Vector3(x+.11,.025,z+.12),Vector3(.045,.006,.10),color,"shell_cloth")
	box("BackWall",Vector3(0,1.65,-4.88),Vector3(12,3.3,.24),"393a48","BackWall","shell_stone")
	for side in [-1,1]:
		box("SideWall%d"%side,Vector3(side*5.88,1.65,0),Vector3(.24,3.3,10),"56515a","SideWall%d"%side,"shell_stone")
		box("SouthWall%d"%side,Vector3(side*3.54,1.65,4.88),Vector3(4.92,3.3,.24),"42383f","SouthWall%d"%side,"shell_stone")
		box("EntryJamb%d"%side,Vector3(side*1.04,.59,4.81),Vector3(.14,1.18,.23),"ad8c59","EntryJamb%d"%side,"metal")
		detail(Vector3(side*5.72,.55,0),Vector3(.04,1.1,9.48),"49392f","shell_wood")
		detail(Vector3(side*5.68,1.14,0),Vector3(.06,.075,9.48),"a48354","metal")
		detail(Vector3(side*5.70,2.98,0),Vector3(.06,.035,9.48),"4eafb0","screen")
	box("RearWainscot",Vector3(0,.58,-4.72),Vector3(11.5,1.16,.035),"49392f","","shell_wood")
	box("RearRail",Vector3(0,1.18,-4.68),Vector3(11.5,.065,.06),"ab8753","","metal")
	box("RearCornice",Vector3(0,3.03,-4.70),Vector3(11.5,.12,.12),"201f2b","","shell_paint")
	detail(Vector3(0,2.96,-4.62),Vector3(11.3,.034,.035),"b594c5","screen")
	box("EntranceMat",Vector3(0,.021,4.20),Vector3(1.86,.025,1.1),"262730","","shell_cloth")
	for side in [-1,1]: detail(Vector3(side*.86,.036,4.20),Vector3(.025,.006,.95),"b78a55","shell_cloth")

func _upright(id: String, at: Vector3, yaw: float, accent: String, screen_kind: int, width := 1.05) -> void:
	var basis := Basis(Vector3.UP,yaw)
	_part(id+"Body",at,basis,Vector3(0,.48,0),Vector3(width,.96,.80),"252631",id)
	_part(id+"Head",at,basis,Vector3(0,1.44,-.13),Vector3(width,1.10,.63),"24232d",id)
	_part(id+"ControlPanel",at,basis,Vector3(0,.995,.36),Vector3(width+.06,.12,.37),accent,id)
	_part(id+"Marquee",at,basis,Vector3(0,1.975,-.05),Vector3(width+.07,.23,.78),accent,id)
	_part(id+"ScreenFrame",at,basis,Vector3(0,1.48,.205),Vector3(width-.16,.76,.045),"10121c")
	_part(id+"Screen",at,basis,Vector3(0,1.49,.235),Vector3(width-.29,.60,.015),"17293a","","screen")
	# Faixas laterais, porta de moedas rebaixada e ventilação levam o mesmo acabamento.
	for side in [-1,1]:
		_bit(at,basis,Vector3(side*(width*.5+.004),1.01,-.05),Vector3(.018,1.89,.55),accent)
		_bit(at,basis,Vector3(side*(width*.5+.015),1.16,.24),Vector3(.012,1.15,.048),"d8bc85","metal")
		_bit(at,basis,Vector3(side*width*.27,1.983,.349),Vector3(width*.3,.034,.023),"eee0b3","screen")
	_part(id+"CoinDoor",at,basis,Vector3(0,.43,.408),Vector3(.30,.36,.023),"3d424b","","metal")
	_bit(at,basis,Vector3(-.065,.51,.426),Vector3(.085,.025,.01),"1c2028")
	_bit(at,basis,Vector3(.09,.35,.427),Vector3(.055,.025,.015),"bc9754","metal")
	for row in 4: _bit(at,basis,Vector3(0,.145+row*.039,.414),Vector3(.43,.012,.01),"121620")
	_bit(at,basis,Vector3(-width*.23,1.105,.34),Vector3(.036,.13,.036),"c6c3b4","metal",true)
	_bit(at,basis,Vector3(-width*.23,1.173,.34),Vector3(.105,.055,.105),accent,"paint",true)
	for button in 3:
		_bit(at,basis,Vector3(width*.06+button*.09,1.068,.39-(button%2)*.09),Vector3(.059,.025,.059),["e8c079","d86c72","64b9a7"][button],"paint",true)
	if screen_kind == 0: _blocks_picture(at,basis,width)
	else: _fighter_picture(at,basis,width)
	cabinet_bounds[id] = _cabinet_bound(at,basis,Vector3(width+.08,2.1,1.1))

func _pinball(at: Vector3) -> void:
	var id := "PinballCabinet"
	box(id+"Body",at+Vector3(0,.80,0),Vector3(1.12,.52,1.72),"77609a",id)
	box(id+"Head",at+Vector3(0,1.59,-.71),Vector3(1.18,1.12,.30),"30293d",id)
	box(id+"BackGlass",at+Vector3(0,1.63,-.548),Vector3(.93,.66,.024),"334166","","screen")
	box(id+"Board",at+Vector3(0,1.075,.02),Vector3(.94,.038,1.46),"275d65","","screen")
	for side in [-1,1]:
		box(id+"Rail",at+Vector3(side*.535,1.10,.03),Vector3(.05,.11,1.58),"c2a780",id,"metal")
		for z in [-.65,.65]: box(id+"Leg",at+Vector3(side*.45,.31,z),Vector3(.06,.62,.07),"c3bcb0",id,"metal")
		detail(at+Vector3(side*.57,.97,.53),Vector3(.035,.047,.052),"d2c39b")
		detail(at+Vector3(side*.40,1.103,.04),Vector3(.025,.019,1.28),"e5c384","metal")
		detail(at+Vector3(side*.20,1.135,.57),Vector3(.29,.033,.06),"e39663","paint",Vector3(0,side*.35,0))
	for p in [Vector2(-.20,-.36),Vector2(.19,-.26),Vector2(-.03,.02)]:
		detail(at+Vector3(p.x,1.145,p.y),Vector3(.20,.082,.20),"e8bd66","paint",Vector3.ZERO,true)
		detail(at+Vector3(p.x,1.191,p.y),Vector3(.13,.015,.13),"e0618d","screen",Vector3.ZERO,true)
	for index in 5:
		detail(at+Vector3(-.32+index*.16,1.12,-.55),Vector3(.056,.035,.045),"a2ccbd","screen")
		detail(at+Vector3(-.36+index*.18,1.62+sin(index)*.15,-.528),Vector3(.10,.08,.017),"ebc48a","screen")
	detail(at+Vector3(.14,1.139,.31),Vector3(.055,.053,.055),"dae0d9","metal",Vector3.ZERO,true)
	box(id+"Apron",at+Vector3(0,.79,.868),Vector3(.89,.33,.025),"3e344f")
	detail(at+Vector3(.35,.84,.894),Vector3(.065,.065,.04),"e0c686","metal",Vector3(PI*.5,0,0),true)
	cabinet_bounds[id] = AABB(at+Vector3(-.59,0,-.88),Vector3(1.18,2.15,1.78))

func _racer(at: Vector3) -> void:
	var id := "RacerCabinet"
	box(id+"Base",at+Vector3(0,.20,.49),Vector3(1.22,.40,2.15),"d69b4c",id,"metal")
	box(id+"Head",at+Vector3(0,1.33,-.32),Vector3(1.23,1.80,.58),"272935",id)
	box(id+"ScreenFrame",at+Vector3(0,1.59,-.014),Vector3(1.09,.76,.06),"0e1724")
	box(id+"Screen",at+Vector3(0,1.60,.023),Vector3(.91,.57,.018),"367777","","screen")
	box(id+"Dash",at+Vector3(0,1.08,.08),Vector3(1.25,.17,.61),"a97039",id)
	box(id+"Seat",at+Vector3(0,.57,1.00),Vector3(.66,.21,.70),"b8654a",id,"cloth")
	box(id+"SeatBack",at+Vector3(0,.91,1.31),Vector3(.72,.89,.16),"c27353",id,"cloth")
	box(id+"SeatInset",at+Vector3(0,.94,1.405),Vector3(.48,.57,.024),"915137")
	# A twelve-segment wheel avoids a viewport or high-poly imported asset.
	for index in 12:
		var angle := TAU*index/12.0
		var next := TAU*(index+1)/12.0
		var first := Vector3(sin(angle)*.215,cos(angle)*.215,0)
		var last := Vector3(sin(next)*.215,cos(next)*.215,0)
		detail(at+Vector3(0,1.26,.40)+(first+last)*.5,Vector3(.035,(last-first).length()+.012,.042),"302f38","paint",Vector3(0,0,-(angle+next)*.5))
	detail(at+Vector3(0,1.26,.39),Vector3(.35,.035,.048),"b6afa3","metal")
	detail(at+Vector3(0,1.26,.42),Vector3(.10,.10,.04),"463e3b")
	# The attract image is a road converging beneath a warm horizon.
	for band in 9:
		var y := 1.36+band*.043
		var width := .57-band*.047
		detail(at+Vector3(0,y,.037),Vector3(width,.044,.011),"2a3145","screen")
		if band%2==0: detail(at+Vector3(0,y,.046),Vector3(.018,.026,.012),"eacb91","screen")
	detail(at+Vector3(.21,1.77,.04),Vector3(.10,.07,.018),"e8b864","screen")
	detail(at+Vector3(-.12,1.44,.053),Vector3(.081,.12,.02),"ec875f","screen")
	for side in [-1,1]:
		detail(at+Vector3(side*.637,1.55,-.30),Vector3(.023,.94,.32),"daa754")
		detail(at+Vector3(side*.52,.414,.67),Vector3(.035,.014,1.49),"efe0af","metal")
	cabinet_bounds[id] = AABB(at+Vector3(-.64,0,-.61),Vector3(1.28,2.23,2.15))

func _lounge() -> void:
	# All seats, side table and token exchanger reserve their whole footprints.
	box("LoungeBench",Vector3(-5.14,.35,.50),Vector3(.83,.7,2.5),"5c675f","LoungeBench","cloth")
	box("LoungeBack",Vector3(-5.55,.68,.50),Vector3(.17,1.18,2.6),"45494a","LoungeBench","cloth")
	for z in [-.30,.50,1.30]:
		box("BenchCushion",Vector3(-5.13,.76,z),Vector3(.84,.15,.76),"a67757","LoungeBench","cloth")
	box("LowTable",Vector3(-4.69,.32,2.30),Vector3(1.14,.64,.62),"614333","LowTable","wood")
	box("TableTop",Vector3(-4.69,.67,2.30),Vector3(1.22,.10,.70),"bc9864","LowTable","wood")
	for i in 3: detail(Vector3(-5.03+i*.27,.735,2.3),Vector3(.19,.018,.32),["715370","587f7e","b39154"][i])
	box("TokenExchanger",Vector3(-5.21,1.0,-1.76),Vector3(.88,2,.72),"b89555","TokenExchanger","metal")
	box("ExchangerFace",Vector3(-5.21,1.16,-1.388),Vector3(.65,.94,.026),"2a3443")
	box("ExchangerScreen",Vector3(-5.21,1.46,-1.368),Vector3(.42,.23,.014),"568e8b","","screen")
	box("CoinBowl",Vector3(-5.21,.86,-1.357),Vector3(.34,.09,.06),"121b29")
	detail(Vector3(-5.09,1.18,-1.354),Vector3(.035,.18,.018),"d4bd83","metal")

func _wall_details() -> void:
	# Estrelas abstratas cromadas e arte de jogos emoldurada, sem sinalização descritiva.
	for x in [-3.03,0,3.03]:
		box("RearFrame",Vector3(x,2.65,-4.70),Vector3(1.55,.62,.07),"9a7652","","metal")
		box("RearPrint",Vector3(x,2.65,-4.65),Vector3(1.41,.49,.028),"243d47")
		for side in [-1,1]:
			detail(Vector3(x+side*.34,2.65,-4.625),Vector3(.09,.31,.016),"ab92b9","screen",Vector3(0,0,side*.48))
			detail(Vector3(x+side*.34,2.65,-4.613),Vector3(.25,.058,.016),"e0bc83","screen")
	# As caixas de som visíveis não têm luzes nem processadores próprios.
	for side in [-1,1]:
		box("RearSpeaker",Vector3(side*5.44,2.64,-4.56),Vector3(.48,.67,.36),"262732")
		for y in [2.48,2.76]: detail(Vector3(side*5.44,y,-4.365),Vector3(.21,.035,.21),"535261","paint",Vector3(PI*.5,0,0),true)

func _part(label: String, at: Vector3, basis: Basis, offset: Vector3, size: Vector3, color: String, solid := "", kind := "paint") -> void:
	box(label,at+basis*offset,size,color,solid,kind,basis.get_euler().y)

func _bit(at: Vector3, basis: Basis, offset: Vector3, size: Vector3, color: String, kind := "paint", round_shape := false) -> void:
	detail(at+basis*offset,size,color,kind,basis.get_euler(),round_shape)

func _blocks_picture(at: Vector3, basis: Basis, width: float) -> void:
	for row in 4:
		for col in 6:
			if row==3 and col in [0,3,4]: continue
			if row==2 and col==3: continue
			_bit(at,basis,Vector3(-width*.28+col*.093,1.235+row*.074,.249),Vector3(.078,.062,.008),["c9a96a","65b7ac","ac85ad"][(row+floori(col*.5))%3],"screen")
	for cell in [Vector2(0,0),Vector2(1,0),Vector2(2,0),Vector2(1,1)]:
		_bit(at,basis,Vector3(-.14+cell.x*.091,1.65+cell.y*.071,.249),Vector3(.078,.062,.008),"e2bf76","screen")

func _fighter_picture(at: Vector3, basis: Basis, width: float) -> void:
	_bit(at,basis,Vector3(0,1.32,.249),Vector3(width-.31,.075,.008),"53536b","screen")
	for side in [-1,1]:
		var color := "e4b073" if side<0 else "80b8ba"
		_bit(at,basis,Vector3(side*.20,1.60,.253),Vector3(.079,.071,.009),color,"screen")
		_bit(at,basis,Vector3(side*.20,1.51,.253),Vector3(.103,.12,.009),color,"screen")
		_bit(at,basis,Vector3(side*.17,1.42,.253),Vector3(.12,.06,.009),color,"screen")
		_bit(at,basis,Vector3(side*.13,1.54,.253),Vector3(.13,.04,.009),color,"screen")
		_bit(at,basis,Vector3(side*(width*.20),1.74,.252),Vector3(width*.32,.025,.009),"bd6780" if side<0 else "7cb8a4","screen")

func _cabinet_bound(at: Vector3, basis: Basis, size: Vector3) -> AABB:
	return Transform3D(basis,at)*AABB(Vector3(-size.x*.5,0,-size.z*.5),size)

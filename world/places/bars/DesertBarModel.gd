extends "res://world/places/arcade/ArcadeGeometry.gd"
## Sede: western counter and separate eastern games bay, native human scale.
var variant := 0
var station_points := {"bar_pool":Vector2(1,1.4),"bar_darts":Vector2(5.3,-3.0)}
const DECOR := preload("res://world/places/bars/BarDecor.gd")
## Com as pinturas, tábuas do piso, almofadas do balcão e anéis do alvo são a imagem.
var painted := false

func _ready() -> void:
	name = "SedeInterior"
	painted = DECOR.available("sede")
	_shell()
	_counter()
	_pool()
	_darts()
	_tables()
	_music_corner()
	_lighting()
	if painted: _paintings()
	flush()
	set_process(false)
	set_physics_process(false)

func _shell() -> void:
	box("FloorSurface",Vector3(0,-.04,0),Vector3(16,.08,12),"795b43","","wood")
	for plank in (0 if painted else 32):
		detail(Vector3(-7.75+plank*.5,.004,0),Vector3(.016,.008,11.72),"493d31","wood")
	box("BackWall",Vector3(0,1.65,-5.88),Vector3(16,3.3,.24),"b59b77","BackWall","stone")
	for side in [-1,1]:
		box("SideWall%d"%side,Vector3(side*7.88,1.65,0),Vector3(.24,3.3,12),"ac906e","SideWall%d"%side,"stone")
		box("SouthWall%d"%side,Vector3(side*4.5,1.65,5.88),Vector3(6.76,3.3,.24),"a58a69","SouthWall%d"%side,"stone")
		box("FrontJamb%d"%side,Vector3(side*1.12,1.35,5.8),Vector3(.13,2.7,.23),"53402f","FrontJamb%d"%side,"wood")
		detail(Vector3(side*7.72,.55,0),Vector3(.055,1.1,11.48),"654a34","wood")
		detail(Vector3(side*7.67,1.15,0),Vector3(.08,.09,11.48),"9c774a","wood")
	for x in [-7.6,-2.5,2.5,7.6]:
		box("RearTimber",Vector3(x,1.6,-5.68),Vector3(.18,3.2,.18),"594430","RearTimber","wood")
	box("BackBeam",Vector3(0,3.07,-5.61),Vector3(15.5,.25,.22),"594430","","wood")
	detail(Vector3(0,.018,4.8),Vector3(2.0,.027,1.3),"43382c","cloth")

func _counter() -> void:
	box("CounterBody",Vector3(-5.6,.52,-1.5),Vector3(1.18,1.04,5),"60432e","Counter","wood")
	box("CounterTop",Vector3(-5.6,1.08,-1.5),Vector3(1.40,.12,5.16),"b08a54","Counter","wood")
	for z in ([] if painted else [-3.4,-2.4,-1.4,-.4,.6]):
		detail(Vector3(-4.986,.55,z),Vector3(.027,.70,.77),"765334","wood")
		detail(Vector3(-4.99,.96,z),Vector3(.031,.045,.84),"ad8d52","metal")
	box("RearBottleShelf",Vector3(-7.48,1.22,-1.5),Vector3(.45,2.44,4.65),"4f3a2d","BottleShelf","wood")
	for shelf in 3:
		var y := .73+shelf*.62
		detail(Vector3(-7.2,y,-1.5),Vector3(.64,.07,4.66),"aa8353","wood")
		for i in 13: _bottle(Vector3(-7.14,y+.04,-3.58+i*.34),i)
	for z in [-2.6,-.9,.3]:
		_bottle(Vector3(-5.45,1.145,z),int(z*10))
		detail(Vector3(-5.15,1.22,z+.17),Vector3(.11,.15,.11),"bc9350","paint",Vector3.ZERO,true)
	box("CounterTill",Vector3(-5.6,1.29,-3.5),Vector3(.40,.28,.42),"383933","Counter","metal")

func _bottle(at: Vector3, index: int) -> void:
	var color: String = ["385444","714a2e","4f6346"][posmod(index,3)]
	detail(at+Vector3(0,.13,0),Vector3(.092,.26,.092),color,"paint",Vector3.ZERO,true)
	detail(at+Vector3(0,.29,0),Vector3(.043,.12,.043),color,"paint",Vector3.ZERO,true)
	detail(at+Vector3(.05,.12,0),Vector3(.007,.09,.071),"d2ba7b","cloth")

func _pool() -> void:
	var at := Vector3(1,0,-.5)
	box("PoolBody",at+Vector3(0,.49,0),Vector3(3.15,.98,1.76),"4e3629","PoolTable","wood")
	box("PoolFelt",at+Vector3(0,1.004,0),Vector3(2.82,.045,1.42),"496a51","PoolTable","cloth")
	for side in [-1,1]:
		box("PoolRailLong",at+Vector3(0,1.04,side*.80),Vector3(3.28,.14,.20),"b58a52","PoolTable","wood")
		box("PoolRailEnd",at+Vector3(side*1.54,1.04,0),Vector3(.20,.14,1.80),"b58a52","PoolTable","wood")
		for z in [-.71,.71]:
			detail(at+Vector3(side*1.42,1.13,z),Vector3(.17,.022,.17),"171d19","paint",Vector3.ZERO,true)
			detail(at+Vector3(side*1.10,.16,z*.82),Vector3(.23,.32,.23),"352d27","wood")
		detail(at+Vector3(0,1.13,side*.72),Vector3(.17,.022,.17),"171d19","paint",Vector3.ZERO,true)
	for i in 8:
		var ball := MeshInstance3D.new()
		ball.name = "PoolBall%d"%i
		var sphere := SphereMesh.new()
		sphere.radius=.034
		sphere.height=.068
		sphere.radial_segments=8
		sphere.rings=4
		ball.mesh=sphere
		ball.material_override=material(["ede7d5","d4ac46","a95640","3a526d","232628","8d644b","75607d","d8c9ad"][i])
		ball.position=at+Vector3(-.9+i*.23,1.062,sin(i*1.7)*.43)
		add_child(ball)
	detail(at+Vector3(.4,1.15,.88),Vector3(1.45,.022,.022),"ccb07a","wood",Vector3(0,.18,0))
	box("CueRack",Vector3(3.1,1.1,-5.57),Vector3(1.0,2.2,.28),"61482e","CueRack","wood")
	for i in 4: detail(Vector3(2.78+i*.21,1.42,-5.39),Vector3(.026,1.43,.026),"c9ae77","wood")

func _darts() -> void:
	box("DartBacking",Vector3(5.3,1.73,-5.68),Vector3(1.46,1.5,.10),"4b3d30","DartBacking","wood")
	for ring in ([] if painted else [[.60,"b6a374"],[.54,"292f2d"],[.46,"b0a17d"],[.31,"3e4940"],[.075,"9b4438"],[.035,"5e8769"]]):
		_dart_detail(Vector3(5.3,1.73,-5.56-float(ring[0])*.02),Vector3(ring[0],.016,ring[0]),ring[1],"cloth",Vector3(PI*.5,0,0),true)
	for i in (0 if painted else 20):
		var angle := TAU*i/20.0
		_dart_detail(Vector3(5.3+sin(angle)*.21,1.73+cos(angle)*.21,-5.542),Vector3(.012,.27,.012),"c3b386","metal",Vector3(0,0,-angle))
	# A regulation throw line is paint, with the lane kept free of solids.
	detail(Vector3(5.3,.014,-3.15),Vector3(1.3,.012,.06),"d2b573","paint")

func _tables() -> void:
	var points := [Vector3(-4.9,0,3),Vector3(5.4,0,3.5)]
	for index in points.size():
		var at: Vector3=points[index]
		var id := "PubTable%d"%index
		box(id,at+Vector3(0,.41,0),Vector3(1.45,.82,1.02),"63472f",id,"wood")
		box(id+"Top",at+Vector3(0,.85,0),Vector3(1.58,.10,1.15),"ac8450",id,"wood")
		_bottle(at+Vector3(-.3,.91,.1),0)
		_bottle(at+Vector3(.32,.91,-.15),1)
		detail(at+Vector3(.25,.99,.22),Vector3(.12,.16,.12),"b98d4d","paint",Vector3.ZERO,true)
	# Bench is away from the standing drinkers and entrance corridor.
	box("EastBench",Vector3(7,.37,3.5),Vector3(.78,.74,2.4),"75533b","EastBench","wood")
	box("EastBenchBack",Vector3(7.4,.86,3.5),Vector3(.12,1.25,2.4),"694733","EastBench","wood")

func _music_corner() -> void:
	box("TurntableCabinet",Vector3(-1.7,.62,-4.9),Vector3(1.5,1.24,.72),"5b4630","MusicCabinet","wood")
	box("RadioHead",Vector3(-1.7,1.5,-4.9),Vector3(1.30,.5,.65),"9f8054","MusicCabinet","wood")
	for side in [-1,1]:
		for i in 6: detail(Vector3(-1.7+side*.40,1.31+i*.055,-4.558),Vector3(.31,.016,.012),"342c24")
	detail(Vector3(-1.7,1.54,-4.556),Vector3(.24,.08,.014),"b4c4a0","screen")
	for x in [-2.15,-1.25]: detail(Vector3(x,1.44,-4.54),Vector3(.07,.025,.07),"bfa171","metal",Vector3(PI*.5,0,0),true)

func _lighting() -> void:
	for at in [Vector3(-4.6,2.8,-1.5),Vector3(1,2.8,-.5),Vector3(6.6,2.8,-4.8)]:
		detail(at+Vector3(0,.2,0),Vector3(.035,.6,.035),"514634","metal")
		detail(at,Vector3(.55,.12,.55),"96704a","metal",Vector3.ZERO,true)
		detail(at-Vector3(0,.07,0),Vector3(.25,.06,.25),"e3c990","screen",Vector3.ZERO,true)
		var light := OmniLight3D.new()
		light.position=at-Vector3(0,.25,0)
		light.light_color=Color("f0d5ab")
		light.light_energy=1.2
		light.light_specular=.25
		light.omni_range=8.0
		light.omni_attenuation=.7
		light.shadow_enabled=false
		add_child(light)

func _paintings() -> void:
	DECOR.shell(self,"sede",1.12)
	DECOR.panel(self,"sede_counter",Vector3(-4.998,.52,-1.5),Vector2(5,1.04),PI*.5,Vector2(2,1))
	DECOR.panel(self,"sede_dartboard",Vector3(5.3,1.73,-5.624),Vector2(.46,.46))
	DECOR.flat(self,"sede_felt",Vector3(1,1.029,-.5),Vector2(2.82,1.42),Vector2(2.82,1.42))
	# Fundo: segunda estante entre as vigas atrás do balcão, neon sobre o rádio e os quadros
	# nos vãos entre o rádio, as vigas, o porta-tacos e o alvo.
	DECOR.panel(self,"sede_shelf",Vector3(-5.05,1.22,-5.745),Vector2(4.65,2.44))
	DECOR.panel(self,"sede_neon",Vector3(-1.7,2.55,-5.745),Vector2(1.4,.6))
	DECOR.panel(self,"sede_skull",Vector3(.55,2.2,-5.745),Vector2(1.0,.8))
	DECOR.panel(self,"sede_map",Vector3(1.75,1.6,-5.745),Vector2(1.2,.9))
	DECOR.panel(self,"sede_menu",Vector3(4.08,1.55,-5.745),Vector2(.8,1.1))
	DECOR.panel(self,"sede_moto",Vector3(6.85,2.35,-5.745),Vector2(1.0,.5))

func _dart_detail(at: Vector3, size: Vector3, color: String, kind := "paint", rotation := Vector3.ZERO, round_shape := false) -> void:
	# Scale in primitive-local axes before rotation; wall discs retain their circle.
	var key := color+kind+str(round_shape)
	if not _batches.has(key): _batches[key]={"color":color,"kind":kind,"round":round_shape,"transforms":[]}
	_batches[key].transforms.append(Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),at))
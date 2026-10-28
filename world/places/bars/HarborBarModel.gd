extends "res://world/places/arcade/ArcadeGeometry.gd"
## Lastro: a brick waterfront bar, with a broad central aisle and separate games bay.
var variant := 0
var station_points := {"bar_pool":Vector2(3.5,2.1),"bar_darts":Vector2(5.3,-2.95)}
const DECOR := preload("res://world/places/bars/BarDecor.gd")
func _ready() -> void:
	# Com as pinturas, a estante, o alvo e o feltro são a imagem; as caixas lisas ficam só sem elas.
	var painted := DECOR.available("lastro")
	box("OakFloor",Vector3(0,-.03,0),Vector3(16,.06,12),"59483d","","wood")
	box("RearBrick",Vector3(0,1.65,-5.88),Vector3(16,3.3,.24),"775443","RearWall","stone")
	for side in [-1,1]:
		box("SideBrick",Vector3(side*7.88,1.65,0),Vector3(.24,3.3,12),"71675c","SideWall%d"%side,"stone")
		box("FrontBrick",Vector3(side*4.55,1.65,5.88),Vector3(6.9,3.3,.24),"665448","FrontWall%d"%side,"stone")
		for y in [.18,2.92]: detail(Vector3(side*7.72,y,0),Vector3(.1,.15,11.5),"42362f","wood")
	# Northern counter; patrons stand on the customer side and staff behind it.
	box("Counter",Vector3(-3.7,.55,-3.6),Vector3(6.6,1.1,.9),"49362e","Counter","wood")
	box("CounterTop",Vector3(-3.7,1.14,-3.6),Vector3(6.85,.13,1.06),"ad865c","Counter","wood")
	box("RearShelf",Vector3(-3.7,1.15,-5.55),Vector3(6.8,2.3,.36),"44362b","RearShelf","wood")
	for level in (0 if painted else 3):
		for bottle in 15:
			detail(Vector3(-6.7+bottle*.43,.55+level*.62,-5.30),Vector3(.11,.33,.11),["506149","8b5d34","3b5557"][bottle%3],"paint",Vector3.ZERO,true)
	for x in [-5.7,-3.6,-1.5]:
		box("CounterMat",Vector3(x,1.22,-3.4),Vector3(.5,.025,.35),"35342d","","cloth")
		detail(Vector3(x+.12,1.37,-3.4),Vector3(.09,.27,.09),"9b713c","paint",Vector3.ZERO,true)
	# Booth west side: explicitly solid benches and table, kept clear of the entry.
	for z in [1.0,3.6]:
		box("Booth",Vector3(-7,.45,z),Vector3(1.1,.9,1.5),"61424b","Booth"+str(z),"cloth")
	box("SocialTable",Vector3(-5.75,.75,2.25),Vector3(1.5,.14,1.2),"98724d","SocialTable","wood")
	box("SocialTableBase",Vector3(-5.75,.35,2.25),Vector3(.65,.7,.65),"443b36","SocialTable","metal")
	# Billiards at natural scale: full footprint blocks movement, not only legs.
	box("PoolBody",Vector3(3.5,.48,0),Vector3(2.0,.96,3.5),"493b31","PoolTable","wood")
	box("PoolFelt",Vector3(3.5,.982,0),Vector3(1.68,.055,3.18),"315f57","PoolTable","cloth")
	for side in [-1,1]:
		box("PoolRail",Vector3(3.5+side*.92,1.01,0),Vector3(.17,.13,3.5),"9f7c50","PoolTable","wood")
		box("PoolRailEnd",Vector3(3.5,1.01,side*1.65),Vector3(1.84,.13,.18),"9f7c50","PoolTable","wood")
		for z in [-1.52,0.0,1.52]: detail(Vector3(3.5+side*.78,1.022,z),Vector3(.18,.024,.18),"171d1b","paint",Vector3.ZERO,true)
	for i in 7: detail(Vector3(3.2+(i%3)*.16,1.08,-.5+floori(i/3)*.15),Vector3(.09,.09,.09),["e9e0b8","bd963d","a94b3d","4d658a"][i%4],"paint",Vector3.ZERO,true)
	# Regulation board: 45 cm sisal face, bull at 1.73 m, with the black number ring around it.
	box("DartBackboard",Vector3(5.3,1.73,-5.68),Vector3(.9,.9,.10),"654934","DartBackboard","wood")
	for ring in ([] if painted else [[.46,"1f2727"],[.34,"a34f3c"],[.32,"d1c9ae"],[.21,"41836a"],[.19,"273f37"],[.032,"41836a"],[.013,"a34f3c"]]):
		_dart_detail(Vector3(5.3,1.73,-5.56-float(ring[0])*.02),Vector3(float(ring[0]),.025,float(ring[0])),str(ring[1]),"paint",Vector3(PI*.5,0,0),true)
	for i in (0 if painted else 20):
		var angle := TAU*i/20.0
		_dart_detail(Vector3(5.3+sin(angle)*.093,1.73+cos(angle)*.093,-5.542),Vector3(.006,.155,.006),"b9ae96","metal",Vector3(0,0,-angle))
	# Oche runs parallel to the wall at the regulation 2.37 m from the board face.
	detail(Vector3(5.3,.009,-3.19),Vector3(1.25,.012,.05),"d9c29b")
	box("Jukebox",Vector3(6.75,.7,3.8),Vector3(.75,1.4,.65),"593d32","Jukebox","wood")
	box("JukeboxFace",Vector3(6.75,1.05,4.14),Vector3(.58,.49,.026),"a5814f","","screen")
	for i in 6: detail(Vector3(6.51+i*.095,.53,4.14),Vector3(.025,.52,.02),"292c29","metal")
	for x in [-4.4,3.5]:
		var lamp_z := -3.6 if x < 0 else -1.1
		box("Pendant",Vector3(x,2.65,lamp_z),Vector3(1.1,.18,.65),"b99562","","metal")
		box("PendantDiffuser",Vector3(x,2.55,lamp_z),Vector3(.9,.025,.50),"e2c395","","screen")
		var light := OmniLight3D.new()
		light.position = Vector3(x,2.35,lamp_z)
		light.light_color = Color("f0d6af")
		light.light_energy = 1.4
		light.omni_range = 8.0
		light.light_specular = .25
		light.shadow_enabled = false
		add_child(light)
	if painted: _paintings()
	flush()
	set_process(false)
	set_physics_process(false)

func _paintings() -> void:
	DECOR.shell(self,"lastro",1.1)
	DECOR.panel(self,"lastro_shelf",Vector3(-3.7,1.15,-5.364),Vector2(6.8,2.3))
	DECOR.panel(self,"lastro_counter",Vector3(-3.7,.55,-3.144),Vector2(6.6,1.1),0.0,Vector2(2,1))
	DECOR.panel(self,"lastro_dartboard",Vector3(5.3,1.73,-5.624),Vector2(.46,.46))
	DECOR.flat(self,"lastro_felt",Vector3(3.5,1.012,0),Vector2(1.68,3.18),Vector2(1.68,3.18))
	# Parede do fundo entre a estante e o alvo, e o peixe sobre os bancos do lado oeste.
	DECOR.panel(self,"lastro_menu",Vector3(.7,1.55,-5.745),Vector2(.9,1.2))
	DECOR.panel(self,"lastro_harbor",Vector3(2.35,1.6,-5.745),Vector2(1.2,.8))
	DECOR.panel(self,"lastro_neon",Vector3(2.35,2.6,-5.745),Vector2(1.4,.6))
	DECOR.panel(self,"lastro_fish",Vector3(-7.745,1.95,2.3),Vector2(1.0,.6),PI*.5)

func _dart_detail(at: Vector3, size: Vector3, color: String, kind := "paint", rotation := Vector3.ZERO, round_shape := false) -> void:
	# Scale in primitive-local axes before rotation; wall discs retain their circle.
	var key := color+kind+str(round_shape)
	if not _batches.has(key): _batches[key]={"color":color,"kind":kind,"round":round_shape,"transforms":[]}
	_batches[key].transforms.append(Transform3D(Basis.from_euler(rotation)*Basis.from_scale(size),at))
extends "res://world/places/amusement_park/ParkGeometry.gd"
## Cenário do parque. Só o carrinho ocupado se move, guiado pela sessão.
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const GEOMETRY := preload("res://world/places/amusement_park/ParkGeometry.gd")
var complete := false
var curve := LAYOUT.coaster_curve()
var carriage: Node3D
var station_gate: Node3D
var gate_body: StaticBody3D
var restraint: Node3D
var carriage_door: Node3D

func set_boarding_open(amount: float) -> void:
	amount = clampf(amount,0,1)
	station_gate.rotation.y = amount*PI*.5
	gate_body.collision_layer = 1 if amount < .98 else 0
	carriage_door.rotation.y = amount*PI*.5
	restraint.rotation.x = -amount*1.35

func _ready() -> void:
	build()
	_start_music()

## Música de carrossel (Gemini/Lyria, 2026-10-15) saindo dos alto-falantes do parque, em loop.
## Posicional: ouve-se de longe, baixinho, e ela cresce ao chegar. Sem o arquivo importado o parque
## segue mudo como antes.
func _start_music() -> void:
	_start_crowd()
	var path := "res://audio/amusement_park/park_music.ogg"
	if not ResourceLoader.exists(path) or get_node_or_null("ParkMusic") != null: return
	var music := load(path) as AudioStreamOggVorbis
	if music == null: return
	music.loop = true
	var voice := AudioStreamPlayer3D.new()
	voice.name = "ParkMusic"
	voice.stream = music
	voice.bus = &"Music" if AudioServer.get_bus_index(&"Music") >= 0 else (&"SFX" if AudioServer.get_bus_index(&"SFX") >= 0 else &"Master")
	voice.volume_db = 2.0
	voice.unit_size = 22.0
	voice.max_distance = 110.0
	voice.position = Vector3(10, 5, 12)
	add_child(voice)
	voice.play(randf() * music.get_length())

func build() -> void:
	if complete: return
	complete = true
	name = "ParqueLume"
	position = LAYOUT.ORIGIN
	painted_exterior = true
	direct_collisions = true
	_ground()
	_perimeter()
	_track()
	_house()
	_plaza()
	preload("res://world/places/amusement_park/ParkLumeDressing.gd").build(self)
	_carriage()
	flush()
	set_coaster_progress(0)
	set_process(false)
	set_physics_process(false)

func coaster_length() -> float: return curve.get_baked_length()

func sample_coaster(distance: float) -> Transform3D:
	var length := coaster_length()
	var progress := fposmod(distance,length)
	var at := curve.sample_baked(progress,true)
	var front := (curve.sample_baked(fposmod(progress+.18,length),true)-curve.sample_baked(fposmod(progress-.18,length),true)).normalized()
	var right := front.cross(Vector3.UP).normalized()
	var pose := Transform3D(Basis(right,right.cross(front).normalized(),-front),at)
	# Funciona destacado durante a preparação do template e também no mundo.
	return global_transform*pose if is_inside_tree() else transform*pose

func coaster_eye(distance: float) -> Transform3D:
	var pose := sample_coaster(distance)
	pose.origin += pose.basis*Vector3(0,1.3,-.1)
	return pose

func set_coaster_progress(distance: float) -> void:
	if not is_instance_valid(carriage): return
	var pose := sample_coaster(distance)
	carriage.transform = (global_transform.affine_inverse() if is_inside_tree() else transform.affine_inverse())*pose

func boarding_position() -> Vector3: return LAYOUT.BOARDING

func _ground() -> void:
	if Engine.get_meta("recreation_ground_before",false):
		_ground_before()
		return
	preload("res://world/places/amusement_park/ParkLumeGround.gd").build(self)

func _ground_before() -> void:
	var polygon := LAYOUT.outline()
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var st := batch("ad9976","stone")
	var faces := PackedVector3Array()
	for i in range(0,triangles.size(),3):
		for index in [triangles[i],triangles[i+1],triangles[i+2]]:
			var point := Vector3(polygon[index].x,.025,polygon[index].y)
			st.set_normal(Vector3.UP)
			st.set_uv(polygon[index]*.2)
			st.add_vertex(point)
			faces.append(point)
	var body := StaticBody3D.new()
	body.name = "ParkGround"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	box("EntranceWalk",Vector3(45.5,-.06,16),Vector3(11,.17,5.8),"b3a185",true,"stone")
	# Um passeio largo em cruz liga as duas atrações e o portão.
	box("MainWalk",Vector3(13,.044,15),Vector3(54,.028,6),"d4c5a2",false,"stone")
	box("UmbraWalk",Vector3(20,.047,4),Vector3(5.2,.03,18),"d4c5a2",false,"stone")
	for z in [11.85,18.15]: box("PavingBorder",Vector3(13,.063,z),Vector3(54,.02,.13),"736951")

func _fence(a: Vector3, b: Vector3, height := 1.15) -> void:
	var direction := (b-a).normalized()
	var fence_basis := Basis(Vector3.UP,atan2(direction.x,direction.z))
	collision_box("Fence",(a+b)*.5+Vector3.UP*height*.5,Vector3(.18,height,a.distance_to(b)),fence_basis)
	beam(a+Vector3.UP*.20,b+Vector3.UP*.20,.10,.12,"385b59","metal")
	beam(a+Vector3.UP*height,b+Vector3.UP*height,.10,.10,"d1ab59","metal")
	var count := maxi(1,ceili(a.distance_to(b)/.72))
	for i in range(count+1):
		var p := a.lerp(b,float(i)/count)
		box("FencePicket",p+Vector3.UP*(height*.5),Vector3(.055,height,.055),"385b59",false,"metal")
		if i%4 == 0: ball(p+Vector3.UP*(height+.04),Vector3.ONE*.17,"d1ab59","metal")

func _perimeter() -> void:
	var outline := LAYOUT.outline()
	for i in outline.size():
		var a := Vector3(outline[i].x,0,outline[i].y)
		var b := Vector3(outline[(i+1)%outline.size()].x,0,outline[(i+1)%outline.size()].y)
		if is_equal_approx(a.x,40) and is_equal_approx(b.x,40):
			_fence(a,Vector3(40,0,12.8))
			_fence(Vector3(40,0,19.2),b)
		else: _fence(a,b)
	for z in [12.35,19.65]:
		box("GatePillar",Vector3(39.8,1.95,z),Vector3(.68,3.9,.68),"38625f",true)
		box("GateCap",Vector3(39.8,3.95,z),Vector3(.94,.22,.94),"d0a655")
	box("GateHeader",Vector3(39.8,3.63,16),Vector3(.5,.8,7.4),"773746")
	sign_text("Parque Lume",Vector3(40.08,3.63,16),64,PI*.5)
	for z in [13.6,18.4]:
		box("EntryBollard",Vector3(42,.42,z),Vector3(.2,.84,.2),"385b59",true,"metal")
	lantern(Vector3(39.4,3.1,12.35),"ffda9d",13,2.0)

func _track() -> void:
	var length := coaster_length()
	var count := ceili(length/.85)
	for i in count:
		var a := sample_coaster(length*i/count)
		var b := sample_coaster(length*(i+1)/count)
		a.origin -= LAYOUT.ORIGIN
		b.origin -= LAYOUT.ORIGIN
		for side in [-.64,.64]: beam(a.origin+a.basis.x*side,b.origin+b.basis.x*side,.085,.09,"b96748","metal")
		beam(a.origin-a.basis.x*.77,a.origin+a.basis.x*.77,.10,.11,"d9ba75","metal")
		beam(a.origin-Vector3.UP*.15,b.origin-Vector3.UP*.15,.25,.22,"3e6d67","metal")
		if i%8 == 0 and a.origin.y>1.0:
			for side in [-.95,.95]:
				var top: Vector3 = a.origin+a.basis.x*float(side)-Vector3.UP*.18
				var foot := Vector3(top.x,0,top.z)
				box("CoasterSupport",(top+foot)*.5,Vector3(.20,top.y,.20),"45615d",true,"metal")
				box("SupportFoundation",foot+Vector3.UP*.12,Vector3(.66,.24,.66),"8b8270",true,"stone")
	# A circulação pública fica fora do envelope do trilho e dos pés de apoio.
	for line in [[Vector3(-37,0,-30),Vector3(-5,0,-30)],[Vector3(-37,0,-30),Vector3(-37,0,23)],
		[Vector3(-37,0,23),Vector3(-5,0,23)],[Vector3(-5,0,-30),Vector3(-5,0,10)],
		[Vector3(-5,0,19),Vector3(-5,0,23)]]: _fence(line[0],line[1],1.25)
	box("BoardingDeck",Vector3(-8.45,.06,14.7),Vector3(5.1,.12,8.1),"745e49",false,"wood")
	var deck := StaticBody3D.new()
	deck.name = "BoardingDeckBody"
	deck.collision_layer = 1
	deck.collision_mask = 0
	deck.set_meta("pedestrian_step",true)
	deck.set_meta("pedestrian_step_top",.12)
	var deck_shape := BoxShape3D.new()
	deck_shape.size = Vector3(5.1,.12,8.1)
	var deck_collision := CollisionShape3D.new()
	deck_collision.shape = deck_shape
	deck_collision.position = Vector3(-8.45,.06,14.7)
	deck.add_child(deck_collision)
	add_child(deck)
	# A estação pública abre para o leste. O trilho visível mantém os pedestres fora da via;
	# o embarque é a interação explícita de atração sentada no centro do deck.
	_fence(Vector3(-11,0,10.3),Vector3(-5,0,10.3),1.15)
	_fence(Vector3(-11,0,10.3),Vector3(-11,0,13.2),1.15)
	_fence(Vector3(-11,0,15.5),Vector3(-11,0,19.1),1.15)
	var gate := GEOMETRY.new()
	gate.name = "BoardingGate"
	gate.painted_exterior = true
	gate.position = Vector3(-11,0,13.2)
	add_child(gate)
	station_gate = gate
	gate.box("GateLeaf",Vector3(0,.7,1.15),Vector3(.10,.10,2.3),"d1ab59",false,"metal")
	gate.box("GateTop",Vector3(0,1.15,1.15),Vector3(.10,.10,2.3),"d1ab59",false,"metal")
	for z in [0,.46,.92,1.38,1.84,2.3]:
		gate.box("GatePicket",Vector3(0,.63,z),Vector3(.06,1.05,.06),"385b59",false,"metal")
	gate.flush()
	gate_body = StaticBody3D.new()
	gate_body.collision_mask = 0
	gate.add_child(gate_body)
	var gate_shape := CollisionShape3D.new()
	var gate_box := BoxShape3D.new()
	gate_box.size = Vector3(.18,1.25,2.3)
	gate_shape.shape = gate_box
	gate_shape.position = Vector3(0,.625,1.15)
	gate_body.add_child(gate_shape)
	# Um degrau curto e sólido liga o deck à porta do carrinho parado.
	box("BoardingStep",Vector3(-11.15,.22,14.35),Vector3(.65,.44,1.6),"745e49",true,"wood")
	_fence(Vector3(-11,0,19.1),Vector3(-5,0,19.1),1.15)
	for x in [-10.4,-6.5]:
		for z in [10.8,18.6]: box("StationPost",Vector3(x,1.65,z),Vector3(.14,3.3,.14),"38625f",true,"metal")
	box("StationCanopy",Vector3(-8.45,3.30,14.7),Vector3(5.4,.16,8.5),"773746")
	for x in [-10.2,-8.5,-6.8]: box("CanopyStripe",Vector3(x,3.397,14.7),Vector3(.55,.03,8.4),"d9ba75")
	lantern(Vector3(-6.5,2.85,10.8),"ffd6a3",13,2.2)

func _house() -> void:
	var c := Vector3(20,0,-12)
	# Fachada maciça com um vão de 2,3 x 2,6 m recuado 1,3 m: as folhas da UmbraDoor
	# giram para dentro dele (antes a porta era uma placa colada na parede e não abria).
	for side in [-1,1]:
		box("UmbraFacade",c+Vector3(side*5.075,2.55,0),Vector3(7.85,5.1,15),"423e4a",true,"wood")
		box("UmbraPlinth",c+Vector3(side*5.225,.17,0),Vector3(8.15,.34,15.6),"71665f",true,"stone")
	box("UmbraFacade",c+Vector3(0,3.85,0),Vector3(2.3,2.5,15),"423e4a",true,"wood")
	box("UmbraFacade",c+Vector3(0,1.3,-.65),Vector3(2.3,2.6,13.7),"423e4a",true,"wood")
	box("UmbraPlinth",c+Vector3(0,.17,-.8),Vector3(2.3,.34,14.0),"71665f",true,"stone")
	# Fundo escuro do recuo e soleira no nível da calçada (sem degrau no vão).
	box("UmbraDoorDark",c+Vector3(0,1.3,6.215),Vector3(2.3,2.6,.03),"0b0b10")
	box("UmbraThreshold",c+Vector3(0,.012,6.9),Vector3(2.3,.024,1.6),"5a5049",false,"stone")
	var door := preload("res://world/places/amusement_park/UmbraDoor.gd").new()
	door.position = c+Vector3(0,0,7.5)
	add_child(door)
	for side in [-1,1]:
		box("DoorJamb",c+Vector3(side*1.25,1.45,7.73),Vector3(.22,2.9,.28),"928171")
		box("Tower",c+Vector3(side*7.5,3.55,0),Vector3(2.1,7.1,4),"4c4552")
		for x in [3.2,5.8]:
			box("WindowFrame",c+Vector3(side*x,2.8,7.57),Vector3(1.30,2.0,.17),"262a32")
			box("WindowGlow",c+Vector3(side*x,2.8,7.68),Vector3(1.04,1.75,.04),"7d677f",false,"glow")
			beam(c+Vector3(side*x-.50,2.2,7.75),c+Vector3(side*x+.48,3.15,7.75),.17,.09,"6d5b4e","wood")
		box("RoofWing",c+Vector3(side*4.7,5.25,0),Vector3(9.8,.23,15.8),"292f38",false,"metal",Basis(Vector3.FORWARD,side*.18))
	box("RoofRidge",c+Vector3(0,6.14,0),Vector3(.25,.3,16),"5c5260")
	sign_text("Umbra",c+Vector3(0,3.7,7.82),118)
	lantern(c+Vector3(-2.3,2.5,7.92),"d1b5e4",12,1.8)
	for x in [-7,7]:
		box("Planter",c+Vector3(x,.35,9.2),Vector3(1.4,.7,1.1),"706457",true,"stone")
		ball(c+Vector3(x,.97,9.2),Vector3(1.25,1.35,1.0),"43574a")

func _plaza() -> void:
	# Pequena cabine listrada; o segredo do casaco fica escondido atrás, não no balcão.
	var c := Vector3(-30,0,31)
	box("Booth",c+Vector3(0,1.0,0),Vector3(5.0,2.0,2.2),"e1cfa4",true,"wood")
	for i in 9: box("BoothStripe",c+Vector3(-2.2+i*.55,1.0,-1.12),Vector3(.25,1.9,.04),"873e4a")
	box("BoothRoof",c+Vector3(0,2.12,0),Vector3(5.6,.20,2.8),"38625f")
	box("BoothCounter",c+Vector3(0,1.07,-1.30),Vector3(5.25,.13,.50),"ae8856",true,"wood")
	for point in [Vector3(12,0,26),Vector3(24,0,23),Vector3(1,0,29)]:
		box("BenchSeat",point+Vector3(0,.47,0),Vector3(3.0,.14,.68),"957250",true,"wood")
		box("BenchBack",point+Vector3(0,.89,.28),Vector3(3.0,.64,.12),"957250",true,"wood")
		for x in [-1.15,1.15]: box("BenchLeg",point+Vector3(x,.24,0),Vector3(.16,.48,.58),"385b59",false,"metal")
	# A stationary carousel centrepiece gives the plaza a readable silhouette.
	var center := Vector3(9,0,-12)
	cylinder(center+Vector3.UP*.25,3.4,.5,"773746")
	collision_box("CarouselPlatform",center+Vector3.UP*.3,Vector3(6.8,.6,6.8))
	cylinder(center+Vector3.UP*2.1,.25,3.8,"d1ab59","metal")
	for i in 6:
		var angle := TAU*i/6.0
		var p := center+Vector3(cos(angle),0,sin(angle))*2.1
		cylinder(p+Vector3.UP*1.85,.06,3.2,"d1ab59","metal")
		ball(p+Vector3.UP*1.1,Vector3(1.25,.65,.5),"ddd0ae")
		ball(p+Vector3(.5,1.55,0),Vector3(.33,.72,.34),"ddd0ae")
		for side in [-1,1]: beam(p+Vector3(side*.35,.99,0),p+Vector3(side*.48,.65,0),.13,.13,"ddd0ae")
	for i in 12:
		var a := TAU*i/12.0
		var b := TAU*(i+1)/12.0
		var st := batch("d1ab59" if i%2 else "38625f","paint")
		for p in [center+Vector3.UP*4.4,center+Vector3(cos(a)*3.6,3.5,sin(a)*3.6),center+Vector3(cos(b)*3.6,3.5,sin(b)*3.6)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x,p.z))
			st.add_vertex(p)
	for p in [Vector3(31,0,31),Vector3(-2,0,-32),Vector3(-36,0,30)]:
		box("FlowerPlanter",p+Vector3.UP*.28,Vector3(1.8,.56,1.4),"b59368",true,"stone")
		ball(p+Vector3.UP*.73,Vector3(1.6,.65,1.2),"506f56")
	# Wardrobe cabin has a recessed open front and a free approach at (29,20).
	box("WardrobeBack",Vector3(32,1.2,20),Vector3(.18,2.4,3.2),"38625f",true,"wood")
	for z in [18.5,21.5]: box("WardrobeSide",Vector3(31,1.2,z),Vector3(2.1,2.4,.15),"38625f",true,"wood")
	box("WardrobeRoof",Vector3(31,2.45,20),Vector3(2.4,.16,3.5),"773746")
	box("WardrobeMirror",Vector3(31.87,1.35,20),Vector3(.03,1.6,1.25),"9ca8ae",false,"metal")
	box("WardrobeMirrorFrame",Vector3(31.92,1.35,20),Vector3(.045,1.82,1.45),"b9965a",false,"metal")
	# Bandejas baixas de revelação são detalhes rasos do piso, nunca móveis que bloqueiam a coleta.
	for p in [Vector3(-31,0,27),Vector3(28,0,27),Vector3(-2,0,-28),Vector3(31,0,-3)]:
		box("SecretTray",p+Vector3.UP*.057,Vector3(.72,.064,.58),"8f734e",false,"wood")

func _carriage() -> void:
	var model := GEOMETRY.new()
	model.name = "CoasterCarriage"
	add_child(model)
	carriage = model
	model.box("CarFloor",Vector3(0,.19,0),Vector3(1.6,.30,2.3),"963f4d",false,"metal")
	model.box("CarNose",Vector3(0,.46,-1.05),Vector3(1.6,.70,.28),"963f4d",false,"metal")
	for side in [-1,1]:
		if side == -1:
			model.box("CarSide",Vector3(side*.76,.58,.05),Vector3(.16,.62,2.0),"963f4d",false,"metal")
		else:
			model.box("CarSideFront",Vector3(.76,.58,-.73),Vector3(.16,.62,.55),"963f4d",false,"metal")
			model.box("CarSideRear",Vector3(.76,.58,.88),Vector3(.16,.62,.34),"963f4d",false,"metal")
		for z in [-.7,.7]: model.cylinder(Vector3(side*.73,-.04,z),.19,.16,"272d35","metal",Basis(Vector3.FORWARD,PI*.5))
	model.box("Seat",Vector3(0,.42,.35),Vector3(1.35,.16,.68),"263c45")
	model.box("SeatBack",Vector3(0,.79,.69),Vector3(1.35,.66,.16),"263c45")
	var door := GEOMETRY.new()
	door.name = "CarriageDoor"
	door.position = Vector3(.76,.27,-.45)
	model.add_child(door)
	carriage_door = door
	door.box("DoorLeaf",Vector3(0,.31,.575),Vector3(.16,.62,1.15),"963f4d",false,"metal")
	door.flush()
	var bar := GEOMETRY.new()
	bar.name = "SafetyBar"
	bar.position = Vector3(0,.85,.60)
	model.add_child(bar)
	restraint = bar
	bar.beam(Vector3(-.65,0,-.82),Vector3(.65,0,-.82),.07,.07,"d4af63","metal")
	for side in [-1,1]: bar.beam(Vector3(side*.65,0,0),Vector3(side*.65,0,-.82),.07,.07,"d4af63","metal")
	bar.flush()
	model.flush()

## Murmúrio de multidão e crianças (Firefly, 2026-10-15), em loop por baixo da música.
func _start_crowd() -> void:
	var bank := preload("res://audio/FireflyBank.gd")
	var crowd := bank.loop("amusement_park", "crowd_loop_%d.wav" % (randi() % 2))
	if crowd == null or get_node_or_null("ParkCrowd") != null: return
	var voice := AudioStreamPlayer3D.new()
	voice.name = "ParkCrowd"
	voice.stream = crowd
	voice.bus = bank.bus_name()
	voice.volume_db = -4.0
	voice.unit_size = 18.0
	voice.max_distance = 70.0
	voice.position = Vector3(8, 2, 14)
	add_child(voice)
	voice.play(randf() * crowd.get_length())

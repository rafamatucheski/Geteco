extends Node3D
## Offline film direction over the actual Harbor set. Never instantiated by gameplay.
## Segunda montagem (16/10): mesma trilha de vozes de 73 s, planos novos para o porto
## atual — descida pelo canal, passagem sob o viaduto, Vicente no cais na lembrança
## e Dante deixando o convés enquanto a câmera revela a cidade.
const ACTOR := preload("res://scripts/Actor.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var world
var terminal
var ferry: Node3D
var dante
var passenger
var vicente
var vicente_light: SpotLight3D
var vicente_phone: Node3D
var _vicente_grip: Node3D
var _toss_from := Vector3.INF
var camera: Camera3D
var phone: Node3D
var bag: Node3D
var elapsed := 0.0
var length := 73.0
var shots := [0.0,7.0,12.0,16.0,21.0,25.0,29.0,31.0,36.5,42.0,49.0,54.0,61.0,67.5]
var extras: Array = []
var night_set
var environment: Environment
var _grade_base := {}
var _shot_origin := Vector3.ZERO
var _last_shot := -1
# Rota da balsa (tempo, posição). Desce o canal de proa a leste do Northstar, gira
# na parte larga do canal durante a conversa e entra de popa na vaga, como no jogo:
# o convés aberto (onde Dante está) é a popa e encosta no terminal (ARRIVAL). Na vaga
# entre o píer e o cargueiro (~16 m) o giro não cabe; de proa, Dante saía para a água.
const ROUTE := [[0.0,Vector3(256,0,70)],[12.0,Vector3(255,0,112)],[27.0,Vector3(253,0,140)],[36.0,Vector3(242,0,161.5)],[47.0,Vector3(236,0,170)],[54.0,Vector3(234,0,177)],[61.0,Vector3(233,0,183.5)]]
const TURN_FROM := 12.0
const TURN_TO := 27.0
# Vicente na lembrança: no cais oeste, junto à amurada (sólida em x = 198..198,5 pelo
# mapa de --probe), olha o celular aceso, joga-o no mar e some no escuro. É por isso
# que "ele não atende mais".
const VICENTE_SPOT := Vector3(198.9,0,191.5)
const VICENTE_LAMP := Vector3(199.8,4.6,191.0)
const PHONE_TOSS := 44.85
const WATER_Y := -0.82 # superfície do oceano da filmagem (FerryNightSet)

func configure(p_world) -> void:
	world = p_world
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().scaling_3d_scale = 1.0
	terminal = world.session.urban_operations.passenger_terminal
	terminal.prepare_arrival()
	terminal.set_process(false)
	ferry = terminal.ferry
	world.camera.set_process(false)
	world.camera.set_physics_process(false)
	world.camera.set_process_unhandled_input(false)
	world.session.arrival.active = false
	night_set = preload("res://cutscenes/opening/ferry/FerryNightSet.gd").new()
	add_child(night_set)
	night_set.configure(world,ferry)
	environment = world.production.environment.environment
	_grade_base = {"exposure":environment.tonemap_exposure,"fog":environment.fog_light_color,"ambient":environment.ambient_light_energy}
	for node in world.find_children("*", "CanvasLayer", true, false): node.hide()
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false): node.hide()
	world.player.hide()
	world.player.set_physics_process(false)
	world.player.input_locked = true
	dante = ACTOR.new()
	dante.is_player = true
	ferry.add_child(dante)
	dante.set_physics_process(false)
	dante.input_locked = true
	dante.position = Vector3(0,.48,4.3)
	dante.visual.rotation.y = PI
	dante.collision_layer = 0
	dante.collision_mask = 0
	dante.show()
	passenger = preload("res://cutscenes/opening/ferry/FerryPassenger.gd").new()
	ferry.add_child(passenger)
	passenger.position = Vector3(1.25,.48,4.30)
	passenger.rotation.y = -.85
	passenger.visual.rotation.y = PI
	passenger.set_process(false)
	for i in 2:
		var extra := CIVILIAN.new()
		extra.appearance_locked = true
		extra.appearance_variant = 8 + i * 7
		extra.wardrobe_overrides = {"top":2,"bottom":0,"hat":0,"bag":0}
		ferry.add_child(extra)
		extra.position = Vector3(-.85 if i == 0 else .85, .48, 2.0)
		extra.rotation.y = PI
		extra.sit_amount = 1.0
		extra.seat_height = .34
		extra.set_process(false)
		_prepare_closeup_materials(extra)
		extras.append(extra)
	# Vicente usa o corpo do Dante (são irmãos) com o sobretudo escuro e o cachecol
	# vermelho; o civil segmentado antigo parecia feito de cilindros de perto.
	vicente = ACTOR.new()
	vicente.name = "FilmVicente"
	vicente.is_player = true
	add_child(vicente)
	vicente.set_physics_process(false)
	vicente.input_locked = true
	vicente.collision_layer = 0
	vicente.collision_mask = 0
	vicente.set_outfit("dante_trench")
	vicente.global_position = VICENTE_SPOT
	vicente.visual.rotation.y = PI*.5
	vicente.hide()
	vicente_phone = Node3D.new()
	add_child(vicente_phone)
	_box(vicente_phone,Vector3.ZERO,Vector3(.070,.145,.009),Color("15232a"))
	var screen := MeshInstance3D.new()
	var face := BoxMesh.new()
	face.size = Vector3(.062,.128,.001)
	screen.mesh = face
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("9fc3ff")
	glow.emission_enabled = true
	glow.emission = Color("b9d4ff")
	glow.emission_energy_multiplier = 1.6
	screen.material_override = glow
	screen.position = Vector3(0,0,.005)
	vicente_phone.add_child(screen)
	var screen_light := OmniLight3D.new()
	screen_light.light_color = Color("a9c8ff")
	# Só o rosto e a mão: com 1,1 / 1,3 m a luz pintava uma faixa branca na amurada.
	screen_light.light_energy = .35
	screen_light.omni_range = .7
	screen_light.position = Vector3(0,0,.08)
	vicente_phone.add_child(screen_light)
	vicente_phone.hide()
	_vicente_grip = Node3D.new()
	add_child(_vicente_grip)
	vicente_light = SpotLight3D.new()
	vicente_light.light_color = Color("ffc98e")
	vicente_light.light_energy = 14.0
	vicente_light.spot_range = 10.0
	vicente_light.spot_angle = 42.0
	vicente_light.spot_attenuation = 1.2
	vicente_light.shadow_enabled = true
	add_child(vicente_light)
	vicente_light.global_position = VICENTE_LAMP
	vicente_light.look_at(Vector3(VICENTE_SPOT.x-.2,0,VICENTE_SPOT.z+.3),Vector3.FORWARD)
	vicente_light.hide()
	phone = Node3D.new()
	ferry.add_child(phone)
	_box(phone,Vector3.ZERO,Vector3(.070,.145,.009),Color("15232a"))
	_box(phone,Vector3(0,0,.005),Vector3(.062,.128,.001),Color("526e7b"))
	_box(phone,Vector3(-.023,.052,-.005),Vector3(.012,.019,.002),Color("090e13"))
	bag = Node3D.new()
	dante.visual.add_child(bag)
	bag.position = Vector3(0,1.10,.20)
	_box(bag,Vector3.ZERO,Vector3(.34,.43,.16),Color("69503b"))
	_box(bag,Vector3(0,-.075,.098),Vector3(.28,.19,.055),Color("866c4f"))
	for x in [-.12,.12]:
		_box(bag,Vector3(x,.04,-.15),Vector3(.041,.46,.035),Color("513f30"))
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.near = .06
	camera.far = 1400.0
	camera.fov = 46.0
	add_child(camera)
	camera.make_current()
	var timing_path := "res://cutscenes/opening/ferry/timing.json"
	if FileAccess.file_exists(timing_path):
		var timing: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(timing_path))
		length = timing.duration
		if timing.shots.size() == shots.size(): shots.assign(timing.shots)
	sample(0.0,1.0/30.0)

func _prepare_closeup_materials(model) -> void:
	# The civilian's segmented wardrobe includes open cuffs and shoulder shells.
	# Close cinematic cameras see their reverse faces; keep this override local.
	for joint in model._joints:
		joint.material_override = model.KIT.material(true)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = model.wardrobe.top_color
	cloth.roughness = .9
	for shoulder in model.upper_arms:
		var cap := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .069
		sphere.height = .138
		cap.mesh = sphere
		cap.material_override = cloth
		cap.position.y = -.018
		shoulder.add_child(cap)

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)

func shot_at(t: float) -> int:
	for index in range(shots.size()-1,-1,-1):
		if t >= shots[index]: return index
	return 0

## Hermite pelo tempo com tangentes de Catmull-Rom: a balsa não para em cada
## ponto da rota; só a chegada ao berço tem velocidade zero.
static func route_position(t: float) -> Vector3:
	if t >= ROUTE[-1][0]: return ROUTE[-1][1]
	var k := 0
	while k < ROUTE.size()-2 and t > ROUTE[k+1][0]: k += 1
	var t0: float = ROUTE[k][0]
	var t1: float = ROUTE[k+1][0]
	var p0: Vector3 = ROUTE[k][1]
	var p1: Vector3 = ROUTE[k+1][1]
	var m0 := _tangent(k)*(t1-t0)
	var m1 := _tangent(k+1)*(t1-t0)
	var s := clampf((t-t0)/(t1-t0),0,1)
	var s2 := s*s
	var s3 := s2*s
	return p0*(2*s3-3*s2+1)+m0*(s3-2*s2+s)+p1*(-2*s3+3*s2)+m1*(s3-s2)

static func _tangent(k: int) -> Vector3:
	if k == ROUTE.size()-1: return Vector3.ZERO
	var a: int = maxi(k-1,0)
	var b: int = mini(k+1,ROUTE.size()-1)
	return ((ROUTE[b][1] as Vector3)-(ROUTE[a][1] as Vector3))/((ROUTE[b][0] as float)-(ROUTE[a][0] as float))

func memory_weight(t: float) -> float:
	return smoothstep(29.0,30.2,t)*(1.0-smoothstep(53.0,54.2,t))

func sample(t: float, delta: float) -> void:
	elapsed = t
	var arrival_u := smoothstep(0.0, 61.0, t)
	ferry.position = route_position(t)
	ferry.rotation.y = PI*(1.0-smoothstep(TURN_FROM,TURN_TO,t))
	ferry.position.y = .025*sin(t*.85)*(1.0-arrival_u)
	ferry.rotation.z = .003*sin(t*.7)*(1.0-arrival_u)
	ferry.rotation.x = .002*sin(t*.53+1.0)*(1.0-arrival_u)
	night_set.sample(t,delta)
	var memory := memory_weight(t)
	_grade(memory)
	_direct_dante(t,delta,memory)
	var speaking := (t >= 12 and t < 15) or (t >= 21 and t < 24) or (t >= 57 and t < 60.2) or (t >= 65 and t < 67)
	passenger.pose_at(t,speaking,delta)
	for i in extras.size():
		extras[i].clock = t + i*2.0
		extras[i]._speed = 0.0
		extras[i]._travel = 0.0
		extras[i]._pose(delta)
	_direct_vicente(t,delta)
	_direct_camera(t)

func _grade(memory: float) -> void:
	# A ligação lembrada: mais fria e menos saturada, sem trocar de cenário.
	environment.adjustment_enabled = memory > .001
	environment.adjustment_saturation = lerpf(1.0,.42,memory)
	environment.adjustment_contrast = lerpf(1.0,1.12,memory)
	environment.adjustment_brightness = lerpf(1.0,.9,memory)
	environment.tonemap_exposure = lerpf(_grade_base.exposure,_grade_base.exposure*.9,memory)
	environment.fog_light_color = (_grade_base.fog as Color).lerp(Color("15243a"),memory)

func _direct_dante(t: float, delta: float, memory: float) -> void:
	dante._pose_delta = delta
	# Saída: a popa dá para o píer; ele já está virado para ela e anda até a amurada.
	var leave := smoothstep(67.9,68.6,t)
	var walk_start := 68.4
	dante.visual.rotation.y = PI
	if t < walk_start:
		dante.position = Vector3(0,.48,4.3)
		dante._idle_clock = t
		dante._apply_pose(dante._idle_pose)
		dante._apply_idle_breath()
	else:
		var distance := minf((t-walk_start)*1.05,1.35)
		var previous := minf(maxf(t-delta-walk_start,0.0)*1.05,1.35)
		dante.position = Vector3(0,.48,4.3+distance)
		var step := distance-previous
		var moving := step > .0005
		# Entra e sai da passada em ~0,6 s: o primeiro quadro do ciclo erguia o braço 15° de uma vez.
		var gait := smoothstep(walk_start,walk_start+.6,t)*maxf(0.0,1.0-smoothstep(1.05,1.35,distance))
		dante.phase = fposmod(dante.phase + step/1.8,1.0)
		dante._pose_cycle("Walking",dante.phase,dante.WALK_START)
		if gait < 1.0 or not moving:
			var walk_pose: Array = dante._capture_pose()
			dante._apply_blend(dante._idle_pose,walk_pose,gait if moving else 0.0)
	var look_passenger := smoothstep(11.3,12.5,t)*(1.0-smoothstep(24.6,25.6,t))
	look_passenger = maxf(look_passenger,smoothstep(61.0,62.0,t)*(1.0-leave))
	# "Tempo demais": desvia o olhar do passageiro para a cidade que fica para trás.
	var look_away := smoothstep(25.2,26.4,t)*(1.0-smoothstep(28.5,29.5,t))
	var head: int = dante.skeleton.find_bone("Head")
	if head >= 0:
		var rest: Quaternion = dante.skeleton.get_bone_pose_rotation(head)
		dante.skeleton.set_bone_pose_rotation(head,rest*Quaternion(Vector3.UP,.35*look_passenger-.42*look_away)*Quaternion(Vector3.RIGHT,.28*memory+.012*sin(t*1.6)))
	var holding := smoothstep(29.0,31.0,t)*(1.0-smoothstep(52.6,54.2,t))
	preload("res://cutscenes/opening/ferry/FerryPhonePose.gd").apply(dante,phone,holding)
	# Desligou e guardou: na saída o aparelho não acompanha a mão balançando.
	phone.visible = t < 55.0

func _direct_vicente(t: float, delta: float) -> void:
	var on_screen := t >= 41.9 and t < 49.1
	vicente.visible = on_screen
	vicente_light.visible = on_screen
	if not on_screen:
		vicente_phone.hide()
		_toss_from = Vector3.INF
		return
	vicente._pose_delta = delta
	# Olha o aparelho aceso; ergue-o num arremesso curto por cima da amurada; fica um
	# instante olhando a água; vira para o sul e vai embora pelo cais.
	var turn := smoothstep(46.3,47.0,t)
	vicente.visual.rotation.y = lerpf(PI*.5,PI,turn)
	var walk_start := 46.8
	var walked := maxf(0.0,t-walk_start)*1.1
	var before := maxf(0.0,t-delta-walk_start)*1.1
	vicente.global_position = VICENTE_SPOT+Vector3(.3*smoothstep(46.8,47.6,t),0,walked)
	vicente._idle_clock = t
	vicente._apply_pose(vicente._idle_pose)
	vicente._apply_idle_breath()
	if t >= walk_start:
		vicente.phase = fposmod(vicente.phase+(walked-before)/1.8,1.0)
		vicente._pose_cycle("Walking",vicente.phase,vicente.WALK_START)
		var walk_pose: Array = vicente._capture_pose()
		vicente._apply_blend(vicente._idle_pose,walk_pose,smoothstep(walk_start,walk_start+.6,t))
	var look := smoothstep(42.0,42.8,t)*(1.0-smoothstep(45.0,45.9,t))
	var raise := smoothstep(44.35,44.8,t)*(1.0-smoothstep(44.9,45.6,t))
	var arm := .55*look+.38*raise
	var head: int = vicente.skeleton.find_bone("Head")
	if head >= 0:
		var rest: Quaternion = vicente.skeleton.get_bone_pose_rotation(head)
		# Cabeça baixa no aparelho; depois acompanha a queda até a água.
		var down := .32*look+.22*smoothstep(44.9,45.4,t)*(1.0-smoothstep(46.0,46.6,t))
		vicente.skeleton.set_bone_pose_rotation(head,rest*Quaternion(Vector3.RIGHT,down))
	var holding := t < PHONE_TOSS
	preload("res://cutscenes/opening/ferry/FerryPhonePose.gd").apply(vicente,vicente_phone if holding else _vicente_grip,arm)
	if holding:
		vicente_phone.show()
		_toss_from = vicente_phone.global_position
		return
	# Arremesso: arco curto para oeste, por cima da amurada, até a linha d'água.
	var dt := t-PHONE_TOSS
	var point := _toss_from+Vector3(-1.7,1.1,.15)*dt+Vector3(0,-4.9,0)*dt*dt
	vicente_phone.visible = point.y > WATER_Y
	vicente_phone.global_position = point
	vicente_phone.rotation = Vector3(dt*9.0,dt*3.0,dt*6.0)

func _direct_camera(t: float) -> void:
	var index := shot_at(t)
	var end: float = shots[index+1] if index+1 < shots.size() else length
	var u := clampf((t-shots[index])/maxf(.01,end-shots[index]),0.0,1.0)
	var e := smoothstep(0.0,1.0,u)
	if index != _last_shot:
		_last_shot = index
		_shot_origin = ferry.global_position
	# Respiração de câmera na mão, pequena o bastante para não tremer o horizonte.
	var hand := Vector3(sin(t*.71)*.012,sin(t*.93+1.3)*.009,sin(t*.57+2.1)*.01)
	camera.fov = 44.0
	var rain_on_camera := false
	match index:
		0:
			# Abertura alta: desce pelo canal com o Northstar à direita e o viaduto à frente.
			camera.fov = 50.0
			_world_shot(Vector3(284,36,38).lerp(Vector3(268,17,58),e),ferry.global_position+Vector3(-2,1,16))
			rain_on_camera = true
		1:
			# Rente à água, a balsa passa pela câmera com a cidade atrás.
			camera.fov = 34.0
			_local_shot(Vector3(-15,1.3,-9).lerp(Vector3(-14.5,1.45,3),u)+hand,Vector3(0,1.5,-1).lerp(Vector3(0,1.6,2.5),u))
		2:
			_local_shot(Vector3(-1.1,2.05,7.15).lerp(Vector3(-.75,2.0,6.9),u)+hand,Vector3(.92,1.83,4.3))
		3:
			camera.fov = 40.0
			_local_shot(Vector3(1.55,1.98,6.9).lerp(Vector3(1.3,1.98,6.45),u)+hand,Vector3(0,1.81,4.3))
		4:
			# Perfil dos dois, a câmera desliza ao lado do casco.
			camera.fov = 40.0
			_local_shot(Vector3(-3.4,1.75,4.9).lerp(Vector3(-3.4,1.78,3.9),u)+hand,Vector3(.6,1.62,4.3))
		5:
			# Por cima do ombro: o que ele olha é o caminho que ficou para trás.
			_local_shot(Vector3(.38,1.9,2.85).lerp(Vector3(.28,1.93,3.25),e)+hand,Vector3(-.6,1.55,12))
		6:
			# Rente à água sob o viaduto, a balsa recua na direção da sombra: a lembrança
			# começa aqui.
			camera.fov = 40.0
			_world_shot(Vector3(246,3.2,167).lerp(Vector3(246.5,3.0,166.4),u),ferry.global_position+Vector3(0,1.6,0))
			rain_on_camera = true
		7:
			camera.fov = 31.0
			_local_shot(Vector3(-1.25,2.0,7.3).lerp(Vector3(-.85,2.02,6.2),e)+hand*.6,Vector3(0,1.93,4.3))
		8:
			camera.fov = 30.0
			_local_shot(Vector3(-2.3,1.95,4.75).lerp(Vector3(-2.05,1.95,4.25),u)+hand*.6,Vector3(0,1.9,4.3))
		9:
			# "Ele foi visto em Harbor": Vicente de costas na rua do cais.
			# Atrás e à direita dele: o aparelho aceso, a amurada e a água escura.
			camera.fov = 38.0
			var v: Vector3 = vicente.global_position
			camera.global_position = Vector3(202.7,1.7,189.3).lerp(Vector3(202.2,1.62,189.8),e)+hand
			var phone_focus := Vector3(198.4,1.2,191.6).lerp(Vector3(197.6,-.2,191.8),smoothstep(44.9,45.6,t))
			camera.look_at(phone_focus.lerp(v+Vector3(0,1.3,0),smoothstep(46.2,47.4,t)),Vector3.UP)
			rain_on_camera = true
		10:
			camera.fov = 27.0
			_local_shot(Vector3(-.6,1.97,5.65).lerp(Vector3(-.45,1.97,5.3),u)+hand*.5,Vector3(0,1.92,4.3))
		11:
			# De volta ao presente: o cais, os guindastes e a vaga que se aproxima.
			# Por cima dos contêineres do cargueiro, olhando a balsa entrar na vaga com o
			# terminal e a cidade atrás. (Do cais a passarela escondia a balsa; do norte,
			# o tabuleiro do viaduto tomava metade do quadro.)
			camera.fov = 42.0
			_world_shot(Vector3(258,14,192).lerp(Vector3(255,12,189),e),ferry.global_position+Vector3(0,.5,0))
			rain_on_camera = true
		12:
			camera.fov = 40.0
			_local_shot(Vector3(.62,1.75,7.7).lerp(Vector3(.62,1.72,7.1),u)+hand,Vector3(.62,1.6,4.3))
		13:
			# Ele deixa o convés; a câmera sobe até a cidade iluminada.
			# A popa encosta no terminal: ele anda até a borda, de frente para a câmera
			# no cais, e a câmera sobe por cima do terminal até a cidade ao norte.
			camera.fov = lerpf(40.0,50.0,e)
			var rise := smoothstep(.3,1.0,u)
			var near := ferry.to_global(Vector3(-2.4,1.65,8.2))
			var far := Vector3(230,23,204)
			var head_point := ferry.to_global(dante.position+Vector3(0,1.5,0))
			var eye := near.lerp(far,rise)
			# Sobe antes de recuar: o telhado do terminal fica logo atrás da câmera.
			eye.y = lerpf(near.y,far.y,smoothstep(0.0,.55,rise))
			camera.global_position = eye
			camera.look_at(head_point.lerp(Vector3(222,6,128),smoothstep(.35,1.0,u)),Vector3.UP)
			rain_on_camera = rise > .3
	night_set.rain.global_position = (camera.global_position if rain_on_camera else ferry.global_position)+Vector3.UP*9

func _local_shot(eye: Vector3, focus: Vector3) -> void:
	camera.global_position = ferry.to_global(eye)
	camera.look_at(ferry.to_global(focus),Vector3.UP)

func _world_shot(eye: Vector3, focus: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(focus,Vector3.UP)

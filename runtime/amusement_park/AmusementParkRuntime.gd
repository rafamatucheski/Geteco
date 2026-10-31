extends Node
## Recreação local; a sessão continua dona das transições e checkpoints.
const LAYOUT = preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const SITE = preload("res://world/places/amusement_park/ParkLume.gd")
const REWARDS = preload("res://activities/amusement_park/AmusementParkRewards.gd")
const LIFE = preload("res://activities/amusement_park/AmusementParkLife.gd")
const VENDING = preload("res://activities/amusement_park/AmusementParkVending.gd")
const BOARDING = preload("res://runtime/amusement_park/CoasterBoarding.gd")
const RIDE_PRICE := 5
var session
var world
var site: Node3D
var rewards: Node
var life: Node
var vending: RefCounted
var active := false
var ride_distance := 0.0
var ride_speed := 4.0
var view: Camera3D
var house_view := false
var yaw := 0.0
var pitch := 0.0
var clock := 0.0
var _saved := {}
var _house_saved := {}
var _ride_hint: CanvasLayer
var _ride_touch_fingers: Dictionary = {}
var _prepared: Node3D
var _exit_pending := false
var _exit_retry := 0.0
var ride_phase := "idle"
var boarding_time := 0.0
var return_requested := false

func configure(owner_session) -> void:
	session = owner_session
	world = session.world

const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

func _ready() -> void:
	name = "AmusementParkRuntime"
	rewards = REWARDS.new()
	rewards.configure(session)
	add_child(rewards)
	life = LIFE.new()
	life.configure(session)
	add_child(life)
	vending = VENDING.new()
	vending.configure(session)
	# Monta fora da árvore de cena enquanto a cortina de carregamento está erguida. Instâncias de colisão,
	# luz e render só são admitidas quando o jogador se aproxima.
	# Adiado para o próximo quadro (call_deferred ainda cairia no mesmo): dentro do _ready da sessão somava ~1 s ao quadro único de ~15 s do
	# carregamento (16/10). _process só usa o modelo depois de `ready_for_play`.
	_prepare_site()

func _prepare_site() -> void:
	# GETECO_PARK_SYNC_PREPARE=1 monta no próprio _ready, como antes (A/B do carregamento).
	if OS.get_environment("GETECO_PARK_SYNC_PREPARE") != "1": await get_tree().process_frame
	if is_instance_valid(_prepared) or is_instance_valid(site) or not is_inside_tree(): return
	var started := STALL_WORK.begin()
	_prepared = SITE.new()
	_prepared.build()
	STALL_WORK.finish("park.prepare_site", started, {})

func _process(delta: float) -> void:
	if get_tree().paused or not is_instance_valid(world) or not session.ready_for_play: return
	if active:
		if _ride_interrupted():
			leave()
		else:
			_tick_ride(delta)
	_sync_house_view()
	if house_view: _tick_house_view(delta)
	clock += delta
	if clock < .15: return
	clock = 0.0
	_update_residency()
	life.refresh(site)
	vending.set_site(site)
	var haunted: Node3D = session.room if session.state.place_id == LAYOUT.HAUNTED_ID else null
	rewards.set_location(site,haunted)
	if not active and _eligible(): rewards.collect_nearby()

var _site_outdoors := true

func _update_residency() -> void:
	var outdoors: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	var at: Vector3 = world.player.global_position if outdoors else session.return_point
	var distance := Vector2(at.x-LAYOUT.ORIGIN.x,at.z-LAYOUT.ORIGIN.z).length()
	var nearby: bool = session.state.region_id == "harbor" and distance < 170.0
	if nearby and not is_instance_valid(site):
		site = _prepared if is_instance_valid(_prepared) else SITE.new()
		_prepared = null
		world.add_child(site)
		# Parque montado com o jogador já dentro da casa (save no Umbra): também passa pela troca abaixo.
		_site_outdoors = true
	if is_instance_valid(site):
		site.visible = outdoors
		# PROCESS_MODE_DISABLED tira da física os corpos do parque, inclusive o chão. Dentro do Umbra a
		# volta (FullSession._clear_return_point) não achava piso no ponto de saída e recusava ("Passagem
		# ocupada"): o jogador ficava preso na casa (teste com janela, 28/10). Chão e paredes ficam na física.
		if not outdoors and _site_outdoors:
			for body in site.find_children("*","StaticBody3D",true,false):
				(body as StaticBody3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		_site_outdoors = outdoors
		site.process_mode = Node.PROCESS_MODE_INHERIT if outdoors else Node.PROCESS_MODE_DISABLED
		if not active and (session.state.region_id != "harbor" or distance > 220.0):
			rewards.set_location(null,null)
			site.queue_free()
			site = null

func nearest_action() -> Dictionary:
	if active: return {"id":"amusement_park","target":"leave","label":"Voltar à estação"}
	if not _eligible(): return {}
	var point: Vector3 = world.player.global_position
	if is_instance_valid(site) and session.state.place_id.is_empty():
		if point.distance_to(site.boarding_position()) < 1.8:
			return {"id":"amusement_park","target":"ride","label":"Andar na montanha-russa — $5"}
		if point.distance_to(LAYOUT.ORIGIN+Vector3(29,.08,20)) < 2.0:
			return {"id":"amusement_park","target":"wardrobe","label":"Trocar roupa e acessórios"}
		var purchase: Dictionary = vending.nearest_action()
		if not purchase.is_empty(): return purchase
	return {}

func _eligible() -> bool:
	if get_tree().paused or not session.ready_for_play or session.modal or session.is_transition_blocked(): return false
	if session.state.region_id != "harbor" or world.gameplay.health <= 0 or world.driving.occupied or world.player.input_locked: return false
	if session.skate != null and session.skate.controls_locked(): return false
	if session.motocross != null and session.motocross.mounted: return false
	if is_instance_valid(world.player.ski_controller) and world.player.ski_controller.skiing: return false
	return true

func perform(target: String) -> bool:
	if target.begins_with("vending:"):
		if not _eligible(): return false
		return vending.open(target.trim_prefix("vending:"))
	match target:
		"ride": return start_ride()
		"leave":
			if not active: return false
			request_exit()
			return true
		"wardrobe":
			if nearest_action().get("target","") != "wardrobe": return false
			rewards.open_wardrobe()
			return true
	return false

func start_ride() -> bool:
	if active or not _eligible() or not is_instance_valid(site) or not session.state.place_id.is_empty(): return false
	if world.player.global_position.distance_to(site.boarding_position()) > 1.8: return false
	if world.gameplay.stars > 0:
		session.show_message("Perca a polícia antes de embarcar.")
		return false
	if not _platform_clear(world.player.global_position):
		session.show_message("Aguarde liberar a plataforma de embarque.")
		return false
	if not session.state.economy.spend(RIDE_PRICE,"coaster:"+session._transaction()):
		session.show_message("Entrada: $5. Dinheiro insuficiente.")
		return false
	# Persiste o débito num checkpoint no chão, antes de os saves ficarem travados pelo brinquedo.
	session.save_game()
	_saved = {"point":world.player.global_position,"locked":world.player.input_locked,
		"physics":world.player.is_physics_processing(),"layer":world.player.collision_layer,
		"mask":world.player.collision_mask,"visible":world.player.visual.visible,
		"camera":get_viewport().get_camera_3d(),"mouse":Input.mouse_mode,
		"generation":session.transition_generation,"region":session.state.region_id,
		"heading":world.player.visual.rotation.y,"hud_visible":world.hud.visible}
	active = true
	ride_phase = "boarding"
	boarding_time = 0.0
	return_requested = false
	_exit_pending = false
	ride_distance = 0.0
	ride_speed = 0.0
	yaw = 0.0
	pitch = 0.0
	world.player.input_locked = true
	world.player.velocity = Vector3.ZERO
	world.player.set_physics_process(false)
	world.player.collision_layer = 0
	world.player.collision_mask = 0
	world.hud.hide()
	view = _new_camera("CoasterCamera",78.0)
	view.environment = _perspective_environment(false)
	_make_hint()
	_tick_ride(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _touch_interface() else Input.MOUSE_MODE_CAPTURED
	return true

func _tick_ride(delta: float) -> void:
	if _exit_pending:
		_exit_retry -= delta
		if _exit_retry <= 0.0: leave()
		return
	if ride_phase == "waiting":
		_exit_retry -= delta
		if _exit_retry <= 0.0:
			_exit_retry = .25
			if _platform_clear(_saved.point): _begin_disembark()
		return
	if ride_phase == "boarding" or ride_phase == "disembarking":
		var exiting := ride_phase == "disembarking"
		if not _platform_clear(_saved.point): return
		boarding_time = clampf(boarding_time+(-delta if exiting else delta),0,BOARDING.SECONDS)
		BOARDING.present(self,boarding_time,exiting,delta)
		if exiting and boarding_time <= 0.0:
			leave()
		elif not exiting and boarding_time >= BOARDING.SECONDS:
			ride_phase = "riding"
			world.player.visual.hide()
		return
	var pose: Transform3D = site.sample_coaster(ride_distance)
	var slope := (-pose.basis.z).y
	var target := clampf(11.0-slope*24.0,3.6,20.0)
	var remaining: float = site.coaster_length()-ride_distance
	if remaining < 18.0: target = minf(target,maxf(.65,sqrt(2.0*1.5*remaining)))
	ride_speed = move_toward(ride_speed,target,delta*3.0)
	ride_distance += delta*ride_speed
	if ride_distance >= site.coaster_length():
		_begin_disembark()
		return
	site.set_coaster_progress(ride_distance)
	pose = site.sample_coaster(ride_distance)
	world.player.global_position = pose.origin+pose.basis.y*.55
	view.global_transform = pose.translated_local(Vector3(0,1.15,-.35))
	view.basis = view.basis*Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)
	_gamepad_look(delta)

func request_exit() -> void:
	if not active or return_requested: return
	return_requested = true
	if ride_phase == "boarding":
		ride_phase = "disembarking"
	elif ride_phase == "riding":
		session.show_message("Retornando à estação.")

func _begin_disembark() -> void:
	_saved["ride_eye"] = view.global_transform
	ride_distance = 0.0
	ride_speed = 0.0
	site.set_coaster_progress(0)
	if not _platform_clear(_saved.point):
		ride_phase = "waiting"
		_exit_retry = .25
		session.show_message("Aguarde liberar a plataforma de desembarque.")
		return
	ride_phase = "disembarking"
	boarding_time = BOARDING.SECONDS

func _platform_clear(start: Vector3) -> bool:
	var dock: Transform3D = site.sample_coaster(0)
	var stand := Vector3(dock.origin.x+1.8,start.y,dock.origin.z+.35)
	# Checa a caminhada pública inteira, não só o spawn final. O portão aberto
	# fica excluído; o volume varrido dele fica reservado enquanto o passageiro está travado.
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = .32
	shape.height = 1.7
	query.shape = shape
	query.collision_mask = 7
	query.exclude = [world.player.get_rid(),site.gate_body.get_rid()]
	var space = world.get_world_3d().direct_space_state
	for i in 9:
		query.transform = Transform3D(Basis.IDENTITY,start.lerp(stand,i/8.0)+Vector3.UP*.9)
		if not space.intersect_shape(query,1).is_empty(): return false
	return session.position_clear(start)

func _ride_interrupted() -> bool:
	return not is_instance_valid(site) or world.gameplay.health <= 0 or session.rescue_pending or session.arrest_pending or session.transition_generation != int(_saved.get("generation",-1)) or session.state.region_id != str(_saved.get("region","")) or not session.state.place_id.is_empty()

func leave() -> void:
	if not active: return
	var player = world.player
	# Só o estado do nosso brinquedo é restaurado. Morte/resgate mantém a trava de entrada.
	var owns: bool = session.transition_generation == int(_saved.generation) and session.state.region_id == str(_saved.region) and session.state.place_id.is_empty()
	var destination: Vector3 = _saved.point
	if owns and world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending:
		destination = Vector3.INF
		for offset in [Vector3.ZERO,Vector3(0,0,1),Vector3(0,0,-1),Vector3(.8,0,0),Vector3(.8,0,1),Vector3(.8,0,-1)]:
			var candidate: Vector3 = _saved.point+offset
			if session.position_clear(candidate):
				destination = candidate
				break
		if not destination.is_finite():
			if not _exit_pending: session.show_message("Aguarde liberar a plataforma de desembarque.")
			_exit_pending = true
			_exit_retry = .25
			ride_distance = 0.0
			site.set_coaster_progress(0.0)
			var dock: Transform3D = site.sample_coaster(0.0)
			player.global_position = dock.origin+dock.basis.y*.55
			view.global_transform = dock.translated_local(Vector3(0,1.15,-.35))
			return
	active = false
	ride_phase = "idle"
	_exit_pending = false
	player.release_seated()
	if owns:
		player.teleport(destination)
		player.visual.rotation.y = float(_saved.heading)
	player.collision_layer = int(_saved.layer)
	player.collision_mask = int(_saved.mask)
	player.set_physics_process(bool(_saved.physics))
	player.visual.visible = bool(_saved.visible)
	world.hud.visible = bool(_saved.get("hud_visible",true))
	if owns and world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending:
		player.input_locked = bool(_saved.locked)
	player.velocity = Vector3.ZERO
	if is_instance_valid(site):
		site.set_coaster_progress(0.0)
		site.set_boarding_open(0)
	_restore_view(_saved)
	if is_instance_valid(_ride_hint): _ride_hint.queue_free()
	_ride_hint = null
	_saved.clear()

func _new_camera(id: String, fov_degrees: float) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = id
	camera.near = .06
	camera.far = 350.0
	camera.fov = fov_degrees
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	return camera

func _perspective_environment(indoor: bool) -> Environment:
	var source: Environment = world.production.environment.environment
	var environment: Environment = source.duplicate(true)
	if indoor:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("10141e")
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color("65758b")
		environment.ambient_light_energy = .055
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		environment.fog_enabled = false
	else:
		var sky := Sky.new()
		var material := ProceduralSkyMaterial.new()
		material.sky_horizon_color = source.background_color
		material.sky_top_color = source.background_color.darkened(.28)
		material.ground_horizon_color = source.background_color
		sky.sky_material = material
		sky.radiance_size = Sky.RADIANCE_SIZE_32
		environment.sky = sky
		environment.background_mode = Environment.BG_SKY
		environment.fog_depth_begin = 80.0
		environment.fog_depth_end = 320.0
	return environment

func _sync_house_view() -> void:
	var illusion: Variant = session.get("upside_world")
	if is_instance_valid(illusion) and illusion.busy():
		if house_view: _end_house_view()
		return
	var inside: bool = session.state.place_id == LAYOUT.HAUNTED_ID and is_instance_valid(session.room) and not session.is_transition_blocked() and world.gameplay.health > 0
	if inside and not house_view:
		_house_saved = {"camera":get_viewport().get_camera_3d(),"mouse":Input.mouse_mode,"visible":world.player.visual.visible,"player_camera":world.player.camera}
		house_view = true
		yaw = 0.0
		pitch = 0.0
		view = _new_camera("HauntedHouseCamera",72.0)
		view.environment = _perspective_environment(true)
		var torch := SpotLight3D.new()
		torch.name = "UmbraVisitorLight"
		torch.position = Vector3(.16,-.22,-.06)
		torch.light_color = Color("cabfaa")
		torch.light_energy = 1.35
		torch.spot_range = 10.0
		torch.spot_angle = 29.0
		torch.spot_attenuation = 1.3
		torch.shadow_enabled = true
		view.add_child(torch)
		world.player.camera = view
		world.player.visual.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif not inside and house_view:
		_end_house_view()

func _tick_house_view(delta: float) -> void:
	if not is_instance_valid(view): return
	view.global_position = world.player.global_position+Vector3.UP*1.65
	view.rotation = Vector3(pitch,yaw,0)
	if not session.modal and not get_tree().paused: _gamepad_look(delta)
	if not session.modal and session.room.model.has_method("update_visitor"):
		session.room.model.update_visitor(session.room.to_local(world.player.global_position),delta)
	# Menus e pausa mantêm o cursor; restaura a captura ao voltar à exploração.
	if session.modal or get_tree().paused: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _end_house_view() -> void:
	if not house_view: return
	house_view = false
	world.player.camera = _house_saved.get("player_camera",world.camera)
	world.player.visual.visible = bool(_house_saved.get("visible",true))
	_restore_view(_house_saved)
	_house_saved.clear()

func _restore_view(saved: Dictionary) -> void:
	Input.mouse_mode = int(saved.get("mouse",Input.MOUSE_MODE_VISIBLE)) as Input.MouseMode
	if is_instance_valid(view): view.queue_free()
	view = null
	var old = saved.get("camera")
	if is_instance_valid(old): old.make_current()
	else: world.camera.make_current()
	world.camera.initialized = false

func _gamepad_look(delta: float) -> void:
	if (not active and not house_view) or session.modal or get_tree().paused: return
	var controls = get_node_or_null("/root/GameInput")
	if controls == null: return
	var stick: Vector2 = controls.touch_aim
	if stick.is_zero_approx() and controls.using_gamepad:
		stick = controls._read_aim_stick()
		var strength := minf(stick.length(),1.0)
		var deadzone: float = controls.AIM_STICK_DEADZONE
		if strength <= deadzone: return
		stick = stick.normalized()*(strength-deadzone)/(1.0-deadzone)
	if not stick.is_zero_approx(): look_delta(stick.limit_length()*delta*1.8)

func look_delta(motion: Vector2) -> void:
	yaw -= motion.x
	if active: yaw = clampf(yaw,-1.25,1.25)
	pitch = clampf(pitch-motion.y,-1.0,.8)

func handle_input(event: InputEvent) -> bool:
	if not active and not house_view: return false
	if event.is_action_pressed("pause_game"):
		if active: leave()
		elif house_view: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return false
	if get_tree().paused or session.modal: return false
	if active and _ride_gui_event(event): return false
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return false
	if event.is_echo(): return active
	if active and (event.is_action_pressed("interact") or event.is_action_pressed("exit_vehicle") or event.is_action_pressed("ui_cancel")):
		request_exit()
		return true
	if event is InputEventMouseMotion:
		look_delta(event.relative*.002)
		return true
	if event is InputEventScreenDrag:
		# A camada é dona de todo o tempo de vida de dedos que começaram nos controles.
		# Cede o arrasto deles mesmo quando o FullSession recebe a entrada antes da camada.
		var touch: Node = world.find_child("AndroidControls",true,false)
		if is_instance_valid(touch) and touch.fingers.has(event.index): return false
		look_delta(event.relative*.003)
		return true
	return active and not (event is InputEventScreenTouch)

func _make_hint() -> void:
	_ride_touch_fingers.clear()
	_ride_hint = CanvasLayer.new()
	_ride_hint.layer = 80
	add_child(_ride_hint)
	var controls = get_node_or_null("/root/GameInput")
	if _touch_interface():
		# Entrar no brinquedo trava o pedestre. Atualiza agora, em vez de depois do
		# timer da camada, para soltar os analógicos e ligar a emulação nativa de botões.
		var touch: Node = world.find_child("AndroidControls",true,false)
		if is_instance_valid(touch): touch._refresh()
		var button := Button.new()
		button.name = "RideExitButton"
		button.text = "Voltar à estação"
		button.position = Vector2(525,630)
		button.custom_minimum_size = Vector2(230,48)
		button.pressed.connect(request_exit)
		_ride_hint.add_child(button)
	else:
		var label := Label.new()
		label.name = "RideExitHint"
		var keys: String = "E" if controls == null else controls.prompt("interact")
		label.text = keys + " — voltar à estação"
		label.position = Vector2(380,630)
		label.custom_minimum_size = Vector2(520,48)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",20)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ride_hint.add_child(label)

func _touch_interface() -> bool:
	var controls := get_node_or_null("/root/GameInput")
	return OS.has_feature("android") or (controls != null and controls.get_meta("touch_controls_active",false))

func _ride_gui_event(event: InputEvent) -> bool:
	if not is_instance_valid(_ride_hint): return false
	var button := _ride_hint.get_node_or_null("RideExitButton") as Button
	if not is_instance_valid(button): return false
	if event is InputEventScreenTouch:
		var owned := _ride_touch_fingers.has(event.index)
		if event.pressed and not event.canceled and button.get_global_rect().has_point(event.position):
			_ride_touch_fingers[event.index] = true
			return true
		if not event.pressed or event.canceled: _ride_touch_fingers.erase(event.index)
		return owned
	if event is InputEventScreenDrag: return _ride_touch_fingers.has(event.index)
	if event is InputEventMouse: return button.get_global_rect().has_point(event.position)
	return false

func _exit_tree() -> void:
	if is_instance_valid(life): life.clear()
	if is_instance_valid(world):
		leave()
		_end_house_view()
	if is_instance_valid(site): site.queue_free()
	if is_instance_valid(_prepared): _prepared.free()

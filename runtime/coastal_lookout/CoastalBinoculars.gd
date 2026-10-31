extends Node
## A luneta fixa de observação pega a entrada emprestada, nunca a posição do jogador nem o save.
## O FullSession roteia a ação/entrada dela e a cancela antes de uma transição de posição.
const OVERLAY := preload("res://runtime/coastal_lookout/BinocularOverlay.gd")
const ACTIVE_META := &"coastal_binoculars_active"
const INTERACTION_RADIUS := 1.5
const MAX_YAW := deg_to_rad(52.0)
const MIN_PITCH := deg_to_rad(-24.0)
const MAX_PITCH := deg_to_rad(24.0)
const FOV_WIDE := 46.0
const FOV_CLOSE := 12.0
var world
var lookout: Node3D
var active := false
var optical_camera: Camera3D
var overlay: CanvasLayer
var yaw := 0.0
var pitch := 0.0
var _base_basis := Basis.IDENTITY
var _saved: Dictionary = {}
var _clock := 0.0
var _sky_clock := 0.0
var _sky_material: ProceduralSkyMaterial

func configure(owner_world, place: Node3D) -> void:
	leave()
	world = owner_world
	lookout = place
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func nearest_action() -> Dictionary:
	if active: return {"id":"coastal_binoculars", "target":"leave", "label":"Sair do binóculo"}
	if not _eligible(): return {}
	return {"id":"coastal_binoculars", "target":"view", "label":"Usar binóculo"}

func perform(target := "view") -> bool:
	if target == "leave":
		if not active: return false
		leave()
		return true
	return enter() if target == "view" else false

func _eligible() -> bool:
	if active or not is_instance_valid(world) or not is_instance_valid(lookout): return false
	if get_tree().paused or not lookout.is_visible_in_tree(): return false
	var session = world.session
	if session == null or not session.ready_for_play or session.modal or session.is_transition_blocked(): return false
	if not session.state.place_id.is_empty() or session.state.region_id != "harbor": return false
	if world.driving.occupied or world.player.input_locked or world.gameplay.health <= 0: return false
	if not session.rebinding_action.is_empty() or session.blocks_driving_change(): return false
	if is_instance_valid(world.player.ski_controller) and world.player.ski_controller.skiing: return false
	return world.player.global_position.distance_to(lookout.binocular_interaction_position()) <= INTERACTION_RADIUS

func enter() -> bool:
	if not _eligible(): return false
	var session = world.session
	_saved = {"camera":get_viewport().get_camera_3d(), "camera_locked":world.camera.locked,
		"player_locked":world.player.input_locked, "mouse":Input.mouse_mode,
		"hud_visible":world.hud.visible, "visual_visible":world.player.visual.visible,
		"generation":session.transition_generation, "region":session.state.region_id,
		"health":world.gameplay.health}
	active = true
	world.player.set_meta(ACTIVE_META, get_instance_id())
	world.player.input_locked = true
	world.player.velocity.x = 0.0
	world.player.velocity.z = 0.0
	world.player.visual.hide()
	world.camera.locked = true
	world.hud.hide()
	optical_camera = Camera3D.new()
	optical_camera.name = "CoastalBinocularCamera"
	# A cabeça óptica é atualizada no tempo de render; a interpolação de física herdada
	# interpolaria um ponto de vista que, fora isso, é parado depois do movimento do mouse.
	optical_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	optical_camera.near = 0.08
	optical_camera.far = 3500.0
	optical_camera.fov = FOV_WIDE
	optical_camera.cull_mask = world.camera.cull_mask
	optical_camera.environment = _optical_environment()
	add_child(optical_camera)
	optical_camera.global_position = lookout.binocular_eye_position()
	optical_camera.look_at(lookout.binocular_target_position(), Vector3.UP)
	_base_basis = optical_camera.global_basis
	yaw = 0.0
	pitch = 0.0
	optical_camera.make_current()
	overlay = OVERLAY.new()
	overlay.controller = self
	add_child(overlay)
	var controls = get_node_or_null("/root/GameInput")
	var touch: bool = OS.has_feature("android") or (controls != null and controls.get_meta("touch_controls_active",false))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if touch else Input.MOUSE_MODE_CAPTURED
	set_process(true)
	return true

func handle_input(event: InputEvent) -> bool:
	if not active: return false
	if get_tree().paused:
		leave()
		return false
	# GUI Buttons need touch-generated mouse events, while raw screen drags own
	# the optical pan. Consuming emulation here swallowed every touch button.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return false
	# Manter a tecla de interação apertada não pode sair na hora pela repetição do SO.
	if event.is_echo(): return true
	if event.is_action_pressed("pause_game"):
		# Solta primeiro; o PauseInput normal ainda recebe este mesmo evento.
		leave()
		return false
	if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("exit_vehicle"):
		leave()
		return true
	if event is InputEventMouseMotion:
		look_delta(event.relative * 0.0018 * optical_camera.fov / FOV_WIDE)
	elif event is InputEventScreenDrag:
		look_delta(event.relative * 0.003 * optical_camera.fov / FOV_WIDE)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: adjust_zoom(-4.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: adjust_zoom(4.0)
	elif event is InputEventKey and event.pressed:
		if event.physical_keycode in [KEY_EQUAL, KEY_KP_ADD]: adjust_zoom(-4.0)
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]: adjust_zoom(4.0)
	# Os botões de toque da camada óptica precisam do evento cru do dedo.
	if event is InputEventScreenTouch: return false
	return true

func look_delta(value: Vector2) -> void:
	if not active: return
	yaw = clampf(yaw - value.x, -MAX_YAW, MAX_YAW)
	pitch = clampf(pitch - value.y, MIN_PITCH, MAX_PITCH)
	optical_camera.global_basis = Basis(Vector3.UP, yaw) * _base_basis * Basis(Vector3.RIGHT, pitch)
	if lookout.has_method("set_binocular_angles"): lookout.set_binocular_angles(yaw, pitch)

func adjust_zoom(amount: float) -> void:
	if active: optical_camera.fov = clampf(optical_camera.fov + amount, FOV_CLOSE, FOV_WIDE)

func _process(delta: float) -> void:
	if not active: return
	if _interrupted():
		leave()
		return
	var controls = get_node_or_null("/root/GameInput")
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if controls != null:
		if controls.using_gamepad:
			var stick: Vector2 = controls._read_aim_stick()
			if stick.length() > 0.18: direction = stick
		if not controls.touch_aim.is_zero_approx(): direction = controls.touch_aim
	look_delta(direction * delta * 0.6 * optical_camera.fov / FOV_WIDE)
	# O zoom pelo gatilho também funciona sem adicionar ligações ao mapa de entrada persistente.
	if controls != null and controls.using_gamepad:
		adjust_zoom((Input.get_action_strength("fire") - Input.get_action_strength("aim")) * delta * 20.0)
	_clock += delta
	_sky_clock += delta
	if _sky_clock >= 1.0:
		_sky_clock = 0.0
		_refresh_sky()
	if _clock >= 0.1:
		_clock = 0.0
		overlay.update_readout(FOV_WIDE / optical_camera.fov)

func _environment_source() -> Environment:
	if is_instance_valid(world.camera.environment): return world.camera.environment
	if &"production" in world and is_instance_valid(world.production) and is_instance_valid(world.production.environment):
		return world.production.environment.environment
	return null

func _optical_environment() -> Environment:
	var source := _environment_source()
	var result: Environment = source.duplicate(true) if source != null else Environment.new()
	# A perspectiva precisa de um horizonte; o mundo ortográfico usa só uma cor chapada.
	# Este céu local à câmera preserva a iluminação do mundo e nunca edita o estado do Weather.
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_curve = 0.18
	_sky_material.ground_curve = 0.18
	_sky_material.sun_angle_max = 4.0
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.sky_material = _sky_material
	result.sky = sky
	result.background_mode = Environment.BG_SKY
	_color_sky(source.background_color if source != null else Color("829da6"))
	_panorama_fog(result)
	return result

func _color_sky(horizon: Color) -> void:
	_sky_material.sky_top_color = horizon.darkened(0.38)
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	_sky_material.ground_bottom_color = horizon.darkened(0.65)

func _refresh_sky() -> void:
	var source := _environment_source()
	if source == null or _sky_material == null or not is_instance_valid(optical_camera): return
	var env := optical_camera.environment
	_color_sky(source.background_color)
	for property in ["ambient_light_color", "ambient_light_energy", "fog_enabled", "fog_light_color", "fog_light_energy", "fog_density", "fog_sky_affect"]:
		env.set(property, source.get(property))
	_panorama_fog(env)

func _panorama_fog(env: Environment) -> void:
	# A névoa de profundidade de 18–75 m do Harbor foi escrita para a câmera de rua vista de cima.
	# A câmera óptica observa quilômetros de costa: mantém a mesma névoa,
	# tom e iluminação, mas escala só a faixa de profundidade para o panorama.
	# O clima continua visível; chuva/tempestade/noite ainda encurtam a visibilidade óptica.
	var weather_state := 0
	var daylight := 1.0
	var session = world.session
	if session != null and &"weather" in session and is_instance_valid(session.weather):
		weather_state = session.weather.weather_state
		daylight = preload("res://runtime/atmosphere/RegionalAtmosphere3D.gd").daylight_at(session.weather.time_of_day)
	var ranges: Vector2 = {0:Vector2(150,2400), 1:Vector2(85,1400), 2:Vector2(50,850), 3:Vector2(115,1900)}.get(weather_state,Vector2(150,2400))
	var night_scale := lerpf(0.75,1.0,daylight)
	env.fog_depth_begin = ranges.x * night_scale
	env.fog_depth_end = ranges.y * night_scale

func _interrupted() -> bool:
	if not is_instance_valid(world) or not is_instance_valid(lookout): return true
	var session = world.session
	if session == null or get_tree().paused or not session.ready_for_play: return true
	if session.modal or session.is_transition_blocked() or not session.state.place_id.is_empty(): return true
	if session.transition_generation != int(_saved.generation) or session.state.region_id != str(_saved.region): return true
	if world.driving.occupied or world.gameplay.health < float(_saved.health) or world.gameplay.health <= 0: return true
	if not session.rebinding_action.is_empty(): return true
	if not is_instance_valid(optical_camera) or not optical_camera.current: return true
	if not lookout.is_visible_in_tree(): return true
	return world.player.global_position.distance_to(lookout.binocular_interaction_position()) > INTERACTION_RADIUS + 0.75

func leave() -> void:
	if not active: return
	active = false
	set_process(false)
	if is_instance_valid(world):
		var session = world.session
		var other_owner: bool = session != null and (session.modal or session.is_transition_blocked() or world.gameplay.health <= 0)
		if is_instance_valid(world.player):
			if world.player.get_meta(ACTIVE_META, 0) == get_instance_id():
				world.player.remove_meta(ACTIVE_META)
				if not other_owner: world.player.input_locked = bool(_saved.player_locked)
			if is_instance_valid(world.player.visual): world.player.visual.visible = bool(_saved.visual_visible)
		if is_instance_valid(world.camera): world.camera.locked = bool(_saved.camera_locked)
		if is_instance_valid(world.hud): world.hud.visible = bool(_saved.hud_visible)
		if get_tree().paused or (session != null and session.modal): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif not other_owner: Input.mouse_mode = _saved.mouse
	if is_instance_valid(optical_camera):
		var previous = _saved.get("camera")
		if optical_camera.current and is_instance_valid(previous): previous.make_current()
		optical_camera.queue_free()
	optical_camera = null
	_sky_material = null
	if is_instance_valid(overlay): overlay.queue_free()
	overlay = null
	if is_instance_valid(lookout) and lookout.has_method("set_binocular_angles"): lookout.set_binocular_angles(0.0, 0.0)
	_saved.clear()

func _exit_tree() -> void:
	leave()

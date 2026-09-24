extends CharacterBody2D
signal bench_rest_started(resident: Node, seat: Node2D)
signal bench_rest_finished(resident: Node, completed: bool)
var resident_name := "NORA"
var coat_color := Color("3c6872")
var role := "ranger"
var lines: Array[String] = ["O vento muda rápido. Leve um casaco."]
var home := Vector2.ZERO
var destination := Vector2.ZERO
var health := 80
var is_dead := false
var fall_presentation := preload("res://characters/CharacterFallPresentation.gd").new()
var viewport: SubViewport
var model: Node3D
var speech: Label
var speech_panel: PanelContainer
var prompt_badge: Label
var is_stationary: bool = false
var dialogue_index: int = 0
var presentation_sprite: Sprite2D
var presentation_camera: Camera3D
var _sprite_origin := Vector2.ZERO
var elapsed := 0.0
var next_line := 4.0
var speech_until := 0.0
var render_clock := 0.0
var danger_response := preload("res://characters/PedestrianDanger.gd").new()
var panic_timer := 0.0
var appearance_variant := -1
var _routine_pause := 0.0
var retaliation_target: Node2D
var retaliation_left := 0.0
var axe_cooldown := 0.0
var axe_windup := 0.0
var work_station: Node2D
var _logger_work := preload("res://world/mountain_pass/LoggerWorkRoutine.gd").new()
var _return_to_work := false
var activity := "idle"
var activity_left := 0.0
var routine_cycle := 0
var conversation_partner: Node2D
var travel_time := 0.0
var _navigation := preload("res://emergency/ResponderNavigation.gd").new()
var _bench_rest := preload("res://world/mountain_pass/MountainBenchRest.gd").new()

func hear_gunfire(origin: Vector2, end: Vector2) -> void:
	if is_dead: return
	if role == "logger":
		var attacker: Variant = get_meta("combat_attacker", null)
		if is_instance_valid(attacker) and attacker is Node2D and attacker != self:
			retaliation_target = attacker
			retaliation_left = 12.0
			_bench_rest.interrupt()
			return
	danger_response.remember(origin, end)
	panic_timer = randf_range(9.0, 12.0)
	_bench_rest.interrupt()

func _process_danger(delta: float) -> bool:
	if is_dead or panic_timer <= 0.0: return false
	panic_timer -= delta
	model.activity = "idle"
	activity = "idle"
	activity_left = 2.0
	speech.text = ""
	velocity = danger_response.movement(self, delta, 95.0)
	preload("res://characters/pedestrians/PersonMotion.gd").move_actor(self)
	model.walking = velocity.length() > 1.0
	if model.walking: model.rotation.y = lerp_angle(model.rotation.y, -velocity.angle() + PI * 0.5, minf(1.0, delta * 9.0))
	model.motion_speed = velocity.length()
	render_clock += delta
	if render_clock >= _visual_interval():
		model._process(render_clock)
		render_clock = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func _ready() -> void:
	add_to_group("pedestrian")
	add_to_group("damageable")
	add_to_group("winter_resident")
	collision_layer = 4
	collision_mask = 7
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	z_index = 9
	home = global_position
	destination = home + Vector2(35,0)
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	collision.shape.radius = 7
	add_child(collision)
	viewport = SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	preload("res://characters/pedestrians/WinterWardrobe.gd").light_viewport(viewport)
	model = _create_model()
	model.coat_color = coat_color
	model.role = role
	if appearance_variant < 0: appearance_variant = posmod(resident_name.hash(),120)
	model.appearance_variant = appearance_variant
	var first_name := resident_name.get_slice("/",0).strip_edges().to_upper()
	model.appearance_female = first_name in ["NORA","MARA","LIA","INÊS","HELENA","RUTE","ÍRIS","DORA","ANA","MILA","LUÍSA","CECÍLIA"]
	_navigation.search_budget = 32
	_navigation.retry_delay = 2.0
	viewport.add_child(model)
	model.set_process(false)
	var camera := Camera3D.new()
	presentation_camera=camera
	viewport.add_child(camera)
	camera.position = Vector3(0,4,3)
	camera.look_at(Vector3(0,0.9,0))
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.reset_physics_interpolation()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-25,0)
	sun.light_energy = 1.5
	viewport.add_child(sun)
	preload("res://systems/ContactShadow.gd").add_person(viewport)
	var sprite := Sprite2D.new()
	presentation_sprite=sprite
	sprite.texture = viewport.get_texture()
	# Tamanho aparente compatível com os NPCs urbanos, mantendo o apoio dos pés.
	sprite.scale = Vector2.ONE * (13.0 * 2.6/128.0)
	sprite.position = (Vector2(64,64)-camera.unproject_position(Vector3.ZERO)) * sprite.scale
	_sprite_origin=sprite.position
	add_child(sprite)
	speech = Label.new()
	speech.position = Vector2(-105,-58)
	speech.size.x = 210
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech.add_theme_font_size_override("font_size",12)
	speech.add_theme_color_override("font_shadow_color",Color.BLACK)
	speech.add_theme_constant_override("shadow_offset_x",1)
	speech.add_theme_constant_override("shadow_offset_y",1)
	speech_panel = PanelContainer.new()
	speech_panel.position = Vector2(-112,-64)
	speech_panel.size = Vector2(224,48)
	speech_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bubble := StyleBoxFlat.new()
	bubble.bg_color = Color(0.035,0.06,0.08,0.88)
	bubble.border_color = Color(0.55,0.72,0.76,0.7)
	bubble.set_border_width_all(1)
	bubble.set_corner_radius_all(6)
	bubble.content_margin_left = 7
	bubble.content_margin_right = 7
	bubble.content_margin_top = 4
	bubble.content_margin_bottom = 4
	speech_panel.add_theme_stylebox_override("panel", bubble)
	speech_panel.add_child(speech)
	add_child(speech_panel)
	speech_panel.hide()

	prompt_badge = Label.new()
	prompt_badge.name = "PromptBadge"
	prompt_badge.text = ""
	prompt_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_badge.position = Vector2(-25, -46)
	prompt_badge.size = Vector2(50, 18)
	prompt_badge.add_theme_font_size_override("font_size", 11)
	prompt_badge.add_theme_color_override("font_color", Color("#f1c40f"))
	prompt_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_badge.add_theme_constant_override("shadow_offset_x", 1)
	prompt_badge.add_theme_constant_override("shadow_offset_y", 1)
	prompt_badge.hide()
	add_child(prompt_badge)

	_bench_rest.configure(self)
	_logger_work.configure(self)
	activity_left = 2.0 + appearance_variant % 9
	model.clock = float(appearance_variant) * 0.73
	if role == "logger":
		var block := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
		work_station = block
		block.name = "FirewoodWorkstation"
		get_parent().add_child.call_deferred(block)
		block.position = position + Vector2(0,10)
		block.z_index = z_index
		block.ready.connect(func():
			block.build_view(preload("res://world/mountain_pass/LoggerWorkBlock.gd"),2.6,13.0,Vector3(0,.5,0),Vector3(0,3.1,3),Vector2i(192,192))
			block.add_solid(Rect2(-.30,-.30,.60,.60),"SolidChoppingBlock")
			block.add_solid(Rect2(.20,.76,.60,.48),"SolidFirewoodPile")
		)
		# Include the raised axe and the workpiece without changing world scale.
		viewport.size = Vector2i(192,192)
		camera.size = 3.4
		sprite.scale = Vector2.ONE*(13.0*3.4/192.0)
		sprite.position = (Vector2(96,96)-camera.unproject_position(Vector3.ZERO))*sprite.scale
		_sprite_origin = sprite.position

func request_bench_rest(max_distance:float=230.0,scope:String="") -> bool:
	if is_stationary or get_parent() == null or not is_inside_tree(): return false
	return _bench_rest.request(max_distance,scope)

func bench_state() -> String:
	return _bench_rest.state

func align_bench_presentation(amount:float,offset:Vector2,height:float) -> void:
	if presentation_sprite==null or presentation_camera==null:return
	if amount<=0.0:
		presentation_sprite.position=_sprite_origin
		return
	if not presentation_camera.is_inside_tree():return
	var projected_height:Vector2=(presentation_camera.unproject_position(Vector3(0,height,0))-presentation_camera.unproject_position(Vector3.ZERO))*presentation_sprite.scale
	presentation_sprite.position=_sprite_origin+(offset-projected_height)*amount

func _process_bench_rest(delta:float) -> bool:
	if _bench_rest.state!="idle" and panic_timer>0.0:_bench_rest.interrupt()
	if not _bench_rest.update(delta):return false
	model.activity = "drink" if _bench_rest.state == "resting" else "idle"
	_refresh_resident_visual(delta)
	return true

func _refresh_resident_visual(delta:float) -> void:
	render_clock+=delta
	if render_clock>=_visual_interval():
		model._process(render_clock)
		render_clock=0.0
		var player:=get_tree().get_first_node_in_group("player") as Node2D
		if player==null or global_position.distance_to(player.global_position)<1100:
			viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _physics_process(delta: float) -> void:
	if role == "logger" and (activity != "work" or is_dead or retaliation_left > 0.0 or panic_timer > 0.0 or _bench_rest.state != "idle"):
		_logger_work.stop()
	if is_dead:
		fall_presentation.update(delta)
		return
	if _process_retaliation(delta): return
	if _process_bench_rest(delta):return
	if _process_danger(delta): return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(global_position) > 750 or is_dead:
		prompt_badge.hide()
		return
	elapsed += delta
	if speech_until > 0.0:
		speech_until -= delta
		if speech_until <= 0.0:
			speech.text = ""
			speech_panel.hide()
	var is_near := _can_interact(player)
	if is_instance_valid(prompt_badge):
		prompt_badge.visible = is_near and speech_until <= 0.0
	if is_near and Input.is_action_just_pressed("interact") and not lines.is_empty():
		_interact_talk(player)
	activity_left -= delta
	if is_stationary:
		activity = "idle"
		velocity = Vector2.ZERO
	elif activity == "talk" and (not is_instance_valid(conversation_partner) or conversation_partner.is_dead or conversation_partner.panic_timer > 0.0 or global_position.distance_to(conversation_partner.global_position) > 85):
		if speech_until <= 0.0:
			activity_left = 0.0
	if not is_stationary and activity_left <= 0.0:
		if activity == "work" and _logger_work.working and fposmod(_logger_work.time,3.2) < 2.7:
			activity_left = .02 # Recover the tool before leaving the block.
		else:
			_choose_activity()
	velocity = Vector2.ZERO
	if activity == "walk":
		travel_time += delta
		var distance := global_position.distance_to(destination)
		velocity = _navigation.movement(self,destination,minf(20.0 + appearance_variant % 8, distance * 1.8),delta)
		preload("res://characters/pedestrians/PersonMotion.gd").move_actor(self)
		if distance < .4 and role == "logger" and _return_to_work:
			activity = "work"
			_return_to_work = false
			activity_left = randf_range(12.0,22.0)
			velocity = Vector2.ZERO
		elif (distance < 5.0 and not _return_to_work) or travel_time > 12.0: activity_left = 0.0
	elif activity == "talk" and is_instance_valid(conversation_partner):
		var direction := conversation_partner.global_position - global_position
		model.rotation.y = lerp_angle(model.rotation.y,-direction.angle()+PI*0.5,delta*3.0)
	elif activity == "talk" and speech_until > 0.0 and is_instance_valid(player):
		var direction := player.global_position - global_position
		model.rotation.y = lerp_angle(model.rotation.y,-direction.angle()+PI*0.5,delta*5.0)
	elif activity == "work":
		_logger_work.update(delta)
	if activity != "work" and role == "logger": _logger_work.stop()
	if velocity.length() > 1: model.rotation.y = lerp_angle(model.rotation.y,-velocity.angle()+PI*0.5,delta*4.0)
	model.walking = velocity.length() > 1
	model.activity = activity
	model.motion_speed = velocity.length()
	render_clock += delta
	if render_clock >= _visual_interval():
		model._process(render_clock)
		render_clock = 0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _interact_talk(target_player: Node2D) -> void:
	if not _can_interact(target_player): return
	get_tree().set_meta("winter_dialogue_frame", Engine.get_process_frames())
	if role == "logger": _logger_work.stop()
	var dir := target_player.global_position - global_position
	if dir.length_squared() > 1.0:
		model.rotation.y = -dir.angle() + PI * 0.5
	speech.text = lines[dialogue_index % lines.size()]
	dialogue_index += 1
	speech_panel.show()
	speech_until = 4.5
	activity = "talk"
	activity_left = 4.5
	velocity = Vector2.ZERO

func _choose_activity() -> void:
	_return_to_work = false
	if is_stationary:
		activity = "idle"
		activity_left = 10.0
		return
	routine_cycle += 1
	conversation_partner = null
	activity_left = randf_range(9.0,18.0)
	if routine_cycle % 4 == 0 and _bench_rest.cooldown <= 0.0 and request_bench_rest():
		activity = "idle"
		return
	if routine_cycle % 3 == 0:
		for other in get_tree().get_nodes_in_group("winter_resident"):
			if other == self or other.get_script() != get_script() or other.is_dead or other.panic_timer > 0.0 or other.bench_state() != "idle" or other.activity in ["talk","work"]: continue
			var distance := global_position.distance_to(other.global_position)
			if distance < 28.0 or distance > 85.0: continue
			var ray := PhysicsRayQueryParameters2D.create(global_position,other.global_position,1)
			if not get_world_2d().direct_space_state.intersect_ray(ray).is_empty(): continue
			conversation_partner = other
			other.conversation_partner = self
			other.activity = "talk"
			other.activity_left = activity_left
			activity = "talk"
			return
	if routine_cycle % 5 == 0:
		activity = "drink"
	elif role == "logger" and routine_cycle % 2 == 1:
		if is_instance_valid(work_station):
			activity = "walk"
			destination = _logger_work.choose_position()
			_return_to_work = true
	elif routine_cycle % 2 == 0:
		activity = "walk"
		var angle := randf_range(0.0,TAU)
		destination = home + Vector2.from_angle(angle)*randf_range(22.0,48.0)
	else:
		activity = "drink" if routine_cycle % 4 == 1 else "warm"
	travel_time = 0.0

func take_damage(amount: int, _source: Variant = null) -> void:
	if is_dead or amount <= 0: return
	if _bench_rest.state!="idle":
		_bench_rest.interrupt()
		panic_timer=maxf(panic_timer,6.0)
	health -= amount
	if role == "logger":
		var attacker: Variant = get_meta("combat_attacker", null)
		if is_instance_valid(attacker) and attacker is Node2D:
			retaliation_target = attacker
			retaliation_left = 14.0
	preload("res://guns/combat/GroundBlood.gd").spawn(self, health <= 0)
	var effects := get_tree().get_first_node_in_group("weapon_effects")
	if effects: effects.spawn_blood(global_position, velocity.normalized(), float(amount))
	panic_timer = maxf(panic_timer, 6.0)
	if health <= 0:
		is_dead = true
		_bench_rest.release(false)
		velocity = Vector2.ZERO
		fall_presentation.start(self, model, viewport)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		speech.text = ""
		collision_layer = 0

func _create_model() -> Node3D:
	return preload("res://world/mountain_pass/WinterResidentModel.gd").new()

func _exit_tree() -> void:
	_logger_work.stop()
	_bench_rest.release(false,false)

func _process_retaliation(delta: float) -> bool:
	if role != "logger" or retaliation_left <= 0.0: return false
	retaliation_left -= delta
	axe_cooldown = maxf(0.0, axe_cooldown - delta)
	if not is_instance_valid(retaliation_target) or retaliation_target.get("is_dead") == true or not retaliation_target.is_visible_in_tree() or retaliation_target.get_meta("mountain_interior", false) or global_position.distance_to(home) > 350.0:
		retaliation_left = 0.0
		axe_windup = 0.0
		activity_left = 0.0
		return false
	panic_timer = 0.0
	speech_panel.hide()
	var distance := global_position.distance_to(retaliation_target.global_position)
	model.rotation.y = lerp_angle(model.rotation.y, -global_position.direction_to(retaliation_target.global_position).angle() + PI * 0.5, minf(1.0, delta * 9.0))
	velocity = Vector2.ZERO
	model.activity = "attack" if axe_windup > 0.0 else "angry"
	if axe_windup > 0.0:
		axe_windup -= delta
		if axe_windup <= 0.0:
			var ray := PhysicsRayQueryParameters2D.create(global_position, retaliation_target.global_position, 3, [get_rid()])
			var obstruction := get_world_2d().direct_space_state.intersect_ray(ray)
			if distance <= 44.0 and (obstruction.is_empty() or obstruction.collider == retaliation_target):
				retaliation_target.set_meta("combat_attacker", self)
				var health_before: int = retaliation_target.health
				# NPC damage is balanced separately from the player's axe.
				var axe_dmg: int = 28
				retaliation_target.take_damage(axe_dmg)
				if retaliation_target.health < health_before:
					preload("res://guns/combat/BodyWound.gd").apply(retaliation_target)
	elif distance <= 38.0 and axe_cooldown <= 0.0:
		axe_windup = 0.38
		axe_cooldown = 1.15
		model.attack_age = 0.0
	else:
		if distance > 30.0: velocity = _navigation.movement(self, retaliation_target.global_position, 105.0, delta)
		preload("res://characters/pedestrians/PersonMotion.gd").move_actor(self)
	model.walking = velocity.length() > 1.0
	model.motion_speed = velocity.length()
	_refresh_resident_visual(delta)
	return true

func _visual_interval() -> float:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	return 1.0 / 60.0 if player != null and global_position.distance_squared_to(player.global_position) < 160000.0 else 1.0 / 30.0

func _can_interact(player: Node2D) -> bool:
	if not is_instance_valid(player) or not player.is_visible_in_tree() or is_dead or lines.is_empty(): return false
	if player.get("is_dead") == true or player.get("is_recovering") == true or player.get("is_control_disabled") == true or player.get("is_in_dialogue") == true: return false
	if player.has_meta("mountain_lift_riding"): return false
	if get_tree().get_meta("winter_dialogue_frame", -1) == Engine.get_process_frames(): return false
	var distance := global_position.distance_squared_to(player.global_position)
	if distance > 65.0 * 65.0: return false
	var query := PhysicsRayQueryParameters2D.create(player.global_position, global_position, 1)
	query.exclude = [get_rid(), player.get_rid()]
	if not get_world_2d().direct_space_state.intersect_ray(query).is_empty(): return false
	for other in get_tree().get_nodes_in_group("winter_resident"):
		if other == self or other.is_dead or not other.is_visible_in_tree() or other.lines.is_empty(): continue
		var other_distance: float = other.global_position.distance_squared_to(player.global_position)
		if other_distance > distance: continue
		if is_equal_approx(other_distance,distance) and other.get_instance_id() > get_instance_id(): continue
		query.to = other.global_position
		query.exclude = [other.get_rid(),player.get_rid()]
		if get_world_2d().direct_space_state.intersect_ray(query).is_empty(): return false
	return true

extends CharacterBody2D
var resident_name := "NORA"
var coat_color := Color("3c6872")
var role := "ranger"
var lines: Array[String] = ["O vento muda rápido. Leve um casaco."]
var home := Vector2.ZERO
var destination := Vector2.ZERO
var health := 80
var is_dead := false
var fall_presentation := preload("res://CharacterFallPresentation.gd").new()
var viewport: SubViewport
var model: Node3D
var speech: Label
var elapsed := 0.0
var next_line := 4.0
var speech_until := 0.0
var render_clock := 0.0
var danger_response := preload("res://PedestrianDanger.gd").new()
var panic_timer := 0.0
var appearance_variant := -1
var _routine_pause := 0.0
var _navigation := preload("res://ResponderNavigation.gd").new()

func hear_gunfire(origin: Vector2, end: Vector2) -> void:
	if is_dead: return
	danger_response.remember(origin, end)
	panic_timer = randf_range(9.0, 12.0)

func _process_danger(delta: float) -> bool:
	if is_dead or panic_timer <= 0.0: return false
	panic_timer -= delta
	speech.text = ""
	velocity = danger_response.movement(self, delta, 95.0)
	move_and_slide()
	model.walking = velocity.length() > 1.0
	if model.walking: model.rotation.y = -velocity.angle() + PI * 0.5
	render_clock += delta
	if render_clock >= 0.083:
		model._process(render_clock)
		render_clock = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true

func _ready() -> void:
	add_to_group("pedestrian")
	add_to_group("winter_resident")
	collision_layer = 4
	collision_mask = 3
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
	preload("res://world/shared/pedestrians/WinterWardrobe.gd").light_viewport(viewport)
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
	var sprite := Sprite2D.new()
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2.ONE * (18.0 * 2.6/128.0)
	sprite.position = (Vector2(64,64)-camera.unproject_position(Vector3.ZERO)) * sprite.scale
	add_child(sprite)
	speech = Label.new()
	speech.position = Vector2(-120,-58)
	speech.size.x = 240
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech.add_theme_font_size_override("font_size",10)
	speech.add_theme_color_override("font_shadow_color",Color.BLACK)
	speech.add_theme_constant_override("shadow_offset_x",1)
	speech.add_theme_constant_override("shadow_offset_y",1)
	add_child(speech)

func _physics_process(delta: float) -> void:
	if is_dead:
		fall_presentation.update(delta)
		return
	if _process_danger(delta): return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or player.global_position.distance_to(global_position) > 750 or is_dead:
		return
	elapsed += delta
	var nearby: bool = player.visible and not player.get_meta("mountain_interior",false) and player.global_position.distance_to(global_position) < 100
	if nearby and elapsed > next_line and not lines.is_empty():
		speech.text = resident_name + ": " + lines.pick_random()
		speech_until = elapsed + 5
		next_line = elapsed + 25
	if elapsed > speech_until: speech.text = ""
	if global_position.distance_to(destination) < 5:
		destination = home + Vector2(-35 if destination.x > home.x else 35, 0)
		_routine_pause = 1.5 + appearance_variant%4
	_routine_pause = maxf(0,_routine_pause-delta)
	velocity = Vector2.ZERO if nearby or _routine_pause > 0 else _navigation.movement(self,destination,18,delta)
	move_and_slide()
	if velocity.length() > 1: model.rotation.y = -velocity.angle() + PI*0.5
	model.walking = velocity.length() > 1
	render_clock += delta
	if render_clock >= 0.083:
		model._process(render_clock)
		render_clock = 0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func take_damage(amount: int, _source: Variant = null) -> void:
	if is_dead: return
	health -= amount
	if health <= 0:
		is_dead = true
		velocity = Vector2.ZERO
		fall_presentation.start(self, model, viewport)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		speech.text = ""
		collision_layer = 0

func _create_model() -> Node3D:
	return preload("res://world/mountain_pass/WinterResidentModel.gd").new()

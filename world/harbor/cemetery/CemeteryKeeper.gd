extends CharacterBody2D

signal route_finished()
signal died()

var home: Node2D
var health := 80
var is_dead := false
var sleeping := false
var hostile := false
var work_pose := false
var route := PackedVector2Array()
var route_index := 0
var viewport_3d: SubViewport
var model: Node3D
var camera: Camera3D
var display: Sprite2D
var weapon: Node3D
var speech: Label
var _render_elapsed := 0.0
var _travel_metres := 0.0
var _speech_left := 0.0
var _shot_cooldown := 1.0
var shots_fired := 0
var pixels_per_metre := 20.0
var impact_velocity := Vector2.ZERO
var fall := preload("res://CharacterFallPresentation.gd").new()
var burial_identity := ""
var burial_work := 0.0
var _burial_point := Vector2.ZERO
var _burial_navigation := preload("res://ResponderNavigation.gd").new()

func request_burial(identity: String, point: Vector2) -> bool:
	if is_dead or sleeping or hostile or not burial_identity.is_empty(): return false
	if not is_instance_valid(home) or home.state != "working" or get_parent() != home: return false
	burial_identity = identity
	_burial_point = point + Vector2(-24,0)
	burial_work = 0.0
	work_pose = false
	_burial_navigation.repath()
	return true

func finish_burial() -> void:
	burial_identity = ""
	burial_work = 0.0
	work_pose = false
	if is_instance_valid(home) and not is_dead and not hostile:
		home.state = "walking_to_work"
		walk_to(PackedVector2Array([home.get_parent().to_global(home.WORK_LOCAL)]))

func _ready() -> void:
	add_to_group("cemetery_keeper")
	# The remote interior must not freeze the resident before he can walk out.
	# Rendering remains proximity-limited in _physics_process.
	add_to_group("simulation_keep_alive")
	add_to_group("pedestrian")
	add_to_group("damageable")
	collision_layer = 4
	collision_mask = 3
	z_index = 9
	var shape := CollisionShape2D.new()
	shape.name = "BodyShape"
	var circle := CircleShape2D.new()
	circle.radius = 6
	shape.shape = circle
	add_child(shape)
	viewport_3d = SubViewport.new()
	viewport_3d.size = Vector2i(384, 384)
	viewport_3d.msaa_3d = Viewport.MSAA_4X
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	model = preload("res://prototypes/gameplay_repair_art_0909/CemeteryWorkerModel.gd").new()
	model.name = "Anselmo"
	viewport_3d.add_child(model)
	camera = Camera3D.new()
	viewport_3d.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.3
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.look_at_from_position(Vector3(0, 4.5, 3.8), Vector3(0, .8, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -25, 0)
	light.light_energy = 1.5
	viewport_3d.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c6ccb2")
	environment.environment.ambient_light_energy = .6
	viewport_3d.add_child(environment)
	display = Sprite2D.new()
	display.texture = viewport_3d.get_texture()
	add_child(display)
	set_visual_scale(20.0)
	# A compact shotgun replaces the shovel only when disturbed.
	weapon = Node3D.new()
	weapon.name = "KeeperShotgun"
	model.right_hand_mount.add_child(weapon)
	var parts := preload("res://world/shared/pedestrians/CitizenDetails.gd")
	parts.piece(weapon, Vector3(.07, .07, .5), Vector3(0, 0, -.23), Color("373e38"))
	parts.piece(weapon, Vector3(.09, .11, .23), Vector3(0, -.03, .09), Color("896444"))
	parts.piece(weapon, Vector3(.09, .08, .18), Vector3(0, -.05, -.22), Color("896444"))
	weapon.hide()
	speech = Label.new()
	speech.position = Vector2(-100, -65)
	speech.size = Vector2(200, 75)
	speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech.add_theme_font_size_override("font_size", 11)
	speech.add_theme_color_override("font_color", Color("f0dbab"))
	speech.add_theme_color_override("font_shadow_color", Color.BLACK)
	speech.add_theme_constant_override("shadow_offset_x", 1)
	speech.add_theme_constant_override("shadow_offset_y", 1)
	add_child(speech)

func set_visual_scale(value: float) -> void:
	pixels_per_metre = value
	var metre := camera.unproject_position(Vector3.RIGHT).distance_to(camera.unproject_position(Vector3.ZERO))
	display.scale = Vector2.ONE * value / metre
	display.position = -(camera.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * .5) * display.scale
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func walk_to(points: PackedVector2Array) -> void:
	route = points
	route_index = 0
	work_pose = false

func say(text: String, duration := 5.0) -> void:
	speech.text = text
	_speech_left = duration

func set_sleeping(value: bool) -> void:
	sleeping = value
	if value:
		speech.text = ""
		_speech_left = 0.0
		model.set_worker_pose(0)
	velocity = Vector2.ZERO
	model.rotation = Vector3(-PI / 2, 0, 0) if value else Vector3.ZERO
	model.position.y = .68 if value else 0.0
	model.shovel.visible = not value and not hostile
	weapon.visible = hostile and not value
	collision_layer = 0 if value or is_dead else 4
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _physics_process(delta: float) -> void:
	if is_dead:
		impact_velocity = preload("res://world/shared/combat/VehiclePersonImpact.gd").move_falling_body(self, impact_velocity, delta)
		fall.update(delta)
		return
	_speech_left -= delta
	if _speech_left <= 0: speech.text = ""
	if sleeping: return
	var before := global_position
	velocity = Vector2.ZERO
	if hostile:
		_tick_hostility(delta)
	elif not burial_identity.is_empty():
		var care := get_node("/root/CoronerCare")
		if care.records().get(burial_identity,{}).get("phase", "") != "burial":
			finish_burial()
		elif global_position.distance_to(_burial_point)>6:
			velocity = _burial_navigation.movement(self,_burial_point,36.0,delta)
			move_and_slide()
		else:
			work_pose = true
			burial_work += delta
	elif route_index < route.size():
		var offset := route[route_index] - global_position
		if offset.length() <= 4:
			route_index += 1
			if route_index == route.size(): route_finished.emit()
		else:
			velocity = offset.normalized() * minf(36.0, offset.length() / maxf(delta, .001))
			move_and_slide()
	var displacement := global_position - before
	var moving := displacement.length() > .001
	if moving:
		var axis := Vector3(displacement.normalized().x, 0, displacement.normalized().y)
		var pixels := camera.unproject_position(axis).distance_to(camera.unproject_position(Vector3.ZERO)) * display.scale.x
		_travel_metres += displacement.length() / maxf(pixels, .001)
	if moving: model.rotation.y = -velocity.angle() - PI * .5
	_render_elapsed += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if _render_elapsed >= (1.0 / 30.0) and is_instance_valid(player) and player.global_position.distance_to(global_position) < 1100:
		if not hostile:
			model.set_worker_pose(2 if work_pose else (1 if moving else 0))
			model.update_animation(_render_elapsed, moving, _travel_metres)
			_travel_metres = 0.0
		else:
			model.right_arm.rotation = Vector3(1.0, 0, -.15)
			model.right_forearm.rotation = Vector3(.3, 0, 0)
			model.left_arm.rotation = Vector3(.95, 0, .2)
			model.left_forearm.rotation = Vector3(.4, 0, 0)
			weapon.rotation.x = -1.3
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
		_render_elapsed = 0.0

func _tick_hostility(delta: float) -> void:
	_shot_cooldown -= delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(home) or not home.can_engage(player): return
	var direction := global_position.direction_to(player.global_position)
	model.rotation.y = -direction.angle() - PI * .5
	weapon.show()
	model.shovel.hide()
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position, 3, [get_rid()])
	if not get_world_2d().direct_space_state.intersect_ray(query).is_empty(): return
	if _shot_cooldown > 0: return
	_shot_cooldown = 1.8
	shots_fired += 1
	for pellet in 4:
		var bullet := preload("res://Bullet.tscn").instantiate()
		bullet.owner_body = self
		bullet.configure_range(WeaponCatalog.get_weapon("shotgun"))
		bullet.damage = 4
		bullet.speed = 750
		bullet.direction = direction.rotated((pellet - 1.5) * .04)
		get_parent().add_child(bullet)
		bullet.global_position = global_position + direction * 16
	var sound := AudioStreamPlayer2D.new()
	sound.stream = ProceduralAudio.get_gunshot_shotgun_stream()
	sound.volume_db = -10
	sound.bus = "SFX"
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if is_dead or amount <= 0: return
	health = maxi(0, health - amount)
	if health == 0:
		is_dead = true
		hostile = false
		collision_layer = 0
		speech.text = ""
		model.shovel.hide()
		weapon.hide()
		fall.start(self, model, viewport_3d, impact_velocity)
		if is_player_attacker: get_node("/root/WantedManager").report_crime(20)
		died.emit()
	elif is_player_attacker and is_instance_valid(home): home.disturb_keeper()

func get_run_over(impact: Vector2, is_player_driver: bool = false) -> void:
	if is_dead or not impact.is_finite() or impact.length() < 35.0: return
	impact_velocity = impact.limit_length(600.0) * 0.75
	take_damage(100, is_player_driver)

func on_medical_discharge() -> void:
	if not is_instance_valid(home): return
	get_node("/root/CampaignState").set_campaign_flag(home.DEAD_FLAG, false)
	home.state = "idle"
	set_sleeping(false)

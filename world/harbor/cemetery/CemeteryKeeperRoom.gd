extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var home: Node2D
var inline_mode := true
var inline_floor_polygon := PackedVector2Array()
var inline_door_blocker: CollisionPolygon2D
var _inline_occupied := false
var _inline_door_amount := 0.0
var viewport_3d: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var art: Node3D
var actor_scale: Node
var camera_3d: Camera3D:
	get: return room_camera
var sprite_3d: Sprite2D:
	get: return room_display
var status: Label
var _message_left := 0.0

func _init() -> void:
	interior_id = &"cemetery_keeper"
	display_name = "CASA DO COVEIRO — SEU ANSELMO"
	room_size = Vector2(480, 370)

func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass
func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _setup_interior_content() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "KeeperRoomViewport"
	viewport_3d.size = Vector2i(800, 667) if inline_mode else Vector2i(1200, 960)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	art = preload("res://world/harbor/cemetery/CemeteryHouseInterior3D.gd").new()
	art.compact_mode = inline_mode
	viewport_3d.add_child(art)
	room_camera = Camera3D.new()
	viewport_3d.add_child(room_camera)
	room_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size = 10.8 if inline_mode else 12.0
	room_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if inline_mode:
		room_camera.look_at_from_position(Vector3(0, 1.1, 0) + Vector3(0, 24, 20), Vector3(0, 1.1, 0))
	else:
		room_camera.look_at_from_position(Vector3(0, 18.25, 15), Vector3(0, .25, 0))
	room_camera.force_update_transform()
	room_camera.reset_physics_interpolation()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b5b9a1")
	environment.environment.ambient_light_energy = .5
	viewport_3d.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -24, 0)
	light.light_color = Color("dfdfb7")
	light.light_energy = .65
	light.shadow_enabled = true
	viewport_3d.add_child(light)
	room_display = Sprite2D.new()
	room_display.texture = viewport_3d.get_texture()
	var metre := room_camera.unproject_position(Vector3.RIGHT).distance_to(room_camera.unproject_position(Vector3.ZERO))
	room_display.scale = Vector2.ONE * (20.0 if inline_mode else 38.0) / metre
	room_display.position = -(room_camera.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * .5) * room_display.scale if inline_mode else Vector2(0, -5)
	add_child(room_display)
	if inline_mode: room_display.hide()
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedHouseSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	var footprints := {
		"NorthWall": Rect2(-4.65, -3.7, 9.3, .22),
		"WestWall": Rect2(-4.7, -3.7, .22, 7.4),
		"EastWall": Rect2(4.48, -3.7, .22, 7.4),
		"SouthWall": Rect2(-4.65, 3.5, 9.3, .22),
		"Workbench": Rect2(-4.17, -3.3, 3.25, 1.02),
		"Bed": Rect2(2.1, -3.23, 1.8, 2.6),
		"BedsideTable": Rect2(1.24, -2.95, .68, .7),
		"Stove": Rect2(-4.15, -.97, .8, .85),
		"Wheelbarrow": Rect2(-3.8, .85, 1.5, 2.15),
		"Sacks": Rect2(3.2, .75, .95, 1.65),
		"Boots": Rect2(2.305, -.555, .51, .37),
		"StoredCrosses": Rect2(1.6275, 3.2175, 1.045, .065),
	}
	if inline_mode:
		footprints = {
			"NorthWall": Rect2(-3.62,-2.82,7.24,.16),
			"WestWall": Rect2(-3.63,-2.8,.16,5.6),
			"EastWall": Rect2(3.47,-2.8,.16,5.6),
			"SouthLeft": Rect2(-3.62,2.62,2.87,.18),
			"SouthRight": Rect2(.75,2.62,2.87,.18),
			"Workbench": Rect2(-3.62,-2.47,3.25,.8),
			"Bed": Rect2(1.49,-2.75,1.66,2.55),
			"BedsideTable": Rect2(.89,-2.3,.7,.7),
			"Stove": Rect2(-3.33,-.79,.8,.8),
			"Wheelbarrow": Rect2(-3.1,.17,1.55,2.15),
			"Sacks": Rect2(2.32,.03,1.0,1.7),
			"Boots": Rect2(1.55,-.42,.5,.4),
			"StoredCrosses": Rect2(1.2,2.35,1.0,.15),
		}
	for id in footprints:
		var rect: Rect2 = footprints[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = _project_compact_rect(rect) if inline_mode else PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
		walls_body.add_child(shape)
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0, 2.2))
		add_child(spawn_point)
		inline_floor_polygon = _project_compact_rect(Rect2(-3.5,-2.65,7.0,5.3))
		inline_door_blocker = CollisionPolygon2D.new()
		inline_door_blocker.name = "DoorLeaves"
		inline_door_blocker.polygon = _project_compact_rect(Rect2(-.7,2.64,1.4,.16))
		walls_body.add_child(inline_door_blocker)
		room_size = Vector2(180,130)
		set_meta("fixed_camera",true)
	else:
		_create_spawn_and_exit(project_floor(Vector2(0, 2.2)), project_floor(Vector2(0, 3.3)), &"cemetery_keeper_return", "SAIR DA CASA")
		exit_door.get_node("Facade").hide()
		exit_door.custom_prompt_text = "E"
	status = Label.new()
	status.position = Vector2(-95, 70) if inline_mode else Vector2(-210, 125)
	status.size = Vector2(190, 65) if inline_mode else Vector2(420, 65)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color("ecd8ac"))
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.z_index = 30
	add_child(status)
	var reward_position := Vector2(1.1, 1.5) if inline_mode else Vector2(1.4, 2.0)
	var reward := add_cash_reward(art, reward_position, 450, "cemetery_keeper_cash_01")
	if inline_mode: reward.position = _project_compact_floor(reward_position)

func _project_compact_floor(point: Vector2) -> Vector2:
	return room_display.position + (room_camera.unproject_position(Vector3(point.x,0,point.y)) - Vector2(viewport_3d.size) * .5) * room_display.scale

func _project_compact_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([_project_compact_floor(rect.position),_project_compact_floor(Vector2(rect.end.x,rect.position.y)),_project_compact_floor(rect.end),_project_compact_floor(Vector2(rect.position.x,rect.end.y))])

func attach_inline_home(owner: Node2D) -> void:
	home = owner
	global_position = owner.global_position
	z_as_relative = false
	z_index = 6

func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point),inline_floor_polygon)
	return super.contains_point(point)

func project_floor(point: Vector2) -> Vector2:
	return _project_compact_floor(Vector2(point.x*.78,point.y*.75) if inline_mode else point)

func actor_inside() -> bool:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	return is_instance_valid(actor) and actor.visible and contains_point(actor.global_position) and actor.get("is_dead") != true and actor.get("is_arrested") != true

func show_message(text: String) -> void:
	status.text = text
	_message_left = 9.0

func _process(delta: float) -> void:
	var inside := actor_inside()
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if inline_mode:
		var near: bool = is_instance_valid(actor) and actor.visible and actor.global_position.distance_to(to_global(_project_compact_floor(Vector2(0,2.7)))) < 62.0
		var keeper_near: bool = is_instance_valid(home.keeper) and home.keeper.global_position.distance_to(to_global(_project_compact_floor(Vector2(0,2.7)))) < 45.0
		_inline_door_amount = move_toward(_inline_door_amount,1.0 if home.entrance._door_open or near or keeper_near or inside else 0.0,delta/.4)
		inline_door_blocker.set_deferred("disabled",_inline_door_amount >= .6)
		if near and not inside and viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
		if inside and not _inline_occupied:
			_inline_occupied = true
			home.sprite_3d.hide()
			room_display.show()
			set_npc_rendering_active(true)
			actor.set_meta("harbor_interior",true)
			actor.set_meta("police_exterior_position",home.entrance.global_position)
			var cam := actor.get_node_or_null("Camera") as Camera2D
			if cam:
				cam.set_meta("compact_interior",get_camera_rect())
				cam.reset_smoothing()
			get_parent().get_parent().emit_signal("actor_entered_interior",actor,interior_id)
		elif not inside and _inline_occupied:
			_inline_occupied = false
			home.sprite_3d.show()
			room_display.hide()
			set_npc_rendering_active(false)
			actor.remove_meta("harbor_interior")
			actor.remove_meta("police_exterior_position")
			var cam := actor.get_node_or_null("Camera") as Camera2D
			if cam: cam.remove_meta("compact_interior")
			get_parent().get_parent().emit_signal("actor_returned_to_exterior",actor,interior_id)
	if inside and not is_instance_valid(actor_scale) and actor.get("viewport_3d") is SubViewport:
		actor_scale = preload("res://systems/interiors/InteriorActorPresentation.gd").new()
		add_child(actor_scale)
		actor_scale.configure(actor, room_camera, room_display)
	elif not inside and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null
	if not inside:
		status.text = ""
		return
	_message_left -= delta
	if _message_left > 0: return
	if home.is_sleep_time():
		status.text = "ANSELMO ESTAVA DORMINDO — saia pela porta!" if home.keeper.hostile else "Silêncio... o coveiro está dormindo."
	else:
		var desk := to_global(project_floor(Vector2(-2.3, -1.9)))
		status.text = "E" if actor.global_position.distance_to(desk) < 55 else ""

func _unhandled_input(event: InputEvent) -> void:
	if not actor_inside() or not event.is_action_pressed("interact") or event.is_echo(): return
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if home.is_sleep_time(): return
	var desk := to_global(project_floor(Vector2(-2.3, -1.9)))
	if actor.global_position.distance_to(desk) < 55:
		get_viewport().set_input_as_handled()
		home.reveal_secret()

func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	if not active and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED

func _exit_tree() -> void:
	if is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null

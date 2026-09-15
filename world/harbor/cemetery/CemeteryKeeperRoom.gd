extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var home: Node2D
var viewport_3d: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var art: Node3D
var actor_scale: Node
var status: Label
var _message_left := 0.0

func _init() -> void:
	interior_id = &"cemetery_keeper"
	display_name = "CASA DO COVEIRO — SEU ANSELMO"
	room_size = Vector2(480, 370)

func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass

func _setup_interior_content() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "KeeperRoomViewport"
	viewport_3d.size = Vector2i(1200, 960)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	art = preload("res://world/harbor/cemetery/CemeteryHouseInterior3D.gd").new()
	viewport_3d.add_child(art)
	room_camera = Camera3D.new()
	viewport_3d.add_child(room_camera)
	room_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size = 12
	room_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.look_at_from_position(Vector3(0, 12, 10), Vector3(0, .25, 0))
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
	room_display.scale = Vector2.ONE * 38.0 / metre
	room_display.position = Vector2(0, -5)
	add_child(room_display)
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
	}
	for id in footprints:
		var rect: Rect2 = footprints[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = PackedVector2Array([project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)), project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))])
		walls_body.add_child(shape)
	_create_spawn_and_exit(project_floor(Vector2(0, 2.2)), project_floor(Vector2(0, 3.3)), &"cemetery_keeper_return", "SAIR DA CASA")
	exit_door.get_node("Facade").hide()
	exit_door.custom_prompt_text = "E"
	status = Label.new()
	status.position = Vector2(-210, 125)
	status.size = Vector2(420, 65)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color("ecd8ac"))
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.z_index = 30
	add_child(status)

func project_floor(point: Vector2) -> Vector2:
	return room_display.position + (room_camera.unproject_position(Vector3(point.x, 0, point.y)) - Vector2(viewport_3d.size) * .5) * room_display.scale

func actor_inside() -> bool:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	return is_instance_valid(actor) and actor.visible and contains_point(actor.global_position) and actor.get("is_dead") != true and actor.get("is_arrested") != true

func show_message(text: String) -> void:
	status.text = text
	_message_left = 9.0

func _process(delta: float) -> void:
	var inside := actor_inside()
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if inside and not is_instance_valid(actor_scale) and actor.get("viewport_3d") is SubViewport:
		actor_scale = preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
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
		status.text = "E" if actor.global_position.distance_to(desk) < 55 else "SEU ANSELMO • ferramentas, café e histórias que ninguém conta."

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
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED

func _exit_tree() -> void:
	if is_instance_valid(actor_scale): actor_scale.restore()

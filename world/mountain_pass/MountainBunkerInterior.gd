extends "res://world/harbor/interiors/HarborInteriorBase.gd"

const MODEL := preload("res://world/mountain_pass/MountainBunker3D.gd")
const VIEW_SIZE := Vector2i(1280, 960)
const DISPLAY_SCALE := 0.66
var viewport_3d: SubViewport
var camera_3d: Camera3D
var model: Node3D
var sprite_3d: Sprite2D
var room_camera: Camera2D
var active := false
var actor: Node2D
var console_position: Vector2
var route_position: Vector2
var note_panel: PanelContainer
var note_text: Label
var hint: Label
var note_open := false
var _last_actor_position := Vector2.INF

func _init() -> void:
	interior_id = &"mountain_bunker"
	display_name = "ESTAÇÃO ZERO / COVIL DOS LOBOS DE GELO"
	room_size = Vector2(820, 490)

# The 3D floor and projected solid geometry replace the rectangular base room.
func _build_walls_and_floor() -> void:
	pass

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "BunkerRender"
	viewport_3d.size = VIEW_SIZE
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_3d)
	model = MODEL.new()
	model.name = "StationZeroModel"
	viewport_3d.add_child(model)
	camera_3d = Camera3D.new()
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = 17.5
	viewport_3d.add_child(camera_3d)
	camera_3d.position = Vector3(0, 20, 13)
	camera_3d.look_at(Vector3(0, 0, 0))
	camera_3d.current = true
	sprite_3d = Sprite2D.new()
	sprite_3d.name = "BunkerDisplay"
	sprite_3d.texture = viewport_3d.get_texture()
	sprite_3d.scale = Vector2.ONE * DISPLAY_SCALE
	add_child(sprite_3d)
	_build_projected_collisions()
	_create_spawn_and_exit(project_floor(Vector2(0, 4.3)), project_floor(Vector2(0, 5.8)), &"bunker_exterior_return", "SAIR DA ESTAÇÃO ZERO")
	exit_door.name = "ExitDoor"
	exit_door.custom_prompt_text = "[E] SAIR DA ESTAÇÃO ZERO"
	exit_door.get_node("Facade").hide()
	var boss_anchor := Marker2D.new()
	boss_anchor.name = "Boss2Anchor"
	boss_anchor.position = project_floor(Vector2(0, -2.5))
	add_child(boss_anchor)
	var arena := Area2D.new()
	arena.name = "FutureBossArena"
	arena.monitoring = false
	arena.collision_layer = 0
	arena.collision_mask = 0
	add_child(arena)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = project_floor(Vector2(3.9, 2.5)) - project_floor(Vector2(-3.9, -3.3))
	shape.shape = rectangle
	shape.position = project_floor(Vector2(0, -0.4))
	arena.add_child(shape)
	console_position = project_floor(Vector2(6.6, -3.15))
	route_position = project_floor(Vector2(0, -3.0))
	room_camera = Camera2D.new()
	room_camera.name = "BunkerCamera"
	room_camera.enabled = false
	room_camera.set_meta("mountain_fixed_framing", true)
	add_child(room_camera)
	_build_ui()

func project_floor(point: Vector2) -> Vector2:
	return (camera_3d.unproject_position(Vector3(point.x, 0, point.y)) - Vector2(VIEW_SIZE) * 0.5) * DISPLAY_SCALE

func _build_projected_collisions() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedBunkerSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	for footprint in model.footprints:
		var rect: Rect2 = footprint["rect"]
		var polygon := CollisionPolygon2D.new()
		polygon.name = String(footprint["id"])
		polygon.polygon = PackedVector2Array([
			project_floor(rect.position), project_floor(Vector2(rect.end.x, rect.position.y)),
			project_floor(rect.end), project_floor(Vector2(rect.position.x, rect.end.y))
		])
		walls_body.add_child(polygon)

func set_npc_rendering_active(value: bool) -> void:
	active = value
	if room_camera:
		room_camera.enabled = value
		if value:
			room_camera.make_current()
			_fit_camera()
	set_process(value)
	set_process_unhandled_key_input(value)
	if viewport_3d:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	if model:
		model.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if hint:
		hint.visible = value
	if note_panel:
		note_panel.hide()
	note_open = false
	actor = get_tree().get_first_node_in_group("player") as Node2D if value else null
	_last_actor_position = Vector2.INF

func _build_ui() -> void:
	var hud := CanvasLayer.new()
	hud.name = "BunkerReadout"
	hud.layer = 108
	add_child(hud)
	var layout := Control.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(layout)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -52
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	layout.add_child(hint)
	note_panel = PanelContainer.new()
	note_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	note_panel.offset_left = -290
	note_panel.offset_right = 290
	note_panel.offset_top = -245
	note_panel.offset_bottom = -65
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17232bf5")
	style.border_color = Color("ba995b")
	style.set_border_width_all(2)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	note_panel.add_theme_stylebox_override("panel", style)
	layout.add_child(note_panel)
	note_text = Label.new()
	note_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_text.custom_minimum_size = Vector2(530, 130)
	note_text.add_theme_font_size_override("font_size", 18)
	note_text.add_theme_color_override("font_color", Color("e0e2d9"))
	note_panel.add_child(note_text)
	note_panel.hide()

func _process(_delta: float) -> void:
	_fit_camera()
	if not is_instance_valid(actor):
		return
	var local := to_local(actor.global_position)
	if local.distance_to(_last_actor_position) > 70 and note_open:
		_close_note()
	if note_open:
		hint.text = "[F] FECHAR"
	elif local.distance_to(console_position) < 58:
		hint.text = "[F] OUVIR O RÁDIO / CANAL 07"
	elif local.distance_to(route_position) < 58:
		hint.text = "[F] EXAMINAR MAPA DE ROTAS"
	else:
		hint.text = "ESTAÇÃO ZERO / ALOJAMENTO — COMANDO — RÁDIO"

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not is_instance_valid(actor):
		return
	if not (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F):
		return
	if note_open:
		_close_note()
	else:
		var local := to_local(actor.global_position)
		if local.distance_to(console_position) < 58:
			note_text.text = "CANAL 07 / TRANSMISSÃO INTERCEPTADA\n\n“O porto caiu. Mantenham os carregamentos na serra. A passagem do deserto continua sob nosso controle. Aguardem o comando de Viktor.”"
		elif local.distance_to(route_position) < 58:
			note_text.text = "MAPA DOS LOBOS DE GELO\n\nPorto → Estação Zero → rodovia do deserto. Uma cidade iluminada encerra a rota. Anotações indicam encontros de pilotos ao longo da rodovia."
		else:
			return
		_last_actor_position = local
		note_open = true
		note_panel.show()
	get_viewport().set_input_as_handled()

func _close_note() -> void:
	note_open = false
	note_panel.hide()

func _fit_camera() -> void:
	var size := get_viewport_rect().size
	var zoom_value := minf(size.x / 880.0, size.y / 660.0)
	room_camera.zoom = Vector2.ONE * clampf(zoom_value, 0.65, 1.8)

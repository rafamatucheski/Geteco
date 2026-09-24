class_name HarborPoliceInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

## Delegacia de Polícia 3D do Porto (Harbor Patrol)
## Renderiza em tempo real a delegacia volumétrica completa via SubViewport (HarborPoliceStation3D),
## com projeção ortogonal calibrada, materiais PBR, iluminação e sombras suaves,
## colisão física 2D projetada (project_floor), calibração dinâmica da escala do jogador,
## múltiplos NPCs vivos (Sargento Morales, Detetive Ribeiro, Policial Ferreira, Detento, Cidadão),
## e terminal interativo de ocorrências e mandados.

const STATION_3D_SCENE := preload("res://world/harbor/interiors/HarborPoliceStation3D.gd")
const COMPACT_STATION_3D_SCENE := preload("res://world/harbor/interiors/HarborPoliceCompactArt3D.gd")
const NPC_SCRIPT := preload("res://world/harbor/interiors/HarborConversationalNPC.gd")
const ACTOR_SCALE_SCRIPT := preload("res://systems/interiors/InteriorActorPresentation.gd")

var view: SubViewport
var room_camera: Camera3D
var station_3d: Node3D
var room_display: Sprite2D
var actor_scale: Node
var actor: Node2D
var inline_mode := false
var inline_facade: Node2D
var inline_entrance: BuildingEntrance
var inline_floor_polygon := PackedVector2Array()
var inline_door_blocker: CollisionPolygon2D
var _inline_occupied := false
var _inline_door_amount := 0.0
var camera_3d: Camera3D:
	get: return room_camera
var sprite_3d: Sprite2D:
	get: return room_display

# NPCs da Delegacia
var sergeant_npc: CharacterBody2D
var detective_npc: CharacterBody2D
var guard_npc: CharacterBody2D
var prisoner_npc: CharacterBody2D
var civilian_npc: CharacterBody2D
var all_npcs: Array[CharacterBody2D] = []

# Terminal de Ocorrências & Mandados
var terminal_area: Area2D
var terminal_badge: Label
var terminal_dialog: PanelContainer
var terminal_text: Label
var is_near_terminal: bool = false

# Efeitos de Iluminação e Alerta
var radio_light: PointLight2D
var anim_clock: float = 0.0

func _init() -> void:
	interior_id = &"police"
	display_name = "HARBOR PATROL"
	room_size = Vector2(960, 660)
	wall_color = Color("#11161f")
	floor_color = Color("#1c2430")
	accent_color = Color("#38bdf8")

func _build_lights() -> void:
	# Toda a iluminação e sombras PBR são geradas pelo HarborPoliceStation3D
	pass

func _build_blackout() -> void:
	if not inline_mode: super._build_blackout()

func _build_walls_and_floor() -> void:
	# A renderização visual é gerada pela cena 3D; colisões físicas 2D
	# são projetadas com exatidão matemática via project_floor.
	pass

func _setup_interior_content() -> void:
	actor = get_tree().get_first_node_in_group("player")
	_setup_3d_station_viewport()
	_project_station_colliders()
	_build_npcs()
	_build_incident_terminal()

	# Configuração do ponto de entrada e saída alinhado às portas duplas da fachada Sul
	if inline_mode:
		spawn_point = Marker2D.new()
		spawn_point.name = "SpawnPoint"
		spawn_point.position = project_floor(Vector2(0,4.9))
		add_child(spawn_point)
		inline_floor_polygon = _project_rect(Rect2(-4.12,-5.82,8.24,11.95))
		inline_door_blocker = CollisionPolygon2D.new()
		inline_door_blocker.name = "DoorLeaves"
		inline_door_blocker.polygon = _project_rect(Rect2(-1.3,5.92,2.6,.18))
		walls_body.add_child(inline_door_blocker)
		room_display.hide()
		set_meta("fixed_camera",true)
	else:
		var spawn_pos := project_floor(Vector2(0.0, 4.8))
		var exit_pos := project_floor(Vector2(0.0, 6.2))
		_create_spawn_and_exit(spawn_pos, exit_pos, &"harbor/District/Police/Entrance/exit", "SAIR DA DELEGACIA")
		exit_door.show_interaction_prompt = false
		exit_door.get_node("Facade").hide()
	add_cash_reward(station_3d, Vector2(1.9, 3.3) if inline_mode else Vector2(1.4, 3.8), 250, "harbor_patrol_cash_01")

# ==============================================================================
# 1. VIEWPORT 3D & PROJEÇÃO ORTOGONAL
# ==============================================================================

func _setup_3d_station_viewport() -> void:
	view = SubViewport.new()
	view.name = "StationViewport3D"
	view.size = Vector2i(800, 667) if inline_mode else Vector2i(1760, 1100)
	view.transparent_bg = true
	view.own_world_3d = true
	view.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#0c1117")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#758a9e")
	env.ambient_light_energy = 0.55
	var world_3d := view.find_world_3d()
	if world_3d:
		world_3d.environment = env

	station_3d = COMPACT_STATION_3D_SCENE.new() if inline_mode else STATION_3D_SCENE.new()
	view.add_child(station_3d)

	room_camera = Camera3D.new()
	room_camera.name = "StationCamera3D"
	room_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size = 12.0 if inline_mode else 18.0
	room_camera.current = true
	view.add_child(room_camera)

	# Ângulo isométrico institucional calibrado (54.5° em relação ao plano horizontal)
	if inline_mode:
		room_camera.look_at_from_position(Vector3(0,24.0,20.0),Vector3(0,1.2,0),Vector3.UP)
	else:
		room_camera.look_at_from_position(Vector3(0.0, 18.0, 14.5), Vector3(0.0, 0.0, -0.5), Vector3.UP)
	room_camera.force_update_transform()
	room_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.reset_physics_interpolation()

	room_display = Sprite2D.new()
	room_display.name = "StationDisplay3D"
	room_display.texture = view.get_texture()
	room_display.position = Vector2(0, 0)
	var unit_x: float = room_camera.unproject_position(Vector3.RIGHT).distance_to(room_camera.unproject_position(Vector3.ZERO))
	room_display.scale = Vector2.ONE * (20.0 / unit_x) if inline_mode else Vector2(0.52, 0.52)
	if inline_mode:
		room_display.position = -(room_camera.unproject_position(Vector3.ZERO)-Vector2(view.size)*.5)*room_display.scale
	room_display.z_index = 0
	add_child(room_display)

## Converte coordenadas no plano do chão 3D (X, Z em metros) para pixels 2D locais
func project_floor(point: Vector2) -> Vector2:
	return room_display.position+(room_camera.unproject_position(Vector3(point.x, 0.0, point.y)) - Vector2(view.size) * 0.5) * room_display.scale

func _project_rect(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])


# ==============================================================================
# 2. COLISORES FÍSICOS 2D PROJETADOS
# ==============================================================================

func _project_station_colliders() -> void:
	walls_body = StaticBody2D.new()
	walls_body.name = "StationMeshSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	preload("res://systems/interiors/InteriorSolidProjection.gd").build(station_3d, walls_body, project_floor)

# ==============================================================================
# 3. NPCS DA DELEGACIA
# ==============================================================================

func _build_npcs() -> void:
	# 1. SARGENTO MORALES (Recepção Central — Atendente da Missão 1)
	sergeant_npc = NPC_SCRIPT.new()
	sergeant_npc.name = "SergeantMorales"
	sergeant_npc.character_name = "Sargento Morales"
	sergeant_npc.title_color = Color("#68a8d3")
	sergeant_npc.shirt_color = Color("#1e3a8a")
	sergeant_npc.pants_color = Color("#0f172a")
	sergeant_npc.has_hat = true
	sergeant_npc.hat_color = Color("#1e3a8a")
	sergeant_npc.dialogues = [
		"Harbor Patrol, 1º Distrito. Mantenha as mãos onde eu possa vê-las, cidadão.",
		"O cais de Breakwater tá tenso ultimamente. Carga sumindo dos contêineres e os Cobras de Ferro rondando.",
		"Se você vir algo suspeito nos becos da Foundry Avenue, venha direto ao balcão.",
		"Não toleramos rachas nem tiroteios no perímetro do porto. Considere isso um aviso amigável."
	]
	sergeant_npc.interact_radius = 80.0
	sergeant_npc.position = project_floor(Vector2(-.6,-1.15) if inline_mode else Vector2(-0.75, -0.1))
	add_child(sergeant_npc)
	all_npcs.append(sergeant_npc)

	# 2. DETETIVE RIBEIRO (Salão dos Detetives / Bullpen)
	detective_npc = NPC_SCRIPT.new()
	detective_npc.name = "DetectiveRibeiro"
	detective_npc.character_name = "Detetive Ribeiro"
	detective_npc.title_color = Color("#f59e0b")
	detective_npc.shirt_color = Color("#374151") # Terno de investigador
	detective_npc.pants_color = Color("#1f2937")
	detective_npc.has_hat = false
	detective_npc.dialogues = [
		"Estamos mapeando a rede de receptação dos Cobras de Ferro no Píer Leste.",
		"Motores adulterados, nitro contrabandeado... eles estão montando uma frota para disputas pesadas.",
		"Aquele mural na parede não mente: cada foto tem ligação direta com os galpões do porto."
	]
	detective_npc.interact_radius = 75.0
	detective_npc.position = project_floor(Vector2(-1.8,-2.65) if inline_mode else Vector2(-3.4, -4.2))
	add_child(detective_npc)
	all_npcs.append(detective_npc)

	# 3. POLICIAL FERREIRA (Guarda da Carceragem)
	guard_npc = NPC_SCRIPT.new()
	guard_npc.name = "OfficerFerreira"
	guard_npc.character_name = "Policial Ferreira"
	guard_npc.title_color = Color("#60a5fa")
	guard_npc.shirt_color = Color("#1e3a8a")
	guard_npc.pants_color = Color("#0f172a")
	guard_npc.has_hat = true
	guard_npc.hat_color = Color("#1e3a8a")
	guard_npc.dialogues = [
		"Custódia temporária. Mantenha distância das grades, cidadão.",
		"O suspeito ali dentro foi apanhado tentando desviar peças nos trilhos da ferrovia.",
		"Delegacia não é ponto turístico. Faça o que veio fazer e siga seu caminho."
	]
	guard_npc.interact_radius = 75.0
	guard_npc.position = project_floor(Vector2(2.25,-1.5) if inline_mode else Vector2(5.5, -1.2))
	add_child(guard_npc)
	all_npcs.append(guard_npc)

	# 4. PRESO "DENTE DE OURO" (Detento na Cela 1)
	prisoner_npc = NPC_SCRIPT.new()
	prisoner_npc.name = "Prisoner"
	prisoner_npc.character_name = "Dente de Ouro"
	prisoner_npc.title_color = Color("#f97316")
	prisoner_npc.shirt_color = Color("#ea580c") # Macacão laranja
	prisoner_npc.pants_color = Color("#c2410c")
	prisoner_npc.has_hat = false
	prisoner_npc.dialogues = [
		"Tá encarando o quê? Sai da frente da grade, moleque.",
		"Eles acham que essas barras de ferro vão segurar os Cobras... logo, logo meu advogado chega.",
		"Se você veio procurar o Vicente... aquele sumiu no mapa faz tempo, tá correndo em outro nível."
	]
	prisoner_npc.interact_radius = 70.0
	prisoner_npc.position = project_floor(Vector2(1.9,-4.5) if inline_mode else Vector2(5.5, -3.8))
	add_child(prisoner_npc)
	all_npcs.append(prisoner_npc)

	# 5. DONA CIDA (Civil na Área de Espera)
	civilian_npc = NPC_SCRIPT.new()
	civilian_npc.name = "CivilianCida"
	civilian_npc.character_name = "Dona Cida"
	civilian_npc.is_female = true
	civilian_npc.title_color = Color("#a78bfa")
	civilian_npc.shirt_color = Color("#7c3aed")
	civilian_npc.pants_color = Color("#2e1065")
	civilian_npc.has_hat = false
	civilian_npc.dialogues = [
		"Vim prestar queixa sobre umas corridas barulhentas no cais de madrugada.",
		"Estou esperando há quase uma hora... esses policiais só correm atrás de caso grande.",
		"Tome cuidado pelas ruas à noite, meu jovem. O porto não perdoa distrações."
	]
	civilian_npc.interact_radius = 70.0
	civilian_npc.position = project_floor(Vector2(-2.25,3.65) if inline_mode else Vector2(-2.4, 4.3))
	add_child(civilian_npc)
	all_npcs.append(civilian_npc)

	for npc in all_npcs:
		npc.configure_room_presentation(room_camera, room_display)

# ==============================================================================
# 4. TERMINAL INTERATIVO DE OCORRÊNCIAS & MANDADOS
# ==============================================================================

func _build_incident_terminal() -> void:
	var terminal_pos := project_floor(Vector2(-2.5,2.15) if inline_mode else Vector2(-4.2, 1.5))

	terminal_area = Area2D.new()
	terminal_area.name = "TerminalArea"
	terminal_area.collision_layer = 0
	terminal_area.collision_mask = 7
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(95, 75)
	col.shape = rect
	terminal_area.add_child(col)
	terminal_area.position = terminal_pos
	add_child(terminal_area)

	terminal_area.body_entered.connect(func(b):
		if b.is_in_group("player"):
			is_near_terminal = true
			if terminal_badge: terminal_badge.visible = true
	)
	terminal_area.body_exited.connect(func(b):
		if b.is_in_group("player"):
			is_near_terminal = false
			if terminal_badge: terminal_badge.visible = false
			if terminal_dialog and terminal_dialog.visible:
				terminal_dialog.visible = false
				modal_closed.emit()
	)

	terminal_badge = Label.new()
	terminal_badge.text = "E"
	terminal_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	terminal_badge.position = terminal_pos + Vector2(-140, -48)
	terminal_badge.size = Vector2(280, 20)
	terminal_badge.add_theme_font_size_override("font_size", 10)
	terminal_badge.add_theme_color_override("font_color", Color("#38bdf8"))
	terminal_badge.add_theme_color_override("font_shadow_color", Color.BLACK)
	terminal_badge.z_index = 10
	terminal_badge.visible = false
	add_child(terminal_badge)

	# UI do Terminal
	var canvas := CanvasLayer.new()
	canvas.layer = 26
	add_child(canvas)

	terminal_dialog = PanelContainer.new()
	terminal_dialog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	terminal_dialog.offset_left = 140.0
	terminal_dialog.offset_right = -140.0
	terminal_dialog.offset_bottom = -28.0
	terminal_dialog.offset_top = -235.0
	terminal_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(terminal_dialog)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("#38bdf8")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 12
	terminal_dialog.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 14)
	terminal_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "POLÍCIA DO PORTO — SISTEMA INTEGRADO DE OCORRÊNCIAS & MANDADOS"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#38bdf8"))
	vbox.add_child(title)

	terminal_text = Label.new()
	terminal_text.text = "OCORRÊNCIA #304: Suspeita de desvio de contêiner com motores preparados no Píer Leste.\nALERTA GERAL: Facção Cobras de Ferro monitorada nas imediações da Foundry Avenue.\nSTATUS DO DISTRITO: Patrulha tática em prontidão • 1 detento sob custódia temporária."
	terminal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terminal_text.add_theme_font_size_override("font_size", 17)
	terminal_text.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(terminal_text)

	var hint := Label.new()
	var is_en := TranslationServer.get_locale().begins_with("en")
	hint.text = "[ E / ESC ] Close terminal" if is_en else "[ E / ESC ] Fechar terminal"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#cbd5e1"))
	vbox.add_child(hint)

	terminal_dialog.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_near_terminal:
		return
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed("interact"):
			if not terminal_dialog.visible:
				_open_terminal()
			else:
				terminal_dialog.visible = false
				modal_closed.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel") and terminal_dialog.visible:
			terminal_dialog.visible = false
			modal_closed.emit()
			get_viewport().set_input_as_handled()

func _open_terminal() -> void:
	terminal_dialog.visible = true
	modal_opened.emit()
	var p := AudioStreamPlayer.new()
	p.stream = ProceduralAudio.get_ui_click_stream()
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ==============================================================================
# 5. ESCALA DO JOGADOR & CICLO DE VIDA
# ==============================================================================

var _warmed: bool = false

func _process(delta: float) -> void:
	if not _warmed and is_instance_valid(view):
		_warmed = true
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if inline_mode: _update_inline_access(delta)
	_sync_actor_scale()
	if is_instance_valid(actor) and is_instance_valid(terminal_area):
		var dist := actor.global_position.distance_to(terminal_area.global_position)
		if dist < 50.0 and not is_near_terminal:
			is_near_terminal = true
			if terminal_badge: terminal_badge.visible = true
		elif dist > 70.0 and is_near_terminal:
			is_near_terminal = false
			if terminal_badge: terminal_badge.visible = false

func on_actor_entered(target: Node2D) -> void:
	if not target.is_in_group("player"): return
	actor = target
	_sync_actor_scale()

func _sync_actor_scale() -> void:
	if not is_instance_valid(actor): actor = get_tree().get_first_node_in_group("player")
	if actor_inside() and not is_instance_valid(actor_scale):
		actor_scale = ACTOR_SCALE_SCRIPT.new()
		add_child(actor_scale)
		actor_scale.configure(actor, room_camera, room_display)
	elif not actor_inside() and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null

func _exit_tree() -> void:
	if is_instance_valid(actor_scale):
		actor_scale.restore()

func actor_inside() -> bool:
	return is_instance_valid(actor) and actor.visible and not actor.is_dead and not actor.is_arrested and contains_point(actor.global_position)

func contains_point(point: Vector2) -> bool:
	if inline_mode: return Geometry2D.is_point_in_polygon(to_local(point),inline_floor_polygon)
	return super.contains_point(point)

func get_camera_rect() -> Rect2:
	if inline_mode: return Rect2(global_position-Vector2(110,135),Vector2(220,270))
	return super.get_camera_rect()

func attach_inline_facade(facade: Node2D, entrance: BuildingEntrance) -> void:
	inline_facade = facade
	inline_entrance = entrance
	global_position = facade.global_position+Vector2(0,30)
	z_as_relative = false
	z_index = 6
	entrance.interior_available = false
	entrance.handle_input_locally = false
	entrance.show_entrance_marker = false
	entrance.show_interaction_prompt = false
	var old_body := facade.get_node_or_null("BuildingSolid") as StaticBody2D
	if old_body:
		old_body.collision_layer = 0
		old_body.queue_free()

func _update_inline_access(delta: float) -> void:
	if not is_instance_valid(inline_facade) or not is_instance_valid(inline_entrance): return
	if not is_instance_valid(actor): actor = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(actor): return
	var inside: bool = actor.visible and actor.get("is_dead") != true and contains_point(actor.global_position)
	var near: bool = actor.visible and actor.get("is_dead") != true and actor.global_position.distance_to(inline_entrance.global_position) < 78.0
	# The facade sensor covers the street side only; the same door must reopen
	# when somebody approaches the threshold from inside the station.
	if near:
		inline_entrance._away_time = 0.0
		if not inline_entrance._door_open: inline_entrance.open_door()
	var target := 1.0 if near and inline_entrance._door_open else 0.0
	var amount := move_toward(_inline_door_amount,target,delta/.4)
	if not is_equal_approx(amount,_inline_door_amount):
		_inline_door_amount = amount
		station_3d.call("set_open_amount",amount)
		inline_door_blocker.set_deferred("disabled",amount >= .6)
		if is_instance_valid(view): view.render_target_update_mode = SubViewport.UPDATE_ONCE if not inside else SubViewport.UPDATE_ALWAYS
	if inside and not _inline_occupied:
		_inline_occupied = true
		inline_facade.set("inline_cutaway",true)
		inline_facade.queue_redraw()
		room_display.show()
		set_npc_rendering_active(true)
		actor.set_meta("harbor_interior",true)
		actor.set_meta("police_exterior_position",inline_entrance.global_position)
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam:
			cam.set_meta("compact_interior",get_camera_rect())
			cam.reset_smoothing()
		get_parent().get_parent().emit_signal("actor_entered_interior",actor,interior_id)
	elif not inside and _inline_occupied:
		_inline_occupied = false
		inline_facade.set("inline_cutaway",false)
		inline_facade.queue_redraw()
		room_display.hide()
		set_npc_rendering_active(false)
		actor.remove_meta("harbor_interior")
		actor.remove_meta("police_exterior_position")
		var cam := actor.get_node_or_null("Camera") as Camera2D
		if cam: cam.remove_meta("compact_interior")
		get_parent().get_parent().emit_signal("actor_returned_to_exterior",actor,interior_id)
	elif not near and is_zero_approx(_inline_door_amount) and is_instance_valid(view):
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED

func set_npc_rendering_active(active: bool) -> void:
	if inline_mode and active:
		for resident in all_npcs:
			if is_instance_valid(resident): resident.show()
	super.set_npc_rendering_active(active)
	if inline_mode and not active:
		for resident in all_npcs:
			if is_instance_valid(resident): resident.hide()
	if is_instance_valid(view):
		if active:
			view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			_warmed = true
		else:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED if _warmed else SubViewport.UPDATE_ONCE
	if not active and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null

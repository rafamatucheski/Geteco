extends Node
## Presentation and physical checkpoints; progression stays independent of scenes.
const PROGRESSION := preload("res://systems/Progression.gd")
var world
var progression = PROGRESSION.new()
var inside := false
var dialogue_open := false
var no_save := false
var save_path: String = PROGRESSION.DEFAULT_SAVE
var save_blocked := false
var ready_to_interact := false
var objective: Label
var prompt: Label
var notice: Label
var direction_arrow: Label
var dialogue: PanelContainer
var dialogue_text: Label
var marker: Node2D
var anchor: Node3D
var saved_heading := 0.0
var saved_size := 28.0
var clock := 0.0

func _ready() -> void:
	no_save = "--no-save" in OS.get_cmdline_user_args()
	anchor = Node3D.new()
	world.add_child(anchor)
	anchor.position = world.maciota_place.camera_target
	objective = _label(Vector2(650,24),20)
	prompt = _label(Vector2(26,584),20)
	notice = _label(Vector2(26,550),16)
	notice.text = "F5  Salvar · F9  Carregar"
	direction_arrow = _label(Vector2.ZERO,30)
	direction_arrow.text = "▲"
	direction_arrow.modulate = Color("f39a38")
	direction_arrow.pivot_offset = Vector2(12,20)
	marker = Node2D.new()
	marker.set_script(preload("res://ui/DoorAccessMarker.gd"))
	world.hud.add_child(marker)
	dialogue = PanelContainer.new()
	dialogue.position = Vector2(190,380)
	dialogue.custom_minimum_size = Vector2(900,165)
	world.hud.add_child(dialogue)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,18)
	dialogue.add_child(margin)
	dialogue_text = Label.new()
	dialogue_text.custom_minimum_size.x = 850
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.add_theme_font_size_override("font_size",18)
	margin.add_child(dialogue_text)
	dialogue.hide()
	_initialize_checkpoint.call_deferred()

func _label(point: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = point
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y",2)
	world.hud.add_child(label)
	return label

func _initialize_checkpoint() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	ready_to_interact = true
	if not no_save: load_checkpoint()
	_refresh()

func _input(event: InputEvent) -> void:
	if get_tree().paused or not ready_to_interact: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if dialogue_open:
		if event.physical_keycode in [KEY_E,KEY_ENTER,KEY_ESCAPE]: close_dialogue()
		get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_E:
			interact_nearest()
			get_viewport().set_input_as_handled()
		KEY_F5: save_checkpoint()
		KEY_F9: load_checkpoint()

func nearest_target() -> String:
	if world.driving.occupied: return ""
	var player_point: Vector3 = world.player.global_position
	var door: Vector3 = world.maciota_place.exit_position if inside else world.maciota_place.entry_position
	if player_point.distance_to(door) < 1.55: return "exit" if inside else "enter"
	if not inside: return ""
	var nearest := ""
	var distance := 1.35
	for key in ["maciota","mechanic","part"]:
		if key == "part" and progression.snapshot().phase != "collect_part": continue
		var point: Vector3 = world.maciota_place.interaction_points[key]
		var candidate := player_point.distance_to(point)
		if candidate < distance:
			var ray := PhysicsRayQueryParameters3D.create(player_point+Vector3.UP*.8,point+Vector3.UP*.8,1)
			if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			distance = candidate
			nearest = "workbench" if key == "part" else key
	return nearest

func interact_nearest() -> bool:
	if dialogue_open or not ready_to_interact: return false
	var target := nearest_target()
	if target in ["enter","exit"]: return transition(target == "enter")
	var result: Dictionary = progression.interact(target)
	if not result.ok: return false
	dialogue_open = true
	notice.hide()
	world.player.input_locked = true
	dialogue_text.text = (str(result.speaker)+"\n" if result.speaker != "" else "")+str(result.message)+"\n\nE  Continuar"
	dialogue.show()
	if result.changed: save_checkpoint()
	_refresh()
	return true

func close_dialogue() -> void:
	dialogue_open = false
	notice.show()
	world.player.input_locked = false
	dialogue.hide()

func checkpoint_clear(point: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .31
	capsule.height = 1.7
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.9)
	query.collision_mask = 7
	query.exclude = [world.player.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func transition(to_interior: bool, autosave := true) -> bool:
	if world.driving.occupied: return false
	var point: Vector3 = world.maciota_place.interior_spawn if to_interior else world.maciota_place.exterior_return
	if not checkpoint_clear(point):
		notice.text = "Passagem ocupada. Aguarde um instante."
		return false
	close_dialogue()
	if to_interior and not inside:
		saved_heading = world.camera.heading
		saved_size = world.camera.target_size
	inside = to_interior
	progression.set_location("harbor_garage" if inside else "harbor_street")
	world.maciota_place.set_interior_active(inside)
	world.player.teleport(point+Vector3.UP*.04)
	world.camera.target = anchor if inside else world.player
	world.camera.heading = 0.0 if inside else saved_heading
	world.camera.target_size = world.maciota_place.camera_size if inside else saved_size
	world.camera.size = world.camera.target_size
	world.camera.offset = world.maciota_place.camera_offset if inside else world.camera.EXTERIOR_OFFSET
	world.camera.locked = inside
	world.camera.initialized = false
	world.camera._process(1.0)
	if autosave: save_checkpoint()
	_refresh()
	return true

func save_checkpoint() -> void:
	if no_save: return
	if world.driving.occupied:
		notice.text = "Saia do carro para salvar."
		return
	if save_blocked:
		notice.text = "Save inválido preservado. Salvamento desativado nesta sessão."
		return
	var error: Error = progression.save_game(save_path)
	notice.text = "Progresso salvo · F9 carregar" if error == OK else "Não foi possível salvar (%d)." % error

func load_checkpoint() -> bool:
	if no_save or world.driving.occupied: return false
	var previous: Dictionary = progression.snapshot()
	var result: Dictionary = progression.load_game(save_path)
	if not result.ok:
		save_blocked = result.status == "invalid"
		if save_blocked: notice.text = "Save inválido preservado. Salvamento desativado nesta sessão."
		return false
	if not transition(progression.snapshot().location_id == "harbor_garage",false):
		progression.restore_snapshot(previous)
		return false
	save_blocked = false
	notice.text = "Backup recuperado." if result.status == "recovered_backup" else "Progresso carregado."
	return true

func _refresh() -> void:
	objective.text = progression.objective()
	if inside and progression.stage == "meet_maciota": objective.text = "Converse com Maciota."
	world.maciota_place.set_part_available(progression.snapshot().phase == "collect_part")

func _process(delta: float) -> void:
	clock += delta
	if clock < .1: return
	clock = 0
	var door: Vector3 = world.maciota_place.exit_position if inside else world.maciota_place.entry_position
	marker.visible = not world.camera.is_position_behind(door)
	if marker.visible: marker.position = world.camera.unproject_position(door+Vector3.UP*.06)
	var screen: Vector2 = world.camera.unproject_position(door)
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_area := Rect2(Vector2(45,80),viewport_size-Vector2(90,185))
	direction_arrow.visible = not inside and progression.stage != "complete" and not safe_area.has_point(screen)
	direction_arrow.position = Vector2(clampf(screen.x,45,viewport_size.x-65),clampf(screen.y,80,viewport_size.y-105))
	direction_arrow.rotation = (screen-viewport_size/2).angle()+PI/2
	var target := nearest_target() if ready_to_interact else ""
	var actions := {"enter":"E  Entrar", "exit":"E  Sair", "maciota":"E  Falar com Maciota", "mechanic":"E  Falar com mecânico", "workbench":"E  Pegar peça"}
	prompt.text = "" if dialogue_open else str(actions.get(target,""))

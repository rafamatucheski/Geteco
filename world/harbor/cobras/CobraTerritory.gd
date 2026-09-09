extends Node2D
## Local encounter, not a replacement for GangManager's campaign reputation.
signal state_changed(previous: String, current: String)
signal warning_issued(message: String)
const RESIDENT := preload("res://world/harbor/cobras/CobraResident.gd")
@export var notice_seconds := 2.0
@export var warning_seconds := 5.0
@export var confrontation_seconds := 5.0
@export var perception_radius := 320.0
var bounds := Rect2()
var guards: Array = []
var residents: Array = []
var state := "calm"
var _guard_points := PackedVector2Array()
var _resident_routes: Array[PackedVector2Array] = []
var _exposure := 0.0
var _lost_time := 0.0
var _tick := 0.0
var _aggressor := false
var _subject: Node2D
var _notice: Label
var _notice_time := 0.0
var _mission_access := false
var _defeated := false
var _encounter_active := false

func set_encounter_active(enabled: bool) -> void:
	_encounter_active = enabled
	if enabled:
		_exposure = 0.0
		_aggressor = false
		_set_state("calm")
		_notice_time = 0.0
		if is_instance_valid(_notice):
			_notice.text = ""
		for actor in guards:
			if is_instance_valid(actor):
				actor.combat_target = null

func set_mission_access(enabled: bool) -> void:
	_mission_access = enabled
	if enabled:
		_exposure = 0.0
		_aggressor = false
		_set_state("calm")
		_notice_time = 0.0
		if is_instance_valid(_notice):
			_notice.text = ""
		for actor in guards:
			if is_instance_valid(actor):
				actor.combat_target = null

func set_campaign_access(enabled: bool) -> void:
	set_mission_access(enabled)

func set_defeated(enabled: bool) -> void:
	_defeated = enabled
	if enabled:
		_exposure = 0.0
		_aggressor = false
		_set_state("calm")
		_notice_time = 0.0
		if is_instance_valid(_notice):
			_notice.text = ""
		for actor in guards:
			if is_instance_valid(actor):
				actor.combat_target = null

func configure(local_bounds: Rect2, guard_points: PackedVector2Array, resident_routes: Array[PackedVector2Array] = []) -> void:
	bounds = local_bounds
	_guard_points = guard_points.duplicate()
	_resident_routes = resident_routes.duplicate()

func _ready() -> void:
	add_to_group("cobra_territory")
	var layer := CanvasLayer.new()
	layer.name = "TerritoryNotice"
	layer.layer = 12
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	_notice = Label.new()
	_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_notice.offset_top = 100.0
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice.add_theme_font_size_override("font_size", 20)
	_notice.add_theme_color_override("font_color", Color("edc3a4"))
	_notice.add_theme_color_override("font_outline_color", Color("181b20"))
	_notice.add_theme_constant_override("outline_size", 6)
	screen.add_child(_notice)
	for index in mini(3, _guard_points.size()):
		_spawn_local(index, true, PackedVector2Array([_guard_points[index]]))
	for index in mini(2, _resident_routes.size()):
		if not _resident_routes[index].is_empty():
			_spawn_local(index, false, _resident_routes[index])

func _spawn_local(index: int, guard: bool, route: PackedVector2Array) -> void:
	var actor = RESIDENT.new()
	actor.name = ("CobraGuard" if guard else "CobraNeighbor") + str(index)
	actor.territory = self
	actor.guard = guard
	actor.profile = index
	actor.combat_role = ["lookout","enforcer","lookout"][index%3]
	actor.position = route[0]
	var world_route := PackedVector2Array()
	for point in route:
		world_route.append(to_global(point))
	actor.patrol = world_route
	add_child(actor)
	if guard:
		guards.append(actor)
	else:
		residents.append(actor)

func interaction_suspended() -> bool:
	if get_tree().paused:
		return true
	var player := get_tree().get_first_node_in_group("player")
	return is_instance_valid(player) and (player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true or player.get("is_dead") == true)

func _find_subject() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(player) and not player.visible:
		for vehicle in get_tree().get_nodes_in_group("vehicle"):
			if vehicle is Node2D and vehicle.get("is_driven_by_player") == true:
				return vehicle
	return player

func _physics_process(delta: float) -> void:
	if interaction_suspended():
		return
	if _mission_access or _defeated or _encounter_active:
		return
	_notice_time = maxf(0.0, _notice_time - delta)
	if _notice_time <= 0.0:
		_notice.text = ""
	_tick += delta
	if _tick < 0.2:
		return
	var elapsed := _tick
	_tick = 0.0
	_subject = _find_subject()
	var seen := false
	if is_instance_valid(_subject) and bounds.has_point(to_local(_subject.global_position)):
		for guard in guards:
			if is_instance_valid(guard) and not guard.is_dead and can_see(guard, _subject):
				seen = true
				break
	if not seen:
		_lost_time += elapsed
		if _lost_time >= 2.0:
			_exposure = 0.0
			_aggressor = false
			_set_state("calm")
		return
	_lost_time = 0.0
	if not _aggressor and get_respect() >= 25:
		_exposure = 0.0
		_set_state("calm")
		return
	_exposure += elapsed
	if _aggressor or _exposure >= notice_seconds + warning_seconds + confrontation_seconds:
		_set_state("combat")
	elif _exposure >= notice_seconds + warning_seconds:
		_set_state("confrontation")
	elif _exposure >= notice_seconds:
		_set_state("warning")
	else:
		_set_state("watch")

func get_respect() -> int:
	var manager := get_tree().get_first_node_in_group("gang_manager")
	return int(manager.get_respect("iron_cobras")) if is_instance_valid(manager) and manager.has_method("get_respect") else 0

func get_status() -> Dictionary:
	var living := 0
	for guard in guards:
		if is_instance_valid(guard) and not guard.is_dead:
			living += 1
	return {"state": state, "exposure": _exposure, "respect": get_respect(), "living_guards": living, "resident_count": residents.size(), "aggressor": _aggressor, "mission_access":_mission_access,"defeated":_defeated,"encounter_active":_encounter_active}

func can_see(observer: Node2D, subject: Node2D) -> bool:
	if not is_instance_valid(subject) or observer.global_position.distance_to(subject.global_position) > perception_radius:
		return false
	var query := PhysicsRayQueryParameters2D.create(observer.global_position, subject.global_position, 1)
	if observer is CollisionObject2D:
		query.exclude = [observer.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == subject

func combat_target_for(guard: Node2D) -> Node2D:
	if _mission_access or _defeated or _encounter_active or state != "combat" or interaction_suspended() or not is_instance_valid(_subject):
		return null
	if not bounds.has_point(to_local(_subject.global_position)) or not can_see(guard, _subject):
		return null
	return _subject

func report_aggression() -> void:
	if _encounter_active or _defeated:
		return
	# Permission to visit is not permission to assault locals. Only a finite
	# campaign encounter suppresses ambient retaliation while it owns the fight.
	_mission_access = false
	_aggressor = true
	_subject = _find_subject()
	_set_state("combat")

func _set_state(next: String) -> void:
	if state == next:
		return
	var previous := state
	state = next
	state_changed.emit(previous, state)
	var english := TranslationServer.get_locale().begins_with("en")
	var message := ""
	match state:
		"warning": message = "Private block. Keep moving." if english else "A quadra é nossa. Segue teu caminho."
		"confrontation": message = "Last warning. Leave now!" if english else "Último aviso. Vai embora agora!"
		"combat": message = "You were warned! Get out!" if english else "Você foi avisado! Sai daqui!"
	if message.is_empty():
		return
	warning_issued.emit(message)
	if is_instance_valid(_notice):
		_notice.text = message
		_notice_time = 4.0
	for guard in guards:
		if is_instance_valid(guard) and not guard.is_dead and can_see(guard, _subject):
			guard.say(message)
			break

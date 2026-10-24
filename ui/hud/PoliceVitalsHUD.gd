extends Control
## Shield-only overlay for equipped officers. Health remains private to combat.
## No per-officer Controls or scene scan per frame.
const STYLE := preload("res://ui/GameStyle.gd")
const MAX_DISTANCE_SQUARED := 45.0 * 45.0
const DAMAGE_VISIBLE_SECONDS := 4.0
const OCCLUSION_INTERVAL := 0.10
const OCCLUSION_BUDGET := 4
const BAR_WIDTH := 48.0
var _officers: Array[Dictionary] = []
var _registry_clock := 0.0
var _occlusion_clock := 0.0
var _occlusion_cursor := 0
var _has_drawn := false

func _ready() -> void:
	name = "PoliceVitals"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or get_tree().paused:
		_clear_overlay()
		return
	_registry_clock -= delta
	if _registry_clock <= 0.0:
		_registry_clock = 0.25
		_refresh_officers()
	if _officers.is_empty(): return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		_clear_overlay()
		return
	_occlusion_clock -= delta
	if _occlusion_clock <= 0.0:
		_occlusion_clock = OCCLUSION_INTERVAL
		_update_occlusion(camera)
	# Camera motion needs smooth projection; physics visibility work is bounded separately.
	queue_redraw()

func _clear_overlay() -> void:
	if not _has_drawn: return
	_has_drawn = false
	queue_redraw()

func _refresh_officers() -> void:
	var previous := {}
	for entry in _officers:
		if is_instance_valid(entry.actor): previous[entry.actor.get_instance_id()] = entry
	_officers.clear()
	for actor in get_tree().get_nodes_in_group("v2_police_officers"):
		if not actor is Node3D or actor.get_viewport() != get_viewport() or float(actor.get("max_armor")) <= 0.0 or float(actor.get("armor")) <= 0.0: continue
		var entry: Dictionary = previous.get(actor.get_instance_id(), {"actor":actor, "clear":false})
		_officers.append(entry)
	if _officers.is_empty(): queue_redraw()

func _eligible(actor: Node3D, camera: Camera3D) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.is_visible_in_tree(): return false
	if bool(actor.get("dead")) or float(actor.get("max_armor")) <= 0.0 or float(actor.get("armor")) <= 0.0: return false
	if not is_instance_valid(actor.get("controller")): return false
	if not actor._shares_player_context(): return false
	if camera.global_position.distance_squared_to(actor.global_position) > MAX_DISTANCE_SQUARED: return false
	var anchor := actor.global_position + Vector3.UP * 2.15
	if not camera.is_position_in_frustum(anchor): return false
	var recent_hit := Time.get_ticks_msec() * 0.001 - float(actor.get("last_damage_time")) < DAMAGE_VISIBLE_SECONDS
	return recent_hit or bool(actor.get("sees_player")) or float(actor.get("response_aggression")) > 0.0

func _update_occlusion(camera: Camera3D) -> void:
	# Four static-world traces per tick at most, shared by all heavy officers.
	# Bodies use layer 2; tracing layer 1 prevents bars revealing actors through solids.
	var remaining := OCCLUSION_BUDGET
	for offset in _officers.size():
		var index := (_occlusion_cursor + offset) % _officers.size()
		var entry: Dictionary = _officers[index]
		if not is_instance_valid(entry.actor): continue
		var actor := entry.actor as Node3D
		if not _eligible(actor, camera):
			entry.clear = false
			continue
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, actor.global_position + Vector3.UP * 1.65, 1)
		query.hit_from_inside = true
		entry.clear = actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		remaining -= 1
		if remaining <= 0:
			_occlusion_cursor = (index + 1) % _officers.size()
			return
	_occlusion_cursor = 0

func _draw() -> void:
	_has_drawn = false
	if get_tree().paused: return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return
	for entry in _officers:
		if not is_instance_valid(entry.actor): continue
		var actor := entry.actor as Node3D
		if not entry.clear or not _eligible(actor, camera): continue
		_has_drawn = true
		var point := camera.unproject_position(actor.global_position + Vector3.UP * 2.15)
		var armor_ratio := clampf(float(actor.get("armor")) / maxf(1.0, float(actor.get("max_armor"))), 0.0, 1.0)
		var origin := (point + Vector2(-BAR_WIDTH * 0.5, -10.0)).round()
		draw_rect(Rect2(origin - Vector2(2,2), Vector2(BAR_WIDTH + 4,9)), Color("171a1fe8"))
		_bar(origin, armor_ratio)

func _bar(origin: Vector2, ratio: float) -> void:
	var track := Rect2(origin, Vector2(BAR_WIDTH,5))
	draw_rect(track, Color("353e49"))
	if ratio > 0.0: draw_rect(Rect2(origin, Vector2(BAR_WIDTH * ratio,5)), STYLE.ARMOR)

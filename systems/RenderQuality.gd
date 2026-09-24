extends Node
## Configure streamed viewports and one shadow-casting key light per 3D world.

## A display setting can touch hundreds of cached 3D viewports in Harbor. MSAA
## allocation and the first redraw are indivisible per viewport, so refreshing
## every cache in the signal callback creates a large synchronous frame spike.
## Authored views keep their explicit AA. Generic live views follow the global
## option through this bounded queue; generic dormant caches are promoted only
## when their owner makes them resident again.
const REFRESH_MAX_VIEWPORTS_PER_FRAME := 4
const REFRESH_PIXEL_BUDGET_PER_FRAME := 1048576
const SMALL_SCENE_IMMEDIATE_LIMIT := 4
const RESIDENCY_GRACE_INTERVAL := 0.125
const RESIDENCY_GRACE_TICKS := 8
const RESIDENCY_GRACE_SCAN_PER_TICK := 64
const PENDING_MSAA_META := &"quality_pending_msaa"
const PENDING_GENERATION_META := &"quality_pending_generation"
const RESIDENCY_HOOK_META := &"quality_residency_hook"

var _refresh_queue: Array[Dictionary] = []
var _grace_deferred: Array[WeakRef] = []
var _residency_grace_timer: Timer
var _residency_grace_ticks_left := 0
var _refresh_generation := 0
var _refresh_stats := {
	"generation": 0,
	"queued": 0,
	"deferred_dormant": 0,
	"applied": 0,
	"awakened": 0,
	"max_applied_in_frame": 0,
	"max_pixels_in_frame": 0,
	"pending": 0,
	"deferred_remaining": 0,
	"grace_checks": 0,
	"idle": true,
}

func _ready() -> void:
	get_tree().root.msaa_2d = Viewport.MSAA_DISABLED
	get_tree().node_added.connect(_configure_node)
	get_parent().display_settings_changed.connect(_refresh_quality)
	_residency_grace_timer = Timer.new()
	_residency_grace_timer.name = "QualityResidencyGrace"
	_residency_grace_timer.one_shot = false
	_residency_grace_timer.wait_time = RESIDENCY_GRACE_INTERVAL
	_residency_grace_timer.timeout.connect(_scan_residency_grace)
	add_child(_residency_grace_timer)
	set_process(false)

func _configure_node(node: Node) -> void:
	if node is SubViewport:
		_configure_viewport(node)
	elif node is Sprite2D:
		_configure_display.call_deferred(node)
	elif node is DirectionalLight3D:
		_configure_light.call_deferred(node)

func _configure_viewport(viewport: SubViewport) -> void:
	if not viewport.has_meta("authored_msaa"):
		viewport.set_meta("authored_msaa", int(viewport.msaa_3d))
	if not viewport.has_meta("authored_msaa_2d"):
		viewport.set_meta("authored_msaa_2d", int(viewport.msaa_2d))
	viewport.add_to_group("quality_viewports")
	if viewport.disable_3d:
		viewport.msaa_2d = _effective_msaa_2d(viewport)
	else:
		viewport.msaa_3d = _effective_msaa_3d(viewport)

func _refresh_quality() -> void:
	get_tree().root.msaa_3d = get_parent().msaa_3d as Viewport.MSAA
	_refresh_generation += 1
	_refresh_queue.clear()
	_grace_deferred.clear()
	_residency_grace_ticks_left = 0
	if is_instance_valid(_residency_grace_timer):
		_residency_grace_timer.stop()
	_reset_refresh_stats()
	var changes: Array[Dictionary] = []
	for candidate in get_tree().get_nodes_in_group("quality_viewports"):
		var viewport := candidate as SubViewport
		if not is_instance_valid(viewport):
			continue
		var target := _effective_msaa_2d(viewport) if viewport.disable_3d else _effective_msaa_3d(viewport)
		var current := int(viewport.msaa_2d) if viewport.disable_3d else int(viewport.msaa_3d)
		if current == int(target):
			_clear_pending_residency(viewport, false)
			continue
		changes.append(_refresh_item(viewport, int(target)))
	_refresh_stats.queued = changes.size()
	if changes.size() <= SMALL_SCENE_IMMEDIATE_LIMIT:
		for item in changes:
			_apply_refresh_item(item, true)
			var viewport := (item.viewport as WeakRef).get_ref() as SubViewport
			_clear_pending_residency(viewport, false)
		_refresh_stats.pending = 0
		return
	for item in changes:
		var viewport := (item.viewport as WeakRef).get_ref() as SubViewport
		if not is_instance_valid(viewport):
			continue
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			_defer_until_resident(viewport, int(item.target))
		else:
			_clear_pending_residency(viewport, false)
			_refresh_queue.append(item)
	_refresh_queue.sort_custom(_refresh_before)
	_refresh_stats.deferred_dormant = _grace_deferred.size()
	_refresh_stats.deferred_remaining = _grace_deferred.size()
	_refresh_stats.pending = _refresh_queue.size()
	if not _grace_deferred.is_empty():
		_residency_grace_ticks_left = RESIDENCY_GRACE_TICKS
		_residency_grace_timer.start()
	set_process(not _refresh_queue.is_empty())
	_update_idle_stat()


func _process(_delta: float) -> void:
	var applied := 0
	var pixels := 0
	while not _refresh_queue.is_empty() and applied < REFRESH_MAX_VIEWPORTS_PER_FRAME:
		var item: Dictionary = _refresh_queue.pop_front()
		var viewport := (item.viewport as WeakRef).get_ref() as SubViewport
		if not is_instance_valid(viewport) or int(item.generation) != _refresh_generation:
			continue
		var item_pixels := maxi(1, viewport.size.x * viewport.size.y)
		if applied > 0 and pixels + item_pixels > REFRESH_PIXEL_BUDGET_PER_FRAME:
			_refresh_queue.push_front(item)
			break
		_apply_refresh_item(item, false)
		applied += 1
		pixels += item_pixels
	_refresh_stats.max_applied_in_frame = maxi(int(_refresh_stats.max_applied_in_frame), applied)
	_refresh_stats.max_pixels_in_frame = maxi(int(_refresh_stats.max_pixels_in_frame), pixels)
	_refresh_stats.pending = _refresh_queue.size()
	if _refresh_queue.is_empty():
		set_process(false)
	_update_idle_stat()


func _scan_residency_grace() -> void:
	if _residency_grace_ticks_left <= 0 or _grace_deferred.is_empty():
		_finish_residency_grace()
		return
	_residency_grace_ticks_left -= 1
	var scans := mini(RESIDENCY_GRACE_SCAN_PER_TICK, _grace_deferred.size())
	for _index in scans:
		var viewport_ref: WeakRef = _grace_deferred.pop_front()
		var viewport := viewport_ref.get_ref() as SubViewport
		_refresh_stats.grace_checks = int(_refresh_stats.grace_checks) + 1
		if not is_instance_valid(viewport):
			_refresh_stats.deferred_remaining = maxi(0, int(_refresh_stats.deferred_remaining) - 1)
			continue
		if int(viewport.get_meta(PENDING_GENERATION_META, -1)) != _refresh_generation:
			continue
		if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED:
			_grace_deferred.append(viewport_ref)
		else:
			_prepare_viewport_residency(viewport)
	if _residency_grace_ticks_left <= 0 or _grace_deferred.is_empty():
		_finish_residency_grace()
	_update_idle_stat()


func _finish_residency_grace() -> void:
	if is_instance_valid(_residency_grace_timer):
		_residency_grace_timer.stop()
	_grace_deferred.clear()
	_residency_grace_ticks_left = 0
	_update_idle_stat()


func _defer_until_resident(viewport: SubViewport, target: int) -> void:
	viewport.set_meta(PENDING_MSAA_META, target)
	viewport.set_meta(PENDING_GENERATION_META, _refresh_generation)
	viewport.set_meta(RESIDENCY_HOOK_META, _prepare_weak_viewport.bind(weakref(viewport)))
	_grace_deferred.append(weakref(viewport))


## Owners that wake a long-lived cached SubViewport call the metadata Callable
## `quality_residency_hook` immediately before changing UPDATE_DISABLED. This is
## event-driven, touches only that viewport and leaves RenderQuality fully idle.
func _prepare_weak_viewport(viewport_ref: WeakRef) -> bool:
	var viewport := viewport_ref.get_ref() as SubViewport
	return _prepare_viewport_residency(viewport)


func prepare_viewport_residency(viewport: SubViewport) -> bool:
	return _prepare_viewport_residency(viewport)


func _prepare_viewport_residency(viewport: SubViewport) -> bool:
	if not is_instance_valid(viewport) or not viewport.has_meta(PENDING_MSAA_META):
		return false
	var target := int(viewport.get_meta(PENDING_MSAA_META))
	var item := _refresh_item(viewport, target)
	_apply_refresh_item(item, false)
	_clear_pending_residency(viewport, true)
	return true


func _clear_pending_residency(viewport: SubViewport, count_completion: bool) -> void:
	if not is_instance_valid(viewport) or not viewport.has_meta(PENDING_MSAA_META):
		return
	viewport.remove_meta(PENDING_MSAA_META)
	viewport.remove_meta(PENDING_GENERATION_META)
	viewport.remove_meta(RESIDENCY_HOOK_META)
	if count_completion:
		_refresh_stats.deferred_remaining = maxi(0, int(_refresh_stats.deferred_remaining) - 1)


func _update_idle_stat() -> void:
	var timer_active := is_instance_valid(_residency_grace_timer) and not _residency_grace_timer.is_stopped()
	_refresh_stats.idle = _refresh_queue.is_empty() and not is_processing() and not timer_active


func _apply_refresh_item(item: Dictionary, immediate: bool) -> void:
	var viewport := (item.viewport as WeakRef).get_ref() as SubViewport
	if not is_instance_valid(viewport) or int(item.generation) != _refresh_generation:
		return
	var changed := false
	if viewport.disable_3d:
		if int(viewport.msaa_2d) != int(item.target):
			viewport.msaa_2d = int(item.target) as Viewport.MSAA
			changed = true
	else:
		if int(viewport.msaa_3d) != int(item.target):
			viewport.msaa_3d = int(item.target) as Viewport.MSAA
			changed = true
	if not changed:
		return
	_refresh_stats.applied = int(_refresh_stats.applied) + 1
	# Tiny isolated scenes keep the historical synchronous contract. Production
	# scenes never wake every cached viewport together: a dormant cache is either
	# deferred until resident or redrawn as one bounded queue item.
	if viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and (immediate or int(item.target) <= int(item.current)):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_refresh_stats.awakened = int(_refresh_stats.awakened) + 1


func _refresh_item(viewport: SubViewport, target: int) -> Dictionary:
	var current := int(viewport.msaa_2d) if viewport.disable_3d else int(viewport.msaa_3d)
	var residence := _residence_priority(viewport)
	return {
		"viewport": weakref(viewport),
		"target": target,
		"current": current,
		"pixels": maxi(1, viewport.size.x * viewport.size.y),
		"residence": residence,
		"generation": _refresh_generation,
	}


func _refresh_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a.residence) != int(b.residence):
		return int(a.residence) < int(b.residence)
	return int(a.pixels) < int(b.pixels)


func _residence_priority(viewport: SubViewport) -> int:
	match viewport.render_target_update_mode:
		SubViewport.UPDATE_ALWAYS, SubViewport.UPDATE_WHEN_VISIBLE:
			return 0
		SubViewport.UPDATE_ONCE:
			return 1
		_:
			return 2


func _effective_msaa_3d(viewport: SubViewport) -> Viewport.MSAA:
	var authored := int(viewport.get_meta("authored_msaa", int(viewport.msaa_3d)))
	# Explicit AA is part of the view's visual contract. The global option is a
	# default for generic runtime views, not a multiplier over authored quality.
	if authored > Viewport.MSAA_DISABLED and not bool(viewport.get_meta("quality_follow_global", false)):
		return authored as Viewport.MSAA
	return maxi(authored, int(get_parent().msaa_3d)) as Viewport.MSAA


func _effective_msaa_2d(viewport: SubViewport) -> Viewport.MSAA:
	var authored := int(viewport.get_meta("authored_msaa_2d", int(viewport.msaa_2d)))
	return (authored if authored > Viewport.MSAA_DISABLED else Viewport.MSAA_2X) as Viewport.MSAA


func _reset_refresh_stats() -> void:
	_refresh_stats = {
		"generation": _refresh_generation,
		"queued": 0,
		"deferred_dormant": 0,
		"applied": 0,
		"awakened": 0,
		"max_applied_in_frame": 0,
		"max_pixels_in_frame": 0,
		"pending": 0,
		"deferred_remaining": 0,
		"grace_checks": 0,
		"idle": true,
	}


func get_refresh_stats() -> Dictionary:
	_update_idle_stat()
	_refresh_stats.pending = _refresh_queue.size()
	return _refresh_stats.duplicate(true)

func _configure_light(light) -> void:
	if not is_instance_valid(light) or not light.is_inside_tree(): return
	var viewport := light.get_viewport() as SubViewport
	if viewport == null: return
	var key: WeakRef = viewport.get_meta("shadow_key") if viewport.has_meta("shadow_key") else null
	if key != null and is_instance_valid(key.get_ref()): return
	viewport.set_meta("shadow_key", weakref(light))
	# Animated humans use the live silhouette; reserve shadow maps for props/rooms.
	if viewport.get_parent() is CharacterBody2D: return
	if viewport.render_target_update_mode not in [SubViewport.UPDATE_ONCE, SubViewport.UPDATE_DISABLED]: return
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL

	var camera := viewport.get_camera_3d()
	if camera:
		light.directional_shadow_max_distance = camera.position.length() + (camera.size * 2.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 6.0)
		light.shadow_bias = 0.02
		light.shadow_normal_bias = 0.1

func _configure_display(display) -> void:
	if not is_instance_valid(display) or not display.is_inside_tree(): return
	if display.name == "PoseShadow" or display.name == "VehicleShadow": return
	var host: Node = display.get_parent()
	# Dante is the permanent visual focus and keeps one live projected silhouette.
	# It reuses the existing character viewport texture, so this does not create a
	# shadow map, light or additional SubViewport. Ambient characters retain only
	# their cheap contact patch until their proximity shadow budget is explicit.
	if host is CharacterBody2D:
		if host.is_in_group("player") and host.get("sprite_3d_display") == display:
			var player_viewport := host.get("viewport_3d") as SubViewport
			if player_viewport != null and player_viewport.transparent_bg:
				preload("res://systems/ContactShadow.gd").add_silhouette(display, player_viewport)
		return
	var viewport: SubViewport
	# Explicit production display contracts; never flatten a whole interior/UI.
	if host.get("sprite_3d_display") == display or host.get("presentation_sprite") == display or (host is CharacterBody2D and host.get("display") == display):
		viewport = host.get("viewport_3d") as SubViewport
		if viewport == null: viewport = host.get("viewport") as SubViewport
	elif (host.get("sprite") == display or host.get("visual") == display) and (host.get("body_viewport") is SubViewport or host.get("viewport_3d") is SubViewport or host.get("viewport") is SubViewport):
		viewport = host.get("body_viewport") as SubViewport
		if viewport == null: viewport = host.get("viewport_3d") as SubViewport
		if viewport == null: viewport = host.get("viewport") as SubViewport
		if viewport != null and viewport.transparent_bg:
			var footprint: Vector2 = host.get("footprint") if host.get("footprint") is Vector2 else Vector2.ZERO
			preload("res://systems/ContactShadow.gd").add_vehicle_silhouette(display, viewport, footprint)
		return
	elif host.get("lamp_sprite") == display:
		return
	elif host.get("sprite_3d") == display and host.has_method("project_floor"):
		viewport = host.get("viewport_3d") as SubViewport
		if viewport != null and host.get("model") is Node3D:
			preload("res://systems/StaticGroundShadow.gd").build(host,host.model,viewport)
		return
	if viewport == null or not viewport.transparent_bg: return
	preload("res://systems/ContactShadow.gd").add_silhouette(display,viewport)

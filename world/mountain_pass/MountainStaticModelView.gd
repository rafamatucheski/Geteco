extends Node2D
## A ground-anchored, metrically calibrated model; physical footprints use the
## exact same projection as the displayed render, including camera foreshortening.
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var model: Node3D
var _build_profile: Dictionary = {}
var _render_once_queued := false
var _render_once_in_flight := false
var _render_started_frame := -1
var _render_completed_frame := -1
var _render_generation := 0
var _active_render_purpose := &""
var _prepare_phase := 0
var _prepare_quiet_frames := 0
var _prepare_started_frame := -1
var _prepare_bootstrap_frame := -1
var _prepare_target_frame := -1
var _prepare_full_frame := -1
var _prepare_completed_frame := -1
var _prepare_bootstrap_usec := 0
var _prepare_target_usec := 0
var _prepare_full_usec := 0
var _prepare_frame_started_usec := 0
var _render_issue_usec := 0
var _prepare_units: Array[VisualInstance3D] = []
var _prepare_unit_visibility: Dictionary = {}
var _prepare_unit_index := 0
var _prepare_unit_total := 0
var _prepare_unit_frames: Array[int] = []
var _prepare_unit_peak_issue_usec := 0
var _prepare_unit_peak_adjacent_usec := 0
var _prepared_for_first_presentation := false
var _first_presentation_reused := false
var _visible_request_pending := false
var _model_visibility_before_prepare := true
var _sprite_visibility_before_prepare := true
var _final_render_size := Vector2i.ZERO
var _tree_mutation_serial := 0
var _observed_mutation_serial := -1
var _tracked_mutation_nodes: Dictionary = {}
var _mutation_tracking_closed := false
var _mutation_during_prepare := false
var _scheduler_request_in_flight := false
var _scheduler_ticket: Dictionary = {}
var _background_deferred_near_frames := 0
var _background_preparation_enabled := true
static var _environment_template: Environment
static var _last_render_claim_frame := -1
static var _global_bootstrap_state := 0
static var _global_bootstrap_loading_counter := 0
static var _global_bootstrap_attempt_session := -1
static var _global_bootstrap_result: Dictionary = {
	"state": "cold",
	"scope": "loading_global",
	"producer": "mountain_static_graphics_backend",
	"charged_to": "loading",
	"ready": false,
	"reused": false,
	"skipped_headless": false,
	"timed_out": false,
	"elapsed_usec": 0,
	"draw_wait_usec": 0,
	"attempts": 0,
}
static var _render_telemetry := {
	"queued_total": 0,
	"started_total": 0,
	"completed_total": 0,
	"visible_reuse_total": 0,
	"deferred_near_total": 0,
	"aborted_mutation_total": 0,
	"pending": 0,
	"in_flight": 0,
	"peak_usec": 0,
	"adjacent_frame_peak_usec": 0,
	"unit_slices_total": 0,
	"max_waited_frames": 0,
}
static var _render_records: Array[Dictionary] = []
const PREPARE_QUIET_FRAMES := 12
const PREPARE_SCREEN_MARGIN := 640.0
const BACKGROUND_RENDER_FRAME_GAP := 3
const MAX_RENDER_RECORDS := 128
const PURPOSE_VISIBLE := &"visible"
const PURPOSE_PREPARE_BOOTSTRAP := &"prepare_bootstrap"
const PURPOSE_PREPARE_TARGET := &"prepare_target"
const PURPOSE_PREPARE_UNIT := &"prepare_unit"
const PURPOSE_PREPARE_FULL := &"prepare_full"

class _BootstrapDrawWaiter extends RefCounted:
	signal resolved(drawn: bool)
	var done := false

	func finish(drawn: bool) -> void:
		if done:
			return
		done = true
		resolved.emit(drawn)

static func global_graphics_backend_ready() -> bool:
	return _global_bootstrap_state == 2

static func global_graphics_prewarm_snapshot() -> Dictionary:
	return _global_bootstrap_result.duplicate(true)

static func begin_graphics_prewarm_loading_session() -> int:
	_global_bootstrap_loading_counter += 1
	return _global_bootstrap_loading_counter

static func prewarm_graphics_backend(tree: SceneTree, timeout_ms := 3000, loading_session := -1) -> Dictionary:
	if tree == null or tree.root == null:
		return {
			"state": "invalid_tree",
			"scope": "loading_global",
			"producer": "mountain_static_graphics_backend",
			"charged_to": "loading",
			"ready": false,
			"reused": false,
			"skipped_headless": false,
			"timed_out": false,
			"elapsed_usec": 0,
			"draw_wait_usec": 0,
			"attempts": int(_global_bootstrap_result.get("attempts", 0)),
		}
	if _global_bootstrap_state == 2:
		var cached := _global_bootstrap_result.duplicate(true)
		cached["reused"] = true
		return cached
	if _global_bootstrap_state == 3:
		# A timeout is terminal for one loading session, preventing an accidental
		# retry loop. A later begin() receives another session and may try once.
		if loading_session < 0 or loading_session == _global_bootstrap_attempt_session:
			var failed_cached := _global_bootstrap_result.duplicate(true)
			failed_cached["reused"] = true
			failed_cached["retry_deferred_to_next_loading"] = true
			return failed_cached
		_global_bootstrap_state = 0
	if _global_bootstrap_state == 1:
		var join_deadline := Time.get_ticks_msec() + maxi(1, timeout_ms)
		while _global_bootstrap_state == 1 and Time.get_ticks_msec() < join_deadline:
			await tree.process_frame
		var joined := _global_bootstrap_result.duplicate(true)
		joined["reused"] = true
		if _global_bootstrap_state == 1:
			joined["state"] = "join_timeout"
			joined["ready"] = false
			joined["timed_out"] = true
		return joined
	# Headless validates the loading contract without pretending to exercise a GPU.
	if DisplayServer.get_name() == "headless":
		_global_bootstrap_result = {
			"state": "skipped_headless",
			"scope": "loading_global",
			"producer": "mountain_static_graphics_backend",
			"charged_to": "loading",
			"ready": false,
			"reused": false,
			"skipped_headless": true,
			"timed_out": false,
			"elapsed_usec": 0,
			"draw_wait_usec": 0,
			"attempts": int(_global_bootstrap_result.get("attempts", 0)),
			"loading_session": loading_session,
		}
		return _global_bootstrap_result.duplicate(true)

	_global_bootstrap_state = 1
	_global_bootstrap_attempt_session = loading_session
	var attempt := int(_global_bootstrap_result.get("attempts", 0)) + 1
	var total_started := Time.get_ticks_usec()
	var host := Node.new()
	host.name = "MountainStaticGraphicsPrewarm"
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport := SubViewport.new()
	viewport.name = "BackendBootstrap1x1"
	viewport.size = Vector2i.ONE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera := Camera3D.new()
	camera.current = true
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -24, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = _new_environment()
	viewport.add_child(environment)
	host.add_child(viewport)
	tree.root.add_child(host)
	# Keep a live texture reference so the off-screen SubViewport cannot be
	# discarded as unused while the loading screen remains on the main viewport.
	var bootstrap_texture := viewport.get_texture()
	await tree.process_frame

	var waiter := _BootstrapDrawWaiter.new()
	var draw_callable := Callable(waiter, "finish").bind(true)
	RenderingServer.frame_post_draw.connect(draw_callable, Object.CONNECT_ONE_SHOT)
	var timer := tree.create_timer(maxf(0.001, float(timeout_ms) / 1000.0), true, false, true)
	var timeout_callable := Callable(waiter, "finish").bind(false)
	timer.timeout.connect(timeout_callable, Object.CONNECT_ONE_SHOT)
	var draw_started := Time.get_ticks_usec()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var drawn: bool = await waiter.resolved
	var draw_wait_usec := Time.get_ticks_usec() - draw_started
	if RenderingServer.frame_post_draw.is_connected(draw_callable):
		RenderingServer.frame_post_draw.disconnect(draw_callable)
	if is_instance_valid(timer) and timer.timeout.is_connected(timeout_callable):
		timer.timeout.disconnect(timeout_callable)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Touching the texture after frame_post_draw makes the completion contract
	# explicit without forcing a synchronous full-size readback.
	var texture_size := bootstrap_texture.get_size()
	var elapsed_usec := Time.get_ticks_usec() - total_started
	host.queue_free()
	await tree.process_frame
	var temporary_viewport_released := not is_instance_valid(host)
	_global_bootstrap_state = 2 if drawn else 3
	_global_bootstrap_result = {
		"state": "ready" if drawn else "timeout",
		"scope": "loading_global",
		"producer": "mountain_static_graphics_backend",
		"charged_to": "loading",
		"ready": drawn,
		"reused": false,
		"skipped_headless": false,
		"timed_out": not drawn,
		"retry_deferred_to_next_loading": not drawn,
		"elapsed_usec": elapsed_usec,
		"draw_wait_usec": draw_wait_usec,
		"attempts": attempt,
		"loading_session": loading_session,
		"frame": Engine.get_process_frames(),
		"texture_size": texture_size,
		"temporary_viewport_released": temporary_viewport_released,
		"renderer": RenderingServer.get_current_rendering_method(),
	}
	return _global_bootstrap_result.duplicate(true)

static func reset_global_graphics_prewarm_for_tests() -> void:
	_global_bootstrap_state = 0
	_global_bootstrap_loading_counter = 0
	_global_bootstrap_attempt_session = -1
	_global_bootstrap_result = {
		"state": "cold",
		"scope": "loading_global",
		"producer": "mountain_static_graphics_backend",
		"charged_to": "loading",
		"ready": false,
		"reused": false,
		"skipped_headless": false,
		"timed_out": false,
		"elapsed_usec": 0,
		"draw_wait_usec": 0,
		"attempts": 0,
	}

static func force_global_graphics_prewarm_timeout_for_tests(loading_session: int) -> void:
	_global_bootstrap_state = 3
	_global_bootstrap_attempt_session = loading_session
	_global_bootstrap_result = {
		"state": "timeout",
		"scope": "loading_global",
		"producer": "mountain_static_graphics_backend",
		"charged_to": "loading",
		"ready": false,
		"reused": false,
		"skipped_headless": false,
		"timed_out": true,
		"retry_deferred_to_next_loading": true,
		"elapsed_usec": 3000000,
		"draw_wait_usec": 3000000,
		"attempts": 1,
		"loading_session": loading_session,
		"temporary_viewport_released": true,
	}

static func _new_environment() -> Environment:
	# The template keeps the immutable configuration warm, while every view gets
	# its own resource because callers legitimately tune ambient energy after
	# build_view(). Sharing that mutable Environment would couple unrelated views.
	if _environment_template == null:
		_environment_template = Environment.new()
		_environment_template.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment_template.ambient_light_color = Color("b8c8d0")
		_environment_template.ambient_light_energy = 0.65
	return _environment_template.duplicate(false) as Environment

static func _has_positional_shadow(node: Node) -> bool:
	if (node is OmniLight3D or node is SpotLight3D) and node.shadow_enabled:
		return true
	for child in node.get_children():
		if _has_positional_shadow(child):
			return true
	return false

func build_view(script: Script, metres_in_view: float, pixels_per_metre: float, target := Vector3.ZERO, view_direction := Vector3(0,24,20), render_size := Vector2i(960,800)) -> void:
	var total_started := Time.get_ticks_usec()
	var stage_started := total_started
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ModelViewport3D"
	viewport_3d.size = render_size
	viewport_3d.transparent_bg = true
	# Never attach a half-built viewport armed for rendering. Streamed callers
	# disable it immediately after this method; UPDATE_DISABLED from allocation
	# prevents the renderer from observing intermediate camera/world states.
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_3d.own_world_3d = true
	viewport_3d.gui_disable_input = true
	model = script.new()
	viewport_3d.add_child(model)
	camera_3d = Camera3D.new()
	viewport_3d.add_child(camera_3d)
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = metres_in_view
	camera_3d.look_at_from_position(target + view_direction, target)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-24,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = _new_environment()
	viewport_3d.add_child(env)
	_build_profile["detached_tree_usec"] = Time.get_ticks_usec()-stage_started

	# Enter the SceneTree once with the complete world. Adding camera, model,
	# light and environment one by one to a live SubViewport repeatedly wakes its
	# rendering state and amplified batches of static views during streaming.
	stage_started = Time.get_ticks_usec()
	add_child(viewport_3d)
	_connect_mutation_tracking()
	# Godot defaults each viewport to a 2048px positional-light shadow atlas.
	# Most static projections only use the directional light above, so retaining
	# that atlas adds allocation/initialization without contributing any pixels.
	# Models that actually contain a shadowed Omni/Spot light keep the default.
	if not _has_positional_shadow(model):
		viewport_3d.positional_shadow_atlas_size = 0
	# Camera fixa: nunca se move depois daqui. Com physics_interpolation ligada no
	# projeto, unproject_position()/project_ray_* usam o transform INTERPOLADO --
	# que no quadro em que a camera nasce ainda e o transform anterior (sem o
	# look_at). Todo o resto deste arquivo projeta geometria de colisao, pontos de
	# interacao e o offset do sprite AQUI, no mesmo quadro, e sairia calculado com
	# uma camera sem orientacao (o chao inteiro colapsando numa faixa horizontal).
	# Sem interpolacao nesta camera, a projecao le o transform de verdade.
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	_build_profile["attach_world_usec"] = Time.get_ticks_usec()-stage_started

	stage_started = Time.get_ticks_usec()
	sprite_3d = Sprite2D.new()
	sprite_3d.name = "GroundAnchoredModel"
	sprite_3d.texture = viewport_3d.get_texture()
	var rendered_metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * pixels_per_metre / rendered_metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale
	add_child(sprite_3d)
	_build_profile["projection_sprite_usec"] = Time.get_ticks_usec()-stage_started
	_build_profile["total_usec"] = Time.get_ticks_usec()-total_started
	# Non-streamed views keep the historical render-once behavior. A streamed
	# caller can set UPDATE_DISABLED before the frame boundary, without any render
	# having been requested while the viewport was incomplete.
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func get_build_profile() -> Dictionary:
	return _build_profile.duplicate()

func get_render_profile() -> Dictionary:
	return {
		"generation": _render_generation,
		"queued": _render_once_queued,
		"in_flight": _render_once_in_flight,
		"started_frame": _render_started_frame,
		"completed_frame": _render_completed_frame,
		"active_purpose": _active_render_purpose,
		"prepare_phase": _prepare_phase,
		"prepare_started_frame": _prepare_started_frame,
		"prepare_bootstrap_frame": _prepare_bootstrap_frame,
		"prepare_target_frame": _prepare_target_frame,
		"prepare_full_frame": _prepare_full_frame,
		"prepare_completed_frame": _prepare_completed_frame,
		"prepare_bootstrap_usec": _prepare_bootstrap_usec,
		"prepare_target_usec": _prepare_target_usec,
		"prepare_full_usec": _prepare_full_usec,
		"prepare_unit_frames": _prepare_unit_frames.duplicate(),
		"prepare_unit_index": _prepare_unit_index,
		"prepare_unit_total": _prepare_unit_total,
		"prepare_unit_peak_issue_usec": _prepare_unit_peak_issue_usec,
		"prepare_unit_peak_adjacent_usec": _prepare_unit_peak_adjacent_usec,
		"prepared_for_first_presentation": _prepared_for_first_presentation,
		"first_presentation_reused": _first_presentation_reused,
		"background_deferred_near_frames": _background_deferred_near_frames,
		"tracked_mutation_nodes": _tracked_mutation_nodes.size(),
	}

static func static_render_telemetry_snapshot() -> Dictionary:
	var result := _render_telemetry.duplicate(true)
	result["records"] = _render_records.duplicate(true)
	result["scheduler"] = RUNTIME_WORK.telemetry_snapshot()
	return result

static func reset_static_render_telemetry_for_tests() -> void:
	_last_render_claim_frame = -1000
	_render_telemetry = {
		"queued_total": 0,
		"started_total": 0,
		"completed_total": 0,
		"visible_reuse_total": 0,
		"deferred_near_total": 0,
		"aborted_mutation_total": 0,
		"pending": 0,
		"in_flight": 0,
		"peak_usec": 0,
		"adjacent_frame_peak_usec": 0,
		"unit_slices_total": 0,
		"max_waited_frames": 0,
	}
	_render_records.clear()

func _connect_mutation_tracking() -> void:
	if _mutation_tracking_closed or model == null or not is_instance_valid(model):
		return
	_track_local_subtree(model)

func _exit_tree() -> void:
	if _scheduler_request_in_flight:
		_scheduler_request_in_flight = false
		_render_telemetry.pending = maxi(0, int(_render_telemetry.pending) - 1)
	if _render_once_in_flight:
		_render_telemetry.in_flight = maxi(0, int(_render_telemetry.in_flight) - 1)
		if not _scheduler_ticket.is_empty():
			RUNTIME_WORK.complete(_scheduler_ticket, _render_issue_usec)
			_scheduler_ticket = {}
	_disconnect_mutation_tracking()

func _track_local_subtree(node: Node) -> void:
	var instance_id := node.get_instance_id()
	if _tracked_mutation_nodes.has(instance_id):
		return
	_tracked_mutation_nodes[instance_id] = weakref(node)
	if not node.child_entered_tree.is_connected(_on_local_child_entered):
		node.child_entered_tree.connect(_on_local_child_entered)
	if not node.child_exiting_tree.is_connected(_on_local_child_exiting):
		node.child_exiting_tree.connect(_on_local_child_exiting)
	for child in node.get_children():
		_track_local_subtree(child)

func _untrack_local_subtree(node: Node) -> void:
	for child in node.get_children():
		_untrack_local_subtree(child)
	if node.child_entered_tree.is_connected(_on_local_child_entered):
		node.child_entered_tree.disconnect(_on_local_child_entered)
	if node.child_exiting_tree.is_connected(_on_local_child_exiting):
		node.child_exiting_tree.disconnect(_on_local_child_exiting)
	_tracked_mutation_nodes.erase(node.get_instance_id())

func _disconnect_mutation_tracking() -> void:
	var references := _tracked_mutation_nodes.values()
	for reference_variant in references:
		var reference := reference_variant as WeakRef
		var node := reference.get_ref() as Node
		if node == null or not is_instance_valid(node):
			continue
		if node.child_entered_tree.is_connected(_on_local_child_entered):
			node.child_entered_tree.disconnect(_on_local_child_entered)
		if node.child_exiting_tree.is_connected(_on_local_child_exiting):
			node.child_exiting_tree.disconnect(_on_local_child_exiting)
	_tracked_mutation_nodes.clear()

func _on_local_child_entered(node: Node) -> void:
	_note_model_mutation()
	_track_local_subtree(node)

func _on_local_child_exiting(node: Node) -> void:
	_note_model_mutation()
	_untrack_local_subtree(node)

func mark_static_render_dirty() -> void:
	# Explicit invalidation for callers that mutate resources or transforms
	# without adding/removing nodes after the bounded automatic tracking window.
	_prepared_for_first_presentation = false
	_first_presentation_reused = false
	_prepare_phase = 0
	_prepare_quiet_frames = 0
	_clear_prepare_units(false)
	_observed_mutation_serial = -1
	_tree_mutation_serial += 1
	_mutation_tracking_closed = false
	_connect_mutation_tracking()

func set_background_static_preparation_enabled(enabled: bool) -> void:
	_background_preparation_enabled = enabled
	if not enabled and _prepare_phase in [1, 2, 3, 4] and not _render_once_in_flight:
		_prepare_phase = 0
		_render_once_queued = false
		_restore_prepare_visibility()
		_clear_prepare_units(false)

func _note_model_mutation() -> void:
	_tree_mutation_serial += 1
	_prepare_quiet_frames = 0
	if _render_once_in_flight and _active_render_purpose in [PURPOSE_PREPARE_BOOTSTRAP, PURPOSE_PREPARE_TARGET, PURPOSE_PREPARE_UNIT, PURPOSE_PREPARE_FULL]:
		_mutation_during_prepare = true
	# A preparation that has not reached the full render is simply restarted.
	# Later runtime mutations keep the established explicit UPDATE_ONCE contract;
	# this automatic path only protects the first static presentation.
	if not _prepared_for_first_presentation and not _render_once_in_flight:
		_prepare_phase = 0
		_render_once_queued = false
		_restore_prepare_visibility()
		_clear_prepare_units(false)

func _restore_prepare_visibility() -> void:
	if viewport_3d != null and _final_render_size != Vector2i.ZERO:
		viewport_3d.size = _final_render_size
	if model != null and is_instance_valid(model):
		model.visible = _model_visibility_before_prepare
	for unit in _prepare_units:
		if is_instance_valid(unit):
			unit.visible = bool(_prepare_unit_visibility.get(unit.get_instance_id(), true))
	if sprite_3d != null and is_instance_valid(sprite_3d):
		sprite_3d.visible = _sprite_visibility_before_prepare


func _capture_prepare_units() -> void:
	_clear_prepare_units(false)
	if model == null or not is_instance_valid(model):
		return
	_collect_prepare_units(model)
	_prepare_unit_total = _prepare_units.size()
	_prepare_unit_index = 0
	_prepare_unit_frames.clear()
	_prepare_unit_peak_issue_usec = 0
	_prepare_unit_peak_adjacent_usec = 0


func _collect_prepare_units(node: Node) -> void:
	for child in node.get_children():
		if child is VisualInstance3D:
			var visual := child as VisualInstance3D
			_prepare_unit_visibility[visual.get_instance_id()] = visual.visible
			if visual.visible:
				_prepare_units.append(visual)
		_collect_prepare_units(child)


func _hide_prepare_units_except(active: VisualInstance3D = null) -> void:
	for unit in _prepare_units:
		if is_instance_valid(unit):
			unit.visible = unit == active and bool(_prepare_unit_visibility.get(unit.get_instance_id(), true))


func _clear_prepare_units(restore_visibility := true) -> void:
	if restore_visibility:
		_restore_prepare_visibility()
	_prepare_units.clear()
	_prepare_unit_visibility.clear()
	_prepare_unit_index = 0

func _begin_render(frame: int, purpose: StringName) -> void:
	_last_render_claim_frame = frame
	_render_once_queued = false
	_render_once_in_flight = true
	_render_started_frame = frame
	_active_render_purpose = purpose
	_prepare_frame_started_usec = Time.get_ticks_usec()
	_render_telemetry.started_total = int(_render_telemetry.started_total) + 1
	_render_telemetry.in_flight = int(_render_telemetry.in_flight) + 1
	# A globally warmed backend skips PURPOSE_PREPARE_BOOTSTRAP, so preparation
	# state must be captured independently from that optional phase.
	if purpose in [PURPOSE_PREPARE_BOOTSTRAP, PURPOSE_PREPARE_TARGET] and _final_render_size == Vector2i.ZERO:
		_model_visibility_before_prepare = model.visible
		_sprite_visibility_before_prepare = sprite_3d.visible
		_final_render_size = viewport_3d.size
	if purpose == PURPOSE_PREPARE_BOOTSTRAP:
		_prepare_bootstrap_frame = frame
		model.visible = false
		sprite_3d.visible = false
		# Warm the backend separately from the final target allocation. The final
		# image keeps its original resolution, model, light and shadows.
		viewport_3d.size = Vector2i.ONE
	elif purpose == PURPOSE_PREPARE_TARGET:
		_prepare_target_frame = frame
		viewport_3d.size = _final_render_size
		# Allocate and clear the final 960x800 target first. The actual model,
		# directional light and shadows are untouched and rendered in the next
		# globally serialized phase; the blank result is never presented.
		model.visible = false
		sprite_3d.visible = false
	elif purpose == PURPOSE_PREPARE_UNIT:
		if _prepare_units.is_empty():
			_capture_prepare_units()
		var unit: VisualInstance3D = _prepare_units[_prepare_unit_index] if _prepare_unit_index < _prepare_units.size() else null
		_prepare_unit_frames.append(frame)
		# Keep the final render target allocated while pipelines are warmed one
		# visual at a time. Shrinking to 128x128 and restoring 960x800 forced a
		# synchronous target reallocation in PREPARE_FULL (6-21 ms in practice).
		viewport_3d.size = _final_render_size
		model.visible = _model_visibility_before_prepare
		sprite_3d.visible = false
		_hide_prepare_units_except(unit)
	elif purpose == PURPOSE_PREPARE_FULL:
		_prepare_full_frame = frame
		viewport_3d.size = _final_render_size
		_restore_prepare_visibility()
		model.visible = _model_visibility_before_prepare
		sprite_3d.visible = false
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _finish_render(frame: int) -> void:
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_render_once_in_flight = false
	_render_completed_frame = frame
	var adjacent_frame_usec := Time.get_ticks_usec() - _prepare_frame_started_usec
	_render_telemetry.in_flight = maxi(0, int(_render_telemetry.in_flight) - 1)
	_render_telemetry.completed_total = int(_render_telemetry.completed_total) + 1
	_render_telemetry.peak_usec = maxi(int(_render_telemetry.peak_usec), _render_issue_usec)
	_render_telemetry.adjacent_frame_peak_usec = maxi(
		int(_render_telemetry.adjacent_frame_peak_usec), adjacent_frame_usec)
	_render_records.append({
		"owner_id": get_instance_id(),
		"owner_path": String(get_path()) if is_inside_tree() else "",
		"model_script": String(model.get_script().resource_path) if model != null and model.get_script() != null else "",
		"purpose": String(_active_render_purpose),
		"started_frame": _render_started_frame,
		"completed_frame": frame,
		"actual_usec": _render_issue_usec,
		"adjacent_frame_usec": adjacent_frame_usec,
		"unit_index": _prepare_unit_index if _active_render_purpose == PURPOSE_PREPARE_UNIT else -1,
		"unit_count": _prepare_unit_total,
		"unit_name": String(_prepare_units[_prepare_unit_index].name) if _active_render_purpose == PURPOSE_PREPARE_UNIT and _prepare_unit_index < _prepare_units.size() and is_instance_valid(_prepare_units[_prepare_unit_index]) else "",
		"near_screen": _is_near_screen(),
	})
	if _render_records.size() > MAX_RENDER_RECORDS:
		_render_records.pop_front()
	if not _scheduler_ticket.is_empty():
		# The scheduler budget is CPU work executed while the reservation is held.
		# The full frame-to-frame render latency stays beside it in static telemetry
		# instead of being mislabeled as this producer's synchronous CPU cost.
		RUNTIME_WORK.complete(_scheduler_ticket, _render_issue_usec)
		_scheduler_ticket = {}
	if _active_render_purpose in [PURPOSE_PREPARE_BOOTSTRAP, PURPOSE_PREPARE_TARGET, PURPOSE_PREPARE_FULL] and _is_near_screen():
		_visible_request_pending = true
	match _active_render_purpose:
		PURPOSE_PREPARE_BOOTSTRAP:
			_prepare_bootstrap_usec = _render_issue_usec
			viewport_3d.size = _final_render_size
			if _mutation_during_prepare:
				_abort_changed_preparation()
			else:
				_prepare_phase = 2
				_render_once_queued = true
		PURPOSE_PREPARE_TARGET:
			_prepare_target_usec = _render_issue_usec
			if _mutation_during_prepare:
				_abort_changed_preparation()
			else:
				_capture_prepare_units()
				_prepare_phase = 3 if not _prepare_units.is_empty() else 4
				_render_once_queued = true
		PURPOSE_PREPARE_UNIT:
			_prepare_unit_peak_issue_usec = maxi(_prepare_unit_peak_issue_usec, _render_issue_usec)
			_prepare_unit_peak_adjacent_usec = maxi(_prepare_unit_peak_adjacent_usec, adjacent_frame_usec)
			_render_telemetry.unit_slices_total = int(_render_telemetry.unit_slices_total) + 1
			if _prepare_unit_index < _prepare_units.size() and is_instance_valid(_prepare_units[_prepare_unit_index]):
				_prepare_units[_prepare_unit_index].visible = false
			_prepare_unit_index += 1
			if _mutation_during_prepare:
				_abort_changed_preparation()
			else:
				_prepare_phase = 3 if _prepare_unit_index < _prepare_units.size() else 4
				_render_once_queued = true
		PURPOSE_PREPARE_FULL:
			_prepare_full_usec = _render_issue_usec
			if _mutation_during_prepare:
				_abort_changed_preparation()
			else:
				_prepare_phase = 0
				_prepare_completed_frame = frame
				_prepared_for_first_presentation = true
				_render_generation += 1
				_restore_prepare_visibility()
				_clear_prepare_units(false)
				_mutation_tracking_closed = true
				_disconnect_mutation_tracking()
				if _visible_request_pending:
					_first_presentation_reused = true
					_visible_request_pending = false
					_render_telemetry.visible_reuse_total = int(_render_telemetry.visible_reuse_total) + 1
		PURPOSE_VISIBLE:
			_render_generation += 1
			_mutation_tracking_closed = true
			_disconnect_mutation_tracking()
	_active_render_purpose = &""

func _abort_changed_preparation() -> void:
	_mutation_during_prepare = false
	if viewport_3d != null and _final_render_size != Vector2i.ZERO:
		viewport_3d.size = _final_render_size
	_prepare_phase = 0
	_prepare_quiet_frames = 0
	_observed_mutation_serial = -1
	_render_once_queued = false
	_restore_prepare_visibility()
	_clear_prepare_units(false)
	_render_telemetry.aborted_mutation_total = int(_render_telemetry.aborted_mutation_total) + 1

func _is_near_screen() -> bool:
	if not is_inside_tree() or get_viewport() == null:
		return true
	var screen_point := get_viewport().get_canvas_transform() * global_position
	return get_viewport_rect().grow(PREPARE_SCREEN_MARGIN).has_point(screen_point)

func _reserve_render_slot(purpose: StringName) -> void:
	_scheduler_request_in_flight = true
	_render_telemetry.queued_total = int(_render_telemetry.queued_total) + 1
	_render_telemetry.pending = int(_render_telemetry.pending) + 1
	var priority := RUNTIME_WORK.PRIORITY_VISIBLE if purpose == PURPOSE_VISIBLE else RUNTIME_WORK.PRIORITY_BACKGROUND
	var ticket: Dictionary = await RUNTIME_WORK.reserve(
		self, &"mountain_static_render", priority, RUNTIME_WORK.FRAME_BUDGET_USEC)
	_scheduler_request_in_flight = false
	_render_telemetry.pending = maxi(0, int(_render_telemetry.pending) - 1)
	if ticket.is_empty():
		return
	if not _render_once_queued or viewport_3d == null or not is_instance_valid(viewport_3d):
		RUNTIME_WORK.complete(ticket, 0)
		return
	var granted_frame := Engine.get_process_frames()
	if purpose != PURPOSE_VISIBLE and granted_frame - _last_render_claim_frame < BACKGROUND_RENDER_FRAME_GAP:
		# Other views may already be waiting in the global scheduler when a peer
		# submits its render. Re-check after the ticket is granted so queued peers
		# cannot produce consecutive GPU submissions and rebuild the same backlog.
		RUNTIME_WORK.complete(ticket, 0)
		return
	_render_telemetry.max_waited_frames = maxi(
		int(_render_telemetry.max_waited_frames), int(ticket.get("waited_frames", 0)))
	if purpose != PURPOSE_VISIBLE and _visible_request_pending:
		# A real screen-entry request supersedes speculative preparation. Render the
		# complete model immediately in the already granted global slot.
		_visible_request_pending = false
		_prepare_phase = 0
		_restore_prepare_visibility()
		_clear_prepare_units(false)
		purpose = PURPOSE_VISIBLE
		_active_render_purpose = PURPOSE_VISIBLE
	elif purpose != PURPOSE_VISIBLE and _is_near_screen():
		RUNTIME_WORK.complete(ticket, 0)
		_prepare_phase = 0
		_render_once_queued = false
		_restore_prepare_visibility()
		_clear_prepare_units(false)
		_background_deferred_near_frames += 1
		_render_telemetry.deferred_near_total = int(_render_telemetry.deferred_near_total) + 1
		return
	_scheduler_ticket = ticket
	var issue_started_usec := Time.get_ticks_usec()
	_begin_render(Engine.get_process_frames(), purpose)
	_render_issue_usec = Time.get_ticks_usec() - issue_started_usec

func _update_background_prepare() -> void:
	if not _background_preparation_enabled:
		return
	if _prepared_for_first_presentation or _prepare_phase != 0:
		return
	if viewport_3d.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		_prepare_quiet_frames = 0
		return
	if _is_near_screen():
		_background_deferred_near_frames += 1
		_render_telemetry.deferred_near_total = int(_render_telemetry.deferred_near_total) + 1
		return
	if _observed_mutation_serial != _tree_mutation_serial:
		_observed_mutation_serial = _tree_mutation_serial
		_prepare_quiet_frames = 0
		return
	_prepare_quiet_frames += 1
	if _prepare_quiet_frames < PREPARE_QUIET_FRAMES:
		return
	# The loading screen has already paid the one-time 1x1 backend cost. New
	# views can start at their target allocation without repeating that cold
	# renderer initialization during traversal.
	_prepare_phase = 2 if global_graphics_backend_ready() else 1
	_prepare_started_frame = Engine.get_process_frames()
	_render_once_queued = true

func _process(_delta: float) -> void:
	if viewport_3d == null:
		return
	_connect_mutation_tracking()
	var frame := Engine.get_process_frames()
	if _render_once_in_flight:
		# RenderingServer consumes the one-shot after this process frame, but in
		# Godot 4.7 the public property can remain UPDATE_ONCE. Close the request on
		# the following process frame and reset it explicitly for future notifiers.
		if frame > _render_started_frame:
			_finish_render(frame)
		return
	# Preserve UPDATE_ALWAYS/WHEN_VISIBLE for callers that intentionally use a
	# dynamic view. Only static one-shot requests participate in this cadence.
	if viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS or viewport_3d.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE:
		# Dynamic callers own their update mode. Cancel a not-yet-started automatic
		# preparation without changing their behavior.
		if _prepare_phase in [1, 2, 3, 4]:
			_prepare_phase = 0
			_render_once_queued = false
			_restore_prepare_visibility()
			_clear_prepare_units(false)
		return
	if viewport_3d.render_target_update_mode == SubViewport.UPDATE_ONCE:
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _prepared_for_first_presentation and not _first_presentation_reused:
			# The complete, full-quality image is already resident. The first screen
			# entry consumes it without waking the render target or compiling a cold
			# pipeline in the presentation frame.
			_first_presentation_reused = true
			_render_telemetry.visible_reuse_total = int(_render_telemetry.visible_reuse_total) + 1
			return
		if _prepare_phase in [1, 2, 3, 4]:
			_visible_request_pending = true
		else:
			_render_once_queued = true
			_active_render_purpose = PURPOSE_VISIBLE
	else:
		_update_background_prepare()
	if _render_once_queued and _last_render_claim_frame != frame:
		var purpose := _active_render_purpose
		if purpose == &"":
			match _prepare_phase:
				1: purpose = PURPOSE_PREPARE_BOOTSTRAP
				2: purpose = PURPOSE_PREPARE_TARGET
				3: purpose = PURPOSE_PREPARE_UNIT
				_: purpose = PURPOSE_PREPARE_FULL
		if purpose != PURPOSE_VISIBLE and frame - _last_render_claim_frame < BACKGROUND_RENDER_FRAME_GAP:
			return
		if not _scheduler_request_in_flight:
			_reserve_render_slot(purpose)

func project_floor(point: Vector2) -> Vector2:
	return project_point(Vector3(point.x,0,point.y))
func project_point(point: Vector3) -> Vector2:
	return sprite_3d.position+(camera_3d.unproject_position(point)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale
func unproject_floor(world_point: Vector2) -> Vector2:
	var image := sprite_3d.to_local(world_point)+Vector2(viewport_3d.size)*0.5
	var ray := camera_3d.project_ray_normal(image)
	var origin := camera_3d.project_ray_origin(image)
	var hit := origin+ray*(-origin.y/ray.y)
	return Vector2(hit.x,hit.z)
func add_solid(rect: Rect2, label: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])
	body.add_child(shape)
	add_child(body)
	return body

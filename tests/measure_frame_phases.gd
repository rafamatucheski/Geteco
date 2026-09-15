extends "res://tests/measure_city_scenarios.gd"
## Diagnostic wall-clock boundaries, not isolated native function timings.
class LastCallbacks extends Node:
	var probe: SceneTree
	func _physics_process(_delta: float) -> void: probe.physics_end()
	func _process(_delta: float) -> void: probe.process_end()

var _physics_start := 0
var _physics_end := 0
var _process_start := 0
var _process_end := 0
var _render_start := 0
var _draw_end := 0
var _physics_us := 0
var _between_physics_us := 0
var _between_frames_us := 0
var _physics_ticks := 0
var _rows: Array[Dictionary] = []

func _initialize() -> void:
	super._initialize()
	_attach_probe.call_deferred()

func _attach_probe() -> void:
	var last := LastCallbacks.new()
	last.probe = self
	last.process_priority = 2147483647
	last.process_physics_priority = 2147483647
	last.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(last)
	physics_frame.connect(physics_begin)
	process_frame.connect(process_begin)
	RenderingServer.frame_pre_draw.connect(render_begin)
	RenderingServer.frame_post_draw.connect(render_end)

func physics_begin() -> void:
	var now := Time.get_ticks_usec()
	if _physics_end > 0: _between_physics_us += now - _physics_end
	elif _draw_end > 0: _between_frames_us = now - _draw_end
	_physics_start = now
	_physics_ticks += 1

func physics_end() -> void:
	_physics_end = Time.get_ticks_usec()
	if _physics_start > 0: _physics_us += _physics_end - _physics_start

func process_begin() -> void:
	_process_start = Time.get_ticks_usec()
	if _physics_end > 0: _between_physics_us += _process_start - _physics_end
	elif _draw_end > 0: _between_frames_us = _process_start - _draw_end

func process_end() -> void: _process_end = Time.get_ticks_usec()
func render_begin() -> void: _render_start = Time.get_ticks_usec()

func render_end() -> void:
	var now := Time.get_ticks_usec()
	if _tracking:
		_rows.append({"physics_callbacks_us": _physics_us,
			"physics_tail_and_sync_us": _between_physics_us,
			"idle_callbacks_us": _process_end - _process_start,
			"post_idle_pre_draw_us": _render_start - _process_end,
			"render_submission_us": now - _render_start,
			"between_frames_us": _between_frames_us, "physics_ticks": _physics_ticks})
	_draw_end = Time.get_ticks_usec()
	_physics_end = 0
	_physics_us = 0
	_between_physics_us = 0
	_physics_ticks = 0

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	await super._sample(output, label, seconds, car)
	if label == "warmup": return
	var file := FileAccess.open(output.path_join("phases.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(_rows))

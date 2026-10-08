extends Node
## One owner for global slow motion. Only charge survives saving; active time never does.
const DURATION := 15.0
const WORLD_SCALE := 0.1
const CAPACITY := 100.0
## Forty points of combat damage fill the meter, including armor absorption.
const DAMAGE_GAIN := 2.5
var gameplay: Node
var charge := 0.0
var active := false
var seconds_left := 0.0
var _previous_scale := 1.0
var _last_usec := 0
var _tint: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_tint = ColorRect.new()
	_tint.name = "RageTint"
	_tint.color = Color(0.20, 0.06, 0.24, 0.13)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint.hide()
	layer.add_child(_tint)
	set_process(false)

func unlocked() -> bool:
	return is_instance_valid(gameplay) and gameplay.state != null and gameplay.state.owns_weapon("katana")

func can_activate() -> bool:
	return unlocked() and not active and charge >= CAPACITY and _permitted() and is_equal_approx(Engine.time_scale, 1.0)

func _permitted() -> bool:
	return is_instance_valid(gameplay) and gameplay.is_inside_tree() and gameplay.attack_allowed() and gameplay._free_play_ok() and gameplay.equipped() == "katana" and is_instance_valid(gameplay.player) and not gameplay.player.input_locked

func add_damage(actual_damage: float) -> void:
	if active or not unlocked() or not is_finite(actual_damage) or actual_damage <= 0.0: return
	charge = minf(CAPACITY, charge + actual_damage * DAMAGE_GAIN)

func activate() -> bool:
	if not can_activate(): return false
	_previous_scale = Engine.time_scale
	charge = 0.0
	seconds_left = DURATION
	active = true
	_last_usec = Time.get_ticks_usec()
	Engine.time_scale = WORLD_SCALE
	gameplay.player.set_meta("katana_rage_speed", 1.0 / WORLD_SCALE)
	if is_instance_valid(_tint): _tint.show()
	set_process(true)
	gameplay.changed.emit()
	return true

func _process(_delta: float) -> void:
	if not active: return
	# Pausing or opening a modal ends the effect; it cannot leave the next scene slowed.
	if not _permitted():
		cancel("interrupted")
		return
	var now := Time.get_ticks_usec()
	advance_real_seconds(float(now - _last_usec) / 1000000.0)
	_last_usec = now

func advance_real_seconds(elapsed: float) -> void:
	if not active or not is_finite(elapsed) or elapsed < 0.0: return
	seconds_left = maxf(0.0, seconds_left - elapsed)
	if seconds_left <= 0.0: cancel("elapsed")

func cancel(_reason := "cancelled") -> void:
	if active and is_equal_approx(Engine.time_scale, WORLD_SCALE): Engine.time_scale = _previous_scale
	active = false
	seconds_left = 0.0
	if is_instance_valid(gameplay) and is_instance_valid(gameplay.player): gameplay.player.remove_meta("katana_rage_speed")
	if is_instance_valid(_tint): _tint.hide()
	set_process(false)

func _exit_tree() -> void:
	cancel("shutdown")

func status() -> Dictionary:
	return {"unlocked": unlocked(), "charge": charge, "active": active, "seconds_left": seconds_left, "ready": can_activate()}

func restore(value: float) -> void:
	cancel("restore")
	charge = clampf(value, 0.0, CAPACITY) if is_finite(value) else 0.0

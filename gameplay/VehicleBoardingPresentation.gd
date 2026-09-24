extends Node
## V1 boarding rhythm adapted to native 3D: approach, door, step, occlusion, seat.
## Bone presentation stays owned by Actor through its existing animation sampler.

signal entered
signal exited(point: Vector3)
signal cancelled(reason: String, point: Vector3)

var world: Node
var vehicle: CharacterBody3D
var actor: CharacterBody3D
var side := -1
var duration := 1.85
var progress := 0.0
var active := false
var exiting := false
var phase := "idle"
var _start := Vector3.ZERO
var _door := Vector3.ZERO
var _seat := Vector3.ZERO
var _landing := Vector3.ZERO
var _motion: Tween
var _visual_yaw := 0.0
var _visual_position := Vector3.ZERO
var _finishing := false

func begin_entry(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, entry_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = entry_side
	duration = 1.85 + (.30 if side > 0 else 0.0)
	_start = actor.global_position
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_landing = _start
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	active = true
	phase = "approach"
	vehicle.animate_driver_door(side, true, .28)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 1.0, duration-.28)
	_motion.tween_callback(_begin_close_entry)
	_motion.tween_interval(.28)
	_motion.tween_callback(_finish_entry)
	_apply()

func begin_exit(owner_world: Node, car: CharacterBody3D, pedestrian: CharacterBody3D, destination: Vector3, exit_side: int) -> void:
	world = owner_world
	vehicle = car
	actor = pedestrian
	side = exit_side
	duration = 1.85 + (.30 if side > 0 else 0.0)
	_start = destination
	_landing = destination
	_door = vehicle.driver_door_anchor(side)
	_seat = vehicle.driver_seat_anchor()
	_visual_yaw = actor.visual.rotation.y
	_visual_position = actor.visual.position
	progress = 1.0
	exiting = true
	active = true
	phase = "open"
	actor.global_position = _seat
	actor.hide()
	vehicle.animate_driver_door(side, true, .28)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, duration)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	_apply()

func reverse_entry_to_exit() -> bool:
	if not active or exiting: return false
	exiting = true
	if is_instance_valid(_motion): _motion.kill()
	var seconds := maxf(.45, (duration-.28) * progress)
	vehicle.animate_driver_door(side, true, .20)
	_motion = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_motion.tween_property(self, "progress", 0.0, seconds)
	_motion.tween_callback(_begin_close_exit)
	_motion.tween_interval(.35)
	_motion.tween_callback(_finish_exit)
	return true

func abort(reason: String) -> void:
	if _finishing: return
	_finishing = true
	if is_instance_valid(_motion): _motion.kill()
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, .18)
	_restore_actor(_landing if _landing.is_finite() else _start)
	cancelled.emit(reason, actor.global_position if is_instance_valid(actor) else _start)
	queue_free()

func _process(_delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion():
		abort("vehicle_removed")
		return
	_apply()

func _apply() -> void:
	if not is_instance_valid(actor) or not is_instance_valid(vehicle): return
	if phase == "close":
		actor.hide()
		return
	if phase == "close_outside":
		actor.global_position = _landing
		actor.show()
		return
	var t := clampf(progress, 0.0, 1.0)
	if t < .20:
		phase = "approach"
		actor.global_position = _start.lerp(_door, smoothstep(0.0, .20, t))
		_pose_cycle("Walking", t / .20)
	elif t < .36:
		phase = "reach"
		actor.global_position = _door
		_pose_transition(.12 + smoothstep(.20, .36, t) * .18)
	elif t < .82:
		phase = "step"
		actor.global_position = _door.lerp(_seat, smoothstep(.36, .82, t))
		_pose_transition(.30 + smoothstep(.36, .82, t) * .52)
	else:
		phase = "seat"
		actor.global_position = _seat
		_pose_transition(.82)
	actor.visual.position = _visual_position
	var toward := vehicle.global_position - actor.global_position
	toward.y = 0
	if toward.length_squared() > .001:
		actor.visual.rotation.y = atan2(-toward.x, -toward.z)
	actor.visible = t < .82

func _begin_close_entry() -> void:
	if not active or exiting: return
	phase = "close"
	actor.hide()
	vehicle.animate_driver_door(side, false, .28)

func _begin_close_exit() -> void:
	if not active: return
	phase = "close_outside"
	_restore_actor(_landing)
	vehicle.animate_driver_door(side, false, .32)

func _pose_cycle(clip: String, normalized: float) -> void:
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip): return
	var animation: Animation = actor.animation.get_animation(clip)
	actor._pose_clip(clip, fposmod(normalized, 1.0) * animation.length)

func _pose_transition(normalized: float) -> void:
	var clip := "Fast_Ladder_Climb"
	if not is_instance_valid(actor.animation) or not actor.animation.has_animation(clip):
		_pose_cycle("Walking", normalized)
		return
	actor._pose_clip(clip, clampf(normalized, 0.0, 1.0) * actor.animation.get_animation(clip).length)

func _finish_entry() -> void:
	if _finishing or not is_instance_valid(actor) or not is_instance_valid(vehicle):
		abort("invalid_entry")
		return
	_finishing = true
	active = false
	actor.hide()
	actor.global_position = vehicle.global_position
	vehicle.animate_driver_door(side, false, 0.0)
	entered.emit()
	queue_free()

func _finish_exit() -> void:
	if _finishing: return
	_finishing = true
	active = false
	if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
	_restore_actor(_landing)
	exited.emit(_landing)
	queue_free()

func _restore_actor(point: Vector3) -> void:
	if not is_instance_valid(actor): return
	actor.teleport(point)
	actor.visual.position = _visual_position
	actor.visual.rotation.y = _visual_yaw
	actor.show()

func _exit_tree() -> void:
	if active and not _finishing:
		if is_instance_valid(_motion): _motion.kill()
		if is_instance_valid(vehicle): vehicle.animate_driver_door(side, false, 0.0)
		_restore_actor(_landing if _landing.is_finite() else _start)

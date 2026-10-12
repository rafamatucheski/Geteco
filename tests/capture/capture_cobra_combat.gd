extends "res://tests/capture/capture_cobra_patrol.gd"
## Full production patrol/theft/retaliation regression, isolated evidence path.
func _initialize() -> void:
	folder = "D:/geteco/artifacts/cobra-combat-20261010-" + str(Time.get_ticks_usec())
	physics_frame.connect(_observe_exit)
	run.call_deferred()

var _last_exit_sample := 0
var _exit_frames := 0
func _observe_exit() -> void:
	if not is_instance_valid(world): return
	var now := Time.get_ticks_msec()
	if now - _last_exit_sample < 150 or _exit_frames >= 16: return
	for patrol in get_nodes_in_group("cobra_patrol"):
		for guard in patrol.crew:
			if not is_instance_valid(guard) or not guard.exiting: continue
			_last_exit_sample = now
			print("EXIT_STATE point=", guard.global_position, " landing=", guard._landing, " elapsed=", guard._elapsed, " closing=", guard._closing)
			if _exit_frames < 16:
				_exit_frames += 1
				photo("exit_%02d" % _exit_frames)
			return

func check(ok: bool, label: String) -> void:
	super.check(ok, label)
	if label != "Disembarked Cobra actually fires at player" or ok: return
	for patrol in get_nodes_in_group("cobra_patrol"):
		for guard in patrol.crew:
			if not is_instance_valid(guard): continue
			var query := PhysicsRayQueryParameters3D.create(guard.global_position + Vector3.UP * 1.4, world.player.global_position + Vector3.UP, 7, [guard.get_rid()])
			print("FOOT_DIAGNOSTIC exiting=", guard.exiting, " engaged=", guard.engaged, " point=", guard.global_position, " target=", world.player.global_position, " hit=", world.get_world_3d().direct_space_state.intersect_ray(query))

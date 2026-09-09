extends SceneTree

const MACIOTA := preload("res://JagerNPC.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var npc := MACIOTA.new()
	root.add_child(npc)
	npc.set_physics_process(false)
	await process_frame
	_check(npc.viewport_3d.size == Vector2i(112, 112), "Maciota keeps the 112px render budget")
	_check(npc.left_hand != null and npc.mouth_node != null, "Articulated hand and mouth are present")
	_check(npc.sprite_3d_display.scale.x * 112.0 < 37.0, "Refinement does not enlarge his gameplay footprint")
	var poses: Array[Vector3] = []
	for gesture in ["welcome", "explain", "point", "nod"]:
		npc.is_talking = true
		npc._show_current_text()
		npc.active_gesture = gesture
		npc.gesture_clock = 0.0
		npc.speech_remaining = 3.0
		var max_mouth := 1.0
		for tick in range(60):
			await physics_frame
			npc._physics_process(1.0 / 60.0)
			max_mouth = maxf(max_mouth, npc.mouth_node.scale.y)
			var cane_bottom: float = npc.cane_mesh.position.y + npc.cane_shaft.position.y - 0.39 * npc.cane_shaft.scale.y
			_check(absf(cane_bottom - 0.025) < 0.0001, "Cane remains grounded during " + gesture)
		poses.append(npc.left_upper_arm.rotation)
		_check(max_mouth > 1.0, "Actual voice drives mouth in " + gesture)
	for first in range(poses.size()):
		for second in range(first + 1, poses.size()):
			_check(poses[first].distance_to(poses[second]) > 0.10, "Authored gestures have distinct arm poses")
	npc.is_talking = false
	npc._close_dialogue()
	_check(not npc.speech_audio.playing, "Closing dialogue stops speech")
	npc._physics_process(1.0 / 60.0)
	_check(is_equal_approx(npc.mouth_node.scale.y, 1.0), "Idle does not loop mouth animation")
	npc.hide()
	_check(npc.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden interior stops NPC rendering")
	var old_clock: float = npc.anim_clock
	npc._physics_process(1.0)
	_check(npc.anim_clock == old_clock, "Hidden character does not evaluate animation")
	npc.show()
	_check(npc.viewport_3d.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Entering interior restores rendering")
	npc.queue_free()
	await process_frame
	print("MACIOTA_CHARACTER: %d failures" % failures)
	quit(0 if failures == 0 else 1)

extends SceneTree

class SavedPlayer extends Node2D:
	var collectibles_found: Array = ["mountain_test_journal"]

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures.append(message)

func _run() -> void:
	var player := SavedPlayer.new()
	player.add_to_group("player")
	root.add_child(player)
	# Driving hides the actor while the restored collectibles remain on it.
	player.hide()
	var evidence_script = load("res://world/mountain_pass/MountainEvidence.gd")
	var collected = evidence_script.new()
	collected.configure("mountain_test_journal", "DIARIO", "Test", "journal")
	root.add_child(collected)
	check(collected.is_queued_for_deletion(), "restored collected evidence is removed")
	check(not collected.is_processing(), "collected evidence cannot process before deferred deletion")
	collected._process(0.016)
	await process_frame
	await process_frame
	check(not is_instance_valid(collected), "collected evidence is freed")
	var unread = evidence_script.new()
	unread.configure("mountain_test_camera", "CAMERA", "Test", "camera")
	root.add_child(unread)
	unread._process(0.016)
	check(is_instance_valid(unread.prompt) and not unread.prompt.visible, "unread evidence stays hidden while driving")
	player.show()
	unread._process(0.016)
	check(unread.prompt.visible, "unread evidence can be examined after leaving the car")
	player.position = Vector2(200, 0)
	unread._process(0.016)
	check(not unread.prompt.visible, "prompt hides outside interaction range")
	unread.queue_free()
	player.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

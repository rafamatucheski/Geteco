extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures += 1
func run() -> void:
	var opening := preload("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start = false
	opening.show_studio_intro = true
	root.add_child(opening)
	check(not opening._running, "Prepared opening does not advance behind loading")
	opening.play()
	check(not opening._studio_audio.playing, "Logo audio waits for first draw")
	check(opening._studio_elapsed == 0.0, "Logo clock waits for first draw")
	await process_frame
	await process_frame
	await process_frame
	check(opening._studio_audio.playing, "Logo audio starts after presentation frame")
	check(opening._studio_card.size.x > 0 and opening._studio_card.size.y > 0, "Logo covers viewport")
	opening.queue_free()
	await process_frame
	quit(1 if failures else 0)

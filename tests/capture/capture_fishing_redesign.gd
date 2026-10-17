extends "res://tests/test_fishing_session.gd"
## The normal paid tournament test plus continuous frames for animation review.
## Capture cost is excluded from the separate performance comparison.
var recording := false
var sequence_started := false
var sequence: Array[Dictionary] = []
var frame_folder := ""

func run() -> void:
	await process_frame
	root.get_node("V2Settings").text_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.size = Vector2i(1280,720)
	await super.run()

func capture(filename: String) -> void:
	await super.capture(filename)
	if filename == "rod-ready" and not sequence_started and DisplayServer.get_name() != "headless":
		sequence_started = true
		Engine.max_fps = 30
		frame_folder = folder.path_join("sequence")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_folder))
		_record.call_deferred()

func _record() -> void:
	recording = true
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < 32000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var fishing = world.session.fishing
		var id := sequence.size()
		var path := frame_folder.path_join("frame-%05d.jpg" % id)
		var image := root.get_texture().get_image()
		image.save_jpg(path, .82)
		sequence.append({"frame":id,"ms":float(now-started)/1000.0,"interval_ms":float(now-previous)/1000.0,"phase":fishing.phase,"fish":str(fishing._rod._fish.global_position) if is_instance_valid(fishing._rod) else "", "tension":fishing.fight.tension})
		previous = now
	recording = false
	FileAccess.open(folder.path_join("sequence.json"), FileAccess.WRITE).store_string(JSON.stringify({"frames":sequence,"every_rendered_frame":true,"fps_cap_for_capture":30,"performance_evidence":false}, "\t"))
	print("FISHING_SEQUENCE ",folder," frames=",sequence.size())

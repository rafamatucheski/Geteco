extends SceneTree
var failed:=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start=false; root.add_child(opening)
	await process_frame
	for shot in opening.Timeline.SHOTS:
		var at: float=float(shot.start)+float(shot.duration)/2
		opening.seek(at); opening.pause_playback()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var error:=root.get_texture().get_image().save_png("res://cutscenes/opening/v3/review/shot_%04d.png" % int(at*10))
		if error!=OK: failed=true
	opening.queue_free(); await process_frame
	print("OPENING_V3_CAPTURE ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)

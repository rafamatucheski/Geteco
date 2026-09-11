extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,720); root.content_scale_size=root.size
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start=false; opening.allow_skip=false; root.add_child(opening)
	await process_frame
	var failed:=false
	for at in [17.3,18.2,18.6,21.0,32.1,33.2,33.7,34.2,35.0,37.2,38.0,38.5,39.2,40.2,40.6,41.1,41.65,41.95,53.0,53.6,54.1,54.8,57.0,60.5]:
		opening.seek(at); opening.pause_playback()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var result:=root.get_texture().get_image().save_png("res://cutscenes/opening/v3/review/contact_%04d.png" % int(at*10))
		if result!=OK: failed=true
	opening.queue_free(); await process_frame; await create_timer(.25).timeout
	print("OPENING_CONTACT_CAPTURE ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)

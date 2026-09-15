extends SceneTree
func _initialize():
	_run.call_deferred()
func _run():
	create_timer(150).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.content_scale_size = root.size
	seed(1409)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_delivery_complete", true)
	change_scene_to_file("res://world/harbor/HarborGame.tscn")
	for i in 90: await process_frame
	var camera := Camera2D.new()
	current_scene.add_child(camera)
	camera.position = Vector2(1550,892)
	camera.zoom = Vector2(1.8,1.8)
	camera.make_current()
	for i in 120: await process_frame
	var samples: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous := start
	while Time.get_ticks_usec() - start < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	await RenderingServer.frame_post_draw
	var label := OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png("D:/geteco/output/rail-"+label+".png")
	samples.sort()
	var slow := 0
	var very_slow := 0
	for value in samples:
		if value > 33.3: slow += 1
		if value > 66.7: very_slow += 1
	print("RAIL_BENCH ", label, " GPU=", RenderingServer.get_video_adapter_name(), " frames=", samples.size(), " fps=", samples.size()*1000000.0/(previous-start), " p50=",samples[int(samples.size()*.5)]," p95=",samples[int(samples.size()*.95)]," p99=",samples[int(samples.size()*.99)], " max=",samples[-1]," over33=",slow," over66=",very_slow)
	quit()

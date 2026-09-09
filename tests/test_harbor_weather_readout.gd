extends SceneTree

const READOUT := preload("res://district/harbor_preview/HarborWeatherReadout.gd")
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for i in count:
		await process_frame
func run() -> void:
	var campaign := root.get_node("CampaignState")
	campaign.reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met"]:
		campaign.set_campaign_flag(StringName(flag),true)
	var scene := load("res://district/harbor_preview/HarborGame.tscn").instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await frames(10)
	var widget := scene.get_node("HarborWeatherReadout")
	var weather: Node = scene.weather
	for sample in [{"time":0.5,"state":0,"icon":"sun","clock":"12:00"},{"time":0.875,"state":0,"icon":"moon","clock":"21:00"},{"time":0.5,"state":1,"icon":"rain","clock":"12:00"},{"time":0.5,"state":2,"icon":"storm","clock":"12:00"},{"time":0.0,"state":0,"icon":"moon","clock":"00:00"}]:
		weather.time_of_day = sample.time
		weather.set_weather(sample.state)
		var before := [weather.time_of_day,weather.weather_state,weather.weather_timer]
		widget.refresh()
		check(widget.clock_label.text == sample.clock,"Clock reads real weather time")
		check(widget.icon.state == sample.icon,"Icon matches existing climate state")
		check(before == [weather.time_of_day,weather.weather_state,weather.weather_timer],"Readout never mutates time/weather")
	check(widget.row.visible,"Readout mounted in production gameplay HUD")
	check(widget.row.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Readout cannot intercept clicks")
	check(widget.icon.mouse_filter==Control.MOUSE_FILTER_IGNORE and widget.clock_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"Children cannot intercept clicks")
	var previous_phase: String = scene.get_node("ArrivalMission").phase
	scene.get_node("ArrivalMission").phase = "arrival"
	widget.refresh()
	check(not widget.row.visible,"No readout over CGI")
	scene.get_node("ArrivalMission").phase = previous_phase
	paused = true
	widget.refresh()
	check(not widget.row.visible,"No readout over pause menu")
	paused = false
	weather.time_of_day = 0.75
	weather.set_weather(1)
	widget.refresh()
	for size in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = size
		await frames(5)
		var rect: Rect2 = widget.row.get_global_rect()
		check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(rect),"Readout within viewport at "+str(size))
		var stars: Control = widget.row.get_parent().get_node("Stars")
		check(not rect.intersects(stars.get_global_rect()),"Readout does not cover wanted stars")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png("D:/geteco/harbor-weather-%d.png" % size.x)==OK,"Weather capture saved")
	print("HARBOR_WEATHER_READOUT failures=",failures)
	scene.queue_free()
	await frames(3)
	quit(0 if failures==0 else 1)

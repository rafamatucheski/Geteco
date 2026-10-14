extends SceneTree
## Rendered coverage and timestamped movement frames; never used as FPS samples.
const SITES := [
	["police",Vector3(67,.1,108),52.0],
	["skate",Vector3(381,.1,132.5),32.0],
	["east",Vector3(392,.1,96),52.0],
	["west",Vector3(118,.1,80),52.0],
	["union",Vector3(104.7,.1,119),48.0],
	["north",Vector3(380,.1,-170),52.0],
	["port",Vector3(296,.1,212),52.0],
	["cobra",Vector3(481.25,.1,106.25),62.0],
	["salvage",Vector3(-46.875,.1,67),58.0],
	["cemetery",Vector3(-40.625,.1,82),58.0],
	["police-return",Vector3(67,.1,108),52.0],
	["hospital",Vector3(120,.2,102),24.0],
	["westgate-home",Vector3(15.625,.1,15),22.0],
	["quayside-home",Vector3(164,.1,130),22.0],
	["canal-home",Vector3(307.1875,.1,-48),22.0],
]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene=world
	var deadline := Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play and world.production.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3); return
	world.player.controlled_automatically=true
	world.camera.set_process_unhandled_input(false)
	world.session.set_process_input(false)
	world.session.weather.time_of_day=.55
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var folder := "res://evidence/harbor-rebuild-20261013/tour"
	var selected := PackedStringArray()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sites="): selected = argument.trim_prefix("--sites=").split(",")
		if argument.begins_with("--variant="): folder = "res://evidence/harbor-rebuild-20261013/"+argument.trim_prefix("--variant=").validate_filename()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var report: Array = []
	for site in SITES:
		if not selected.is_empty() and site[0] not in selected: continue
		world.player.automatic_direction=Vector3.ZERO
		world.player.teleport(site[1])
		world.production.region.set_focus(site[1],true)
		world.camera.heading=0
		world.camera.target_size=site[2]
		world.camera.initialized=false
		for i in 180:
			await process_frame
			if i>60 and world.production.region.is_streaming_idle(): break
		for i in 10:
			world.player.automatic_direction=Vector3.RIGHT if i>=2 and i<7 else Vector3.ZERO
			world.camera.heading=float(i)*.025
			await create_timer(.25).timeout
			await RenderingServer.frame_post_draw
			var at: Vector3=world.player.global_position
			var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at-Vector3.UP*4,1)
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
			var path := "%s/%s-%02d.png"%[folder,site[0],i]
			root.get_texture().get_image().save_png(path)
			report.append({"site":site[0],"frame":i,"ticks_ms":Time.get_ticks_msec(),"position":str(at),"support":str(hit.get("position","none")),"image":path})
		print("HARBOR_TOUR ",site[0]," at=",world.player.position)
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit(0)

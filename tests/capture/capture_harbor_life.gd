extends SceneTree
var world
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 2400:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	world.player.controlled_automatically=true
	world.session.weather.time_of_day=.93
	world.session.weather.weather_state=0
	world.session.weather._update()
	world.session.weather.set_process(false)
	world.session.urban_operations.security.authorized_visit=true
	world.camera.set_process(false)
	var folder:="res://evidence/harbor-life-20260928/review/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for site in [{"id":"terminal","point":Vector3(229,.2,195),"size":35.0},{"id":"quay","point":Vector3(265,.1,210),"size":45.0},{"id":"fishing","point":Vector3(238.6,.2,189),"size":18.0}]:
		world.player.teleport(site.point)
		world.session.urban_operations.security.authorized_visit=true
		world.session.urban_operations.security.was_inside=world.session.urban_operations.security._inside_security_zone(site.point)
		world.production.region.set_focus(site.point)
		world.camera.size=site.size
		world.camera.global_position=site.point+Vector3(25,28,25)
		world.camera.look_at(site.point)
		await create_timer(8.0).timeout
		var lighting=world.find_child("CityLocalLighting",true,false)
		print("LIGHT_REVIEW ",site.id," focus=",world.player.global_position," camera=",world.camera.global_position," sources=",get_nodes_in_group("city_local_light_source").size())
		if lighting!=null:
			for light in lighting.lights: print("LAMP ",light.global_position," energy=",light.light_energy," visible=",light.visible," fade=",light.distance_fade_enabled)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+site.id+".png")
	# Stable camera, same actor and furniture: front, behind and beside the bench.
	world.camera.size=12
	world.camera.global_position=Vector3(240,14,210)
	world.camera.look_at(Vector3(233,0,200))
	for site in [{"id":"bench-front","point":Vector3(234.4,.2,201)},{"id":"bench-behind","point":Vector3(234.4,.2,199)},{"id":"bench-side","point":Vector3(232.9,.2,200)}]:
		world.player.teleport(site.point)
		for i in 15: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder+site.id+".png")
	world.free()
	await process_frame
	quit()

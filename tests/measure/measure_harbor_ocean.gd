extends "res://tests/measure/measure.gd"
## Rendered production scene. --capture-only for visual QA; otherwise 5s warmup + 30s.
## Run with --no-save --skip-arrival --benchmark --population=24.
class LegacyWater extends RefCounted:
	var material := StandardMaterial3D.new()
	func _init() -> void:
		material.albedo_color = Color("244954")
		material.roughness = 0.86
	func build_chunk(parent: Node3D, rect: Rect2) -> MeshInstance3D:
		var surface := MeshInstance3D.new()
		surface.name = "Water"
		var box := BoxMesh.new()
		box.size = Vector3(rect.size.x,0.12,rect.size.y)
		surface.mesh = box
		surface.material_override = material
		surface.position = Vector3(rect.get_center().x,-1,rect.get_center().y)
		parent.add_child(surface)
		return surface

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	label = "harbor-ocean"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1200:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(1); return
	if "--baseline" in OS.get_cmdline_user_args():
		label = "harbor-ocean-baseline"
		var region = world.production.region
		region.harbor_ocean = LegacyWater.new()
		for key in region.chunks:
			var chunk: Node3D = region.chunks[key]
			var water := chunk.get_node_or_null("Water")
			if water != null: water.free()
			region.harbor_ocean.build_chunk(chunk,Rect2(key.x*64,key.y*64,64,64))
	# Existing south-port land, facing the open western basin.
	var origin := Vector3(202,0.08,219)
	world.player.teleport(origin)
	world.production.region.set_focus(origin)
	world.player.controlled_automatically = true
	world.camera.heading = PI * 0.5
	world.camera.target_size = 42
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(false)
	world.session.weather.time_of_day = 0.32
	world.session.weather.weather_state = 0
	world.session.weather.weather_timer = 1000
	world.session.weather._update()
	route = PackedVector3Array([origin,origin+Vector3(0,0,8)])
	world.player.speed = 1.5
	if "--capture-only" in OS.get_cmdline_user_args():
		await create_timer(8).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/harbor-ocean.png")
		world.camera.target_size = 26
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/harbor-ocean-walk.png")
		world.session.weather.time_of_day = 0.0
		world.session.weather._update()
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/harbor-ocean-night.png")
		if "--shore-detail" in OS.get_cmdline_user_args():
			world.session.weather.time_of_day = 0.32
			world.session.weather._update()
			world.player.teleport(Vector3(268,0.08,203))
			world.production.region.set_focus(world.player.position)
			world.camera.heading = 0.0
			world.camera.target_size = 32
			world.camera.initialized = false
			await create_timer(3).timeout
			for frame in 16:
				await create_timer(0.55).timeout
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://evidence/harbor-shore-%02d.png"%frame)
		print("OCEAN_CAPTURE ",world.player.global_position)
		world.queue_free()
		await process_frame
		quit()
		return
	started = Time.get_ticks_usec()
	previous = started

extends SceneTree
## Temporal capture of real ambient riders; never writes a player save.
const LAYOUT = preload("res://activities/skate/SkateParkLayout.gd")
const OUT := "res://output/skate-npc-20261010"
var world
var samples: Array[Dictionary] = []
func _initialize(): run.call_deferred()
func frames(count: int):
	for i in count: await physics_frame
func run():
	if DisplayServer.get_name() == "headless" or not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 2400:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		quit(2)
		return
	var session = world.session
	session.state.intro.stage = "complete"
	session.weather.time_of_day = .45
	session.weather.weather_state = 0
	session.weather.weather_timer = 1000
	session.weather._update()
	for park in ([false] if "--street-only" in OS.get_cmdline_user_args() else [true, false]):
		world.player.teleport(LAYOUT.ENTRY + Vector3(.8, .1, 0) if park else Vector3(-65, .1, -65))
		world.production.region.set_focus(world.player.position)
		world.player.controlled_automatically = true
		world.player.speed = 0
		world.camera.initialized = false
		await frames(300 if park else 600)
		var row: Dictionary = {}
		for candidate in session.skate.ambient:
			if candidate.park == park:
				row = candidate
				break
		# Population routes are seeded per visit. If the eligible pedestrian is
		# just outside activation range, approach that real actor rather than
		# spawning a stand-in or changing the production activation radius.
		if row.is_empty() and not park:
			for actor in world.people:
				if actor.identity % 5 == 0 and not actor.has_meta("skate_used") and actor.is_on_floor() and not actor.dead and actor.health == 100:
					world.player.teleport(actor.position + Vector3(0, .1, 6))
					world.production.region.set_focus(world.player.position)
					await frames(120)
					break
			for candidate in session.skate.ambient:
				if not candidate.park:
					row = candidate
					break
		if row.is_empty():
			FileAccess.open(OUT + ("/temporal-street.json" if "--street-only" in OS.get_cmdline_user_args() else "/temporal.json"), FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
			for actor in world.people:
				if actor.identity % 5 == 0:
					print("STREET_CANDIDATE identity=", actor.identity, " distance=", actor.position.distance_to(world.player.position), " floor=", actor.is_on_floor(), " route=", actor.route.size(), " used=", actor.has_meta("skate_used"))
			push_error("No ambient rider for capture park=%s" % park)
			quit(3)
			return
		world.camera.set_process(false)
		world.camera.size = 4
		for i in 36:
			await frames(5)
			if not is_instance_valid(row.board) or not row.board.riding: break
			var board = row.board
			world.camera.global_position = board.position + Vector3(3.8, 2.2, 3.8)
			world.camera.look_at(board.position + Vector3.UP * .7)
			await process_frame
			await RenderingServer.frame_post_draw
			var label := "%s-%02d" % ["park" if park else "street", i]
			root.get_texture().get_image().save_png(OUT + "/" + label + ".png")
			samples.append({"frame": label, "position": str(board.position), "pushing": board.pushing, "phase": board.push_phase, "contact": board.push_contact, "slope": str(board.visual.rotation), "speed": board.speed})
		world.camera.set_process(true)
	FileAccess.open(OUT + ("/temporal-street.json" if "--street-only" in OS.get_cmdline_user_args() else "/temporal.json"), FileAccess.WRITE).store_string(JSON.stringify(samples, "\t"))
	print("SKATE_NPC_CAPTURE frames=", samples.size())
	world.free()
	quit()

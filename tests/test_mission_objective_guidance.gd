extends "res://tests/measure/measure_maciota_objective.gd"
## Main integration: persistent objective, contextual tow waypoint and real player sweeps.
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)

func run() -> void:
	await super.run()
	if not is_instance_valid(world): return
	var campaign: Dictionary = preload("res://tests/fixtures/NorthGatewayFixtures.gd").prefix(1)
	campaign.active_id = "cobra_contact"
	campaign.step = 1
	check(world.session.state.campaign.restore_snapshot(campaign),"validated mission checkpoint")
	var mission = world.session.mission_world
	check(mission.begin_tow_job({"story":true,"kind":"local"}),"real tow truck and cargo prepared")
	check("guincho do Neco" in mission.objective(),"objective explains tow truck first")
	if is_instance_valid(mission.truck):
		check(mission.target_position() == mission.truck.global_position,"marker guides player to truck before cargo")
		var previous_car = world.driving.car
		world.driving.car = mission.truck
		world.driving.occupied = true
		check("traseira" in mission.objective(),"seated truck guidance explains loading")
		check(mission.target_position() == mission.cargo.global_position,"truck driver destination is cargo")
		world.driving.occupied = false
		world.driving.car = previous_car
	for frame in 20: await physics_frame
	world.hud.refresh_from_state()
	await process_frame
	await process_frame
	var hud = world.hud
	check(hud.current_objective.visible and "guincho do Neco" in hud.current_objective_label.text,"persistent HUD uses current mission guidance")
	check(hud.current_objective.get_global_rect().end.y < hud.minimap.get_global_rect().position.y,"objective stays above minimap")
	world.session.show_journal()
	check(world.session.column.get_children().any(func(child): return child is Label and "guincho do Neco" in child.text),"journal explains the same next action as read-only information")
	world.session.close_menu()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("after-objective.png"))
	started = Time.get_ticks_usec()
	previous = started

func finish() -> void:
	print("MISSION_GUIDANCE_END ",JSON.stringify({"place":world.session.state.place_id,"player":str(world.player.global_position),"room":str(world.maciota_place.room.global_position),"locked":world.player.input_locked,"modal":world.session.modal}))
	check(world.hud.current_objective.visible and world.hud.current_objective.modulate.a > .99,"current objective remains readable after 30 seconds")
	# Actual player body, independent collision checks in both directions.
	world.player.automatic_direction = Vector3.ZERO
	for row in [[Vector3(1.2,.04,2.5),Vector3(2,0,0)], [Vector3(3.2,.04,2.5),Vector3(-2,0,0)]]:
		world.player.teleport(world.maciota_place.room.to_global(row[0]))
		var origin: Vector3 = world.player.global_position
		check(world.player.move_and_collide(row[1]) == null and world.player.global_position.distance_to(origin+row[1]) < .01,"player crosses widened office approach " + str(row[0]))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("after-passage-"+str(checks)+".png"))
	check(not world.player.input_locked and not world.session.state.weapons_allowed(),"control remains free and garage stays weapon free")
	check(await world.session.leave_place(),"real garage exit returns control outside")
	for frame in 20: await physics_frame
	world.hud.refresh_from_state()
	check(world.hud.current_objective.visible and world.hud.minimap.visible,"objective and minimap remain visible outdoors")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("after-exterior-objective.png"))
	print("MISSION_GUIDANCE ",checks," checks failures=",failures)
	if not failures.is_empty():
		world.free()
		quit(1)
		return
	await super.finish()

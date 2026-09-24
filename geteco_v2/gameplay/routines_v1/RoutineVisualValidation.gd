extends SceneTree
## Captura real do lodge com os tres residentes V1 materializados pelo diretor.

var world

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--no-save" not in arguments or "--skip-arrival" not in arguments:
		push_error("ROUTINE_VISUAL recusada: use --no-save --skip-arrival")
		quit(2)
		return
	var output := ""
	for argument in arguments:
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if output.is_empty():
		push_error("ROUTINE_VISUAL recusada: informe --out=<arquivo.png>")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for _frame in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play and world.session.weather != null: break
	if world.session == null or not world.session.ready_for_play or not world.production.no_save:
		push_error("ROUTINE_VISUAL mundo inseguro ou incompleto")
		quit(1)
		return
	if not world.production.travel("mountain"):
		push_error("ROUTINE_VISUAL viagem para serra recusada")
		quit(1)
		return
	for _frame in 900:
		await physics_frame
		if world.session.state.region_id == "mountain" and world.session.ready_for_play: break
	if not await world.session.enter_place("ski_lodge", false):
		push_error("ROUTINE_VISUAL entrada no lodge recusada")
		quit(1)
		return
	for _frame in 30: await physics_frame
	var director = world.get_node_or_null("V1RoutineDirector")
	var ids: Array[String] = director.active_ids() if director != null else []
	if ids.size() != 3:
		push_error("ROUTINE_VISUAL residentes ausentes: " + str(ids))
		quit(1)
		return
	world.diagnostic_label.hide()
	if "--stabilize-camera" in arguments:
		# Fixture isolada para inspecionar os atores. A transicao integrada sem
		# isto fica registrada separadamente como defeito do anchor central.
		world.session.anchor.reset_physics_interpolation()
		world.camera.initialized = false
		world.camera._process(1.0)
		world.camera.reset_physics_interpolation()
		world.hud.visible = false
		world.pause_panel.hide()
		for _frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output)
	print("ROUTINE_VISUAL ", "PASS" if error == OK else "FAIL", " output=", output, " actors=", ids)
	world.free()
	await process_frame
	quit(0 if error == OK else 1)

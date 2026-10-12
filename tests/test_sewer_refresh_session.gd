extends SceneTree
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
var world
var failures: Array[String] = []
var checks := 0
var leaked := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func observe_audio() -> void:
	for node in world.find_children("SewerAmbience", "", true, false):
		if node.channel != null and node.channel.playing:
			if world.session.room != node.get_parent().get_parent() or world.session.state.place_id.is_empty(): leaked = true
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 18000:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "mundo inicia")
	if not failures.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute("res://output/sewer-refresh")
	for id in NETWORK.ids() + ["sewer_warehouse"]:
		var definition := CATALOG.get_definition(id)
		world.session.controller.region.set_focus(definition.entry_position)
		world.player.teleport(definition.entry_position + Vector3(-1.2,.08,1.0))
		for i in 60: await physics_frame
		var hatch: Node3D = world.session._find_sewer_hatch(id)
		if is_instance_valid(hatch):
			world.player.teleport(hatch.to_global(Vector3(0,.08,1.1)))
			for i in 3: await physics_frame
		leaked = false
		process_frame.connect(observe_audio)
		var entered: bool = await world.session.enter_place(id, false)
		process_frame.disconnect(observe_audio)
		check(entered, id + ": descida pela sessão real")
		if not entered: print("ENTRY_DIAGNOSTIC ", id, " ", world.player.global_position, " notice=", world.session.notice.text)
		check(not leaked, id + ": preparação da sala sem som na rua")
		if not entered: continue
		var room = world.session.room
		var ambience: Node = room.model.get_node("SewerAmbience")
		await create_timer(.3).timeout
		check(ambience.channel.playing, id + ": correnteza/goteiras presentes")
		check(world.player.is_physics_processing() and not world.player.input_locked, id + ": controles restaurados")
		check(world.session.room_npcs.size() == definition.npcs.size(), id + ": moradores preservados")
		for reward in definition.get("rewards", [definition.reward]):
			var transform: Transform3D = world.player.global_transform
			transform.origin = room.to_global(reward.local_position + Vector3.UP*.04)
			check(not world.player.test_move(transform,Vector3.UP*.001), id + ": corpo cabe no ponto de coleta " + str(reward.id))
		if DisplayServer.get_name() != "headless":
			for i in 30: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://output/sewer-refresh/gameplay-"+id+".png")
		world.player.teleport(room.to_global(definition.exit + Vector3.UP*.04))
		var left: bool = await world.session.leave_place()
		check(left and world.session.state.place_id.is_empty(), id + ": subida e retorno à rua")
		await create_timer(.3).timeout
		check(not is_instance_valid(ambience) or not ambience.channel.playing, id + ": saída encerra áudio")
		check(not world.player.input_locked, id + ": rua com controle livre")
	print("SEWER_REFRESH_SESSION checks=%d failures=%s" % [checks,failures])
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

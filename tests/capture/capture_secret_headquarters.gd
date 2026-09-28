extends SceneTree
## Visual review harness for the optional Vicente route. Requires --no-save.

const DEFAULT_OUTPUT := "user://secret-headquarters-20260928"

var world
var session
var passage
var tunnel
var output := DEFAULT_OUTPUT
var _baseline_resources: Array[Resource] = []

func _initialize() -> void:
	run.call_deferred()

func settle(frames := 16) -> void:
	for _frame in frames: await process_frame

func shot(id: String) -> void:
	await settle(12)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(ProjectSettings.globalize_path(output+"/"+id+".png"))
	if error != OK: push_error("SECRET_HQ_CAPTURE failed "+id+": "+error_string(error))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("out="): output = argument.trim_prefix("out=")
		if argument.begins_with("baseline="):
			var folder := argument.trim_prefix("baseline=")
			for id in ["SecretTunnel3D", "TruckersVillageSecretPassage"]:
				var script: GDScript = load("res://gameplay/urban_v1/"+id+".gd")
				script.source_code = FileAccess.get_file_as_string(folder+"/"+id+".gd.txt")
				if script.reload(true) != OK: quit(4); return
				_baseline_resources.append(script)
	root.size = Vector2i(1600,900)
	seed(195107)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for _frame in 420:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play:
		push_error("SECRET_HQ_CAPTURE Main did not become ready")
		quit(1)
		return
	session = world.session
	await settle(150)
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	session.weather.set_process(false)
	session.weather.time_of_day = .4
	session.weather.weather_state = 0
	session.weather._update()
	if is_instance_valid(session.world.hud): session.world.hud.hide()
	passage = session.urban_operations.secret_passage
	tunnel = passage.tunnel
	var progression = session.urban_operations.secret_network
	progression.receive_dossier()
	for id in progression.FRAGMENT_IDS: progression.collect_fragment(id)
	for id in progression.KEYPAD_CLUE_IDS: progression.discover_keypad_clue(id)
	progression.discover_house()
	progression.unlock_keypad()
	progression.discover_headquarters()
	progression.activate_power_node("power_main")
	progression.activate_power_node("power_drainage")
	progression.activate_route("route_village_house")
	progression.activate_route("route_harbor_sewer")
	passage.refresh_state()
	passage.set_region_active(true)
	if "--ramp-only" in OS.get_cmdline_user_args():
		# Diagnóstico da subida da escada da Casa 1: sobe da base até a sala.
		world.player.speed = 3.5
		world.player.teleport(passage.home.to_global(Vector3(.65,-4.2,-9.0)))
		await settle(30)
		var goal: Vector3 = passage.home.to_global(Vector3(.65,.04,-3.1))
		for frame in 420:
			var direction: Vector3 = goal-world.player.global_position
			direction.y = 0
			world.player.automatic_direction = direction.normalized()
			await physics_frame
			if frame%20 == 0: print("RAMP local=",passage.home.to_local(world.player.global_position)," floor=",world.player.is_on_floor())
			if frame == 200:
				var hit := KinematicCollision3D.new()
				var ahead: Vector3 = (passage.home.to_global(Vector3(0,0,.12))-passage.home.to_global(Vector3.ZERO))
				var blocked: bool = world.player.test_move(world.player.global_transform,ahead,hit,.001,true,4)
				print("RAMP test_move blocked=",blocked)
				for index in hit.get_collision_count():
					print("RAMP hit ",hit.get_collider(index).get_path()," normal=",hit.get_normal(index)," at=",passage.home.to_local(hit.get_position(index)))
		quit(0)
		return
	if "--walk-only" in OS.get_cmdline_user_args():
		var completed := await walk_route()
		if not completed: await shot("06-travessia-bloqueada")
		quit(0 if completed else 5)
		return

	session.world.player.teleport(passage.home.to_global(Vector3(.65,.04,-3.1)))
	await shot("01-casa-ampliada")
	session.world.player.teleport(passage.cellar_root.to_global(Vector3(0,.04,1.2)))
	await shot("02-porao-estante")
	tunnel.set_enabled(true)
	session.world.player.teleport(tunnel.to_global(Vector3(18,.04,-12)))
	await shot("03-tunel")
	session.world.player.teleport(tunnel.to_global(tunnel.HQ_CENTER+Vector3(-2.4,.04,2.0)))
	await shot("04-quartel")
	session.world.player.teleport(tunnel.to_global(tunnel.HQ_CENTER+Vector3(2.2,.04,-5.4)))
	await shot("05-setor-selado")
	for extra in [
		{"id":"08-arco-porto","at":Vector3(6.0,.04,-11.0)},
		{"id":"09-arco-serra","at":Vector3(28.5,.04,-11.0)},
		{"id":"10-bomba","at":Vector3(35.0,.04,-3.5)},
		{"id":"11-disjuntores","at":Vector3(42.0,.04,1.5)},
	]:
		session.world.player.teleport(tunnel.to_global(extra.at))
		await shot(extra.id)
	# Setor lacrado energizado: quadro no teto, portão aberto e cofre (fechado, depois aberto).
	tunnel.set_sealed_access(true)
	session.world.player.teleport(tunnel.vault_console_global())
	await shot("12-cofre-fechado")
	tunnel.set_vault_open(true)
	await shot("13-cofre-aberto")
	if "--depth" in OS.get_cmdline_user_args(): await depth_review()
	if "--walk" in OS.get_cmdline_user_args():
		if not await walk_route():
			await shot("06-travessia-bloqueada")
			quit(5)
			return

	if "--fort" in OS.get_cmdline_user_args():
		progression.activate_power_node("power_sealed_sector")
		progression.discover_audio_log("audio_sealed_sector")
		for id in progression.LAB_CLUE_IDS: progression.discover_lab_clue(id)
		progression.discover_sealed_sector()
		progression.unlock_final_door()
		tunnel.set_return_camera(world.camera)
		await session.enter_place("mountain_fort",false,"secret_network")
		await settle(40)
		print("FORT_DEBUG place=",session.state.place_id," room=",session.room.global_position," player=",world.player.global_position," cam=",world.camera.global_position," cam_current=",root.get_camera_3d()," model_vis=",session.room.model.visible," lights=",session.room.model.lights.size())
		await shot("14-forte")
		session.world.player.teleport(session.room.model.to_global(Vector3(0,.04,-3.0)))
		await shot("15-forte-porta")
		# Sala de operações: porta aberta, jogador no vão, depois em combate e com alarme.
		var fort = session.room
		fort.model.set_blast_open(true)
		fort.operation.rebuild_navigation()
		session.world.player.teleport(fort.model.to_global(Vector3(0,.04,-8.5)))
		await settle(60)
		await shot("16-operacoes-guarda")
		session.world.gameplay.health = 100.0
		await settle(150)
		session.world.gameplay.health = 100.0
		await shot("17-operacoes-combate")
		fort.operation.reinforcement_delay = .5
		fort.operation.trigger_alarm(session.world.player.global_position)
		await settle(240)
		session.world.gameplay.health = 100.0
		await shot("18-operacoes-alarme")
	print("SECRET_HQ_CAPTURE PASS "+ProjectSettings.globalize_path(output))
	world.free()
	await process_frame
	quit(0)

func walk_route() -> bool:
	# Only the initial placement is a teleport. Actor.gd owns every subsequent
	# movement, floor snap, gravity and collision in the actual production world.
	world.player.speed = 3.5
	world.player.teleport(passage.home.to_global(Vector3(.65,.04,-3.1)))
	await settle(30)
	var route: Array[Vector3] = [
		passage.home.to_global(Vector3(.65,.04,-4.65)),
		passage.home.to_global(Vector3(.65,-.64,-5.5)),
		passage.home.to_global(passage.STAIR_BOTTOM_LOCAL+Vector3(0,.1,0)),
		passage.home.to_global(Vector3(0,-4.31,-10.35)),
		passage.home.to_global(Vector3(-2,-4.31,-10.35)),
		passage.cellar_root.to_global(Vector3(-2,.04,.15)),
		passage.cellar_root.to_global(passage.CELLAR_SHELF_POINT),
		tunnel.entry_global(),
		tunnel.to_global(Vector3(0,.04,-4)),
		tunnel.to_global(Vector3(0,.04,-12)),
		tunnel.to_global(Vector3(36,.04,-12)),
		tunnel.to_global(Vector3(36,.04,2)),
		tunnel.to_global(Vector3(50.8,.04,2)),
		tunnel.to_global(Vector3(50.8,.04,2.6)),
		tunnel.to_global(Vector3(54,.04,2.6)),
		tunnel.to_global(tunnel.HQ_CENTER+Vector3(-3.0,.04,3.5)),
	]
	for index in route.size():
		var target := route[index]
		var started := Time.get_ticks_msec()
		while world.player.global_position.distance_to(target) > .18:
			var direction: Vector3 = target-world.player.global_position
			direction.y = 0
			world.player.automatic_direction = direction.normalized()
			await physics_frame
			if Time.get_ticks_msec()-started > 20000:
				world.player.automatic_direction = Vector3.ZERO
				push_error("SECRET_HQ_WALK blocked waypoint=%d actual=%s target=%s"%[index,world.player.global_position,target])
				print("SECRET_HQ_WALK home_local=",passage.home.to_local(world.player.global_position)," tunnel_local=",tunnel.to_local(world.player.global_position))
				for collision_index in world.player.get_slide_collision_count():
					var collision: KinematicCollision3D = world.player.get_slide_collision(collision_index)
					print("SECRET_HQ_WALK collider=",collision.get_collider().get_path()," normal=",collision.get_normal())
				return false
		print("SECRET_HQ_WALK waypoint=",index," position=",world.player.global_position)
	world.player.automatic_direction = Vector3.ZERO
	await shot("06-travessia-completa")
	print("SECRET_HQ_WALK PASS house-cellar-tunnel-headquarters")
	# Return along the same physical stairs also checks camera ownership; no
	# interior exit action or transfer is used in either direction.
	var reverse_route := route.duplicate()
	reverse_route.reverse()
	reverse_route.append(passage.home.to_global(Vector3(.65,.04,-3.1)))
	for target in reverse_route:
		var started := Time.get_ticks_msec()
		while world.player.global_position.distance_to(target) > .18:
			var direction: Vector3 = target-world.player.global_position
			direction.y = 0
			world.player.automatic_direction = direction.normalized()
			await physics_frame
			if Time.get_ticks_msec()-started > 20000:
				world.player.automatic_direction = Vector3.ZERO
				push_error("SECRET_HQ_RETURN blocked actual=%s target=%s"%[world.player.global_position,target])
				print("SECRET_HQ_RETURN home_local=",passage.home.to_local(world.player.global_position)," floor=",world.player.is_on_floor())
				for collision_index in world.player.get_slide_collision_count():
					var collision: KinematicCollision3D = world.player.get_slide_collision(collision_index)
					print("SECRET_HQ_RETURN collider=",collision.get_collider().get_path()," normal=",collision.get_normal())
				return false
	world.player.automatic_direction = Vector3.ZERO
	await shot("07-retorno-casa")
	# Ao voltar para dentro da Casa 1 quem manda é a câmera de interior da casa.
	if root.get_camera_3d() != world.camera and root.get_camera_3d() != passage.homes.interior_camera:
		push_error("SECRET_HQ_RETURN incorrect surface camera: "+str(root.get_camera_3d()))
		return false
	print("SECRET_HQ_RETURN PASS headquarters-tunnel-cellar-house")
	return true

func depth_review() -> void:
	var visitor = load("res://scripts/Actor.gd").new()
	visitor.name = "SecretHQDepthVisitor"
	visitor.identity = 5
	visitor.controlled_automatically = true
	world.add_child(visitor)
	for geometry in visitor.find_children("*","GeometryInstance3D",true,false):
		geometry.layers |= tunnel.UNDERGROUND_LAYER
	for view in [
		{"id":"frente","a":Vector3(-.8,.04,3.1),"b":Vector3(.8,.04,3.1)},
		{"id":"atras","a":Vector3(-.8,.04,-.5),"b":Vector3(.8,.04,-.5)},
		{"id":"lado","a":Vector3(-2.4,.04,1.2),"b":Vector3(2.4,.04,1.2)},
	]:
		world.player.teleport(tunnel.to_global(tunnel.HQ_CENTER+view.a))
		visitor.teleport(tunnel.to_global(tunnel.HQ_CENTER+view.b))
		await shot("depth-"+view.id)
	visitor.queue_free()

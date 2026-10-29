extends "res://tests/test_vertice_depth.gd"
## Escritório da Serra Bruta (29/10): colisão varrida e oclusão renderizada na sala nativa.
## Dante (Actor de produção) e um NPC real (BarPatronModel) contra os móveis; a máscara
## diagnóstica compara a cena com a mesma pose sem a sala (controle positivo).
## Uso (com tela): tools/run_godot_locked.sh --path . --script res://tests/test_mining_office_depth.gd
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const RESIDENTS := preload("res://world/places/OriginalResidents.gd")
const DEST := "res://evidence/mining-office-20261029/depth"
const VISITOR := {"id":"mining_office_visitor", "name":"Visitante", "model":"res://world/places/bars/BarPatronModel.gd", "appearance":{"patron_variant":5}, "local_position":Vector3.ZERO}
## Todo móvel que bloqueia o corpo. Paredes, soleira e piso não entram no inventário.
const FURNITURE := ["ConsoleDesk", "OfficeChair", "Lockers", "FilingCabinet", "RadioTable", "WaterCooler", "CoatRack", "KeyCabinet"]

func make_actor(stage: Node3D, player: bool) -> CharacterBody3D:
	var actor := ACTOR.new()
	actor.is_player = player
	actor.controlled_automatically = true
	actor.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	stage.add_child(actor)
	actor.set_physics_process(false)
	if not player:
		var original: Node = actor.visual.get_child(0)
		actor.visual.remove_child(original)
		original.queue_free()
		actor.visual.add_child(RESIDENTS.create_model(VISITOR))
	return actor

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 960)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("40382f")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("eee1cc")
	settings.ambient_light_energy = .55
	env.environment = settings
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60, -20, 0)
	light.light_energy = .55
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 90
	stage.add_child(camera)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1, 0, 1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var room = CATALOG.create_place("mining_office")
	check(room != null, "mining_office existe no catálogo")
	if room == null: _finish(stage); return
	stage.add_child(room)
	camera.size = room.camera_size
	camera.position = room.camera_target + Vector3(0, 18, 15)
	camera.look_at(room.camera_target)
	for frame in 4: await physics_frame
	# Inventário: cada móvel visível tem um sólido próprio.
	var ids := {}
	for body in room.solid_bodies: ids[str(body.get_meta("interior_solid_id", ""))] = body.get_meta("bounds")
	for id in FURNITURE: check(ids.has(id), "sólido de " + id)
	var dante := make_actor(stage, true)
	dante.position = room.definition.spawn + Vector3.UP * .04
	var visitor := make_actor(stage, false)
	visitor.position = Vector3(1.2, .04, 1.0)
	for frame in 30: await process_frame
	var natural := await capture()
	check(natural.save_png(DEST.path_join("natural.png")) == OK, "sala natural com Dante e visitante salva")
	visitor.free()
	# Spawn, saída e recompensa cabem no corpo inteiro.
	for point in [["spawn", room.definition.spawn], ["exit", room.definition.exit], ["reward", room.definition.rewards[0].local_position]]:
		dante.position = Vector3(point[1]) + Vector3.UP * .04
		dante.reset_physics_interpolation()
		await physics_frame
		check(not dante.test_move(dante.global_transform, Vector3.UP * .001), point[0] + " com cápsula livre")
	# Varredura: de um ponto livre, um deslocamento grande na direção de cada móvel bate nele
	# antes de chegar ao centro (não atravessa nem por passo longo).
	# Início livre e alvo de cada varredura, em linha reta até o meio do móvel, sem passar por outro.
	var sweeps := {"ConsoleDesk":[Vector3(-.9, .04, -1.55), Vector3(-.9, .04, -2.55)], "OfficeChair":[Vector3(-2.0, .04, -.2), Vector3(-2.0, .04, -1.72)],
		"Lockers":[Vector3(3.0, .04, -1.85), Vector3(4.11, .04, -1.85)], "FilingCabinet":[Vector3(2.27, .04, -1.1), Vector3(2.27, .04, -2.62)],
		"RadioTable":[Vector3(-2.9, .04, -.55), Vector3(-4.06, .04, -.55)], "WaterCooler":[Vector3(-2.6, .04, 1.4), Vector3(-3.75, .04, 1.4)],
		"CoatRack":[Vector3(2.9, .04, 2.35), Vector3(3.95, .04, 2.35)], "KeyCabinet":[Vector3(.9, .04, -1.3), Vector3(.9, .04, -2.9)]}
	for id in FURNITURE:
		var start: Vector3 = sweeps[id][0]
		var target: Vector3 = sweeps[id][1]
		dante.position = start
		dante.reset_physics_interpolation()
		await physics_frame
		var clear := not dante.test_move(dante.global_transform, Vector3.UP * .001)
		var collision := KinematicCollision3D.new()
		var hit := dante.test_move(dante.global_transform, target - start, collision)
		var blocker := ""
		if hit and collision.get_collider() != null: blocker = str(collision.get_collider().get_meta("interior_solid_id", collision.get_collider().name))
		check(clear and hit and blocker == id, id + " bloqueia o corpo (início livre=" + str(clear) + ", bateu em " + blocker + ")")
	# Caminhos válidos: os sólidos não fecham os corredores.
	var paths: Array = [[room.definition.spawn, room.definition.rewards[0].local_position], [room.definition.spawn, Vector3(-.9, 0, -1.75)],
		[room.definition.spawn, Vector3(3.25, 0, -1.85)], [room.definition.spawn, Vector3(-3.75, 0, .75)], [room.definition.spawn, room.definition.exit]]
	for path in paths:
		var a: Vector3 = path[0] + Vector3.UP * .04
		var b: Vector3 = path[1] + Vector3.UP * .04
		var ok := true
		for step in 20:
			dante.position = a.lerp(b, float(step) / 19.0)
			dante.reset_physics_interpolation()
			if dante.test_move(dante.global_transform, Vector3.UP * .001): ok = false
		check(ok, "corredor livre de " + str(Vector3(path[0]).snappedf(.1)) + " até " + str(Vector3(path[1]).snappedf(.1)))
	dante.free()
	var setups: Array[Dictionary] = [
		{"id":"cooler", "poses":{"front":Vector3(-3.75, .04, 2.05), "behind":Vector3(-3.75, .04, .78), "side":Vector3(-3.0, .04, 1.4)}},
		{"id":"console", "poses":{"front":Vector3(-.9, .04, -1.75), "side":Vector3(.25, .04, -2.5)}},
		{"id":"lockers", "poses":{"side":Vector3(3.25, .04, -1.85)}},
	]
	for player in [true, false]:
		var actor := make_actor(stage, player)
		for frame in 12: await process_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual, diagnostic)
		var who := "Dante" if player else "visitor"
		for setup in setups:
			for pose in setup.poses:
				actor.position = setup.poses[pose]
				actor.reset_physics_interpolation()
				var key: String = "mining_office-" + who + "-" + setup.id + "-" + pose
				check(not actor.test_move(actor.global_transform, Vector3.UP * .001), key + " cápsula livre")
				room.show()
				var actual := await capture()
				room.hide()
				var control := await capture()
				room.show()
				var visible_pixels := mask_count(actual)
				var control_pixels := mask_count(control)
				var ratio := float(visible_pixels) / maxf(1, control_pixels)
				check(control_pixels > 150, key + " controle positivo visível")
				if pose == "behind":
					check(ratio > .1 and ratio < .98, key + " móvel encobre a parte de baixo e o tronco aparece ratio=" + str(ratio))
				else:
					check(ratio > .80, key + " ator visível na frente/ao lado ratio=" + str(ratio))
				actual.save_png(DEST.path_join(key + ".png"))
				control.save_png(DEST.path_join(key + "-control.png"))
				records.append({"actor":who, "prop":setup.id, "pose":pose, "visible_pixels":visible_pixels, "control_pixels":control_pixels, "ratio":ratio})
		actor.free()
	_finish(stage)

func _finish(stage: Node3D) -> void:
	var report := {"checks":checks, "failures":failures, "renderer":RenderingServer.get_current_rendering_method(), "viewport":"1280x960", "records":records}
	FileAccess.open(DEST.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MINING_OFFICE_DEPTH checks=", checks, " failures=", failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

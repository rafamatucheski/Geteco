extends "res://tests/test_vertice_depth.gd"
## Rendered native depth using the final room camera and real player/visitor
## rigs. Positive controls hide the room only; they never hide the actor.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("CELLAR_DEPTH requires the real renderer; headless is not depth evidence")
		quit(2); return
	create_timer(90).timeout.connect(func(): push_error("CELLAR_DEPTH timeout"); quit(3))
	var folder := FIXTURE.output_dir("curitiba-cellar-depth")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var room = PLACES.create_place("harbor_curitiba_cellar")
	if room == null: check(false, "dedicated cellar room exists"); quit(1); return
	stage.add_child(room)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("312a28")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4c2b5")
	settings.ambient_light_energy = .55
	environment.environment = settings
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = room.camera_size
	stage.add_child(camera)
	camera.position = room.camera_target + Vector3(0, 18, 15)
	camera.look_at(room.camera_target)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1, 0, 1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for is_player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		for frame in 5: await process_frame
		var who := "dante" if is_player else "visitor"
		actor.position = Vector3(-1.8, .04, -1.35)
		actor.reset_physics_interpolation()
		var natural := await capture()
		check(natural.save_png(folder.path_join(who + "-natural.png")) == OK, who + " natural material evidence")
		mask_meshes(actor.visual, diagnostic)
		for setup in [
			{"id":"entry", "at":Vector3(0, .04, 4.0), "occluded":false},
			{"id":"counter-front", "at":Vector3(-1.8, .04, -1.35), "occluded":false},
			{"id":"counter-behind", "at":Vector3(-1.8, .04, -3.62), "occluded":false},
			{"id":"rack-front", "at":Vector3(6.28, .04, 1.83), "occluded":false},
			{"id":"rack-side", "at":Vector3(5.08, .04, 1.83), "occluded":false},
			{"id":"rack-behind", "at":Vector3(6.28, .04, -2.07), "occluded":true},
		]:
			actor.position = setup.at
			actor.reset_physics_interpolation()
			room.show()
			var rendered := await capture()
			room.hide()
			var control := await capture()
			room.show()
			var count := mask_count(control)
			var actual := mask_count(rendered)
			var ratio := float(actual) / maxf(float(count), 1)
			check(count > 35, who + " " + setup.id + " unobstructed positive control")
			if setup.occluded:
				check(ratio < .97, who + " loaded rack naturally occludes the real body: " + str(ratio))
			else:
				check(ratio > .70, who + " " + setup.id + " remains visible: " + str(ratio))
			rendered.save_png(folder.path_join(who + "-" + setup.id + ".png"))
			control.save_png(folder.path_join(who + "-" + setup.id + "-control.png"))
			records.append({"actor":who, "pose":setup.id, "visible":actual, "control":count, "ratio":ratio})
		actor.free()
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "records":records, "renderer":RenderingServer.get_current_rendering_method(), "notes":"Final orthographic room camera. Native player and visitor masks; room-hidden positive controls. Separate fixture diagnoses depth and does not certify integrated Main performance or resident animation."}, "\t"))
	print("CELLAR_DEPTH ", folder, " checks=", checks, " failures=", failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

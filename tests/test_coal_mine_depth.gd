extends "res://tests/test_vertice_depth.gd"
## Evidência renderizada separada: o jogador e o NPC reais precisam continuar visíveis
## na frente/ao lado do vagão enquanto o corpo sólido dele tampa as pernas atrás.
const COAL := preload("res://world/mining/coal/CoalMinePlace.gd")
const DEST := "res://evidence/mining-20261006/coal-depth"

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Coal mine occlusion requires rendered output")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DEST))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var mine := COAL.new()
	stage.add_child(mine)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("10161a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("99a8b3")
	settings.ambient_light_energy = .35
	environment.environment = settings
	stage.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = mine.camera_size
	stage.add_child(camera)
	camera.position = mine.camera_target + Vector3(0, 18, 15)
	camera.look_at(mine.camera_target)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1, 0, 1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shots: Array[Dictionary] = []
	for player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		for frame in 20: await process_frame
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var who := "player" if player else "npc"
		actor.position = Vector3(-8.9, .04, -4.05)
		var natural := await capture()
		natural.save_png(DEST.path_join(who + "-natural.png"))
		mask_meshes(actor.visual, diagnostic)
		for setup in [
			{"id": "front", "point": Vector3(-7.5, .04, -5.7)},
			{"id": "behind", "point": Vector3(-7.5, .04, -9.72), "occluded": true},
			{"id": "side", "point": Vector3(-5.75, .04, -7.8)},
			{"id": "tunnel", "point": Vector3(9, .04, 5.5)},
			{"id": "raid-cover-front", "point": Vector3(24, .04, 2.35)},
			{"id": "raid-cover-behind", "point": Vector3(24, .04, -.05), "occluded": true},
			{"id": "raid-cover-side", "point": Vector3(26.15, .04, 1)},
			{"id": "raid-table-front", "point": Vector3(28, .04, -2.9)},
			{"id": "raid-table-behind", "point": Vector3(28, .04, -5.65), "occluded": true}]:
			actor.position = setup.point
			actor.reset_physics_interpolation()
			var actual := await capture()
			mine.hide()
			var control := await capture()
			mine.show()
			var actual_count := mask_count(actual)
			var control_count := mask_count(control)
			var ratio := float(actual_count) / maxf(1, control_count)
			check(control_count > 60, who + " " + setup.id + " has positive actor visibility control")
			if setup.get("occluded", false): check(ratio > .15 and ratio < .87, who + " " + setup.id + " hides legs while upper body remains visible " + str(ratio))
			else: check(ratio > .88, who + " " + setup.id + " keeps actor visible " + str(ratio))
			var file := who + "-" + str(setup.id)
			actual.save_png(DEST.path_join(file + ".png"))
			control.save_png(DEST.path_join(file + "-control.png"))
			shots.append({"actor": who, "position": setup.id, "visible_pixels": actual_count, "control_pixels": control_count, "ratio": ratio})
		actor.free()
	mine.restore_secret(true)
	var revealed := await capture()
	revealed.save_png(DEST.path_join("revealed.png"))
	FileAccess.open(DEST.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "records": shots}, "\t"))
	stage.free()
	viewport.free()
	print("COAL_DEPTH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

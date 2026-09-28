extends SceneTree
## Real Actor rigs, warehouse meshes and rendered depth. Magenta is a diagnostic
## actor mask; the unoccluded control hides architecture, never the actor.
const BUILDING := preload("res://gameplay/urban_v1/PortDepotBuilding.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const OUTPUT := "res://evidence/port-logistics-20260928/depth"
var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var records: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("VERTICE_DEPTH ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func capture() -> Image:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func mask_count(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.r > .55 and color.b > .55 and color.g < .2: count += 1
	return count

func mask_meshes(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.material_overlay = null
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): mask_meshes(child, material)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendered depth requires a GPU display; headless is not evidence")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("b7c4c6")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = .65
	environment.environment = settings
	scene.add_child(environment)
	var sunlight := DirectionalLight3D.new()
	sunlight.rotation_degrees = Vector3(-48, -30, 0)
	sunlight.light_energy = 1.0
	scene.add_child(sunlight)
	var depot := BUILDING.new()
	scene.add_child(depot)
	depot.set_cutaway(true)
	depot.set_office_open(1)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10
	camera.far = 90
	scene.add_child(camera)
	camera.current = true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color = Color(1, 0, 1)
	diagnostic.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var setups := [
		{"id": "rack", "camera": Vector3(-19, 4.5, 14), "target": Vector3(-19, 1.6, -4),
		 "front": Vector3(-19, .04, -1.4), "behind": Vector3(-19, .04, -6.5), "side": Vector3(-23, .04, -4)},
		{"id": "desk", "camera": Vector3(39.3, 3.8, 25), "target": Vector3(39.3, 1.0, 14),
		 "front": Vector3(38.1, .04, 16.3), "behind": Vector3(38.1, .04, 12.7), "side": Vector3(36.8, .04, 14)}]
	for is_player in [true, false]:
		var actor := ACTOR.new()
		actor.is_player = is_player
		actor.controlled_automatically = true
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var who := "player" if is_player else "npc"
		# Natural materials first: one evidence image of each real rig by a rack.
		actor.position = Vector3(-19, .04, -1.4)
		camera.position = setups[0].camera
		camera.look_at(setups[0].target)
		var natural := await capture()
		check(natural.save_png(OUTPUT + "/" + who + "-natural.png") == OK, who + " natural evidence saved")
		mask_meshes(actor.visual, diagnostic)
		for setup in setups:
			camera.position = setup.camera
			camera.look_at(setup.target)
			for pose in ["front", "behind", "side"]:
				actor.position = setup[pose]
				depot.show()
				var rendered := await capture()
				var visible_pixels := mask_count(rendered)
				var id: String = who + "-" + setup.id + "-" + pose
				check(rendered.save_png(OUTPUT + "/" + id + ".png") == OK, id + " evidence saved")
				depot.hide()
				var control := await capture()
				var control_pixels := mask_count(control)
				check(control.save_png(OUTPUT + "/" + id + "-control.png") == OK, id + " control saved")
				check(control_pixels > 150, id + " unoccluded positive control contains actor")
				var ratio := float(visible_pixels) / maxf(float(control_pixels), 1.0)
				if pose != "behind":
					check(ratio > .9, id + " actor is visibly in front or beside furniture: " + str(ratio))
				elif setup.id == "rack":
					check(ratio < .15, id + " loaded rack occludes actor: " + str(ratio))
				else:
					check(ratio > .05 and ratio < .9, id + " desk occludes lower body while upper body remains visible: " + str(ratio))
				records.append({"actor": who, "prop": setup.id, "pose": pose, "visible_pixels": visible_pixels, "control_pixels": control_pixels, "visible_ratio": ratio})
				depot.show()
		actor.free()
	var report := FileAccess.open(OUTPUT + "/results.json", FileAccess.WRITE)
	check(report != null, "Depth evidence report can be saved")
	if report:
		report.store_string(JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_current_rendering_method(), "records": records}, "\t"))
	print("VERTICE_DEPTH checks=", checks, " failures=", failures)
	scene.free()
	viewport.free()
	for frame in 2: await process_frame
	quit(0 if failures.is_empty() else 1)

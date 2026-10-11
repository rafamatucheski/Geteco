extends SceneTree
## Captura os mesmos corpos e poses de vários lados: uma tolerância numérica do punho não comprova a pegada visual.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
var output_dir := "res://evidence/npc-meshy/refinement-20261011/contacts"
var weapon_id := "m4a1"
var full_body := false
var sources := ["police/suit_m", "police/suit_f", "country/country_m_a", "country/country_f_a", "police/tactical_gray"]

func _prepare_source(path: String) -> String:
	if not path.begins_with("res://evidence/"): return path
	# evidence é ignorada pelo importador; gera uma cena local sem reimportar assets de outras sessões.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file(ProjectSettings.globalize_path(path), state) == OK)
	var scene := document.generate_scene(state)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	var scene_path := path.get_basename() + ".tscn"
	assert(ResourceSaver.save(packed, scene_path, ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK)
	scene.free()
	return scene_path

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("Captura excedeu o prazo"); quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--body="): sources = [arg.substr(7)]
		elif arg.begins_with("--bodies="): sources = Array(arg.substr(9).split(","))
		elif arg.begins_with("--weapon="): weapon_id = arg.substr(9)
		elif arg == "--full-body": full_body = true
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8fa3ad")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9c4cc")
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 35, 0)
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	stage.add_child(ground)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 32.0 if full_body else 24.0
	for source in sources:
		var path: String = source if source.begins_with("res://") else "res://assets/civilians/meshy/%s.glb" % source
		CATALOG.override[2] = _prepare_source(path)
		var police := MODEL.new()
		police.tier = 2
		police.appearance_index = 2
		stage.add_child(police)
		police.equip(weapon_id)
		for step in 8: await process_frame
		# Os equipamentos procedurais do override escondem a costura que estamos inspecionando.
		for piece in police.body.find_children("Equip_*", "MeshInstance3D", true, false): piece.hide()
		for state in ["idle", "walk", "aim", "recoil", "reload-fetch", "reload-insert", "reload-rack", "run"]:
			police.body.set_process(true)
			police.weapon.visible = state not in ["idle", "walk"]
			for step in 36:
				var speed := 1.4 if state == "walk" else (4.5 if state == "run" else 0.0)
				police.position.z -= speed / 60.0
				if state == "recoil" and (step % 8 == 0 or step == 35): police.attack()
				var reloading: bool = state.begins_with("reload")
				var progress: float = {"reload-fetch": .18, "reload-insert": .48, "reload-rack": .72}.get(state, 0.0)
				police.update_pose(1.0 / 60.0, state in ["aim", "recoil"] or reloading, reloading, progress, 0.0)
				if state in ["idle", "walk"]:
					police.body.hand_provider = Callable()
					police.body.hand_targets = [null, null]
				await process_frame
			await create_timer(0.0).timeout
			police.body.set_process(false)
			var bones: Array = []
			var skeleton: Skeleton3D = police.body.skeleton
			for bone in skeleton.get_bone_count():
				var pose := skeleton.get_bone_global_pose(bone)
				bones.append({"name": skeleton.get_bone_name(bone), "matrix": [
					[pose.basis.x.x, pose.basis.y.x, pose.basis.z.x, pose.origin.x],
					[pose.basis.x.y, pose.basis.y.y, pose.basis.z.y, pose.origin.y],
					[pose.basis.x.z, pose.basis.y.z, pose.basis.z.z, pose.origin.z], [0, 0, 0, 1]]})
			var pose_file := FileAccess.open("%s/%s-%s-bones.json" % [output_dir, path.get_file().get_basename(), state], FileAccess.WRITE)
			pose_file.store_string(JSON.stringify(bones))
			for view in [["front", Vector3(0, 1.25, -4.0)], ["back", Vector3(0, 1.25, 4.0)], ["side", Vector3(4.0, 1.25, 0)]]:
				camera.position = police.position + view[1]
				if full_body: camera.position.y = police.position.y + 1.0
				camera.look_at(police.position + Vector3(0, .9 if full_body else 1.12, 0), Vector3.UP)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s-%s-%s.png" % [output_dir, path.get_file().get_basename(), state, view[0]]))
		police.queue_free()
		await process_frame
	CATALOG.override.clear()
	print("Capturas de contato e costura em ", output_dir)
	quit(0)

extends "res://tests/test_maciota_workshop_session.gd"
## Captura no jogo real (Main.tscn) de pedestres de rua com corpo do Meshy, com o jogador perto deles.
## Só evidência visual: procura corpos de CivilianModel com esqueleto importado, leva o jogador até cada um
## e salva a tela inteira e um recorte ampliado em torno do pedestre.
## Uso: "$GODOT" --path . --script res://tests/diagnostics/pedestrian_closeup.gd -- --out=res://evidence/npc-meshy/closeup
var output_dir := "res://evidence/npc-meshy/closeup"

func _initialize() -> void:
	create_timer(280).timeout.connect(func(): push_error("CLOSEUP timeout"); quit(3))
	_run.call_deferred()

func _meshy_bodies() -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in root.find_children("*", "Node3D", true, false):
		if node.get("body_source") != null and String(node.get("body_source")) != "" and node.get("skeleton") != null and node.is_visible_in_tree():
			found.append(node)
	return found

func _run() -> void:
	if DisplayServer.get_name() == "headless": _finish(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	folder = FIXTURE.output_dir("pedestrian-closeup")
	path = FIXTURE.write_fixture(folder, "checkpoint.json", _seed())
	var launch := root.get_node_or_null("V2Launch")
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	root.size = Vector2i(1280, 720)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var start: Vector3 = world.player.global_position
	var taken := 0
	for point in [start, Vector3(166, .08, 111.8), Vector3(-226.7, .13, -39)]:
		world.player.teleport(point)
		await create_timer(10.0).timeout
		var bodies := _meshy_bodies()
		var nearest: Node3D = null
		for body in bodies:
			var gap := body.global_position.distance_to(world.player.global_position)
			if nearest == null or gap < nearest.global_position.distance_to(world.player.global_position): nearest = body
		if nearest == null: continue
		world.player.teleport(nearest.global_position + Vector3(1.8, 0, 1.8))
		await create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("%s/rua-%d.png" % [output_dir, taken]))
		var camera := root.get_viewport().get_camera_3d()
		if camera != null and not camera.is_position_behind(nearest.global_position):
			var screen := camera.unproject_position(nearest.global_position + Vector3(0, 0.9, 0))
			var half := Vector2i(150, 150)
			var origin := Vector2i(int(screen.x), int(screen.y)) - half
			origin = origin.clamp(Vector2i.ZERO, Vector2i(image.get_width() - 300, image.get_height() - 300))
			var crop := image.get_region(Rect2i(origin, half * 2))
			crop.resize(900, 900, Image.INTERPOLATE_LANCZOS)
			crop.save_png(ProjectSettings.globalize_path("%s/rua-%d-zoom.png" % [output_dir, taken]))
		print("CLOSEUP ", taken, " corpo=", nearest.get("body_source"), " visíveis_meshy=", bodies.size())
		taken += 1
	_finish(0)

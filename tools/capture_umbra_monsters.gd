extends SceneTree
## Evidência visual da Umbra com texturas grandes e monstros do Meshy (21/10/2026): salão com o monstrão
## no palco (parado e no susto), anexo com banquete, galeria e cripta.
## Uso: "$GODOT" --path . --script res://tools/capture_umbra_monsters.gd -- --out=res://evidence/umbra-meshy
const INTERIOR := preload("res://world/places/amusement_park/HauntedHouseInterior.gd")
var output_dir := "res://evidence/umbra-meshy"
var camera: Camera3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func _shot(label: String, from: Vector3, at: Vector3, frames := 20) -> void:
	camera.look_at_from_position(from, at)
	for i in frames: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir.path_join(label + ".png")))
	print("captura ", label)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1280, 720)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0b0c10")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("8a8494")
	env.environment.ambient_light_energy = .55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var room := INTERIOR.new()
	root.add_child(room)
	camera = Camera3D.new()
	camera.fov = 62.0
	root.add_child(camera)
	camera.current = true
	for i in 20: await process_frame
	await _shot("1-salao-palco", Vector3(0, 1.65, 6.4), Vector3(0, 1.4, -3))
	await _shot("2-salao-lateral", Vector3(-6.5, 1.65, 4.5), Vector3(2, 1.2, -4))
	for i in 90:
		room.update_visitor(Vector3(0, 0, 3.2), 1.0 / 60.0)
		await process_frame
	await _shot("3-monstrao-susto", Vector3(0, 1.65, 3.2), Vector3(-.4, 2.0, -3.1), 2)
	room.update_visitor(Vector3(40, 0, 40), 5.0)
	await _shot("4-anexo-banquete", Vector3(0, 1.65, -9.5), Vector3(0, 1.4, -17))
	await _shot("5-galeria-berco-relogio", Vector3(0, 5.1, -19.5), Vector3(0, 4.3, -26))
	await _shot("6-cripta", Vector3(0, 1.65, -20.5), Vector3(0, 1.2, -26.2))
	for station in room.annex.scares:
		for i in 40:
			room.annex.update_visitor(station.trigger, 1.0 / 60.0)
			await process_frame
		var rig: Node3D = station.rig
		var view: Vector3 = room.annex.to_global(station.trigger) + Vector3.UP * 1.65
		await _shot("7-susto-" + String(rig.name), view, rig.global_position + Vector3.UP * 1.2, 2)
		room.annex.update_visitor(Vector3(40, 0, 40), 5.0)
	quit(0)

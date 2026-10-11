extends SceneTree
## Mãos e braços de pedestres do Meshy andando: 8 quadros de um ciclo, de lado e de frente, câmera perto do tronco.
## Uso: "$GODOT" --path . --script res://tools/capture_walk_hands.gd -- --body=res://assets/civilians/meshy/pedestrians/m_medium_a.glb --out=res://evidence/npc-meshy/walk-hands
const CIVILIAN := preload("res://assets/CivilianModel.gd")
var roll := 70.0
var body := "res://assets/civilians/meshy/pedestrians/m_medium_a.glb"
var output_dir := "res://evidence/npc-meshy/walk-hands"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
		elif arg.begins_with("--body="): body = arg.substr(7)
		elif arg.begins_with("--roll="): roll = float(arg.substr(7))
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1600, 600)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	stage.add_child(sun)
	preload("res://assets/civilians/MeshyBodyRig.gd").hand_roll = deg_to_rad(roll)
	var walker := Node3D.new()
	stage.add_child(walker)
	var model := CIVILIAN.new() as Node3D
	model.appearance_locked = true
	model.appearance_variant = 5
	model.body_source = body
	walker.add_child(model)
	var camera := Camera3D.new()
	camera.fov = 22.0
	stage.add_child(camera)
	camera.current = true
	for view in [["side", Vector3(3.2, 1.0, 0.0)], ["front", Vector3(0.0, 1.0, 3.2)]]:
		var shots: Array[Image] = []
		walker.position = Vector3.ZERO
		for i in 40: await process_frame
		var frame := 0
		while shots.size() < 8:
			walker.position.z += 1.4 / 60.0
			camera.position = walker.position + view[1]
			camera.look_at(walker.position + Vector3(0, 0.95, 0), Vector3.UP)
			await process_frame
			frame += 1
			if frame % 9 == 0: shots.append(root.get_texture().get_image())
		var sheet := Image.create(400 * 4, 300 * 2, false, Image.FORMAT_RGB8)
		for k in shots.size():
			var im := shots[k]
			im.convert(Image.FORMAT_RGB8)
			im.resize(400, 300)
			sheet.blit_rect(im, Rect2i(0, 0, 400, 300), Vector2i((k % 4) * 400, (k / 4) * 300))
		sheet.save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, view[0]]))
	print("capturas em ", output_dir)
	quit(0)

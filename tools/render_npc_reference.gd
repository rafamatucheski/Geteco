extends SceneTree
## Renderiza vistas frontal, lateral e traseira de um modelo de NPC, em fundo neutro e luz plana,
## para servir de referência de imagem-para-3D (Meshy). Não é medição de desempenho.
## Uso: "$GODOT" --path . --script res://tools/render_npc_reference.gd -- --model=res://assets/maciota/MechanicModel.gd --out=res://evidence/npc-meshy/mechanic-ref
var model_path := "res://assets/maciota/MechanicModel.gd"
var output_dir := "res://evidence/npc-meshy/mechanic-ref"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): model_path = arg.substr(8)
		elif arg.begins_with("--out="): output_dir = arg.substr(6)
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	root.size = Vector2i(1024, 1024)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("d9d9d9")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.85
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.55
	stage.add_child(sun)
	var actor := (load(model_path) as GDScript).new() as Node3D
	stage.add_child(actor)
	var camera := Camera3D.new()
	camera.fov = 18.0
	stage.add_child(camera)
	camera.current = true
	for i in 12: await process_frame
	# O modelo antigo olha para -Z; o corpo articulado fica na frente de +Z do modelo.
	var views := {"front": 0.0, "side": 90.0, "back": 180.0}
	for view in views:
		actor.rotation_degrees.y = float(views[view])
		camera.position = Vector3(0, 0.95, 6.8)
		camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)
		for i in 6: await process_frame
		var shot := root.get_texture().get_image()
		# Quadrado central: tira o selo da versão do canto e deixa o personagem centralizado.
		var side := mini(shot.get_width(), shot.get_height())
		shot = shot.get_region(Rect2i((shot.get_width() - side) / 2, 0, side, side))
		shot.save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, view]))
	print("referências em ", output_dir)
	quit(0)

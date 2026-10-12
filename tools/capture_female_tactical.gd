extends SceneTree
## Policial tática feminina (SWAT e Exército) mirando, de frente, de lado e de costas.
## Uso: "$GODOT" --path . --script res://tools/capture_female_tactical.gd -- --out=res://evidence/npc-meshy/police-f
const MODEL := preload("res://gameplay/PoliceModel.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var out := "res://evidence/npc-meshy/police-f"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1400, 600)
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
	var cops: Array = []
	for k in 6:
		var police := MODEL.new()
		police.tier = 2 if k < 3 else 4
		police.appearance_index = 4 # perfil feminino do PoliceAppearance
		police.position = Vector3((k - 2.5) * 1.3, 0, 0)
		police.rotation.y = deg_to_rad([0.0, 90.0, 180.0][k % 3])
		stage.add_child(police)
		cops.append(police)
	var camera := Camera3D.new()
	camera.fov = 30.0
	stage.add_child(camera)
	camera.current = true
	await process_frame
	for police in cops: police.equip("m4a1")
	for i in 40:
		for police in cops: police.update_pose(1.0 / 60.0, true, false, 0.0, 0.0)
		await process_frame
	camera.position = Vector3(0, 1.2, 9.5)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	for i in 6: await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/feminina.png"))
	quit(0)

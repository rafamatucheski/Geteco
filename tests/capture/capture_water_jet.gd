extends SceneTree
## Jato d'água isolado visto de lado: da altura do canhão (2,46 m) até um alvo no
## chão a 7,8 m, com marcador no alvo. Saída em res://evidence/water-jet-0924/.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/water-jet-0924/"))
	root.size = Vector2i(1280, 540)
	var scene := Node3D.new()
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.38)
	scene.add_child(env)
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.2, 0.4, 0.2)
	marker.mesh = box
	marker.position = Vector3(7.8, 0.2, 0)
	scene.add_child(marker)
	var origin_marker := marker.duplicate()
	origin_marker.position = Vector3(0, 2.46, 0)
	scene.add_child(origin_marker)
	var jet = preload("res://gameplay/fx/WaterJet3D.gd").new()
	jet.flight_time = 0.9
	jet.drop_scale = 2.4
	scene.add_child(jet)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.look_at_from_position(Vector3(4, 1.5, 11), Vector3(4, 1.2, 0))
	for i in 120:
		jet.aim(Vector3(0, 2.46, 0), Vector3(7.8, 0.2, 0))
		jet.set_active(true)
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/water-jet-0924/lado.png"))
	print("LIFE ", jet.drops.lifetime, " vmin ", jet.drops.initial_velocity_min, " dir ", jet.drops.direction)
	quit(0)

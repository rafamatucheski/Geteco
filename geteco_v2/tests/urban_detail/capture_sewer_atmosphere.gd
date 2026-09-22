extends SceneTree
## Captura renderizada da galeria do esgoto e da tampa na rua.
## Uso: Godot --path geteco_v2 --script res://tests/urban_detail/capture_sewer_atmosphere.gd -- --tag=antes
## Não roda em headless: o renderer dummy não produz imagem.
const CATALOG = preload("res://world/places/PlaceCatalog.gd")
const OUT := "res://evidence/sewer-atmosphere-0922/"

func _initialize() -> void: call_deferred("run")

func capture(path: String) -> void:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("SEWER_CAPTURE ",ProjectSettings.globalize_path(path))

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var tag := "atual"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="): tag = arg.trim_prefix("--tag=")
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1600,900)
	var fixture := Node3D.new()
	root.add_child(fixture)
	# Iluminação de interior escura: o esgoto depende das próprias lâmpadas.
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("0b1112")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("7f95a0")
	env.environment.ambient_light_energy = .35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	fixture.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	fixture.add_child(camera)
	camera.make_current()
	var room = CATALOG.create_place("harbor_sewer")
	fixture.add_child(room)
	camera.size = room.camera_size
	camera.position = room.camera_target+Vector3(0,18,15)
	camera.look_at(room.camera_target)
	# Deixa partículas e água animarem um pouco antes da foto.
	for i in 90: await process_frame
	await capture(OUT+tag+"-galeria.png")
	# Close no esconderijo e no deságue.
	camera.size = 7.0
	camera.position = room.to_global(Vector3(7.2,.3,1.5))+Vector3(0,18,15)
	camera.look_at(room.to_global(Vector3(7.2,.3,1.5)))
	await capture(OUT+tag+"-esconderijo.png")
	camera.position = room.to_global(Vector3(2,.3,-4.2))+Vector3(0,18,15)
	camera.look_at(room.to_global(Vector3(2,.3,-4.2)))
	await capture(OUT+tag+"-desague.png")
	room.free()
	# Tampa na rua, sobre um asfalto simples.
	var street := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12,12)
	street.mesh = plane
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("3a3d40")
	street.material_override = asphalt
	fixture.add_child(street)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_energy = .6
	fixture.add_child(sun)
	var manhole = preload("res://world/urban_detail/HarborManholeExterior3D.gd").new()
	manhole.setup({"id":"harbor_sewer","kind":"sewer","size":Vector2(2,2)})
	fixture.add_child(manhole)
	camera.size = 4.0
	camera.position = Vector3(0,18,15)
	camera.look_at(Vector3(0,.3,0))
	for i in 150: await process_frame
	await capture(OUT+tag+"-tampa.png")
	quit(0)

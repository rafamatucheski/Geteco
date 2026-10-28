extends SceneTree
## Retratos do Dante real com cada acessório da Union e corpo inteiro das roupas novas.
## Precisa de janela (sem --headless). Não é medição de desempenho.
const ACTOR := preload("res://scripts/Actor.gd")
const CATALOG := preload("res://data/catalogs/AccessoryCatalog.gd")
const LOOK := preload("res://assets/outfits/DanteAccessories.gd")
const NEW_OUTFITS := ["dante_biker", "dante_hoodie", "dante_tracksuit", "dante_varsity", "dante_mechanic", "dante_urban_camo", "dante_tuxedo", "dante_puffer"]
var folder := ""
var shots: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Retratos de acessórios precisam de janela")
		quit(2)
		return
	folder = "res://evidence/wardrobe-accessories-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(640, 640)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("303a45")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("dde8f2")
	settings.ambient_light_energy = .65
	environment.environment = settings
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, -145, 0)
	key.light_energy = 1.1
	stage.add_child(key)
	var player := ACTOR.new()
	player.is_player = true
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_outfit("dante_classic")
	var camera := Camera3D.new()
	camera.fov = 32
	camera.near = .01
	stage.add_child(camera)
	camera.make_current()
	await create_timer(.8).timeout
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	for id in CATALOG.ORDER:
		if not only.is_empty() and not id.begins_with(only): continue
		LOOK.apply(player, {CATALOG.ITEMS[id].slot: id})
		var target := Vector3(0, 1.36, 0) if CATALOG.ITEMS[id].slot == "neck" else Vector3(0, 1.55, 0)
		for view in ["front", "side"]:
			camera.position = target + (Vector3(0, .05, -1.3) if view == "front" else Vector3(-1.0, .1, -.85))
			camera.look_at(target)
			if not await shot("%s-%s.png" % [id, view]): return
	LOOK.apply(player, {})
	if only.is_empty():
		for id in NEW_OUTFITS:
			player.set_outfit(id)
			for view in ["front", "three-quarter"]:
				camera.position = Vector3(0, 1.0, -4.6) if view == "front" else Vector3(-3.0, 1.1, -3.5)
				camera.look_at(Vector3(0, .95, 0))
				if not await shot("outfit-%s-%s.png" % [id, view]): return
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"capture_not_benchmark":true, "shots":shots}, "\t"))
	print("WARDROBE_PORTRAITS ", ProjectSettings.globalize_path(folder), " count=", shots.size())
	quit()

func shot(filename: String) -> bool:
	await create_timer(.1).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(folder.path_join(filename)) != OK:
		push_error("Falhou retrato: " + filename)
		quit(3)
		return false
	shots.append(filename)
	return true

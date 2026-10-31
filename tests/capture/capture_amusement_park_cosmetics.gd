extends SceneTree
## Retrato isolado do Dante real. Pose, câmeras e iluminação fixas em cada roupa.
## Renderize com Godot .NET, -- --label=before|after. Isto não é benchmark.
const ACTOR := preload("res://scripts/Actor.gd")
const COSMETICS := preload("res://activities/amusement_park/AmusementParkCosmetics.gd")
const STATE := preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
var folder := ""
var shots: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cosmetic fitting requires rendered portraits")
		quit(2)
		return
	var label := "after"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	folder = "res://evidence/amusement-park-cosmetics-%s-%d" % [label, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size = Vector2i(1280, 720)
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
	player.set_outfit("dante_lume")
	var camera := Camera3D.new()
	camera.fov = 32
	camera.near = .01
	stage.add_child(camera)
	camera.position = Vector3(0, 1.57, -1.2)
	camera.look_at(Vector3(0, 1.52, 0))
	camera.make_current()
	await create_timer(.8).timeout
	var variants := {
		"bare": ["", ""],
		"star": ["star_glasses", ""],
		"fox": ["", "fox_mask"],
		"star-fox": ["star_glasses", "fox_mask"],
		"amber": ["amber_glasses", ""],
		"ghost": ["", "ghost_mask"],
		"amber-ghost": ["amber_glasses", "ghost_mask"],
	}
	for variant: String in variants:
		var saved := STATE.fresh()
		saved.found = ["star_glasses", "amber_glasses", "fox_mask", "ghost_mask"]
		saved.glasses = variants[variant][0]
		saved.mask = variants[variant][1]
		COSMETICS.apply(player, {STATE.KEY:saved})
		for view: String in ["front", "three-quarter"]:
			camera.position = Vector3(0, 1.57, -1.2) if view == "front" else Vector3(-.77, 1.57, -.92)
			camera.look_at(Vector3(0, 1.52, 0))
			await create_timer(.12).timeout
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var filename := "%s-%s.png" % [variant, view]
			if root.get_texture().get_image().save_png(folder.path_join(filename)) != OK:
				push_error("Failed portrait: " + filename)
				quit(3)
				return
			shots.append(filename)
	var report := {"fixture":"isolated real Actor/Dante", "capture_not_benchmark":true,
		"shots":shots, "resolution":str(root.size), "renderer":RenderingServer.get_current_rendering_method(),
		"source_hashes":{"art":FileAccess.get_sha256("res://activities/amusement_park/AmusementParkCosmeticArt.gd"),
			"attachment":FileAccess.get_sha256("res://activities/amusement_park/AmusementParkCosmetics.gd")}}
	FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PARK_COSMETIC_PORTRAITS ", ProjectSettings.globalize_path(folder), " count=", shots.size())
	quit()

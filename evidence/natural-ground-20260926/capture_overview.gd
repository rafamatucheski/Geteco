extends SceneTree
## Vista aérea ortográfica de Mountain como a prévia do editor. Rodar renderizado.
## Uso: --script res://evidence/natural-ground-20260926/capture_overview.gd -- --no-save --label=after
const REGION := preload("res://world/editing/EditableRegion.gd")
const SPOTS := {"cabana": Vector3(648,0,-268), "lago": Vector3(700,0,-300)}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var label := "shot"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(1500,800)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("829da6")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("c0d0e2")
	env.environment.ambient_light_energy = .65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52,-30,0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 2000
	root.add_child(camera)
	camera.make_current()
	var folder := ProjectSettings.globalize_path("res://evidence/natural-ground-20260926/")
	for spot in SPOTS:
		var focus: Vector3 = SPOTS[spot]
		var region: Node3D = REGION.build_region("mountain",focus)
		root.add_child(region)
		for i in 1800:
			await process_frame
			if region.is_streaming_idle(): break
		if region.terrain != null: focus.y = region.terrain.surface_height_at(Vector2(focus.x,focus.z))
		for size in [70.0,22.0]:
			camera.size = size
			camera.position = focus+Vector3(0,sin(.88),cos(.88))*180
			camera.look_at(focus)
			for i in 12: await process_frame
			root.get_texture().get_image().save_png(folder+"%s_%s_%d.png" % [label,spot,int(size)])
		region.free()
		await process_frame
	print("CAPTURE_DONE")
	quit(0)

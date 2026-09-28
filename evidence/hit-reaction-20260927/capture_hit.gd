extends SceneTree
## Sequência renderizada da reação ao tiro: civil (vista lateral) e Dante no jogo.
## Uso: --script res://evidence/hit-reaction-20260927/capture_hit.gd -- --no-save
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const OUT := "res://evidence/hit-reaction-20260927/"
func _initialize() -> void: run.call_deferred()
func strip(frames: Array, name: String) -> void:
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var sheet := Image.create(w * frames.size(), h, false, frames[0].get_format())
	for i in frames.size(): sheet.blit_rect(frames[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.save_png(ProjectSettings.globalize_path(OUT + name))
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(360, 480)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("48525a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("9aa4ae")
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(3.2, 1.1, 0)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.make_current()
	var model := CIVILIAN.new()
	model.lod_enabled = false
	root.add_child(model)
	for i in 10: await process_frame
	var frames := []
	var travel: Vector3 = model.global_basis * Vector3(0, 0, -1)
	for frame in 72:
		if frame % 6 == 0 and frame < 36: model.take_hit(travel, 0.8)
		await process_frame
		if frame % 8 == 0: frames.append(root.get_texture().get_image())
	strip(frames, "civil_rajada.png")
	model.queue_free()
	# Dante no jogo real.
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var player = world.player
	var names := []
	for bone in ["Spine01", "Spine02"]: names.append("%s=%d" % [bone, player._combat_bones.get(bone, -1)])
	print("DANTE_BONES ", names)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var frames2 := []
	var peak := 0.0
	for frame in 72:
		if frame % 6 == 0 and frame < 36: player.present_hit()
		await process_frame
		peak = maxf(peak, player._hit_lean.x)
		if frame % 8 == 0: frames2.append(root.get_texture().get_image())
	strip(frames2, "dante_rajada.png")
	print("DANTE_HIT peak=%.3f final=%.4f cam=%s" % [peak, player._hit_lean.x, cam != null])
	quit(0)

extends SceneTree

var failures: Array[String] = []
var capture := false
var atlas: Image

func capture_actor(officer: Node, column: int, row: int) -> void:
	if not capture: return
	await process_frame
	await RenderingServer.frame_post_draw
	atlas.blend_rect(officer.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 180, 240), Vector2i(column * 180, row * 240))

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	capture = "capture" in OS.get_cmdline_user_args()
	if capture:
		atlas = Image.create(900, 720, false, Image.FORMAT_RGBA8)
		atlas.fill(Color("28303a"))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	for level in [1, 3, 4, 5, 6]:
		var officer := preload("res://police/PoliceOfficer.gd").new()
		# Each case is a different resident, not a streamed return of a corpse.
		officer.name = "UniformCase%d" % level
		officer.set_meta("quiet_patrol", true)
		officer.set_meta("response_tier_level", level)
		officer.local_security = true
		world.add_child(officer)
		officer.set_physics_process(false)
		if capture:
			officer.viewport_3d.size = Vector2i(180, 240)
			officer.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var camera := officer.viewport_3d.get_camera_3d()
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 1.9
			camera.position = Vector3(0, 2.3, 3.5)
			camera.look_at(Vector3(0, .7, 0))
			officer.model_root.rotation.y = PI
		var column: int = [1, 3, 4, 5, 6].find(level)
		await capture_actor(officer, column, 0)
		var original := officer.mat_uniform.albedo_color
		var model := officer.model_root
		var appearance := officer.appearance_model
		var health := officer.health
		officer.take_damage(1)
		check(officer.health == health - 1, "level %d receives damage" % level)
		await create_timer(0.3).timeout
		check(officer.mat_uniform.albedo_color.is_equal_approx(original), "level %d restores original uniform after hit" % level)
		officer.take_damage(1)
		await create_timer(0.05).timeout
		officer.take_damage(1)
		await create_timer(0.3).timeout
		check(officer.mat_uniform.albedo_color.is_equal_approx(original), "level %d restores uniform after overlapping hits" % level)
		await capture_actor(officer, column, 1)
		officer.take_damage(1)
		await create_timer(0.05).timeout
		officer.take_damage(officer.health)
		await create_timer(0.3).timeout
		check(officer.is_dead and officer.health == 0, "level %d dies from lethal hit" % level)
		check(officer.mat_uniform.albedo_color.is_equal_approx(original), "level %d corpse keeps original uniform" % level)
		check(officer.model_root == model and officer.appearance_model == appearance, "level %d retains character identity" % level)
		if capture:
			# Advance the real death presentation with the otherwise paused AI.
			for frame in 60: officer.fall_presentation.update(1.0 / 60.0)
		await capture_actor(officer, column, 2)
		officer.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	print("POLICE_UNIFORM_DAMAGE failures=", failures)
	if capture:
		atlas.save_png("res://../artifacts/police-uniform-damage-0914/uniforms.png")
	quit(0 if failures.is_empty() else 1)

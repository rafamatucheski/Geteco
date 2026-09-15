extends SceneTree
## Rendered regression: atmosphere moves, foreground stays still, reduced
## motion freezes both shader and birds, and layers follow the cropped art.
var failures: Array[String] = []
const OUTPUT := "D:/geteco/artifacts/menu-atmosphere-0910/"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok: failures.append(description)

func capture(presentation: Control, time: float) -> Image:
	presentation.atmosphere.elapsed = time
	presentation.atmosphere.queue_redraw()
	presentation.background.material.set_shader_parameter("atmosphere_time", time)
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func changed(a: Image, b: Image, uv: Rect2, art_size: Vector2) -> int:
	var count := 0
	var from := Vector2i(uv.position * art_size)
	var to := Vector2i(uv.end * art_size)
	for y in range(from.y, mini(to.y, a.get_height()), 2):
		for x in range(from.x, mini(to.x, a.get_width()), 2):
			if a.get_pixel(x, y) != b.get_pixel(x, y): count += 1
	return count

func run() -> void:
	var settings := root.get_node("SettingsManager")
	var previous: bool = settings.reduce_motion
	settings.reduce_motion = false
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(1.1).timeout
	var presentation: Control = menu.get_node("SunsetPresentation")
	check(presentation.atmosphere.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"atmosphere cannot intercept menu input")
	check(presentation.buttons[0].has_focus(), "menu keeps keyboard focus")
	presentation.set_process(false)
	var a: Image = await capture(presentation, 0.0)
	var b: Image = await capture(presentation, 8.0)
	a.save_png(OUTPUT + "menu-00.png")
	b.save_png(OUTPUT + "menu-08.png")
	var art_size: Vector2 = presentation.background.size * root.get_stretch_transform().get_scale()
	check(changed(a, b, Rect2(0.32, 0.45, 0.04, 0.06), art_size) > 100,
		"harbour water and sunset reflections visibly move")
	check(changed(a, b, Rect2(0.48, 0.04, 0.12, 0.09), art_size) > 100,
		"cloud wisps move across open sky")
	check(changed(a, b, Rect2(0.65, 0.07, 0.077, 0.88), art_size) == 0,
		"Dante remains perfectly still")
	check(changed(a, b, Rect2(0.424, 0.467, 0.17, 0.065), art_size) == 0,
		"windshield and its frame remain perfectly still")
	check(changed(a, b, Rect2(0.38, 0.58, 0.22, 0.29), art_size) == 0,
		"car paint and wheels remain perfectly still")
	check(changed(a, b, Rect2(0.03, 0.09, 0.27, 0.26), art_size) == 0,
		"logo remains perfectly still")
	settings.reduce_motion = true
	presentation.set_process(true)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var frozen_a := root.get_texture().get_image()
	var frozen_time: float = presentation.atmosphere.elapsed
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	check(is_equal_approx(frozen_time, presentation.atmosphere.elapsed), "reduced motion freezes atmospheric clock")
	check(frozen_a.get_data() == root.get_texture().get_image().get_data(),
		"reduced motion freezes the complete rendered menu")
	presentation.set_process(false)
	for dimensions in [Vector2(1280, 720), Vector2(1024, 768), Vector2(1920, 800)]:
		presentation.size = dimensions
		presentation.arrange()
		check(presentation.atmosphere.size == presentation.background.size
			and presentation.atmosphere.position == presentation.background.position,
			"birds stay aligned with background at " + str(dimensions))
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	presentation.arrange()
	if "--preview" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(OUTPUT + "frames")
		for i in 96:
			var frame: Image = await capture(presentation, float(i) / 12.0)
			frame.resize(960, 540, Image.INTERPOLATE_LANCZOS)
			frame.save_png(OUTPUT + "frames/%03d.png" % i)
	settings.reduce_motion = previous
	menu.queue_free()
	await process_frame
	print("MENU_ATMOSPHERE failures=", failures)
	quit(0 if failures.is_empty() else 1)

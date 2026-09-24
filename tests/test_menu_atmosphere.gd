extends SceneTree
## Rendered regression for the static, sharp menu presentation.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	print(("PASS " if ok else "FAIL ") + description)
	if not ok: failures.append(description)

func run() -> void:
	# The refreshed menu intentionally keeps its environment art static and sharp.
	# Validate the art, focus, title and crop contract together.
	var refreshed_menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(refreshed_menu)
	current_scene = refreshed_menu
	await create_timer(1.1).timeout
	var refreshed_presentation: Control = refreshed_menu.get_node("SunsetPresentation")
	check(refreshed_presentation.background.texture.resource_path == "res://ui/art/menu_harbor_bluehour.png",
		"menu uses the current harbor artwork")
	check(refreshed_presentation.background.material == null,
		"menu artwork stays free of illustration-specific distortion shaders")
	check(refreshed_presentation.cover.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"contrast vignette cannot intercept menu input")
	check(refreshed_presentation.buttons[0].has_focus(), "menu keeps keyboard focus")
	check(refreshed_menu.game_title.get_parent() == refreshed_presentation and refreshed_menu.game_title.visible,
		"GETECO title is crisp interface text instead of baked artwork")
	for dimensions in [Vector2(1280, 720), Vector2(1024, 768), Vector2(1920, 800)]:
		refreshed_presentation.size = dimensions
		refreshed_presentation.arrange()
		var source_size: Vector2 = refreshed_presentation.background.texture.get_size()
		var expected_size := source_size * maxf(dimensions.x / source_size.x, dimensions.y / source_size.y)
		var expected_position: Vector2 = (Vector2(dimensions) - expected_size) * 0.5
		check(refreshed_presentation.background.size.is_equal_approx(expected_size)
			and refreshed_presentation.background.position.is_equal_approx(expected_position),
			"harbor crop remains centered at " + str(dimensions))
		check(refreshed_presentation.cover.size.is_equal_approx(dimensions),
			"contrast vignette covers the viewport at " + str(dimensions))
		check(Rect2(Vector2.ZERO, dimensions).encloses(refreshed_menu.game_title.get_rect()),
			"title remains inside the viewport at " + str(dimensions))
		for button in refreshed_presentation.buttons:
			check(Rect2(Vector2.ZERO, dimensions).encloses(button.get_rect()),
				"menu action remains inside the viewport at " + str(dimensions))
	refreshed_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	refreshed_presentation.arrange()
	refreshed_menu.queue_free()
	await process_frame
	print("MENU_PRESENTATION failures=", failures)
	quit(0 if failures.is_empty() else 1)

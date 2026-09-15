extends SceneTree

## Exercise the menu's background loader from a cold resource cache.
## Do not preload gameplay scripts: doing so hides loading-order failures.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var menu: PackedScene = load("res://ui/MainMenu.tscn")
	change_scene_to_packed(menu)
	await scene_changed
	var loader := root.get_node("GameLoading")
	loader.finished.connect(_loaded, CONNECT_ONE_SHOT)
	loader.failed.connect(func(message: String): _fail(message), CONNECT_ONE_SHOT)
	create_timer(90.0, true).timeout.connect(func(): _fail("Loading timed out"))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--slot="):
			# Use only a copied slot in an isolated APPDATA directory.
			current_scene._select_and_load_slot(argument.trim_prefix("--slot="))
			return
	if not loader.begin("res://legacy/Main.tscn"):
		_fail("Menu loader refused the legacy scene")

func _loaded() -> void:
	var loader := root.get_node("GameLoading")
	if current_scene == null or current_scene.scene_file_path != "res://legacy/Main.tscn":
		_fail("Legacy scene was not installed")
		return
	var cars := get_nodes_in_group("docks_parked_vehicle")
	if cars.size() != 2:
		failures.append("Expected both dock cars, got %d" % cars.size())
	for car in cars:
		if car.get_script() == null or not car.has_method("ensure_presentation"):
			failures.append("Dock vehicle has no working traffic script")
	if get_nodes_in_group("modern_traffic").size() < 32:
		failures.append("Legacy moving traffic did not populate")
	if get_nodes_in_group("modern_parked_vehicle").size() < 20:
		failures.append("Legacy parked traffic did not populate")
	if paused or loader.active:
		failures.append("Loading did not release gameplay")
	print("MENU_LEGACY_LOADING_RESULT failures=%d docks=%d" % [failures.size(), cars.size()])
	for message in failures:
		push_error(message)
	current_scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _fail(message: String) -> void:
	push_error("MENU_LEGACY_LOADING: " + message)
	quit(1)

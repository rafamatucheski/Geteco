extends Node
## Owns the real pending session. Simulation stays frozen until the camera lands.
## The gameplay camera, actors and interior framing are never edited for the flight.
signal boot_finished
signal released
const MAIN := "res://Main.tscn"
const FLIGHT_SECONDS := 3.0
var menu: Control
var world: Node3D
var is_ready := false
var loading := false
var transferred := false
var failed := false
var continuing := false
var preview_path := ""
var preview_fingerprint := ""
var camera: Camera3D
var clouds: CanvasLayer
var cloud_rect: ColorRect
var material: ShaderMaterial
var ui_layer: CanvasLayer
var held_nodes: Array[Dictionary] = []
var hidden_layers: Array[CanvasLayer] = []
var air_transform: Transform3D
var air_size := 100.0
var elapsed := 0.0
var reveal: Tween
const CLOUD_CLEAR_END := 0.42
const TURN_START := 0.48

func install(source: Control) -> void:
	menu = source
	process_mode = Node.PROCESS_MODE_ALWAYS
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 126
	menu.add_child(ui_layer)
	for child in menu.get_children():
		if child is Control: child.reparent(ui_layer)
	clouds = CanvasLayer.new()
	clouds.layer = 125
	add_child(clouds)
	cloud_rect = ColorRect.new()
	cloud_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cloud_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = ShaderMaterial.new()
	material.shader = preload("res://ui/art/sky_clouds.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 25092026
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.noise = noise
	material.set_shader_parameter("cloud_noise", texture)
	cloud_rect.material = material
	clouds.add_child(cloud_rect)
	clouds.hide()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.far = 650.0
	add_child(camera)
	if not menu.latest_save.is_empty() and "--no-save" not in OS.get_cmdline_user_args():
		boot_path(str(menu.latest_save.path))

static func fingerprint(path: String) -> String:
	var result := ""
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): result += FileAccess.get_sha256(path + suffix)
	return result

func boot_path(path: String) -> void:
	if loading or is_ready: return
	loading = true
	failed = false
	preview_path = path
	preview_fingerprint = fingerprint(path)
	menu.presentation.background.hide()
	clouds.show()
	material.set_shader_parameter("coverage", 1.0)
	var error := ResourceLoader.load_threaded_request(MAIN)
	if error != OK:
		_boot_failed()
		return
	while ResourceLoader.load_threaded_get_status(MAIN) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(MAIN) != ResourceLoader.THREAD_LOAD_LOADED:
		_boot_failed()
		return
	var packed = ResourceLoader.load_threaded_get(MAIN)
	world = packed.instantiate()
	world.set_meta("menu_preview", self)
	world.set_meta("menu_save_path", path)
	get_tree().root.add_child(world)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _boot_failed() -> void:
	loading = false
	failed = true
	if not continuing:
		clouds.hide()
		menu.presentation.background.show()
	boot_finished.emit()

## Runs at the click, before waiting for a preview or replacing its save.
func begin_continue() -> void:
	if continuing: return
	continuing = true
	ui_layer.hide()
	var focused := menu.get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	clouds.show()
	if not is_ready:
		material.set_shader_parameter("coverage", 1.0)
		material.set_shader_parameter("descent", 0.0)

func cancel_continue() -> void:
	continuing = false
	ui_layer.show()
	clouds.hide()
	menu.presentation.background.show()

## Called after restoration and population, before the arrival/mission can start.
func hold_world(scene: Node3D) -> void:
	world = scene
	# Garage rewards can restore a driver asynchronously after restore_location
	# returns. Freezing halfway through that admission postpones the car/body to
	# the first gameplay frame. Keep the clouds opaque until it has finished.
	while _vehicle_restore_pending():
		await get_tree().physics_frame
	world.camera._process(0.0)
	var point: Vector3 = world.camera.focus
	if not world.session.state.place_id.is_empty(): point = world.session.return_point
	var mountain: bool = world.session.state.region_id == "mountain"
	# The opening fits inside the guaranteed 64 m resident margin even at a
	# streaming-cell boundary; the shader keeps this footprint on ultrawide too.
	air_size = 90.0 if mountain else 100.0
	material.set_shader_parameter("aperture", 0.30 if mountain else 0.36)
	camera.size = air_size
	camera.position = point + Vector3(0, 155, 48)
	camera.look_at(point)
	air_transform = camera.transform
	_hold_always_nodes(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = true
	camera.make_current()
	# Fill the bounded resident neighbourhood under opaque clouds. Only the
	# existing geometry build queue advances; missions/physics remain frozen.
	for region in world.production.regions.values():
		while not region.is_streaming_idle():
			region._process(0.0)
			await get_tree().process_frame
	var curtain = world.get_node_or_null("LoadingCurtain")
	if curtain != null: curtain.queue_free()
	# Remove the temporary automatic-control override only after simulation stops.
	world.player.controlled_automatically = false
	# All deferred mesh changes and interpolation history must be ready before
	# clouds open. Render the actual landing camera too, while fully covered.
	world.reset_physics_interpolation()
	world.camera.make_current()
	for i in 3: await get_tree().process_frame
	camera.make_current()
	for i in 2: await get_tree().process_frame
	reveal = create_tween()
	reveal.tween_method(func(value: float): material.set_shader_parameter("coverage", value), 1.0, 0.0, 1.2)
	loading = false
	is_ready = true
	boot_finished.emit()
	await released

func _vehicle_restore_pending() -> bool:
	if world.driving.is_body_transition_active(): return true
	for car in world.production.vehicles:
		if is_instance_valid(car) and car.get_meta("garage_driver_pending", false): return true
	return false

func _hold_always_nodes(node: Node) -> void:
	for child in node.get_children():
		if child.process_mode in [Node.PROCESS_MODE_ALWAYS, Node.PROCESS_MODE_WHEN_PAUSED]:
			held_nodes.append({"node": child, "mode": child.process_mode})
			child.process_mode = Node.PROCESS_MODE_DISABLED
		if child is CanvasLayer and child.visible:
			hidden_layers.append(child)
			child.hide()
		_hold_always_nodes(child)

func _process(delta: float) -> void:
	if not clouds.visible: return
	# Speed up the drift continuously, without jumping to another noise phase.
	elapsed += delta * (3.0 if continuing else 1.0)
	material.set_shader_parameter("clock", elapsed)

func continue_game() -> bool:
	begin_continue()
	if loading: await boot_finished
	if failed or not is_ready: return false
	if reveal != null and reveal.is_running(): await reveal.finished
	var flight := create_tween().set_parallel(true)
	var music := menu.get_node_or_null("MenuMusic")
	if music != null: flight.tween_property(music, "volume_db", -45.0, 1.8)
	flight.tween_method(_flight, 0.0, 1.0, FLIGHT_SECONDS)
	await flight.finished
	# Exact handoff: no camera-rig state, target, heading or saved position changes.
	world.camera.make_current()
	for entry in held_nodes:
		if is_instance_valid(entry.node): entry.node.process_mode = entry.mode
	for layer in hidden_layers:
		if is_instance_valid(layer): layer.show()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.production.no_save = "--no-save" in OS.get_cmdline_user_args()
	world.remove_meta("menu_preview")
	world.remove_meta("menu_save_path")
	transferred = true
	get_tree().current_scene = world
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	released.emit()
	menu.queue_free()
	return true

func _flight(progress: float) -> void:
	var interior: bool = not world.session.state.place_id.is_empty()
	if not interior:
		# First descend vertically, then remove clouds, then turn toward gameplay.
		# At cloud clearance the footprint already fits the loaded neighbourhood.
		var drop := smoothstep(0.0, TURN_START, progress)
		var turn := smoothstep(TURN_START, 1.0, progress)
		var approach := air_transform
		var focus: Vector3 = world.camera.focus
		var air_offset := air_transform.origin - focus
		approach.origin = focus + air_offset.normalized() * lerpf(air_offset.length(), 60.0, drop)
		camera.transform = approach.interpolate_with(world.camera.global_transform, turn)
		var close_size := maxf(world.camera.size, 42.0)
		camera.size = exp(lerpf(log(air_size), log(close_size), drop))
		camera.size = lerpf(camera.size, world.camera.size, turn)
		material.set_shader_parameter("descent", smoothstep(0.12, CLOUD_CLEAR_END, progress))
	else:
		# Off-map interiors must never expose the intervening void or roof cutaway.
		if progress < 0.55:
			camera.size = lerpf(air_size, 45.0, smoothstep(0.0, 0.55, progress))
			material.set_shader_parameter("coverage", smoothstep(0.10, 0.50, progress))
		else:
			camera.transform = world.camera.global_transform
			camera.size = world.camera.size
			material.set_shader_parameter("descent", clampf((progress - 0.55) / 0.45, 0, 1))

func discard_preview() -> void:
	if loading: await boot_finished
	if reveal != null: reveal.kill()
	if is_instance_valid(world):
		world.queue_free()
		released.emit()
		world = null
	get_tree().paused = false
	is_ready = false
	held_nodes.clear()
	hidden_layers.clear()
	clouds.visible = continuing
	material.set_shader_parameter("coverage", 1.0)
	material.set_shader_parameter("descent", 0.0)
	menu.presentation.background.visible = not continuing
	await get_tree().process_frame

func _exit_tree() -> void:
	if not transferred and is_instance_valid(world):
		world.queue_free()
		get_tree().paused = false

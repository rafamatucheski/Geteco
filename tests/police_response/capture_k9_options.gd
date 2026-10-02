extends SceneTree
## Production meshes in a neutral review stage; --main also records the real city.
const DOG = preload("res://gameplay/police_response/air_k9/PoliceK9.gd")
const LABELS := ["01  PRETO E CARAMELO", "02  MEL", "03  PRETO E GRAFITE", "04  AREIA E CREME"]
const SIZES := ["Porte médio", "Porte menor", "Porte maior", "Porte intermediário"]
var folder := "res://evidence/k9-options-20261002"
var scene: Node3D
var camera: Camera3D
var dogs: Array[Node3D] = []

func _initialize() -> void: run.call_deferred()

func photo(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 1000)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(folder)
	if "--main" in OS.get_cmdline_user_args():
		await main_capture()
		return
	# The neutral review image carries its own captions, outside gameplay UI.
	var watermark := root.get_node_or_null("BuildWatermark")
	if watermark is CanvasLayer: watermark.visible = false
	var settings := root.get_node_or_null("V2Settings")
	if settings != null and is_instance_valid(settings.get("_fps_layer")): settings._fps_layer.visible = false
	scene = Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202b35")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5e4f0")
	environment.environment.ambient_light_energy = 0.65
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_color = Color("fff0d9")
	light.light_energy = 1.3
	light.shadow_enabled = true
	scene.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("65717a")
	mat.roughness = 1.0
	ground.material_override = mat
	scene.add_child(ground)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.25
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(camera)
	camera.make_current()
	for index in 4:
		var dog := DOG.new()
		dog.appearance_variant = index
		dog.position.x = index * 4.0
		scene.add_child(dog)
		dog.set_physics_process(false)
		dogs.append(dog)
	for index in 4:
		for other in 4: dogs[other].visible = other == index
		var focus := dogs[index].global_position + Vector3(0, 0.57, 0)
		camera.position = focus + Vector3(3.2, 1.35, -4.1)
		camera.look_at(focus)
		await photo("option-%d" % (index + 1))
		# Side view keeps scale/camera identical across all four options.
		camera.position = focus + Vector3(4, 0.8, 0.4)
		camera.look_at(focus)
		await photo("profile-%d" % (index + 1))
	# One comparison image uses identical camera scale and a common floor.
	root.size = Vector2i(1800, 700)
	root.content_scale_size = root.size
	for index in 4:
		dogs[index].visible = true
		dogs[index].position = Vector3((3 - index) * 2.25, 0, 0)
		dogs[index].rotation.y = -0.6
	camera.size = 3.5
	camera.position = Vector3(3.375, 2.0, -7)
	camera.look_at(Vector3(3.375, 0.50, 0))
	var captions := CanvasLayer.new()
	root.add_child(captions)
	for index in 4:
		var title := Label.new()
		title.text = LABELS[index] + "\n" + SIZES[index]
		title.position = Vector2(index * 450, 570)
		title.size = Vector2(450, 85)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 24)
		captions.add_child(title)
	await photo("four-options")
	print("K9_OPTIONS stage complete")
	scene.queue_free()
	await process_frame
	quit(0)

func main_capture() -> void:
	scene = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival", true)
	root.add_child(scene)
	for index in 2400:
		await process_frame
		if scene.session != null and scene.session.ready_for_play: break
	if scene.session == null or not scene.session.ready_for_play: quit(4); return
	scene.player.controlled_automatically = true
	scene.player.automatic_direction = Vector3.ZERO
	for index in 120: await physics_frame
	var director: Node3D = scene.gameplay.police_air
	var zone: Dictionary = director.find_landing_zone(scene.player.global_position)
	if zone.is_empty(): push_error("No clear review street"); quit(5); return
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	scene.add_child(camera)
	camera.make_current()
	var dog := DOG.new()
	dog.director = director
	dog.position = zone.center
	scene.add_child(dog)
	dog.set_physics_process(false)
	var focus := dog.global_position + Vector3.UP * 0.55
	camera.position = focus + Vector3(3, 1.8, -3)
	camera.look_at(focus)
	await photo("city-standing")
	dog._attack_time = 0.0
	dog._tick_attack(0.24, scene.player)
	await photo("city-windup")
	dog._tick_attack(0.11, scene.player)
	await photo("city-snap")
	dog.receive_damage(100)
	dog.set_physics_process(false)
	for index in 9:
		dog._animate_death(0.1)
		await photo("city-fall-%02d" % index)
	scene.queue_free()
	await process_frame
	print("K9_OPTIONS city complete")
	quit(0)

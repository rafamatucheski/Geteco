extends SceneTree
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func hide_hud(node: Node) -> void:
	if node is CanvasLayer: node.hide()
	for child in node.get_children(): hide_hud(child)
func photo(label: String) -> void:
	hide_hud(current_scene)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/artifacts/forklift-" + label + ".png")
func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	root.size = Vector2i(1600,720)
	root.content_scale_size = root.size
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	await frames(15)
	var port = scene.get_node("SouthPort")
	var player = scene.get_node("Player")
	var camera := Camera2D.new()
	scene.add_child(camera)
	camera.position = Vector2(4680,3300)
	camera.zoom = Vector2.ONE * .85
	camera.make_current()
	player.global_position = Vector2(4410,3490)
	player.set_physics_process(false)
	await frames(20)
	await photo("01-quay")
	var forklift = port.forklifts[0]
	forklift.rotation = 0
	player.global_position = forklift.global_position + Vector2(0,42)
	forklift.enter_vehicle(player)
	await frames(160)
	assert(forklift.is_driven_by_player and forklift.get_node("ForkliftLift").can_operate())
	camera.position = forklift.global_position + Vector2(28,-12)
	camera.zoom = Vector2.ONE * 6
	camera.make_current()
	var crate = port.get_node("ForkliftCrate0_0")
	crate.global_position = forklift.global_position + Vector2(35,0)
	await frames(4)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await frames(120)
	click.pressed = false
	Input.parse_input_event(click)
	assert(forklift.get_node("ForkliftLift").cargo == crate)
	await photo("02-crate")
	Input.action_press("aim")
	await frames(150)
	Input.action_release("aim")
	crate.global_position += Vector2(140,0)
	var car = FACTORY.spawn_parked_vehicle(port,"CaptureCar",forklift.position + Vector2(33,0),PI*.5,"sedan_classic",0,Color("638da4"))
	await frames(5)
	Input.action_press("fire")
	await frames(135)
	Input.action_release("fire")
	assert(forklift.get_node("ForkliftLift").cargo == car)
	await photo("03-car")
	print("HARBOR_FORKLIFT_MOUSE PASS; forklifts=",port.forklifts.size())
	quit(0)

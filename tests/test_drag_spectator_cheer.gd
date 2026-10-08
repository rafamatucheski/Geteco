extends SceneTree
const SPECTATOR := preload("res://runtime/desert/drag_meet/DragStripSpectator.gd")
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("CHEER timeout"); quit(3))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	print("CHEER ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var at := Vector3(-843, .03, -1331)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, .2, 30)
	shape.shape = box
	floor_body.position = at - Vector3.UP * .13
	floor_body.add_child(shape)
	scene.add_child(floor_body)
	var camera := Camera3D.new()
	camera.position = at + Vector3(0, 3, 5)
	scene.add_child(camera)
	camera.look_at(at + Vector3.UP)
	camera.make_current()
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(640,640)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40,-30,0)
		scene.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("323c47")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = .6
		scene.add_child(environment)
	var actor := SPECTATOR.new()
	actor.position = at
	actor.identity = 11000
	actor.specification = {"coat":Color("754534"),"walk_end":at,"focus":at+Vector3(0,0,5),"team":"strip","roamer":false}
	scene.add_child(actor)
	for frame in 35: await physics_frame
	check(actor.person.activity == "cheer", "idle roadside spectator cheers")
	var hand: Vector3 = actor.person.forearms[1].to_global(Vector3(0,-.25,0))
	check(hand.y > actor.person.upper_arms[1].global_position.y + .12, "cheering hand rises visibly above shoulder")
	for frame in 20: await physics_frame
	check(hand.distance_to(actor.person.forearms[1].to_global(Vector3(0,-.25,0))) > .015, "raised arm waves over time")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://evidence/drag-spectator-cheer.png")
	actor.alert(at + Vector3(0,0,5))
	check(actor.person.activity.is_empty() and actor._panic > 0.0, "threat immediately cancels cheering")
	for frame in 6: await physics_frame
	check(actor.person._cheer_weight == 0.0 and actor.person.activity.is_empty(), "panic retains retreat pose instead of cheering")
	check(actor._refuge.z < actor._home.z, "retreat stays on protected shoulder")
	actor._panic = 0.0
	for frame in 80: await physics_frame
	check(actor.person.activity == "cheer", "spectator resumes cheering after returning safely")
	camera.position += Vector3(0,0,100)
	actor._update_budget()
	check(not actor.person.is_processing() and not actor.is_physics_processing(), "distant spectator remains within animation budget")
	actor.receive_damage(1000.0)
	check(actor.dead, "ordinary lethal damage remains effective")
	scene.free()
	print("CHEER_DONE failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

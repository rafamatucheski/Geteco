extends SceneTree

const DOG = preload("res://gameplay/police_response/air_k9/PoliceK9.gd")
var world: Node3D
var folder := "res://evidence/k9-20261002"

func _initialize() -> void: run.call_deferred()

func shot(label: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(folder)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for index in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	if world.session == null or not world.session.ready_for_play: quit(4); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	for index in 120: await physics_frame
	var dog := DOG.new()
	dog.director = world.gameplay.police_air
	var zone: Dictionary = dog.director.find_landing_zone(world.player.global_position)
	if zone.is_empty(): push_error("No clear street for K9 capture"); quit(5); return
	dog.position = zone.center
	world.add_child(dog)
	dog.set_physics_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position = dog.global_position + Vector3(3, 2.8, -3)
	camera.look_at(dog.global_position + Vector3.UP * 0.6)
	camera.make_current()
	await shot("k9-standing")
	dog._attack_time = 0.0
	dog._tick_attack(0.24, world.player)
	await shot("k9-windup")
	dog._tick_attack(0.11, world.player)
	await shot("k9-snap")
	dog.receive_damage(100)
	dog.set_physics_process(false)
	for index in 9:
		dog._animate_death(0.1)
		await shot("k9-fall-%02d" % index)
	print("K9_CAPTURE complete")
	world.queue_free()
	await process_frame
	quit(0)

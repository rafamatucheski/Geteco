extends SceneTree
var world: Node3D
var failures: Array[String] = []
const OUT := "res://evidence/developer-mode-20261010"

func _initialize() -> void: call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error("DEV_TEST " + label)
		if is_instance_valid(world) and world.session != null:
			print("DEV_FAILURE_STATE ",JSON.stringify({"position":str(world.player.global_position),"velocity":str(world.player.velocity),
				"health":world.gameplay.health,"modal":world.session.modal,"place":world.session.state.place_id,
				"transition":world.session.transition_kind,"locked":world.player.input_locked,"reason":world.pause_panel.developer_panel.tools.message}))
	else: print("DEV_PASS ",label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	Input.parse_input_event(event)
	event = InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = false
	Input.parse_input_event(event)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(240,true).timeout.connect(func(): push_error("DEV_TEST_TIMEOUT"); quit(3))
	world = load("res://Main.tscn").instantiate()
	root.add_child(world)
	while world.session == null or not world.session.ready_for_play: await physics_frame
	await create_timer(3).timeout
	var panel = world.pause_panel.developer_panel
	var tools = panel.tools
	var player = world.player
	var origin: Vector3 = player.global_position
	var before := {"layer":player.collision_layer,"mask":player.collision_mask,"physics":player.is_physics_processing(),
		"locked":player.input_locked,"god":world.gameplay.god_mode,"no_save":world.production.no_save}
	check(not tools.active and not tools.is_physics_processing(),"disabled by default without physics loop")
	key(KEY_F10)
	await process_frame
	check(panel.visible and paused,"F10 opens paused panel")
	panel.enabled_toggle.set_pressed(true)
	check(tools.active and world.production.no_save,"activation suspends saves")
	check(world.session.save_block_reason().contains("desenvolvedor"),"save API rejects developer session")
	check(not world.session.save_game(),"save rejected without writing")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+"/panel.png")
	tools.set_speed(5)
	check(player.get_meta("developer_speed_multiplier",1.0)==5.0,"speed setting applied")
	tools.set_invincible(true)
	check(world.gameplay.god_mode,"invulnerability enabled")
	tools.set_invincible(false)
	panel.close_panel(true)
	check(not paused and not panel.visible,"return to gameplay restores pause")
	Input.action_press("move_right")
	for i in 3: await physics_frame
	check(Vector2(player.velocity.x,player.velocity.z).length()>15,"actual movement uses speed multiplier")
	Input.action_release("move_right")
	tools.set_speed(1)
	check(await tools.teleport_to(origin),"teleport validates and returns to origin")
	check(not await tools.teleport_to(Vector3.INF),"invalid coordinates rejected")
	var before_invalid: Vector3 = player.global_position
	check(not await tools.teleport_to(Vector3(origin.x,-1000,origin.z)),"destination without ground rejected")
	check(player.global_position.distance_to(before_invalid)<.1,"failed teleport preserves player position")
	check(not await tools.travel_to("desert"),"locked campaign region remains locked")
	# The production spawn is beside Maciota's automatic entrance. Walking right
	# there enters the garage; exercise the test wall away from that real trigger.
	check(await tools.teleport_to(origin+Vector3(0,0,12)),"collision fixture placed away from garage entrance")
	panel.open_panel()
	check(tools.begin_flight(),"flight enabled")
	check(player.collision_layer==0 and player.collision_mask==0 and not player.is_physics_processing(),"flight owns collision and physics")
	check(not tools.set_active(false) or not tools.flying,"mode can safely land when disabled on ground")
	if not tools.active: tools.set_active(true)
	if not tools.flying: tools.begin_flight()
	panel.close_panel(true)
	var flight_origin: Vector3 = player.global_position
	var direction: Vector3 = world.camera.global_basis.x
	direction.y = 0; direction = direction.normalized()
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2,8,2)
	collision.shape = box
	obstacle.add_child(collision)
	world.add_child(obstacle)
	obstacle.global_position = flight_origin + direction*3 + Vector3.UP*2
	Input.action_press("move_right")
	for i in 30: await physics_frame
	Input.action_release("move_right")
	check((player.global_position-flight_origin).dot(direction)>8,"flight crosses solid without collision")
	check(await tools.return_to_anchor(),"emergency return lands at safe origin")
	check(player.collision_layer==before.layer and player.collision_mask==before.mask,"collision restored exactly")
	check(player.input_locked==before.locked and player.is_physics_processing()==before.physics,"player controls restored")
	Input.action_press("move_right")
	for i in 60: await physics_frame
	Input.action_release("move_right")
	var normal_distance: float = (player.global_position-flight_origin).dot(direction)
	print("DEV_COLLISION_DISTANCE ",normal_distance," origin=",flight_origin," direction=",direction)
	check(normal_distance>.1 and normal_distance<2.8,"restored walking physically collides with same solid")
	if not failures.is_empty():
		quit(1)
		return
	obstacle.queue_free()
	await physics_frame
	check(await tools.teleport_to(flight_origin),"return after collision check")
	var civilian: Node = tools.spawn_civilian()
	check(is_instance_valid(civilian),"civilian created on available ground")
	if is_instance_valid(civilian):
		await physics_frame
		check(civilian.get_meta("developer_spawned",false),"only test civilian is tracked")
		check(not world.people.has(civilian),"campaign/ambient population not replaced")
		tools.remove_last_civilian()
		await process_frame
		check(not is_instance_valid(civilian),"removal frees test civilian")
	check(await tools.travel_to("mountain"),"regional teleport reaches mountain through production streaming")
	check(await tools.travel_to("harbor"),"regional return reaches Harbor")
	check(await tools.teleport_to(origin),"local teleport after regional return")
	var temporary: Node = tools.spawn_civilian()
	tools.set_speed(10)
	tools.set_invincible(true)
	check(tools.set_active(false),"mode disabled")
	await process_frame
	check(not is_instance_valid(temporary),"disable cleans test civilians")
	check(not player.has_meta("developer_speed_multiplier") and world.gameplay.god_mode==before.god,"speed and god state restored")
	check(world.production.no_save==before.no_save and not world.has_meta("developer_mode_active"),"save policy restored")
	key(KEY_F10)
	await process_frame
	key(KEY_ESCAPE)
	await process_frame
	check(not panel.visible and world.pause_panel.visible and paused,"Escape returns to pause menu")
	world.pause_panel.resume_game()
	world.gameplay.god_mode = true
	tools.set_active(true)
	tools.set_invincible(false)
	check(world.gameplay.god_mode,"preexisting god mode remains enabled")
	tools.set_active(false)
	check(world.gameplay.god_mode,"preexisting god mode restored on disable")
	world.gameplay.god_mode = before.god
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"engine":Engine.get_version_info().string,"rendered":DisplayServer.get_name()!="headless"},"\t"))
	file.close()
	print("DEV_RESULT ",JSON.stringify(failures))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

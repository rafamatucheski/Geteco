extends SceneTree
var camera: Camera2D
var mountain: Node2D
var output := "D:/geteco/artifacts/mountain-rebuild-0913/"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	root.get_node("SaveManager")._save_dir = output+"saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	seed(912)
	mountain = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(mountain)
	current_scene = mountain
	while not mountain.region_ready: await process_frame
	var player = mountain.player_instance
	player.set_physics_process(false)
	camera = Camera2D.new()
	camera.set_meta("mountain_fixed_framing",true)
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mountain.add_child(camera)
	player.global_position = Vector2(7130,-2635)
	await capture("resort",Vector2(7110,-2710),2.1)
	var room = mountain.interior_manager.ski_lodge_interior
	var lodge = mountain.get_node("MountainSettlement").find_child("SummitSkiLodge",true,false)
	player.global_position = lodge.entrance.global_position+Vector2(0,20)
	mountain.interior_manager._on_entrance_requested(lodge.entrance,player,&"ski_lodge",null,&"",lodge.entrance)
	await capture("lodge-people",room.global_position,1.35)
	for npc in room.find_children("*","CharacterBody2D",true,false):
		if npc.has_meta("interior_actor_presentation"):
			var helper = npc.get_meta("interior_actor_presentation")
			print("CABIN_ACTOR ",npc.name," authored_height=",helper.standing_rig_height," world_height=",helper.standing_rig_height*helper.anchor.scale.y)
	player.money = 1000
	player.begin_ski_rental(250)
	player.take_ski_equipment()
	mountain.interior_manager._on_exit_requested(room.slope_exit,player,&"",null,&"",&"ski_lodge")
	player.global_position = Vector2(7000,-3150)
	player.velocity = Vector2(0,-180)
	player.ski_controller._apply_pose(.75,.3)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	await capture("dante-ski",player.global_position,4.0)
	var npc = get_first_node_in_group("mountain_skier")
	player.global_position = npc.global_position+Vector2(80,80)
	await capture("skiers",npc.global_position,3.2)
	player.stop_skiing()
	var station = mountain.get_node("MountainSkiArea/BaseLiftStation")
	player.global_position = station.global_position+Vector2(0,40)
	player.is_control_disabled = false
	player.is_recovering = false
	station._return_to_summit(player)
	await create_timer(.6).timeout
	await capture("dante-chairlift",player.global_position,3.5)
	await create_timer(6.2).timeout
	# Leave the station's shared depth buffer before checking the normal view.
	player.global_position += Vector2(200,0)
	await create_timer(.3).timeout
	print("LIFT_RECOVERY staging_physics=",player.is_physics_processing()," locked=",player.is_control_disabled," model_view_restored=",player.model_root.get_viewport()==player.viewport_3d)
	mountain.queue_free()
	await process_frame
	quit()

func capture(label: String, point: Vector2, zoom: float) -> void:
	camera.position = point
	camera.zoom = Vector2.ONE*zoom
	camera.make_current()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")

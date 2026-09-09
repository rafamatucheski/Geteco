extends SceneTree
var failures: Array[String] = []
class StreamedRegion extends Node2D:
	var streamed_region := true
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label)
func _run() -> void:
	root.size = Vector2i(1280,720)
	var world := StreamedRegion.new()
	root.add_child(world)
	current_scene = world
	var manager := preload("res://district/mountain_pass/MountainInteriorManager.gd").new()
	world.add_child(manager)
	check(not manager.region_ready,"streaming does not construct all rooms in one frame")
	var frames := 0
	while not manager.region_ready and frames<20:
		await process_frame
		frames += 1
	check(manager.region_ready and frames>=2,"staged interiors signal readiness after room construction")
	var room: Node2D = manager._interiors.get(&"lumberjack_shelter")
	check(room!=null and room!=manager.cabin_interior,"loggers use a distinct interior")
	check(room._active_weapon_stations.is_empty(),"logger shelter does not duplicate rifle/knife loot")
	check(room.cabin_3d_world.find_children("WorkerBunk*","Node3D",true,false).size()==4,"shelter has four worker bunk beds")
	check(room.cabin_3d_world.find_child("LoggingWorkbench",true,false)!=null,"shelter has its logging workbench")
	check(room.viewport_3d.render_target_update_mode==SubViewport.UPDATE_DISABLED,"empty shelter is not rendered")
	check(room.spawn_point!=null and room.exit_door!=null,"shelter keeps real entry and return")
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var entrance: BuildingEntrance = preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	world.add_child(entrance)
	var return_point := Vector2(125,225)
	manager.register_exterior_entrance(entrance,&"lumberjack_shelter",return_point)
	manager._on_entrance_requested(entrance,player,&"lumberjack_shelter",null,&"",entrance)
	check(player.get_meta("mountain_interior_id")==&"lumberjack_shelter","logger entrance routes to its own room id")
	check(player.global_position.distance_to(room.spawn_point.global_position)<0.1,"logger entry uses its actual spawn")
	manager._on_exit_requested(room.exit_door,player,&"",null,&"",&"lumberjack_shelter")
	check(player.global_position.distance_to(return_point)<0.1 and not player.has_meta("mountain_interior"),"logger exit returns to the selected exterior door")
	if DisplayServer.get_name()!="headless":
		player.global_position = room.to_global(room.project_floor(Vector2(0,2.5)))
		room.set_npc_rendering_active(true)
		var helper := preload("res://district/mountain_pass/MountainInteriorActorScale.gd").new()
		world.add_child(helper)
		helper.configure(player,room.camera_3d,room.sprite_3d)
		var review := Camera2D.new()
		review.position = room.global_position+Vector2(0,-50)
		review.zoom = Vector2.ONE*1.45
		world.add_child(review)
		review.make_current()
		for frame in 30: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/lumberjack-shelter-interior-review.png")
		helper.restore()
	print("LUMBERJACK / STAGED INTERIORS FAILURES: ",failures," staged_frames=",frames)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

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
	var manager := preload("res://world/mountain_pass/MountainInteriorManager.gd").new()
	world.add_child(manager)
	check(not manager.region_ready,"streaming does not construct all rooms in one frame")
	var frames := 0
	while not manager.region_ready and frames<20:
		await process_frame
		frames += 1
	check(manager.region_ready and frames>=2,"staged interiors signal readiness after room construction")
	var room: Node2D = manager._interiors.get(&"lumberjack_shelter")
	check(room!=null and room!=manager.cabin_interior,"loggers use a distinct interior")
	check(room.inline_mode and room._active_weapon_stations.size() == 1,"logger shelter keeps only its own axe")
	check(room.cabin_3d_world.find_children("WorkerBunk*","Node3D",true,false).size()==2 and room.cabin_3d_world.find_children("Mattress*","Node3D",true,false).size()==4,"compact shelter has four worker beds")
	check(room.cabin_3d_world.find_child("WorkBench",true,false)!=null,"shelter has its logging workbench")
	check(room.viewport_3d.render_target_update_mode==SubViewport.UPDATE_DISABLED,"empty shelter is not rendered")
	check(room.spawn_point != null and room.exit_door == null,"shelter has physical floor and no off-map exit")
	for id in [&"lumberjack_shelter_1", &"lumberjack_shelter_2"]:
		var other: Node2D = manager.get_interior(id)
		check(other != room and other.inline_mode,"separate room instance for distant facade " + String(id))
		check(other.get_node("WoodAxeStation").pickup_id == room.get_node("WoodAxeStation").pickup_id,"all facades share one logical axe reward")
	print("LUMBERJACK / STAGED INTERIORS FAILURES: ",failures," staged_frames=",frames)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

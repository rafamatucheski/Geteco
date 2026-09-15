extends SceneTree
var failures := 0
class Interiors extends Node2D:
	var _door_configs := {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func run() -> void:
	Engine.max_fps = 0
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var manager := Interiors.new()
	manager.name = "Interiors"
	world.add_child(manager)
	var room := preload("res://world/mountain_pass/MountainCabinInterior.gd").new()
	room.position = Vector2(22000,20000)
	manager.add_child(room)
	var door := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	door.name = "ExteriorDoor"
	door.position = Vector2(300,100)
	world.add_child(door)
	manager._door_configs["ExteriorDoor"] = {"interior":room,"spawn":room.spawn_point}
	var victim := preload("res://characters/AnimatedPedestrian3D.gd").new()
	room.add_child(victim)
	victim.position = room.project_floor(Vector2(.8,2.0))
	await physics_frame
	victim._die()
	var medical := root.get_node("NPCMedicalCare")
	medical.witness_called(victim)
	var care := root.get_node("CoronerCare")
	var key: String = care.identity(victim)
	var address: Node2D = preload("res://emergency/CoronerInteriorAccess.gd").target_for(victim)
	check(address!=null and address.global_position.distance_to(door.global_position)<50,"Service address is the exterior door, not the remote interior")
	var director := EmergencyDepotDirector.new()
	world.add_child(director)
	var depot := EmergencyDepotMarker.new()
	depot.service_key = "coroner"
	depot.position = Vector2(100,100)
	director.add_child(depot)
	director.register_depot(depot)
	var shared_depth := false
	var returned_depth := false
	var crew_seen: Array = []
	var killed := false
	var recovered_depth := false
	for frame in 3600:
		await physics_frame
		if OS.get_cmdline_user_args().has("crew_loss") and not killed and care.records()[key].phase=="carrying":
			var carrier: Node = care.active[key].carrier.get_ref()
			carrier.take_damage(100)
			killed = true
		for bag in room.find_children("*","Node2D",true,false):
			if bag.get_meta("coroner_recovery",false):
				recovered_depth = is_instance_valid(bag.room_mesh) and bag.room_mesh.get_viewport()==room.viewport_3d and bag.solid.get_child(0) is CollisionPolygon2D
		for worker in get_nodes_in_group("mortician"):
			if worker.has_meta("interior_actor_presentation"):
				shared_depth = worker.model_root.get_viewport()==room.viewport_3d and not worker.sprite_3d_display.visible
				if not crew_seen.has(worker): crew_seen.append(worker)
		for worker in crew_seen:
			if is_instance_valid(worker) and not worker.has_meta("interior_actor_presentation") and worker.global_position.distance_to(door.global_position)<200:
				returned_depth = true
		if frame%600==0:
			var states := []
			if frame==600:
				var query := PhysicsRayQueryParameters2D.create(Vector2(150,100),Vector2(300,142),3)
				var obstruction := world.get_world_2d().direct_space_state.intersect_ray(query)
				print("EXTERIOR_OBSTRUCTION ",obstruction.collider.get_path() if not obstruction.is_empty() else "none")
			for worker in get_nodes_in_group("mortician"): states.append({"id":worker.get_meta("medical_identity",""),"dead":worker.is_dead,"position":worker.global_position,"state":worker.state,"unit":worker.hearse.global_position if is_instance_valid(worker.hearse) else Vector2.INF,"target":worker.target.global_position if is_instance_valid(worker.target) else Vector2.INF,"return":worker._return_route,"passing":worker._passing_point,"path":worker.movement_navigation.path,"portal":worker.has_meta("coroner_portal"),"physics":worker.is_physics_processing(),"velocity":worker.velocity,"dest":worker.movement_navigation.destination,"clear":worker.movement_navigation.direct_clear,"scale":worker.collision_shape.scale})
			print("INTERIOR_FLOW ",frame," ",care.records()[key].phase," ",states)
		if care.records()[key].phase in ["transport","morgue"]: break
	check(shared_depth,"Visiting agents share the room depth buffer and suspend their exterior sprite")
	check(returned_depth,"Agents restore their original rig after physically reaching the exit")
	check(care.records()[key].phase in ["transport","morgue"],"The interior victim reaches the van through both authored doors")
	check(victim.is_dead and not victim.visible,"Indoor collection preserves the death and removes the corpse")
	if OS.get_cmdline_user_args().has("crew_loss"):
		check(killed and recovered_depth,"Indoor cargo recovery uses room depth and physics derived from its visible mesh")
	world.queue_free()
	for i in 3: await process_frame
	print("CORONER_INTERIOR failures=",failures)
	quit(0 if failures==0 else 1)

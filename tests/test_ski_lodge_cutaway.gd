extends SceneTree
var failures := 0
const OUT := "D:/geteco/artifacts/lodge-cutaway/"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func settle() -> void:
	for i in 4: await physics_frame
func fireplace_depth(actor: Node2D, helper: Node, room: Node2D) -> void:
	var fire = room.room_view.model.get_node("LivingHearth")
	fire.set_process(false)
	# Freeze actors for image comparisons; only visibility changes between frames.
	var old_process: bool = actor.is_processing()
	actor.set_process(false)
	# The adapter normally restores visibility every frame; suspend it while
	# toggling the rig for the paired image comparison (as in the shared test).
	helper.set_process(false)
	for fixture in [[Vector2(-6.5,1.9),false],[Vector2(-3.5,2.3),true]]:
		actor.global_position = room.to_global(room.room_view.project_floor(fixture[0]))
		helper._update_scale()
		await settle()
		var pixel: Vector2 = room.camera_3d.unproject_position(helper.anchor.position+Vector3.UP*.8)
		await RenderingServer.frame_post_draw
		var visible: Image = room.viewport_3d.get_texture().get_image()
		helper.anchor.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden: Image = room.viewport_3d.get_texture().get_image()
		var changed := 0
		for y in range(int(pixel.y)-8,int(pixel.y)+8):
			for x in range(int(pixel.x)-6,int(pixel.x)+6):
				if visible.get_pixel(x,y) != hidden.get_pixel(x,y): changed += 1
		print("FIREPLACE_DEPTH ",actor.name," floor=",fixture[0]," changed=",changed)
		check(changed > 30 if fixture[1] else changed == 0,"Actual fireplace occlusion / visible side control for "+actor.name)
		helper.anchor.show()
	actor.set_process(old_process)
	helper.set_process(true)
	fire.set_process(true)
func walk(actor: CharacterBody2D, room: Node2D, route: Array) -> void:
	actor.global_position = room.to_global(room.room_view.project_floor(route[0]))
	for point in route.slice(1):
		var target: Vector2 = room.to_global(room.room_view.project_floor(point))
		var hit := actor.move_and_collide(target-actor.global_position)
		if hit: print("ROUTE_HIT ",actor.name," collider=",hit.get_collider().name," position=",room.room_view.unproject_floor(actor.global_position))
		check(hit == null and actor.global_position.distance_to(target)<.1, "Clear circulation %s to %s" % [actor.name,point])
		await settle()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	create_timer(120).timeout.connect(func(): quit(2))
	root.get_node("SaveManager")._save_dir = OUT+"saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.size = Vector2i(1280,800)
	root.content_scale_size = root.size
	var scene = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.region_ready: await process_frame
	while not scene.interior_manager.region_ready: await process_frame
	await settle()
	var manager = scene.interior_manager
	var room = manager._interiors[&"ski_lodge"]
	var actor = scene.player_instance
	actor.set_physics_process(false)
	var entrance: BuildingEntrance
	for door in manager._exterior_doors:
		if manager._exterior_doors[door]["interior_id"] == &"ski_lodge":
			entrance = door
			break
	actor.global_position = entrance.global_position+Vector2(0,24)
	await settle()
	check(entrance.request_interaction(actor), "Real lodge entry")
	await create_timer(.4).timeout
	check(actor.global_position.distance_to(room.spawn_point.global_position)<1, "Entry places full body at clear spawn")
	var bounds := preload("res://systems/interiors/InteriorSolidProjection.gd").mesh_bounds(room.room_view.model)
	for id in ["RentalCounter","RentalShelf","ChangingRooms","SkiRack","BootBench","Fireplace","LoungeBench"]:
		check(bounds.has(StringName(id)), "Furniture inventory has mesh-derived solid: "+id)
	for node in room.room_view.model.find_children("*","MeshInstance3D",true,false):
		check(node.has_meta("interior_solid_id") or node.get_parent().name == "LivingHearth", "Mesh classified: "+node.name)
	var visitor = load("res://characters/AnimatedPedestrian3D.gd").new()
	scene.add_child(visitor)
	visitor.set_physics_process(false)
	var presentation := preload("res://systems/interiors/InteriorActorPresentation.gd").new()
	scene.add_child(presentation)
	visitor.global_position = room.spawn_point.global_position
	presentation.configure(visitor,room.camera_3d,room.sprite_3d)
	# Both side lanes reach the north exit, plus rental/equipment approaches.
	for walker in [actor,visitor]:
		var other: Node2D = visitor if walker == actor else actor
		other.global_position = room.to_global(room.room_view.project_floor(Vector2(-6.8,0)))
		await settle()
		await walk(walker,room,[Vector2(0,4),Vector2(-2,3),Vector2(-2,-1.45),Vector2(-4.7,-1.45)])
		await walk(walker,room,[Vector2(-2,-1.45),Vector2(-2,-4),Vector2(1.4,-4),Vector2(0,-4.65)])
		await walk(walker,room,[Vector2(0,4),Vector2(1.8,2.3),Vector2(1.8,-.8),Vector2(4.8,-.8)])
		await walk(walker,room,[Vector2(1.8,-.8),Vector2(1.8,-4),Vector2(0,-4.65)])
		await walk(walker,room,[Vector2(0,4),Vector2(0,4.8)])
		if DisplayServer.get_name() != "headless":
			var helper: Node = actor.get_meta("interior_actor_presentation") if walker == actor else presentation
			await fireplace_depth(walker,helper,room)
	presentation.restore()
	presentation.queue_free()
	visitor.queue_free()
	actor.money = 1000
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(-4.7,-1.45)))
	await settle()
	var rental = room.get_node("RentalCounter")
	check(rental._near, "Rental prompt reachable on free floor")
	rental._activate(actor,true)
	check(actor.ski_rental_active, "Real rental station equips clothing")
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(4.8,-.8)))
	await settle()
	var rack = room.get_node("EquipmentRack")
	check(rack._near, "Equipment prompt reachable on free floor")
	rack._activate(actor,true)
	check(actor.ski_equipment_ready, "Real rack provides equipment")
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(0,-4.65)))
	await settle()
	check(room.slope_exit.request_interaction(actor), "Actual slope exit accepts actor")
	await create_timer(.4).timeout
	check(not actor.has_meta("mountain_interior"), "Slope exit restores exterior")
	await create_timer(.8).timeout
	actor.global_position = entrance.global_position+Vector2(0,24)
	await settle()
	check(entrance.request_interaction(actor), "Reentry after slope exit")
	await create_timer(.4).timeout
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(0,3)))
	scene.main_camera.reset_smoothing()
	await settle()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		room.viewport_3d.get_texture().get_image().save_png(OUT+"room.png")
		root.get_texture().get_image().save_png(OUT+"gameplay.png")
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(0,4.8)))
	await settle()
	check(room.front_exit.request_interaction(actor), "Actual courtyard exit accepts actor")
	await create_timer(.4).timeout
	check(room.viewport_3d.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Vacant lodge suspends rendering")
	var fire = room.room_view.model.get_node("LivingHearth")
	var old_clock: float = fire.clock
	await create_timer(.15).timeout
	check(fire.clock == old_clock, "Vacant lodge suspends hearth animation")
	actor.global_position = room.to_global(room.room_view.project_floor(Vector2(-4.7,-2.5)))
	scene.restore_region_interior(actor,{"interior":"ski_lodge","exterior_return":[6350,600]})
	await settle()
	check(actor.global_position.distance_to(room.spawn_point.global_position)<1,"Old save inside furniture recovers to free spawn")
	actor._respawn_at_hospital()
	actor.set_physics_process(false)
	await settle()
	check(not actor.has_meta("mountain_interior") and actor.model_root.get_viewport()==actor.viewport_3d,"Respawn restores original rig")
	scene.queue_free()
	await process_frame
	print("LODGE_CUTAWAY failures=",failures)
	quit(0 if failures==0 else 1)


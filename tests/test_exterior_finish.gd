extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	root.get_node("SaveManager")._save_dir = "D:/geteco/artifacts/exterior-0913/test-saves/"
	root.get_node("SaveManager")._save_directory_ready = false
	root.get_node("SaveManager").clear_pending_save()
	for flag in ["harbor_arrival_seen","harbor_arrival_call_complete","harbor_maciota_met","harbor_delivery_complete"]:
		root.get_node("CampaignState").set_campaign_flag(StringName(flag),true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready or not world.world_build_ready: await process_frame
	for i in 5: await physics_frame
	var player: CharacterBody2D = world.get_node("Player")
	var npc: CharacterBody2D = world.get_node("CobraTerritory").residents[0]
	var trees := get_nodes_in_group("exterior_finish_solid")
	check(trees.size() >= 20,"Exterior planting is integrated into the production world")
	for actor in [player,npc]:
		var original: Vector2 = actor.global_position
		var original_mask: int = actor.collision_mask
		actor.set_physics_process(false)
		for tree in trees:
			var shape: CollisionShape2D = tree.get_node("TrunkCollision")
			check(is_equal_approx(shape.shape.radius,12.0*tree.crown_scale),"Trunk collision follows rendered tree scale")
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				actor.global_position = shape.global_position+direction*55
				var hit: KinematicCollision2D = actor.move_and_collide(-direction*110,true)
				check(hit != null and hit.get_collider()==tree,"Real actor sweep blocks at tree %s from %s" % [str(tree.get_path())+" at "+str(tree.global_position)+" hit "+(str(hit.get_collider().get_path()) if hit else "none"),direction])
		for stone in get_nodes_in_group("exterior_finish_rock"):
			check(stone.get_node("RockCollision").shape.points==stone._points,"Rock collision derives from its visible outline")
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				actor.global_position=stone.global_position+direction*50
				var hit: KinematicCollision2D=actor.move_and_collide(-direction*100,true)
				check(hit!=null and hit.get_collider()==stone,"Rock stops player and NPC from "+str(direction))
		for id in ["BridgeCourtWest","BridgeCourtEast","BridgeQuayHouse"]:
			var building: Node2D = world.get_node("NorthDistrict/"+id)
			var bounds: Rect2 = building.get_solid_rects()[0]
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
				actor.global_position = building.global_position+direction*(bounds.size*.5+Vector2(30,30))
				var hit: KinematicCollision2D = actor.move_and_collide(-direction*100,true)
				check(hit != null,"New building blocks real actor on each face: "+id)
			actor.global_position = building.global_position+Vector2(0,150)
			check(actor.move_and_collide(Vector2(0,-40),true)==null,"Building frontage remains accessible: "+id)
		# Public walks, court paths and the salvage driveway must stay traversable.
		var routes: Array = world.get_node("CobraNeighborhood").get_garden_paths()
		routes.append(PackedVector2Array([Vector2(-1250,1170),Vector2(-1250,1000),Vector2(-750,1000),Vector2(-750,900)]))
		for route in routes:
			for i in range(route.size()-1):
				actor.global_position=route[i]
				check(actor.move_and_collide(route[i+1]-route[i],true)==null,"Player/NPC circulation preserved at "+str(route[i]))
		check(actor.collision_mask==original_mask,"Validation preserves production collision masks")
		actor.global_position=original
	if DisplayServer.get_name() != "headless":
		root.size=Vector2i(1280,720)
		root.content_scale_size=root.size
		world.weather.time_of_day=.45
		world.weather.is_dynamic_time=false
		world.weather.set_weather(0)
		for layer in world.find_children("*","CanvasLayer",true,false): layer.hide()
		var camera := Camera2D.new()
		camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		world.add_child(camera)
		camera.make_current()
		camera.zoom=Vector2.ONE*2.0
		var building: Node2D=world.get_node("NorthDistrict/BridgeCourtWest")
		camera.global_position=building.global_position
		for pose in [["front",Vector2(-35,115),Vector2(40,115)],["rear",Vector2(-35,-110),Vector2(40,-110)],["side",Vector2(-158,0),Vector2(158,0)]]:
			player.global_position=building.global_position+pose[1]
			npc.global_position=building.global_position+pose[2]
			player.show()
			npc.show()
			camera.force_update_scroll()
			for i in 10: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/exterior-0913/depth-"+pose[0]+".png")
	print("EXTERIOR_FINISH checks=%d trees=%d failures=%d" % [checks,trees.size(),failures.size()])
	quit(0 if failures.is_empty() else 1)


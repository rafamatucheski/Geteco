extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	root.size = Vector2i(1280,720)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_arrival_seen",true)
	root.get_node("CampaignState").set_campaign_flag(&"harbor_call_complete",true)
	var world = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	while not world.gameplay_ready: await process_frame
	world.weather.is_dynamic_time = false
	world.weather.time_of_day = .5
	var player = world.get_node("Player")
	var cam := Camera2D.new()
	world.add_child(cam)
	cam.zoom = Vector2.ONE * .85
	cam.make_current()
	var tag := "before" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0]
	var checks_only := tag in ["checks", "yard"]
	for target in (["ChopShopZone"] if tag == "yard" else ["Cemetery", "ChopShopZone"]):
		var site = world.get_node(target)
		player.global_position = site.global_position + Vector2(0,-320)
		player.velocity = Vector2.ZERO
		cam.global_position = site.global_position
		for i in 90: await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/"+tag+"-"+target+".png")
		if target == "Cemetery":
			var home = site.get_node_or_null("KeeperHouse")
			print("HOME ",home," state=",home.state if home else "missing", " keeper=",home.keeper if home else "missing")
		var samples: Array[float] = []
		if checks_only and target == "Cemetery":
			while site.get_node("KeeperHouse").state != "working": await physics_frame
		var begin := Time.get_ticks_usec()
		var previous := begin
		while Time.get_ticks_usec()-begin < (100000 if checks_only else 30000000):
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous=now
		if target == "Cemetery":
			var home = site.get_node("KeeperHouse")
			print("KEEPER_AFTER ",home.state," pos=",home.keeper.global_position," processing=",home.keeper.can_process()," route=",home.keeper.route)
		if target == "Cemetery":
			var home = site.get_node("KeeperHouse")
			check(home.state == "working", "Resident completes the real indoor/outdoor route under population streaming")
			check(home.keeper.can_process() and home.keeper.is_visible_in_tree(), "Living keeper remains available outside")
			check(home.position == home.HOME_LOCAL and home.entrance.destination_id != &"", "Existing cottage keeps its authored location and registered entrance")
			var transform: Transform2D = player.global_transform
			for x in [-100.0, 100.0]:
				transform.origin = home.global_position + Vector2(x,0)
				check(player.test_move(transform,Vector2(-x,0)), "Player sweep cannot cross cottage wall")
				transform.origin = home.global_position + Vector2(x,0)
				check(home.keeper.test_move(transform,Vector2(-x,0)), "Keeper sweep cannot cross cottage wall")
			transform.origin = site.to_global(Vector2(0,-420))
			check(not player.test_move(transform,Vector2(0,100)), "Cemetery gate admits the complete player body")
			transform.origin = site.to_global(Vector2(0,-145))
			var hit := KinematicCollision2D.new()
			var blocked: bool = player.test_move(transform,Vector2(-235,0),hit)
			# A visiting NPC may cross the aisle. This check isolates static solids;
			# the live route above still ran with normal actor collisions.
			if blocked and hit.get_collider() is CharacterBody2D:
				var visitor := hit.get_collider() as CharacterBody2D
				player.add_collision_exception_with(visitor)
				blocked = player.test_move(transform,Vector2(-235,0))
				player.remove_collision_exception_with(visitor)
			check(not blocked, "Service aisle remains open to cottage")
			transform.origin = home._outside_approach()
			check(not player.test_move(transform,Vector2(0,16)), "Cottage return position and approach remain clear")
			for group in ["cemetery_tree", "memorial_verge_tree"]:
				for plant in get_nodes_in_group(group):
					var road_clear := true
					for road in preload("res://world/harbor/HarborRoadLayout.gd").STREET_DEFINITIONS:
						var closest := Geometry2D.get_closest_point_to_segment(plant.global_position,road.start,road.end)
						road_clear = road_clear and closest.distance_to(plant.global_position) > float(road.width)*.5+45
					check(road_clear, "3D tree remains clear of roads and sidewalks")
					transform.origin = plant.global_position + Vector2(-55,3*plant.tree_scale)
					check(player.test_move(transform,Vector2(110,0)), "3D tree blocks swept player movement")
			player.global_position = home._outside_approach()
			player.velocity = Vector2.ZERO
			for i in 3: await physics_frame
			check(home.entrance.request_interaction(player), "Cottage entrance accepts the real player")
			await create_timer(1.0).timeout
			check(home.room.contains_point(player.global_position), "Registered door enters the existing cottage interior")
			player.global_position = home.room.exit_door.global_position + Vector2(0,-18)
			for i in 3: await physics_frame
			print("EXIT_STATE pos=",player.global_position," door=",home.room.exit_door.global_position," enabled=",home.room.exit_door.enabled," nearby=",home.room.exit_door.is_actor_in_range(player))
			check(home.room.exit_door.request_interaction(player), "Existing cottage exit accepts the real player")
			await create_timer(.7).timeout
			check(player.global_position.distance_to(home._outside_approach()) < 2, "Cottage exit returns to the clear exterior approach")
			cam.make_current()
			cam.global_position = site.global_position
			for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/"+tag+"-Cemetery.png")
		if target == "ChopShopZone":
			var access: PackedVector2Array = site.access_road().points
			for plant in site.get_children():
				if not plant.is_in_group("exterior_finish_solid"): continue
				var clear := true
				for j in range(access.size()-1):
					clear = clear and Geometry2D.get_closest_point_to_segment(plant.global_position,access[j],access[j+1]).distance_to(plant.global_position) > 100
				check(clear, "Neco tree leaves the tow truck access clear")
				var transform: Transform2D = player.global_transform
				transform.origin = plant.global_position + Vector2(-55,3*plant.tree_scale)
				check(player.test_move(transform,Vector2(110,0)), "Neco 3D tree blocks the player")
		samples.sort()
		if not checks_only: print("PERF ",tag," ",target," GPU=",RenderingServer.get_video_adapter_name()," frames=",samples.size()," fps=",samples.size()*1000000.0/(previous-begin)," p50=",samples[int(samples.size()*.5)]," p95=",samples[int(samples.size()*.95)]," p99=",samples[int(samples.size()*.99)]," max=",samples.back())
	print("RESTORATION_FAILURES=",failures)
	quit(0 if failures == 0 else 1)

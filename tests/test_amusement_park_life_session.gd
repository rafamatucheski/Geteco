extends SceneTree
## Main/.NET: walking residents, physical purchases, circulation, depth and residency.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var world
var park
var folder := ""
var checks := 0
var failures: Array[String] = []
var depth := {}
var patrol_evidence: Array = []
var save_evidence := {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PARK_LIFE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func frames(amount := 6) -> void:
	for frame in amount: await physics_frame

func walk(local: Vector3) -> bool:
	return await walk_global(LAYOUT.ORIGIN+local)

func walk_global(point: Vector3) -> bool:
	for frame in 1100:
		var offset: Vector3 = point-world.player.global_position
		offset.y = 0
		if offset.length()<.24: break
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var distance: Vector3 = point-world.player.global_position
	distance.y = 0
	if distance.length()>=.38: print("PARK_WALK_BLOCK ",point," at=",world.player.global_position)
	return distance.length()<.38

func capture(id: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func click_button(prefix: String) -> bool:
	await frames()
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix):
			var point: Vector2 = child.get_global_rect().get_center()
			var motion := InputEventMouseMotion.new()
			motion.position = point
			root.push_input(motion,true)
			for pressed in [true,false]:
				var event := InputEventMouseButton.new()
				event.position = point
				event.global_position = point
				event.button_index = MOUSE_BUTTON_LEFT
				event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
				event.pressed = pressed
				root.push_input(event,true)
				await frames(2)
			return true
	return false

func depth_probe(local: Vector3, id: String, back_offset: float, front_offset: float) -> void:
	var at: Vector3 = LAYOUT.ORIGIN+local
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.7
	camera.global_position = at+Vector3(0,2.7,8)
	camera.look_at(at+Vector3.UP*1.05)
	camera.make_current()
	paused = true
	# Body visibility is measured separately from its cast shadow on the ground.
	var shadow_modes := {}
	for mesh: GeometryInstance3D in world.player.visual.find_children("*","GeometryInstance3D",true,false):
		shadow_modes[mesh] = mesh.cast_shadow
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var counts := {}
	for side: String in ["front","behind"]:
		world.player.teleport(at+Vector3(0,.08,front_offset if side == "front" else back_offset))
		world.player.visual.show()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		await capture(id+"_"+side)
		var shown: Image = root.get_texture().get_image()
		world.player.visual.hide()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var hidden: Image = root.get_texture().get_image()
		counts[side] = {
			"lower":body_difference(shown,hidden,camera,.30,.55),
			"upper":body_difference(shown,hidden,camera,1.02,1.62),
			"whole":body_difference(shown,hidden,camera,.02,1.90)}
	for mesh: GeometryInstance3D in shadow_modes: mesh.cast_shadow = shadow_modes[mesh]
	world.player.visual.show()
	paused = false
	world.camera.make_current()
	world.camera.initialized = false
	camera.queue_free()
	depth[id] = counts
	# The .30–.55 m band projects into this tabletop; chest/head remain above it.
	# The stall is opaque over the complete standing body instead.
	var correct: bool = counts.front.whole>1000 and counts.behind.whole<counts.front.whole*.20 if id=="stall" else counts.front.lower>200 and counts.behind.lower<counts.front.lower*.20 and counts.behind.upper>500
	check(correct,"native depth hides geometrically covered body at "+id+" with visible front and upper control "+str(counts))

func body_difference(shown: Image, hidden: Image, camera: Camera3D, low: float, high: float) -> int:
	var scale := Vector2(shown.get_width(),shown.get_height())/root.get_visible_rect().size
	var point: Vector3 = world.player.global_position
	var left: Vector2 = camera.unproject_position(point-camera.global_basis.x*.34+Vector3.UP*high)*scale
	var right: Vector2 = camera.unproject_position(point+camera.global_basis.x*.34+Vector3.UP*low)*scale
	var count := 0
	for y in range(maxi(0,int(left.y)),mini(shown.get_height(),ceili(right.y))):
		for x in range(maxi(0,int(left.x)),mini(shown.get_width(),ceili(right.x))):
			var a := shown.get_pixel(x,y)
			var b := hidden.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.12: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	create_timer(280).timeout.connect(func(): push_error("Park life session timeout"); finish(3))
	folder = FIXTURE.output_dir("amusement-park-life-session")
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.08,112.8),false)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"production scene retains C# router")
	var entry := LAYOUT.ENTRY+Vector3(4,.02,0)
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	world.player.teleport(entry)
	world.camera.initialized = false
	park = world.session.amusement_park
	await create_timer(2.5).timeout
	check(park.life.actors.size()==4,"four distinct clowns admitted after physical park")
	if "--commerce-depth-only" in OS.get_cmdline_user_args() or "--commerce-save-only" in OS.get_cmdline_user_args():
		world.player.teleport(LAYOUT.ORIGIN+Vector3(29,.08,20))
		world.camera.initialized = false
		await purchase_flow()
		if "--commerce-depth-only" in OS.get_cmdline_user_args():
			await depth_probe(Vector3(11,0,6),"table",-1.6,1.6)
			await reentry_flow(entry)
		finish()
		return
	var starts := []
	for actor in park.life.actors: starts.append(actor.global_position)
	check(await walk(Vector3(40,.08,16)),"walk from city approach through gate")
	await capture("gameplay_gate")
	check(await walk(Vector3(-7,.16,15)),"Dante walks around mobile residents to coaster boarding")
	check(park.nearest_action().get("target","")=="ride","boarding interaction remains reachable")
	for index in park.life.actors.size():
		var actor = park.life.actors[index]
		patrol_evidence.append({"index":index,"start":str(starts[index]),"after":str(actor.global_position),"travelled":actor.travelled})
		check(actor.travelled>4.0 and actor.global_position.distance_to(starts[index])>.3,"clown %d walks through native physics during visit"%index)
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.far = 300
	overview.global_position = LAYOUT.ORIGIN+Vector3(48,42,59)
	overview.look_at(LAYOUT.ORIGIN+Vector3(0,1,0))
	overview.make_current()
	await frames(10)
	await capture("overview")
	for index in park.life.actors.size():
		var actor = park.life.actors[index]
		overview.global_position = actor.global_position+actor.model.global_basis.z*3.2+Vector3.UP*1.55
		overview.look_at(actor.global_position+Vector3.UP*1.15)
		await frames(4)
		await capture("clown_%d"%index)
	world.camera.make_current()
	overview.queue_free()
	check(await walk(Vector3(20,.08,15)) and await walk(Vector3(20,.08,-2.2)),"house promenade remains clear")
	check(await world.session.interact(),"real Umbra entrance interaction accepted")
	while world.session.is_transition_blocked(): await physics_frame
	await frames(20)
	var inactive: bool = park.life.actors.size()==4
	for actor in park.life.actors: inactive = inactive and not actor.visible and actor.process_mode==Node.PROCESS_MODE_DISABLED
	check(world.session.state.place_id==LAYOUT.HAUNTED_ID and inactive,"house entry hides and disables exterior clown branches")
	check(await walk_global(world.session.room.exit_position) and await world.session.interact(),"house exit returns through real session")
	await frames(20)
	var resumed := true
	for actor in park.life.actors: resumed = resumed and actor.visible and actor.process_mode==Node.PROCESS_MODE_PAUSABLE
	check(resumed,"exterior clowns resume after house return")
	check(await walk(Vector3(20,.08,9)) and await walk(Vector3(29,.08,9)) and await walk(Vector3(29,.08,20)),"wardrobe retains a clear public approach")
	check(park.nearest_action().get("target","")=="wardrobe","wardrobe action remains available")
	await purchase_flow()
	# Real threat adapter must regain patrol; no custom immunity or teleport routine.
	var clown = park.life.actors[0]
	var reaction: Node = clown.get_node("WorkplaceThreatReaction")
	reaction._notice(clown.global_position+Vector3.RIGHT*2,3.0)
	check(reaction.active,"clown uses shared collision-checked threat reaction")
	await create_timer(7.0).timeout
	check(not reaction.active and clown.is_physics_processing(),"quiet period restores clown patrol")
	var injured = park.life.actors[3]
	injured.receive_damage(15.0)
	injured.recover_from_injury()
	check(not injured.dead and injured.health==100,"shared injury recovery preserves living clown")
	injured.receive_damage(1000.0)
	check(injured.dead and not injured.is_physics_processing() and injured.collision_layer==0,"shared death presentation stops patrol and releases body collision")
	await depth_probe(Vector3(11,0,6),"table",-1.6,1.6)
	await depth_probe(Vector3(3,0,3),"stall",-2.1,2.1)
	await reentry_flow(entry)
	finish()

func purchase_flow() -> void:
	# The wardrobe opens west; first return north along its open face, then east.
	check(await walk(Vector3(29,.08,15)) and await walk(Vector3(34,.08,15)) and await walk(Vector3(34,.08,7.4)),"walk around wardrobe side to visible drink machine")
	world.session.state.economy.grant_reward("park_life_fixture",1000)
	var cash: int = world.session.state.economy.balance
	check(await world.session.interact() and world.session.modal,"mapped interaction opens vending interface")
	await capture("vending_before")
	check(await click_button("Água"),"actual mouse press/release reaches purchase button")
	await frames(20)
	check(world.session.state.economy.inventory.get("water",0)==1 and world.session.state.economy.balance==cash-6 and park.vending.remaining("drinks","water")==23,"UI purchase charges correct price and decrements stock with item")
	await capture("vending_after")
	# This fixture begins in cobra_finale. A purchase must queue a checkpoint,
	# preserving the mission save guard until that artificial mission is cancelled.
	check(world.session.state.campaign.active_id=="cobra_finale" and world.session.save_block_reason().contains("missão") and world.session._checkpoint_retry!=null and not world.session._checkpoint_retry.is_stopped(),"mission purchase retains save guard and schedules checkpoint retry")
	check(world.session.state.campaign.cancel("park_save_fixture"),"fixture cancels active mission to release ordinary save guard")
	await create_timer(1.4).timeout
	var saved: Dictionary = STORE.read_valid(world.session.controller.store.path)
	save_evidence = {"path":world.session.controller.store.path,"block_reason":world.session.save_block_reason(),"error":world.session.last_save_error,"retry_stopped":world.session._checkpoint_retry.is_stopped()}
	check(not saved.is_empty() and saved.economy.inventory.get("water",0)==1 and world.session._checkpoint_retry.is_stopped(),"queued production purchase writes isolated save after mission ends")
	var restored = preload("res://runtime/GameState.gd").new()
	var reloaded_shop = preload("res://activities/amusement_park/AmusementParkVending.gd").new()
	reloaded_shop.configure({"state":restored})
	check(restored.restore_snapshot(saved) and restored.economy.balance==cash-6 and restored.economy.inventory.get("water",0)==1 and reloaded_shop.remaining("drinks","water")==23,"real save restore recovers wallet item and machine stock receipt")
	save_evidence["restored_balance"] = restored.economy.balance
	save_evidence["restored_water"] = restored.economy.inventory.get("water",0)
	save_evidence["restored_stock"] = reloaded_shop.remaining("drinks","water")
	check(await click_button("Fechar") and not world.player.input_locked,"machine close restores walking")
	await capture("gameplay_machine")

func reentry_flow(entry: Vector3) -> void:
	# Streaming boundary relocation is a lifecycle fixture, not evidence of walking that distance.
	var away := Vector3(166,.08,112.8)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	await frames(24)
	check(not is_instance_valid(park.site) and get_nodes_in_group("park_clown").is_empty(),"streaming unload removes geometry and all clown branches")
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	world.player.teleport(entry)
	await create_timer(2).timeout
	check(park.life.actors.size()==4 and get_nodes_in_group("park_clown").size()==4,"return admits exactly four residents without duplicates")
	check(park.vending.remaining("drinks","water")==23 and world.session.state.economy.inventory.get("water",0)==1,"unload and reentry retain bought inventory and machine stock")

func finish(code := -1) -> void:
	var report := {"checks":checks,"failures":failures,"depth":depth,"patrol":patrol_evidence,"save":save_evidence,"capture_not_benchmark":true}
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("PARK_LIFE_RESULT ",folder," ",JSON.stringify(report))
	quit(code if code>=0 else (0 if failures.is_empty() else 1))

extends SceneTree
## Real player/NPC circulation at the sofa corner shown in the user recording.
var world
var checks := 0
var failures: Array[String] = []
const OUT := "res://evidence/residence-circulation-20261009"
var label := "after"
var homes: Array[String] = ["quayside_house","westgate_garden","canal_north"]

func _initialize() -> void: run.call_deferred()
func check(ok: bool, description: String) -> void:
	checks += 1
	print("HOME_CIRCULATION ", "PASS " if ok else "FAIL ", description)
	if not ok: failures.append(description)
func frames(count := 4) -> void:
	for i in count: await physics_frame
func photo(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+label+"-"+name+".png")
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
		if arg.begins_with("--homes="): homes.assign(arg.trim_prefix("--homes=").split(","))
	DirAccess.make_dir_recursive_absolute(OUT)
	create_timer(240).timeout.connect(func(): quit(3))
	seed(10092026)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	while world.session == null or not world.session.ready_for_play: await process_frame
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.session.weather.time_of_day = .38
	world.session.weather.weather_timer = 99999
	world.session.weather.weather_state = 0
	world.session.weather._update()
	if not "--measure" in OS.get_cmdline_user_args() and not "--layout-only" in OS.get_cmdline_user_args(): await purchase_flow()
	for id in homes:
		world.session.activities.residence.data.active_home = id
		var entered: bool = await world.session.enter_place(id,false)
		check(entered,id+" enter")
		if not entered or not is_instance_valid(world.session.room): break
		await create_timer(3).timeout
		await photo(id)
		if "--verify-and-measure" in OS.get_cmdline_user_args() and id=="quayside_house": await sample(id)
		if "--measure" in OS.get_cmdline_user_args():
			await sample(id)
			await world.session.leave_place()
			break
		var room = world.session.room
		var sofa: Rect2 = room.model.solid_rects.Sofa
		var table: Rect2 = room.model.solid_rects.CoffeeTable
		check(table.position.y-sofa.end.y >= .9,id+" sofa aisle has human clearance")
		var npc = preload("res://scripts/Actor.gd").new()
		npc.controlled_automatically = true
		world.add_child(npc)
		for actor in [world.player,npc]:
			for rect: Rect2 in [sofa,table]:
				for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
					var extent := (rect.size.x if direction.x!=0 else rect.size.y)*.5+.5
					var approach := rect.get_center()+direction*extent
					var local := Vector3(approach.x,.04,approach.y)
					if not room.is_floor_clear(local,.32): continue
					var motion := Vector3(-direction.x,0,-direction.y)*extent*2
					check(actor.test_move(Transform3D(Basis.IDENTITY,room.to_global(local)),motion),id+" furniture blocks swept body "+str(actor==world.player)+str(direction))
			var lane := (sofa.end.y+table.position.y)*.5
			var start: Vector3 = room.to_global(Vector3(sofa.end.x+.6,.04,lane))
			var end: Vector3 = room.to_global(Vector3(sofa.position.x-.6,.04,lane))
			check(not actor.test_move(Transform3D(Basis.IDENTITY,start),end-start),id+" swept aisle "+str(actor==world.player))
			actor.teleport(start)
			await frames()
			await photo(id+"-aisle-"+str(actor==world.player))
			actor.automatic_direction = Vector3.LEFT
			await create_timer(2).timeout
			actor.automatic_direction = Vector3.ZERO
			check(actor.position.x < start.x-1.0,id+" real movement leaves sofa corner "+str(actor==world.player))
			check(absf(room.to_local(actor.position).y) < .15,id+" actor stays on floor beside furniture")
			await photo(id+"-crossed-"+str(actor==world.player))
			for view in ["behind-sofa","front-table"]:
				var point := Vector3(sofa.get_center().x,.04,sofa.position.y-.4) if view=="behind-sofa" else Vector3(table.get_center().x,.04,table.end.y+.35)
				check(room.is_floor_clear(point,.32),id+" depth viewpoint has physical clearance "+view)
				actor.teleport(room.to_global(point))
				await frames(6)
				await photo(id+"-"+view+"-"+str(actor==world.player))
			actor.teleport(room.spawn_position)
			npc.teleport(room.to_global(Vector3(0,.04,2)))
		npc.queue_free()
		world.session.service_roofs._update_ground_access()
		var roofs = world.session.service_roofs
		check(is_instance_valid(roofs.access_visual),id+" roof access exists")
		if is_instance_valid(roofs.access_visual):
			var ladder: Vector3 = room.to_local(roofs.access_visual.to_global(Vector3(0,0,.74)))
			check(ladder.z < -4.6,id+" ladder against back wall")
			for curtain in room.model.find_children("Curtain*","MeshInstance3D",true,false):
				var curtain_bounds: AABB = (room.global_transform.affine_inverse()*curtain.global_transform)*curtain.get_aabb()
				var ladder_bounds := AABB(ladder+Vector3(-.5,0,-.17),Vector3(1,2.6,.34))
				check(not ladder_bounds.intersects(curtain_bounds),id+" ladder leaves curtain clear")
			check(world.session.position_clear(roofs.access_point),id+" ladder approach fits player")
			world.player.teleport(roofs.access_point)
			await frames()
			check(await roofs.use_stairs(),id+" roof ascent")
			if roofs.is_active():
				world.player.teleport(roofs.roof.to_global(roofs.roof.stair_point()+Vector3.UP*.04))
				await frames()
				check(await roofs.use_stairs(),id+" return from roof")
				check(not world.player.input_locked and world.session.position_clear(world.player.position),id+" return restores control on clear floor")
		check(await walk(room.spawn_position),id+" clear route from ladder to doorway")
		world.player.automatic_direction = Vector3.BACK
		var exit_deadline := Time.get_ticks_msec()+6000
		while world.session.state.place_id == id and Time.get_ticks_msec()<exit_deadline: await physics_frame
		world.player.automatic_direction = Vector3.ZERO
		check(world.session.state.place_id.is_empty(),id+" walking exits after furniture movement")
		var settle_deadline := Time.get_ticks_msec()+5000
		while (world.session.is_transition_blocked() or world.player.input_locked or world.session.weapon_shop_entrance._leaving) and Time.get_ticks_msec()<settle_deadline: await physics_frame
		check(not world.player.input_locked and not world.session.weapon_shop_entrance._leaving,id+" exterior camera return completes and releases controls")
	print("HOME_CIRCULATION_RESULT checks=",checks," failures=",failures.size()," ",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func purchase_flow() -> void:
	var session = world.session
	var home = session.activities.residence
	session.state.economy.grant_reward("circulation_purchase",100000)
	# Settle the existing cash achievements before checking the purchase debit.
	session.activities.refresh_achievements()
	world.production.region.set_focus(home.entry("quayside_house"))
	world.player.teleport(home.entry("quayside_house")+Vector3(0,.04,.8))
	await create_timer(3).timeout
	check(session.activities.perform("home_buy:quayside_house"),"purchase prompt opens")
	await frames(15)
	check(session.panel.size.x <= 380 and session.panel.size.y <= 260,"purchase card is compact")
	check(session.column.get_child(session.column.get_child_count()-1).get_global_rect().end.y <= session.column.get_parent().get_global_rect().end.y,"cancel button fully visible without scrolling")
	await photo("purchase")
	var balance: int = session.state.economy.balance
	var confirm: Button
	for child in session.column.get_children():
		if child is Button: confirm=child; break
	var clicked_at := Time.get_ticks_msec()
	if is_instance_valid(confirm): confirm.pressed.emit()
	check(home.can_enter("quayside_house") and not session.modal,"confirmation buys and closes")
	check(session.state.economy.balance == balance-25000,"purchase charges price once")
	var host: Node = current_scene if current_scene != null else root
	var pool: Node = host.get_node_or_null("RewardAudioVoices")
	check(is_instance_valid(pool) and int(pool.get_meta("last_achievement",-1))>=clicked_at,"purchase plays achievement cue")
	var stamp: int = pool.get_meta("last_achievement",-1) if is_instance_valid(pool) else -1
	await frames(8)
	check(not home.buy("quayside_house") and session.state.economy.balance == balance-25000,"repeat purchase rejected")
	check(is_instance_valid(pool) and pool.get_meta("last_achievement",-2)==stamp,"rejected purchase does not replay cue")
	var minimum: Vector2 = session.column.get_parent().custom_minimum_size
	session.activities._open_home_purchase("westgate_garden")
	await frames(12)
	check(session.panel.size.x <= 380 and session.panel.size.y <= 260,"trade-in card stays compact")
	check(session.column.get_child(session.column.get_child_count()-1).get_global_rect().end.y <= session.column.get_parent().get_global_rect().end.y,"trade-in cancel button fully visible")
	await photo("purchase-trade")
	session._menu("Teste de restauração")
	check(session.column.get_parent().custom_minimum_size==minimum,"replacement menu restores scroll constraints")
	session.close_menu()

func walk(destination: Vector3) -> bool:
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		var delta: Vector3 = destination-world.player.position
		delta.y = 0
		if delta.length()<.25:
			world.player.automatic_direction = Vector3.ZERO
			return true
		world.player.automatic_direction = delta.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	return false

func sample(id: String) -> void:
	var rows: Array[float] = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec()-started < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append((now-previous)/1000.0)
		previous = now
	var sorted := rows.duplicate()
	sorted.sort()
	var result := {"scenario":id,"samples_ms":rows,"frames":rows.size(),"seconds":(previous-started)/1000000.0,"fps":rows.size()*1000000.0/(previous-started),"p50":sorted[int(sorted.size()*.5)],"p95":sorted[int(sorted.size()*.95)],"p99":sorted[int(sorted.size()*.99)],"max":sorted.back(),"over_33":rows.filter(func(v): return v>33.3).size(),"over_66":rows.filter(func(v): return v>66.7).size(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"resolution":str(root.size)}
	FileAccess.open(OUT+"/"+label+".json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("HOME_MEASURE ",label," p95=",result.p95," p99=",result.p99)

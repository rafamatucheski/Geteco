extends SceneTree
## Checkpoint isolado no Main; só posicionamentos/pré-requisitos iniciais são fixtures.
const F:=preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const S:=preload("res://runtime/secret_travel/SecretTravelState.gd")
const T:=preload("res://runtime/secret_travel/SecretTravel.gd")
var world
var folder:=""
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("FAST_TRAVEL ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func boot(path: String) -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	await create_timer(1).timeout
	check(world.production.store.path==path and path.begins_with(folder) and not world.production.save_invalid,"disk writes restricted to isolated fixture")
	if world.production.store.path!=path or not path.begins_with(folder) or world.production.save_invalid: quit(2); return
	world.production.no_save=false
func relay(): return world.session.desert.extras.travel
func stage(id: String) -> void:
	var point:=T.arrival(id)
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	await physics_frame
	world.player.teleport(point+Vector3.UP*.08)
	await create_timer(1).timeout
func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func button(prefix: String) -> Button:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix): return child
	return null
func open_menu() -> bool:
	var action: Dictionary=world.session.desert.nearest_action()
	check(action.get("target")=="secret_fast_travel","relay integrated in ordinary action selection")
	var opened: bool=await world.session.interact()
	check(opened and world.session.modal,"ordinary interaction opens destination menu")
	return opened and world.session.modal
func choose(id: String) -> void:
	if not await open_menu(): return
	var target: Button=button(T.SITES[id].title)
	check(target!=null and not target.disabled,"discovered destination enabled "+id)
	if target==null or target.disabled: world.session.close_menu(); return
	await photo("menu-"+world.session.state.region_id+"-to-"+id)
	target.pressed.emit()
	await process_frame
	while relay().transferring or world.production.travel_busy: await process_frame
	await create_timer(1).timeout
	check(world.session.state.region_id==id,"menu transfer committed "+id)
	check(world.player.global_position.distance_to(T.arrival(id))<.5,"arrives at concealed terminal "+id)
	check(world.session.position_clear(world.player.global_position),"arrival clear and supported "+id)
	check(not world.player.input_locked and not paused and not world.session.modal,"controls restored "+id)
	await photo("arrival-"+id)
func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("FAST_TRAVEL timeout"); quit(3))
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1280,720)
	var state:={}
	check(S.valid(S.data(state)),"old saves default to no discoveries")
	check(S.discover(state,"desert") and not S.discover(state,"desert"),"discovery idempotent")
	check(S.valid(JSON.parse_string(JSON.stringify(state[S.KEY]))),"JSON round trip")
	check(not S.valid({"version":1,"discovered":["desert","desert"]}),"duplicate rejected")
	check(not S.valid({"version":1,"discovered":["map3"]}),"unimplemented map rejected")
	folder=F.output_dir("secret-fast-travel")
	var snapshot:=F.full_snapshot(T.arrival("desert")+Vector3.UP*.08,true)
	snapshot.region_id="desert"
	snapshot.campaign.aftermath={"call_complete":true}
	var p:=T.arrival("desert")+Vector3.UP*.08
	snapshot.world.pedestrian={"region":"desert","position":[p.x,p.y,p.z]}
	var path:=F.write_fixture(folder,"save.json",snapshot)
	check(not path.is_empty(),"isolated old checkpoint valid")
	if path.is_empty(): quit(1); return
	await boot(path)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"compiled C# routing active")
	await stage("desert")
	check(not relay().nearest_action().is_empty(),"concealed desert access physically reachable")
	check(relay().perform(),"discover without power")
	check("desert" in S.data(world.session.state.world_state).discovered,"discovery persisted in state")
	check(not world.session.modal and not relay().block_reason().is_empty(),"power prerequisite respected")
	# Fixture grants existing network's progression through its public methods.
	var network=world.session.urban_operations.secret_network
	for id in network.KEYPAD_CLUE_IDS: network.discover_keypad_clue(id)
	network.discover_house()
	network.unlock_keypad()
	network.discover_headquarters()
	network.activate_power_node("power_main")
	network.activate_power_node("power_drainage")
	network.activate_route("route_village_house")
	check(relay().block_reason().is_empty(),"existing network power unlocks travel")
	world.gameplay.stars=1
	check(not relay().block_reason().is_empty(),"wanted blocks travel")
	world.gameplay.stars=0
	if await open_menu():
		check(button(T.SITES.mountain.title).disabled,"undiscovered mountain disabled")
		check(not button(T.SITES.harbor.title).disabled,"existing village route migrated")
		world.session.close_menu()
	check(world.player.test_move(world.player.global_transform,Vector3(0,0,-3)),"actual player capsule blocked by cabinet")
	await photo("desert-terminal")
	if "--relay-only" in OS.get_cmdline_user_args():
		check(not world.player.test_move(world.player.global_transform,Vector3(0,0,-.8)),"front alcove approach remains walkable")
		for offset in [Vector3(-2,0,-.2),Vector3(0,0,-2),Vector3(2,0,-.2)]:
			world.player.teleport(T.SITES.desert.point+offset+Vector3.UP*.08)
			await create_timer(.6).timeout
			check(world.session.position_clear(world.player.global_position),"side/rear inspection stands on clear ground")
			check(relay().nearest_action().is_empty(),"side/rear cannot interact through rock/cabinet")
			await photo("relay-depth-"+str(offset.x)+"-"+str(offset.z))
		world.session.show_map()
		var map=world.hud.get_node("MapUI")
		var names: Array=[]
		for marker in map._markers: names.append(marker.title)
		for title in ["Leito seco","Água para Santa Lua","Limpeza da cava"]: check(title in names,"activity visible on ordinary map "+title)
		check(not "Rede de passagens" in names and not T.SITES.desert.title in names,"map preserves concealed access")
		map.center=map._bounds.get_center()
		map.target_center=map.center
		map.zoom=1.0
		map.target_zoom=1.0
		map.select_marker(names.find("Leito seco"))
		await process_frame
		await photo("desert-activities-map")
		world.session.close_menu()
		print("FAST_TRAVEL_LOCAL_RESULT checks=",checks," failures=",failures," evidence=",folder)
		quit(0 if failures==0 else 1)
		return
	await choose("harbor")
	if world.session.state.region_id!="harbor": quit(1); return
	# Explora o terceiro local usando a viagem de autoridade existente como fixture.
	check(world.production.travel("mountain",T.arrival("mountain")),"mountain exploration fixture admitted")
	while world.production.travel_busy: await process_frame
	await create_timer(1).timeout
	check(world.session.state.region_id=="mountain","mountain terminal destination physically supported")
	if world.session.state.region_id!="mountain": quit(1); return
	if await open_menu(): world.session.close_menu()
	check("mountain" in S.data(world.session.state.world_state).discovered,"mountain discovered through real interaction")
	# Um destino ocupado precisa deixar intactos a cena de origem, os controles e o save.
	var blocker:=StaticBody3D.new()
	var shape:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(3,3,3)
	shape.shape=box
	blocker.add_child(shape)
	blocker.position=T.arrival("desert")+Vector3.UP
	world.add_child(blocker)
	await physics_frame
	if await open_menu():
		button(T.SITES.desert.title).pressed.emit()
		await process_frame
		while relay().transferring or world.production.travel_busy: await process_frame
		check(world.session.state.region_id=="mountain","occupied destination leaves source intact")
		check(not paused and not world.player.input_locked and not world.session.modal,"failed admission restores controls")
	blocker.queue_free()
	await physics_frame
	await choose("desert")
	await choose("mountain")
	await choose("harbor")
	check(world.session.save_game(),"discovery and arrival saved to isolated disk")
	var previous: Dictionary=S.data(world.session.state.world_state)
	root.remove_child(world)
	world.queue_free()
	await process_frame
	await boot(path)
	var restored:=S.data(world.session.state.world_state)
	check(S.valid(restored) and restored.discovered==previous.discovered and int(restored.version)==int(previous.version),"discoveries survive cold reload")
	check(world.session.state.region_id=="harbor" and world.session.position_clear(world.player.global_position),"cold arrival remains supported")
	print("FAST_TRAVEL_RESULT checks=",checks," failures=",failures," evidence=",folder)
	quit(0 if failures==0 else 1)

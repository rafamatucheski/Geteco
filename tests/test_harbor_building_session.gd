extends SceneTree
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const STORE = preload("res://runtime/SaveStore.gd")
var checks:=0
var failures: Array[String]=[]
var world
var folder:=""

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("BUILDING_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func walk(point: Vector3) -> bool:
	var end:=Time.get_ticks_msec()+12000
	while world.player.global_position.distance_to(point)>.22 and Time.get_ticks_msec()<end:
		var direction: Vector3=point-world.player.global_position
		direction.y=0
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	return world.player.global_position.distance_to(point)<.3

func boot(path: String) -> void:
	world=load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	while world.session==null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	for i in 5: await physics_frame

func photo(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func stairs_to(destination: int) -> bool:
	var room=world.session.room
	var prefix: String="Subir" if destination>room.floor_index else "Descer"
	if not await world.session.interact(): return false
	if world.session.modal:
		var selected:=false
		for button in world.session.column.get_children():
			if button is Button and button.text.begins_with(prefix):
				button.pressed.emit()
				selected=true
				break
		if not selected: return false
	var deadline:=Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if room.floor_index==destination and not world.session.is_transition_blocked(): return true
	return false

func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("BUILDING_SESSION timeout"); quit(3))
	folder=FIXTURE.output_dir("harbor-building-session")
	var snapshot:=FIXTURE.full_snapshot(Vector3(173.75,.08,17),true)
	snapshot.campaign.aftermath={"call_complete":true}
	var path:=FIXTURE.write_fixture(folder,"save.json",snapshot)
	await boot(path)
	check(world.production.loaded_save and not world.production.save_invalid,"isolated checkpoint loaded")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native!=null,"C# path active")
	for definition in CATALOG.definitions():
		world.production.region.set_focus(definition.entry_position)
		var cold=world.session.cold
		if cold!=null: cold.prepare_collision_at(definition.entry_position)
		for i in 120: await physics_frame
		world.player.teleport(definition.entry_position+Vector3(0,.08,1.2))
		check(world.session.position_clear(world.player.global_position),definition.id+" exterior supported")
		check(await walk(definition.entry_position+Vector3.UP*.04),definition.id+" walk to facade")
		await photo(definition.id+"-exterior")
		var action: Dictionary=world.session.nearest()
		check(action.get("id")=="enter" and action.get("place")==definition.id,definition.id+" actual door action")
		world.session.interact()
		for i in 300:
			await physics_frame
			if world.session.state.place_id==definition.id and not world.session.is_transition_blocked(): break
		check(world.session.state.place_id==definition.id,definition.id+" entered through interaction")
		if world.session.state.place_id!=definition.id: finish(); return
		var room=world.session.room
		check(room.floor_index==0 and not world.player.input_locked,definition.id+" ground floor control")
		await photo(definition.id+"-ground")
		check(await walk(room.to_global(Vector3(0,.04,1.45))),definition.id+" walk entrance corridor")
		check(await walk(room.to_global(room.stair_point()+Vector3.UP*.04)),definition.id+" walk to stairs")
		check(world.session.nearest().get("id")=="building_stairs",definition.id+" stairs prompt")
		check(await stairs_to(1),definition.id+" ascend through interaction")
		check(room.floor_index==1 and room.get_child_count()==1 and not world.player.input_locked,definition.id+" one loaded floor and control")
		await photo(definition.id+"-upper")
		for target in [2,3]:
			check(await stairs_to(target),definition.id+" stairs choice reaches floor "+str(target))
			check(room.get_child_count()==1 and not world.player.input_locked,definition.id+" single floor and control "+str(target))
			await photo(definition.id+"-floor-"+str(target))
		var save_ok: bool=world.session.save_game()
		check(save_ok,definition.id+" upper floor save")
		if not save_ok:
			print("SAVE_DIAGNOSTIC block=",world.session.save_block_reason()," error=",world.session.last_save_error)
			FileAccess.open(folder.path_join("rejected.json"),FileAccess.WRITE).store_string(JSON.stringify(world.session.state.snapshot(),"\t"))
			finish(); return
		var saved:=STORE.read_valid(path)
		check(saved.get("world",{}).get("harbor_building_floors",{}).get(definition.id,-1)==3,definition.id+" top floor persisted")
		# Cold scene reload, not a mocked restore of the floor dictionary.
		world.free()
		await process_frame
		await boot(path)
		room=world.session.room
		check(is_instance_valid(room) and room.floor_index==3 and world.session.state.place_id==definition.id,definition.id+" cold reload restores top floor")
		if not is_instance_valid(room): finish(); return
		check(world.session.position_clear(world.player.global_position),definition.id+" restored landing clear")
		check(await walk(room.to_global(room.stair_point()+Vector3.UP*.04)),definition.id+" return to stairs")
		for target in [2,1,0]:
			check(await stairs_to(target),definition.id+" descend through interaction to "+str(target))
		check(room.floor_index==0,definition.id+" ground restored")
		check(await walk(room.to_global(Vector3(0,.04,1.45))),definition.id+" return corridor")
		check(await walk(room.exit_position+Vector3.UP*.04),definition.id+" walk to exit")
		check(await world.session.interact(),definition.id+" leave through interaction")
		check(world.session.state.place_id.is_empty() and not is_instance_valid(world.session.room) and not world.player.input_locked,definition.id+" exterior cleanup and control")
		check(world.player.global_position.distance_to(definition.return_position)<1,definition.id+" correct return facade")
	finish()

func finish() -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("BUILDING_SESSION ",folder," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

extends SceneTree
const FIXTURE = preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT = preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const COSMETICS = preload("res://activities/amusement_park/AmusementParkCosmeticState.gd")
var world
var folder := ""
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print("PARK_SESSION ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)

func walk(to: Vector3) -> bool:
	for frame in 1000:
		var offset: Vector3 = to-world.player.global_position
		offset.y = 0
		if offset.length() < .24: break
		world.player.automatic_direction = offset.normalized()
		await physics_frame
	world.player.automatic_direction = Vector3.ZERO
	var offset: Vector3 = to-world.player.global_position
	offset.y = 0
	return offset.length() < .36

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(id+".png"))

func run() -> void:
	create_timer(300).timeout.connect(func(): push_error("Park session timeout"); quit(3))
	folder = FIXTURE.output_dir("amusement-park-session")
	var snapshot := FIXTURE.full_snapshot(Vector3(166,.1,112.8),false)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("menu_save_path",FIXTURE.write_fixture(folder,"save.json",snapshot))
	root.add_child(world)
	current_scene = world
	while world.session == null or not world.session.ready_for_play or not world.production.startup_streaming_settled: await physics_frame
	world.player.controlled_automatically = true
	world.player.speed = 3.5
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	var entry := LAYOUT.ENTRY+Vector3(13,.08,0)
	world.production.region.set_focus(entry)
	world.production.region.prepare_collision_at(entry)
	world.player.teleport(entry)
	world.camera.initialized = false
	var park = world.session.amusement_park
	park._update_residency()
	await create_timer(2).timeout
	check(is_instance_valid(park.site),"park streams into productive Harbor")
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null,"C# router remains active")
	check(await walk(LAYOUT.ENTRY),"walk from city approach through park gate")
	await capture("gate")
	check(await walk(LAYOUT.BOARDING),"walk promenade to accessible boarding")
	await capture("station")
	var camera: Camera3D = world.camera
	var layer: int = world.player.collision_layer
	var mask: int = world.player.collision_mask
	check(await world.session.interact() and park.active,"mapped session interaction starts coaster")
	if not park.active: finish(); return
	check(root.get_camera_3d() == park.view and park.view.projection == Camera3D.PROJECTION_PERSPECTIVE,"ride uses actual perspective camera")
	check(world.session.blocks_driving_change() and not world.session.save_block_reason().is_empty(),"ride blocks driving and saves in midair")
	await create_timer(3).timeout
	check(park.ride_distance > 5 and world.player.global_position.distance_to(LAYOUT.BOARDING)>2,"carriage and rider travel together")
	await capture("coaster")
	var cancel := InputEventAction.new()
	cancel.action = "interact"
	cancel.pressed = true
	world.session._input(cancel)
	check(not park.active and not world.player.input_locked,"interaction cancels ride and restores control")
	check(world.player.collision_layer == layer and world.player.collision_mask == mask and world.player.is_physics_processing(),"cancellation restores physics and collision")
	check(root.get_camera_3d() == camera and world.player.visual.visible,"cancellation restores camera and visible Dante")
	check(world.session.position_clear(world.player.global_position),"return is fully supported and clear")
	check(park.start_ride(),"ride supports pause cancellation")
	var pause_event := InputEventAction.new()
	pause_event.action = "pause_game"
	pause_event.pressed = true
	check(not park.handle_input(pause_event) and not park.active and not world.player.input_locked,"pause releases attraction and passes event to pause owner")
	check(park.start_ride(),"ride can be repeated")
	for frame in 5000:
		if not park.active: break
		await physics_frame
	check(not park.active and not world.player.input_locked,"full lap automatically disembarks")
	check(await walk(LAYOUT.ORIGIN+Vector3(20,.08,15)),"walk to haunted-house promenade")
	check(await walk(LAYOUT.HAUNTED_ENTRY),"walk to Umbra entrance")
	var entrance_accepted: bool = await world.session.interact()
	while world.session.is_transition_blocked(): await physics_frame
	check(entrance_accepted and world.session.state.place_id == LAYOUT.HAUNTED_ID,"real entrance interaction admits house")
	if world.session.state.place_id != LAYOUT.HAUNTED_ID: finish(); return
	await create_timer(.35).timeout
	check(park.house_view and world.player.camera == park.view,"house uses first-person movement camera")
	await capture("house_entry")
	for point in LAYOUT.house_route():
		check(await walk(world.session.room.to_global(point)),"house route free at "+str(point))
		await create_timer(.2).timeout
		if point.z < -4: await capture("house_"+str(int(point.x)))
	var found: Array = COSMETICS.data(world.session.state.world_state).found
	check(found.has("ghost_mask") and found.has("fox_mask"),"both hidden house masks collected through exploration")
	check(await walk(world.session.room.exit_position),"return to house exit on foot")
	check(await world.session.interact() and world.session.state.place_id.is_empty(),"house exit returns to same park entrance")
	await create_timer(.35).timeout
	check(not park.house_view and root.get_camera_3d() == camera and world.player.camera == camera,"exit restores outside view and movement basis")
	check(await walk(LAYOUT.ORIGIN+Vector3(20,.08,15)),"return to central promenade")
	for point in [Vector3(0,.08,27),Vector3(-31,.08,27),Vector3(0,.08,27),Vector3(-2,.08,9),Vector3(-2,.08,-28),Vector3(-2,.08,9),Vector3(31,.08,10),Vector3(31,.08,-3),Vector3(31,.08,10),Vector3(28,.08,27)]:
		check(await walk(LAYOUT.ORIGIN+point),"exterior secret route free at "+str(point))
		await create_timer(.2).timeout
	check(COSMETICS.data(world.session.state.world_state).found.size() == 6,"all six secrets found through physical exploration")
	check(await walk(LAYOUT.ORIGIN+Vector3(29,.08,20)),"wardrobe interaction has clear approach")
	check(await world.session.interact() and world.session.modal,"park wardrobe opens from mapped action")
	for label in ["Jaqueta Lume","Óculos Estrela","Máscara Raposa"]:
		var selected := false
		for child in world.session.column.get_children():
			if child is Button and child.text.begins_with(label):
				child.pressed.emit()
				selected = true
				break
		check(selected,"wardrobe equips "+label+" through its button")
	await capture("wardrobe")
	world.session.close_menu()
	check(not world.player.input_locked,"wardrobe closes without stale input lock")
	var dressed := COSMETICS.data(world.session.state.world_state)
	check(world.session.state.economy.outfit == "dante_lume" and dressed.glasses == "star_glasses" and dressed.mask == "fox_mask","outfit glasses and mask remain equipped together")
	var portrait := Camera3D.new()
	world.add_child(portrait)
	portrait.global_position = world.player.global_position+Vector3(0,1.65,-3.0)
	portrait.look_at(world.player.global_position+Vector3.UP*1.25)
	world.player.visual.rotation.y = 0
	portrait.make_current()
	await create_timer(.3).timeout
	await capture("cosmetics")
	camera.make_current()
	portrait.queue_free()
	world.player.teleport(LAYOUT.BOARDING+Vector3.UP*.06)
	await create_timer(.3).timeout
	check(park.start_ride(),"ride admits recovery scenario")
	await create_timer(.5).timeout
	world.gameplay.damage_player(1000.0)
	check(not park.active and world.session.rescue_pending,"lethal damage cancels occupied ride immediately")
	for frame in 1200:
		if not world.session.rescue_pending and not world.session.respawn_busy: break
		await physics_frame
	check(world.gameplay.health > 0 and not world.player.input_locked and world.player.visual.visible,"real rescue returns a living controllable visible actor")
	check(root.get_camera_3d() == camera and not is_instance_valid(park.view),"rescue leaves no attraction camera")
	check(COSMETICS.data(world.session.state.world_state).found.size() == 6,"recovery preserves collected cosmetics")
	var away := Vector3(166,.12,112.8)
	world.production.region.set_focus(away)
	world.production.region.prepare_collision_at(away)
	world.player.teleport(away)
	park._update_residency()
	await process_frame
	check(not is_instance_valid(park.site),"leaving unloads park geometry and lights")
	finish()

func finish() -> void:
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("PARK_SESSION_RESULT ",folder," checks=",checks," failures=",failures)
	quit(1 if not failures.is_empty() else 0)

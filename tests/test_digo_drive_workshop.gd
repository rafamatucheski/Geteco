extends SceneTree
## Actual Main, isolated disk save and cold reload. No personal save is opened.
## This fixture covers admission/persistence, not the visual quality or frame time.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const ID := "test_digo_drive_car"
var world: Node3D
var failures: Array[String] = []
var path := ""
var old_path := ""

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DIGO_DRIVE timeout"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	print("DIGO_DRIVE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _frames(count: int) -> void:
	for frame in count: await physics_frame

func _check_room_music(label: String, active: bool) -> void:
	# The existing location update runs every .3s; allow that pulse plus its
	# .8s/1s fades without calling the helper directly from the fixture.
	await create_timer(1.4).timeout
	var music: Node = world.session.desert.workshop_music
	if not _check(is_instance_valid(music),label+" retains the real location-owned workshop music helper"): return
	var voices := world.find_children("DigoWorkshopMusicVoice","AudioStreamPlayer",true,false)
	if not _check(voices.size()==1,label+" has exactly one workshop music voice"): return
	var voice := voices[0] as AudioStreamPlayer
	var audio_owner: Node = world.production.world_audio
	if active:
		_check(voice.playing and voice.bus==&"Music" and is_equal_approx(voice.volume_db,-18.0),label+" plays the background track on Music at its completed -18dB fade")
		_check(voice.stream is AudioStreamOggVorbis and (voice.stream as AudioStreamOggVorbis).loop,label+" uses the imported compressed looping workshop composition")
		_check(audio_owner._scoped_music_owner != null and audio_owner._scoped_music_owner.get_ref()==music,label+" soundtrack owns the scoped radio override")
		_check(not audio_owner.radio.playing or audio_owner.radio.stream_paused,label+" pauses an active vehicle radio instead of overlapping songs")
	else:
		_check(not voice.playing and not music._active,label+" stops the workshop soundtrack after its exit fade")
		_check(audio_owner._scoped_music_owner==null and not audio_owner.radio.stream_paused,label+" releases scoped radio ownership after leaving")

func _capture(label: String) -> void:
	if not "--digo-capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	world.diagnostic_label.hide()
	var settings := root.get_node_or_null("V2Settings")
	if settings != null and is_instance_valid(settings.get("_fps_layer")): settings.get("_fps_layer").visible = false
	var watermark := root.get_node_or_null("BuildWatermark")
	if watermark is CanvasLayer: watermark.visible = false
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := "res://artifacts/tuning-design-20261019/hierarchical-main"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
	print("DIGO_DRIVE_CAPTURE ",label," viewport=",root.size," window=",DisplayServer.window_get_size())

func _activate_button(button: Button) -> void:
	button.grab_focus()
	await process_frame
	var event := InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventAction.new()
	event.action = "ui_accept"
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)

func _ready_world() -> bool:
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if _boot_complete(): break
	if is_instance_valid(world) and world.get("production") != null:
		print("DIGO_DRIVE startup_streaming_settled=",world.production.startup_streaming_settled," (false means residual runtime streaming; boot completion is checked separately)")
	return _check(_boot_complete(),"actual Main boot completed and curtain released") and _check(world.production.store.path == path and not world.production.no_save,"isolated real SaveStore")

func _boot_complete() -> bool:
	if not is_instance_valid(world) or world.get("session") == null or world.get("production") == null: return false
	var curtain := world.get_node_or_null("LoadingCurtain")
	return world.session.ready_for_play and world.production.ready_for_play and (curtain == null or curtain.is_queued_for_deletion())

func _wait_access() -> void:
	var deadline := Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if not world.session.desert.workshop_drive._busy: return
	_check(false,"access completes within finite deadline")

func _drive_until(action: String, place: String) -> bool:
	# Actual analogue pedal input and productive vehicle physics cross the portal.
	# No pose, speed or occupancy is injected for this part of the fixture.
	var deadline := Time.get_ticks_msec()+20000
	var starting: Vector3 = world.driving.car.global_position
	while Time.get_ticks_msec() < deadline:
		if world.session.state.place_id == place: break
		var speed: float = absf(world.driving.car.speed)
		if speed < .8: Input.action_press(action,.18)
		elif speed > 1.3: Input.action_release(action)
		await physics_frame
	Input.action_release(action)
	var crossed: bool = world.session.state.place_id == place
	_check(crossed,"analogue pedal crosses actual portal automatically")
	if not crossed: print("DIGO_DRIVE crossing diagnostic start=",starting," end=",world.driving.car.global_position," speed=",world.driving.car.speed)
	await _wait_access()
	return crossed

func _seed() -> Dictionary:
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(Vector3(-137.8,.08,-942),true)): return {}
	state.set_location("desert")
	state.checkpoint_id = "desert_digo"
	state.world_state.pedestrian = {"region":"desert","position":[-137.8,.08,-942]}
	DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true)
	state.economy.grant_reward("test_digo_drive_funds",100000)
	state.world_state.vehicles = [{"archetype":"desert_coyote","vehicle_id":ID,"was_driven":true,"paint":"ccae50ff","position":[-140,.12,-942],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec("desert_coyote").durability)*.75,"region":"desert","equipment":{}}]
	return state.snapshot()

func _run() -> void:
	if "--digo-capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280,720))
	if not _check(not "--no-save" in OS.get_cmdline_user_args(),"fixture requires isolated disk writes, no --no-save"):
		_finish(2); return
	path = FIXTURE.write_fixture(FIXTURE.output_dir("digo-drive-workshop"),"checkpoint.json",_seed())
	if not _check(not path.is_empty(),"fixture passes native save validation"): _finish(1); return
	var launch := root.get_node_or_null("V2Launch")
	if not _check(launch != null,"launch available"): _finish(1); return
	old_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	var session = world.session
	var car: CharacterBody3D = world.driving.car
	world.gameplay.god_mode = true
	if not _check(world.driving.occupied and car.vehicle_id == ID,"saved driver starts in own car"): _finish(1); return
	var helper = session.desert.workshop_drive
	var exterior_gate: Node3D
	for candidate in get_nodes_in_group("digo_vehicle_gate"):
		if world.is_ancestor_of(candidate): exterior_gate = candidate; break
	if not _check(is_instance_valid(exterior_gate) and not exterior_gate.is_open(),"exterior garage has a real closed shutter before admission"): _finish(1); return
	var gate_events: Array[Dictionary] = []
	exterior_gate.access_changed.connect(func(opened: bool): gate_events.append({"opened":opened,"transition":session.transition_kind,"car_locked":car.input_locked,"player_locked":world.player.input_locked}))
	var relationship: Dictionary = session.state.world_state.digo.duplicate(true)
	session.state.world_state.digo = DIGO.DEFAULT.duplicate(true)
	_check(not helper.perform("digo_drive_enter") and session.state.place_id.is_empty(),"workshop unlock gates drive admission")
	_check(not exterior_gate.is_open(),"locked workshop keeps physical exterior gate closed")
	session.state.world_state.digo = relationship
	world.gameplay.stars = 1
	_check(not helper.perform("digo_drive_enter") and session.state.place_id.is_empty(),"wanted driver cannot enter peaceful workshop")
	_check(not exterior_gate.is_open(),"wanted driver keeps physical exterior gate closed")
	world.gameplay.stars = 0
	await _capture("exterior-closed")
	if not await _drive_until("accelerate",DRIVE.PLACE): _finish(1); return
	if not _check(session.state.place_id == DRIVE.PLACE and world.driving.occupied,"same driver and car enter actual interior"): _finish(1); return
	_check(gate_events.size() >= 2 and gate_events[0].opened and gate_events[0].transition == "garage_vehicle" and gate_events[0].car_locked and gate_events[0].player_locked and not gate_events[-1].opened,"exterior gate opens only under owned input transition then closes")
	_check(car.vehicle_id == ID and car.get_meta("garage_place","") == DRIVE.PLACE,"entry preserves durable vehicle identity")
	_check(world.player.seated and world.player.has_meta("seated_state"),"entry keeps real driver seated instead of standing through the roof")
	_check(session.modal and session.desert.tuning_panel.visible,"entry opens live service UI")
	await _check_room_music("entry",true)
	if not _check(helper._service_walls.size() == 2 and is_instance_valid(helper._service_shutter),"service restores authored front walls and closes real rolling shutter"): _finish(1); return
	var service_wall: MeshInstance3D = helper._service_walls[0].node.get_ref()
	var shutter_barrier: StaticBody3D = helper._service_shutter.get_node("Collision")
	_check(is_equal_approx(float(service_wall.mesh.size.y),4.6),"service front wall keeps original full physical height")
	await _frames(2)
	var portal_query := PhysicsRayQueryParameters3D.create(session.room.to_global(Vector3(0,1.1,7.6)),session.room.to_global(Vector3(0,1.1,9.6)),1)
	var closed_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(portal_query)
	_check(closed_hit.get("collider") == shutter_barrier,"closed service shutter physically blocks the aperture")
	helper.focus_slot("taillights")
	_check(car.equipment._tail_lens_preview,"taillight inspection temporarily suppresses brake emission")
	helper.focus_slot("wheel_model")
	var view_size: Vector2 = root.get_visible_rect().size
	var stage := Rect2(Vector2(view_size.x*.28+10.0,view_size.y*76.0/720.0),Vector2(view_size.x*.72-22.0,view_size.y*(720.0-186.0)/720.0))
	for angle in [-.95,-.65,0.0,.65,.95]:
		helper._yaw = angle
		helper._update_camera()
		var fully_visible := true
		for side in [-1.0,1.0]:
			for end in [-1.0,1.0]:
				for height in [0.0,float(car.body_height)+.25]:
					var point: Vector3 = car.global_position+car.global_basis*Vector3(side*car.half_width,height,end*car.half_length)
					if not stage.has_point(helper._camera.unproject_position(point)): fully_visible = false
		_check(fully_visible,"orbit keeps complete car above footer and beside sidebar at "+str(angle))
	helper.camera_action("reset",0.0)
	await _capture("service-live")
	var tuning: Node = session.desert.tuning_panel
	if "--digo-capture" in OS.get_cmdline_user_args():
		await _capture("menu-visuais")
		var roof_button: Button
		for button in tuning._cards.get_children():
			if button is Button and button.get_meta("menu_key","") == "sunroof": roof_button = button; break
		if not _check(is_instance_valid(roof_button),"visual menu exposes real roof navigation button"): _finish(1); return
		await _activate_button(roof_button)
		if not _check(tuning._menu_level == 2 and tuning._slot == "sunroof","real focused button opens roof options"): _finish(1); return
		await _capture("teto-opcoes")
		await _activate_button(tuning._groups.get_node("MenuBack"))
		if not _check(tuning._menu_level == 0 and root.gui_get_focus_owner().get_meta("menu_key","") == "sunroof","real back button returns to visual menu and preserves roof focus"): _finish(1); return
		await _capture("voltar-visuais")
	var balance_before_preview: int = session.state.economy.balance
	var installed_before_preview: Dictionary = tuning._parts.duplicate(true)
	tuning._choose_part("paint","paint_graphite")
	var pending_preview: Dictionary = tuning._draft_parts.duplicate(true)
	if not _check(pending_preview != installed_before_preview,"live service holds an uncommitted paint preview"): _finish(1); return
	for cancel_step in 3:
		var cancel := InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		Input.parse_input_event(cancel)
		await process_frame
		cancel = InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = false
		Input.parse_input_event(cancel)
		await _frames(2)
		if not _check(session.modal and tuning.visible and tuning._exit_prompt.visible == (cancel_step == 1),"live cancel returns to Visuais before exit confirmation"): _finish(1); return
		if not _check(tuning._menu_level == 0,"cancel navigation remains in the parent visual menu"): _finish(1); return
		if not _check(tuning._draft_parts == pending_preview and tuning._parts == installed_before_preview and session.state.economy.balance == balance_before_preview,"cancel preserves draft, installed loadout and real wallet"): _finish(1); return
	tuning.discard_and_close()
	if not _check(not session.modal and not tuning.visible and tuning._draft_parts == installed_before_preview,"explicit discard closes live service and forgets preview"): _finish(1); return
	_check(helper._service_walls.is_empty() and helper._service_shutter == null and shutter_barrier.collision_layer == 0,"close immediately releases shutter collider and service geometry ownership")
	_check(is_equal_approx(float(service_wall.mesh.size.y),.3) and helper._camera == null and world.camera.current,"close restores original wall cutaway and gameplay camera")
	_check(not car.equipment._tail_lens_preview,"close restores actual taillight and brake presentation")
	await _frames(2)
	var portal_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(portal_query)
	_check(not is_instance_valid(shutter_barrier) and portal_hit.get("collider") == session.room.model.get_node("InteriorVehicleGate")._barrier,"service cleanup frees temporary shutter and preserves physical exit admission gate")
	_check(world.production.vehicle_position_clear(car,car.position,car.rotation.y),"full hull and floor admit actual bay")
	if not _check(helper.perform("digo_drive_service") and session.modal and tuning.visible,"driver reopens real Digo tuning service"): _finish(1); return
	var paint_button: Button
	for button in tuning._cards.get_children():
		if button is Button and button.get_meta("menu_key","") == "paint": paint_button = button; break
	if not _check(is_instance_valid(paint_button),"visual menu exposes paint navigation button"): _finish(1); return
	await _activate_button(paint_button)
	await _activate_button(tuning.button_for_part("paint_ocean"))
	var paint_cost: int = tuning._draft_cost()
	var wallet_before_install: int = session.state.economy.balance
	await _activate_button(tuning._apply)
	var result := {"parts":GARAGE.vehicle(session.state.world_state,ID,car.archetype).parts}
	if not _check(result.parts.get("paint","") == "paint_ocean" and session.state.economy.balance == wallet_before_install-paint_cost,"real UI application purchases durable paint with wallet receipt"): _finish(1); return
	var confirmation := tuning.get_node_or_null("TuningInstallConfirmation") as AudioStreamPlayer
	_check(is_instance_valid(confirmation) and confirmation.playing and confirmation.bus == preload("res://ui/MenuAudio.gd").get_sfx_bus_name() and confirmation.stream == preload("res://ui/MenuAudio.gd").get_click_stream(),"accepted real Digo application plays configured confirmation cue")
	_check(car.get_meta("desert_parts",{}) == result.parts,"accepted real UI application updates original vehicle appearance")
	tuning.discard_and_close()
	_check(not car.input_locked and world.driving.occupied,"closing panel restores driver control")
	if not _check(session.save_game(),"seated workshop save writes"): _finish(1); return
	var disk := STORE.read_valid(path)
	_check(not disk.is_empty() and disk.world.get(DRIVE.KEY,{}).get("vehicle_id","") == ID,"disk accepts workshop access metadata")
	var orphan: Dictionary = disk.duplicate(true)
	orphan.world[DRIVE.KEY].vehicle_id = "missing_workshop_car"
	_check(not STATE.new().restore_snapshot(orphan),"native save contract rejects orphan workshop identity")
	orphan = disk.duplicate(true)
	orphan.world[DRIVE.KEY].was_driven = not bool(orphan.world[DRIVE.KEY].was_driven)
	_check(not STATE.new().restore_snapshot(orphan),"native save contract rejects mismatched seated state")
	orphan = disk.duplicate(true)
	orphan.place_id = ""
	_check(not STATE.new().restore_snapshot(orphan),"native save contract rejects interior metadata at exterior location")
	_check(GARAGE.vehicle(disk.world,ID,car.archetype).parts == result.parts,"part receipts remain under original identity")
	var instance := world.get_instance_id()
	session.load_game()
	await process_frame
	_check(is_instance_valid(world) and world.get_instance_id() == instance,"in-car load command is refused by existing product rule")
	# Cold boot the same isolated slot instead of bypassing the product's in-car load gate.
	if reload_current_scene() != OK: _check(false,"cold boot request accepted"); _finish(1); return
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != instance:
			world = current_scene as Node3D
			break
	if not _check(is_instance_valid(world) and world.get_instance_id() != instance,"actual cold reload replaces scene"): _finish(1); return
	if not await _ready_world(): _finish(1); return
	session = world.session
	helper = session.desert.workshop_drive
	car = world.driving.car
	_check(world.driving.occupied and car.vehicle_id == ID and session.state.place_id == DRIVE.PLACE,"reload restores seated driver inside workshop")
	_check(car.get_meta("desert_parts",{}) == result.parts,"reload restores installed appearance")
	await _check_room_music("cold restore",true)
	var count := 0
	for candidate in world.production.vehicles:
		if is_instance_valid(candidate) and candidate.vehicle_id == ID: count += 1
	_check(count == 1,"reload has exactly one instance of owned vehicle")
	var inside_gate: Node3D = session.room.model.get_node("InteriorVehicleGate")
	_check(not inside_gate.is_open() and inside_gate._barrier.collision_layer == 1,"cold restore keeps the physical interior exit closed until admission")
	var exit_gate_events: Array[Dictionary] = []
	inside_gate.access_changed.connect(func(opened: bool): exit_gate_events.append({"opened":opened,"transition":session.transition_kind,"car_locked":car.input_locked,"player_locked":world.player.input_locked}))
	if not await _drive_until("accelerate",""): _finish(1); return
	_check(not exit_gate_events.is_empty() and exit_gate_events[0].opened and exit_gate_events[0].transition == "garage_vehicle" and exit_gate_events[0].car_locked and exit_gate_events[0].player_locked,"actual driving exit opens interior shutter only under owned input transition")
	_check(session.state.place_id.is_empty() and world.driving.occupied and car.vehicle_id == ID,"exit returns same car and driver to street")
	_check(world.player.seated and world.player.has_meta("seated_state"),"exit keeps actual driver pose seated")
	var gates_closed := true
	for candidate in get_nodes_in_group("digo_vehicle_gate"):
		if world.is_ancestor_of(candidate) and candidate.is_open(): gates_closed = false
	_check(gates_closed,"exit leaves exterior gate physically closed")
	_check(not car.input_locked and not world.camera.locked and world.camera.target == car,"exit restores controls and exterior camera")
	_check(not session.state.world_state.has(DRIVE.KEY),"exit clears interior access metadata")
	await _check_room_music("exit",false)
	await _capture("exterior-exit")
	_finish(0 if failures.is_empty() else 1)

func _finish(code: int) -> void:
	var launch := root.get_node_or_null("V2Launch")
	if launch != null: launch.selected_path = old_path
	print("DIGO_DRIVE failures=",failures)
	quit(code)

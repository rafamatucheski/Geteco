extends SceneTree
## Finite actual-Main test: real doorway, focused GUI buttons, native wallet,
## isolated disk SaveStore, cold reload, and owned-car distance despawn/restore.
## Fixture seeds three verified-result prerequisites; it does not claim to test
## those races (covered by the drag integration fixture).
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
var world: Node3D
var failures: Array[String] = []
var checks := 0
var folder := ""
var path := ""
var old_launch_path := ""
var last_button_diagnostic: Dictionary = {}
var gui_trace_active := false
var gui_trace_phase := ""
var gui_trace: Array[Dictionary] = []
const LEGACY_ID := "test_desert_workshop_legacy"
const OWNED_ID := "desert_owned_desert_faisca"
const PAINT := Color("8a3e5aff")

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("DESERT_WORKSHOP_SESSION timeout"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	checks += 1
	print("DESERT_WORKSHOP_SESSION ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _seed() -> Dictionary:
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(Vector3(-140,.08,-936),true)): return {}
	state.set_location("desert")
	state.checkpoint_id = "desert_digo"
	state.world_state.pedestrian = {"region":"desert","position":[-140,.08,-936]}
	state.world_state.vehicles = [{"archetype":"sport_coupe","vehicle_id":LEGACY_ID,"was_driven":false,"paint":"ccae50ff","position":[-133,.14,-936],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec("sport_coupe").durability)*.55,"region":"desert","equipment":{}}]
	DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true)
	for rival in ["digo","livia","raul"]:
		if RACE.record_finish(state.world_state,rival,true,22.0).is_empty(): return {}
		state.economy.grant_reward("desert_drag:"+rival,RACE.reward_amount(rival))
	state.economy.grant_reward("test_desert_workshop_seed",100000)
	return state.snapshot()

func _run() -> void:
	# --no-save would make session.save_game return true without disk persistence.
	if not _check(not "--no-save" in OS.get_cmdline_user_args(),"fixture requires real isolated disk writes, without --no-save"):
		_finish(2); return
	folder = FIXTURE.output_dir("desert-workshop-session")
	path = FIXTURE.write_fixture(folder,"checkpoint.json",_seed())
	if not _check(not path.is_empty(),"completed-campaign desert workshop fixture validates"):
		_finish(1); return
	var launch := root.get_node_or_null("V2Launch")
	if not _check(launch != null,"launch autoload available for isolated cold reload"):
		_finish(1); return
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	var session = world.session
	var legacy: CharacterBody3D = world.driving.car
	if not _check(legacy.vehicle_id==LEGACY_ID,"selected legacy car restored by the actual fleet"):
		_finish(1); return
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var parked: Vector3 = legacy.global_position
	if not _check(await session.enter_place("desert_digo",false),"real Digo interior transition accepted"):
		_finish(1); return
	await _frames(4)
	_check(legacy.global_position.distance_to(parked)<.3 and not world.driving.occupied,"car remains parked outside while Dante enters on foot")
	if not await _open_workshop(): _finish(1); return
	if not await _press_menu("Preparar "): _finish(1); return
	var before_money: int = session.state.economy.balance
	if not await _press_part("street_cam"): _finish(1); return
	_check(session.state.economy.balance==before_money-int(TUNING.PARTS.street_cam.cost),"GUI motor purchase debits the real wallet once")
	if not await _press_part("lightweight"): _finish(1); return
	var expected_parts := {"engine":"street_cam","weight":"lightweight"}
	_check(CARS.parts_for_vehicle(legacy)==expected_parts,"GUI purchases install both parts on selected vehicle")
	_check(legacy.get_meta("desert_powertrain")==legacy.handling.drive,"installed part uses actual free-driving powertrain")
	var legacy_health: float = legacy.health
	var legacy_max: float = legacy.max_health
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("tuning.png"))
	# Exercise FullSession._input, not the panel's close signal directly.
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await process_frame
	cancel = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = false
	Input.parse_input_event(cancel)
	await process_frame
	if not _check(not session.modal and not session.desert.tuning_panel.visible and not world.player.input_locked,"cancel closes tuning overlay and releases input together"):
		_finish(1); return
	if not await _open_workshop(): _finish(1); return
	before_money = session.state.economy.balance
	if not await _press_menu("Faísca GT"): _finish(1); return
	await _frames(4)
	var purchased := _find_car(OWNED_ID)
	if not _check(purchased != null,"GUI purchase delivers an owned car at the exterior bay"):
		await _diagnose_failed_delivery(before_money)
		_finish(1); return
	_check(session.state.economy.balance==before_money-int(CARS.spec("desert_faisca").price),"GUI car purchase charges its catalogue price")
	_check(not purchased.get_meta("awaiting_ground",false),"paid delivery has an admitted physical bay")
	# Native setters after _ready, then real persistence, protect model repaint.
	purchased.paint_color = PAINT
	purchased.restore_health(purchased.max_health*.57)
	var owned_health: float = purchased.health
	_check(_paint_matches(purchased),"post-ready repaint reaches actual body materials")
	var expected_balance: int = session.state.economy.balance
	if not _check(session.save_game(),"actual session writes the workshop state to isolated SaveStore"):
		_finish(1); return
	var disk := STORE.read_valid(path)
	if not _check(not disk.is_empty(),"saved JSON passes native GameState validation"):
		_finish(1); return
	_check(disk.world.desert_fleet[OWNED_ID].paint==PAINT.to_html(true),"owned car colour is persisted separately from selected legacy car")
	_check(GARAGE.vehicle(disk.world,LEGACY_ID,"sport_coupe").parts==expected_parts,"legacy tuning is persisted by identity")
	var old_instance := world.get_instance_id()
	session.load_game()
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id()!=old_instance:
			world = current_scene as Node3D
			break
	if not _check(is_instance_valid(world) and world.get_instance_id()!=old_instance,"load_game replaces actual Main scene"):
		_finish(1); return
	if not await _ready_world(): _finish(1); return
	session = world.session
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	await _frames(30)
	legacy = world.driving.car
	_check(session.state.place_id=="desert_digo","cold reload restores the real workshop interior")
	_check(legacy.vehicle_id==LEGACY_ID and CARS.parts_for_vehicle(legacy)==expected_parts,"legacy identity and tuning survive cold reload")
	_check(is_equal_approx(legacy.health,legacy_health) and is_equal_approx(legacy.max_health,legacy_max),"cold reload does not compound weight-related durability loss")
	_check(session.state.economy.balance==expected_balance,"reload never recharges purchases")
	if not _check(await session.leave_place(),"real workshop exit restores exterior"):
		_finish(1); return
	await _frames(50)
	purchased = _find_car(OWNED_ID)
	if not _check(purchased != null,"owned car restored on returning to its region"):
		_finish(1); return
	_check(_count_car(OWNED_ID)==1 and _paint_matches(purchased) and is_equal_approx(purchased.health,owned_health),"owned restore preserves one instance, repaint and damage")
	var outside: Vector3 = world.player.global_position
	var distant := Vector3(-140,.1,-705)
	world.production.region.prepare_collision_at(distant)
	await _frames(3)
	world.player.teleport(distant)
	await _frames(90)
	_check(_find_car(OWNED_ID)==null,"owned non-selected car can unload at distance")
	world.production.region.prepare_collision_at(outside)
	await _frames(3)
	world.player.teleport(outside)
	await _frames(90)
	purchased = _find_car(OWNED_ID)
	_check(purchased!=null and _count_car(OWNED_ID)==1,"return respawns exactly one owned car")
	if purchased != null: _check(_paint_matches(purchased) and is_equal_approx(purchased.health,owned_health),"streaming preserves body paint and damage")
	_finish(0 if failures.is_empty() else 1)

func _ready_world() -> bool:
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if is_instance_valid(world) and world.get("session")!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if not _check(is_instance_valid(world) and world.get("session")!=null and world.session.ready_for_play,"Main session becomes ready"):
		return false
	_check(world.production.store.path==path and world.production.loaded_save and not world.production.no_save and not world.production.save_invalid,"Main uses only the isolated disk fixture")
	world.dispatch.router.nearest_edge(world.player.global_position)
	return _check(world.dispatch.router._native!=null,"compiled C# route backend is active")

func _open_workshop() -> bool:
	var point: Vector3 = world.session.room.to_global(Vector3(8.4,.04,1.65))
	if not _check(world.session.position_clear(point),"Digo interaction point is physically clear"): return false
	world.player.teleport(point)
	await _frames(3)
	if not _check(world.session.nearest().get("target","")=="workshop","real proximity interaction selects Digo preparation"): return false
	return _check(await world.session.interact(),"real interaction opens Digo menu")

func _press_menu(prefix: String) -> bool:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix): return await _press_button(child)
	return _check(false,"menu button exists: "+prefix)

func _press_part(id: String) -> bool:
	var panel: Node = world.session.desert.tuning_panel
	for row in panel._rows.get_children():
		var label: Label = row.get_child(0).get_child(0)
		if label.text==str(TUNING.PARTS[id].label): return await _press_button(row.get_child(1))
	return _check(false,"part button exists: "+id)

func _press_button(button: Button) -> bool:
	if not _check(button.is_visible_in_tree() and not button.disabled,"GUI button usable: "+button.text): return false
	gui_trace.clear()
	gui_trace_active = true
	gui_trace_phase = "settling"
	var focus_callback := Callable(self,"_trace_gui_focus")
	if not root.gui_focus_changed.is_connected(focus_callback): root.gui_focus_changed.connect(focus_callback)
	for candidate in root.find_children("*","Button",true,false):
		var candidate_button := candidate as Button
		if candidate_button.is_visible_in_tree(): _hook_gui_trace(candidate_button)
	var callbacks: Array[String] = []
	for connection in button.pressed.get_connections(): callbacks.append(str(connection.callable))
	_trace_gui("requested",button.text+" "+str(button.get_path()),{"pressed_callbacks":callbacks})
	# FullSession defers initial focus to its first menu button. Let that existing
	# lifecycle finish before selecting the target for this real keyboard event.
	await _frames(2)
	gui_trace_phase = "selecting"
	button.grab_focus()
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button); break
		parent = parent.get_parent()
	await process_frame
	var focused := root.gui_get_focus_owner()
	last_button_diagnostic = {"requested":button.text,"requested_path":str(button.get_path()),"has_focus":button.has_focus(),"focused_path":str(focused.get_path()) if focused != null else "","focused_text":str(focused.text) if focused is Button else ""}
	print("DESERT_WORKSHOP_GUI_INPUT ",JSON.stringify(last_button_diagnostic))
	if not _check(button.has_focus(),"requested GUI button owns focus before input: "+button.text):
		gui_trace_active = false
		return false
	var accept := InputEventAction.new()
	accept.action="ui_accept"
	accept.pressed=true
	gui_trace_phase = "press"
	Input.parse_input_event(accept)
	_trace_gui("press_dispatched","")
	await process_frame
	gui_trace_phase = "release"
	accept=InputEventAction.new()
	accept.action="ui_accept"
	accept.pressed=false
	Input.parse_input_event(accept)
	_trace_gui("release_dispatched","")
	gui_trace_phase = "after_release"
	await _frames(3)
	last_button_diagnostic["trace"] = gui_trace.duplicate(true)
	gui_trace_active = false
	return true

func _hook_gui_trace(button: Button) -> void:
	if button.has_meta("desert_test_gui_trace"): return
	button.set_meta("desert_test_gui_trace",true)
	var label := button.text+" "+str(button.get_path())
	button.pressed.connect(func(): _trace_gui("pressed",label))
	button.mouse_entered.connect(func(): _trace_gui("mouse_entered",label))
	button.gui_input.connect(func(event: InputEvent):
		if event.is_action("ui_accept"): _trace_gui("gui_accept",label,{"pressed":event.is_pressed()}))

func _trace_gui_focus(control: Control) -> void:
	_trace_gui("focus_changed",str(control.get_path()) if control != null else "",{"text":str(control.text) if control is Button else ""})

func _trace_gui(kind: String, target: String, details: Dictionary = {}) -> void:
	if not gui_trace_active: return
	var focused := root.gui_get_focus_owner()
	var event := {"kind":kind,"phase":gui_trace_phase,"frame":Engine.get_process_frames(),"ticks":Time.get_ticks_msec(),"target":target,"focused":str(focused.text) if focused is Button else "","details":details}
	gui_trace.append(event)
	print("DESERT_WORKSHOP_GUI_TRACE ",JSON.stringify(event))

func _diagnose_failed_delivery(before_money: int) -> void:
	var point := Vector3(-123,.1,-940)
	var report := {"notice":world.session.notice.text,"balance_before":before_money,"balance_after":world.session.state.economy.balance,"balance_delta":world.session.state.economy.balance-before_money,"purchased":GARAGE.data(world.session.state.world_state).purchased,"button":last_button_diagnostic,"modal":world.session.modal,"tuning_visible":world.session.desert.tuning_panel.visible,"player":str(world.player.global_position),"place":world.session.state.place_id,"nearby":[],"support_rays":[],"shape_hits":[]}
	for car in world.production.vehicles:
		if not is_instance_valid(car) or car.global_position.distance_to(point)>35.0: continue
		report.nearby.append({"id":car.vehicle_id,"archetype":car.archetype,"position":str(car.global_position),"yaw":car.rotation.y,"half_width":car.half_width,"half_length":car.half_length,"layer":car.collision_layer,"mask":car.collision_mask,"queued":car.is_queued_for_deletion(),"awaiting_ground":car.get_meta("awaiting_ground",false)})
	# Inspect the real candidate hull without invoking the purchase transaction.
	var candidate := preload("res://scripts/Vehicle.gd").new()
	candidate.archetype="desert_faisca"
	candidate.vehicle_id="test_delivery_probe"
	candidate.position=point
	candidate.rotation.y=PI
	world.add_child(candidate)
	candidate.set_physics_process(false)
	candidate.collision_layer=0
	candidate.collision_mask=0
	await physics_frame
	var basis := Basis(Vector3.UP,PI)
	var space := world.get_world_3d().direct_space_state
	for x in [-candidate.half_width*.8,candidate.half_width*.8]:
		for z in [-candidate.half_length*.8,candidate.half_length*.8]:
			var support: Vector3=point+basis*Vector3(x,0,z)
			var ray:=PhysicsRayQueryParameters3D.create(support+Vector3.UP*.6,support-Vector3.UP*.5,1,[candidate.get_rid()])
			var hit:=space.intersect_ray(ray)
			report.support_rays.append({"point":str(support),"hit":not hit.is_empty(),"position":str(hit.get("position","")),"normal":str(hit.get("normal","")),"collider":str(hit.collider.get_path()) if not hit.is_empty() and hit.collider is Node else ""})
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=candidate.shape.shape
	query.transform=Transform3D(basis,point+basis*candidate.shape.position)
	query.collision_mask=7
	query.exclude=[candidate.get_rid()]
	for hit in space.intersect_shape(query,16):
		var collider: Object=hit.collider
		report.shape_hits.append({"collider":str(collider.get_path()) if collider is Node else str(collider),"ramp_exception":collider.has_meta("vehicle_ramp_structure"),"layer":collider.collision_layer if collider is CollisionObject3D else -1})
	report.actual_admission=world.production.vehicle_position_clear(candidate,point,PI)
	report.hull_size=str(candidate.shape.shape.size)
	candidate.free()
	print("DESERT_WORKSHOP_DELIVERY_DIAGNOSTIC ",JSON.stringify(report))
	var file:=FileAccess.open(folder.path_join("delivery-diagnostic.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t"))

func _find_car(id: String) -> CharacterBody3D:
	for car in world.production.vehicles:
		if is_instance_valid(car) and not car.is_queued_for_deletion() and car.vehicle_id==id: return car
	return null

func _count_car(id: String) -> int:
	var count := 0
	for car in world.production.vehicles:
		if is_instance_valid(car) and not car.is_queued_for_deletion() and car.vehicle_id==id: count+=1
	return count

func _paint_matches(car: CharacterBody3D) -> bool:
	if car._paint.materials.is_empty(): return false
	for material in car._paint.materials:
		if not material.albedo_color.is_equal_approx(PAINT): return false
	return true

func _finish(code: int) -> void:
	var launch := root.get_node_or_null("V2Launch")
	if launch != null and not old_launch_path.is_empty(): launch.selected_path=old_launch_path
	print("DESERT_WORKSHOP_SESSION checks=%d failures=%d evidence=%s"%[checks,failures.size(),folder])
	quit(code)

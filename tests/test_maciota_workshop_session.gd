extends SceneTree
## Main real em Harbor: entrada na garagem, conversa com o mecânico, compra por tecla
## real, carteira nativa, SaveStore em disco isolado e recarga a frio.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const GARAGE := preload("res://runtime/desert/DesertGarageState.gd")
const WINS := preload("res://systems/campaign/RaceWins.gd")
const RACE := preload("res://activities/desert_drag/DesertDragProgress.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const CAR_ID := "test_maciota_workshop_car"
var world: Node3D
var failures: Array[String] = []
var folder := ""
var path := ""
var old_launch_path := ""

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("MACIOTA_WORKSHOP timeout"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	print("MACIOTA_WORKSHOP ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _frames(count: int) -> void:
	for i in count: await physics_frame

func _seed() -> Dictionary:
	var state := STATE.new()
	# Campanha ainda aberta: depois de concluída, o aviso de recolher o Ironback sombreia
	# todas as interações da garagem até o jogador recolher o carro.
	if not state.restore_snapshot(FIXTURE.full_snapshot(Vector3(166,.08,111.8),false)): return {}
	DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true)
	for rival in ["digo","livia"]:
		if RACE.record_finish(state.world_state,rival,true,22.0).is_empty(): return {}
		state.economy.grant_reward("desert_drag:"+rival,RACE.reward_amount(rival))
	state.world_state.vehicles = [{"archetype":"sport_coupe","vehicle_id":CAR_ID,"was_driven":false,"paint":"ccae50ff","position":[160,.14,113.5],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec("sport_coupe").durability),"region":"harbor","equipment":{}}]
	state.economy.grant_reward("test_maciota_workshop_seed",100000)
	return state.snapshot()

func _ready_world() -> bool:
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if is_instance_valid(world) and world.get("session") != null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	return _check(is_instance_valid(world) and world.get("session") != null and world.session.ready_for_play,"Main session becomes ready") and _check(world.production.store.path == path and not world.production.no_save,"Main uses only the isolated disk fixture")

func _run() -> void:
	if not _check(not "--no-save" in OS.get_cmdline_user_args(),"fixture requires real isolated disk writes, without --no-save"):
		_finish(2); return
	folder = FIXTURE.output_dir("maciota-workshop-session")
	path = FIXTURE.write_fixture(folder,"checkpoint.json",_seed())
	if not _check(not path.is_empty(),"Harbor fixture with two race wins validates"): _finish(1); return
	var launch := root.get_node_or_null("V2Launch")
	if not _check(launch != null,"launch autoload available"): _finish(1); return
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	var session = world.session
	var car: CharacterBody3D = world.driving.car
	if not _check(car != null and car.vehicle_id == CAR_ID,"parked car restored by the actual fleet near the garage"): _finish(1); return
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var wins := WINS.count(session.state.world_state,session.state.campaign.snapshot())
	# Duas da arrancada semeadas mais a corrida dos Cobras que a fixture já traz concluída.
	_check(wins == 3,"two drag wins plus the completed Cobra race are counted (%d)" % wins)
	# Missão ativa bloqueia o salvamento (regra do jogo); encerra para testar a persistência.
	session.state.campaign.cancel("test_fixture")
	_check(session.state.campaign.active_id.is_empty(),"fixture mission is cancelled so the save is allowed")
	var parked: Vector3 = car.global_position
	if not _check(await session.enter_place("maciota",false),"real Maciota interior transition accepted"): _finish(1); return
	await _frames(4)
	_check(car.global_position.distance_to(parked) < .3 and not world.driving.occupied,"car stays parked outside while Dante enters on foot")
	_check(session.maciota_workshop.candidate_car() == car,"the parked car is the one the mechanic can prepare")
	if not await _open_mechanic(): _finish(1); return
	if not await _press_menu("Preparar "): _finish(1); return
	var panel: Node = session.maciota_workshop.panel
	_check(panel.visible and panel.mechanic_name == "Mecânico","tuning panel opens for the mechanic")
	var before: int = session.state.economy.balance
	if not await _press_part("ecu_1"): _finish(1); return
	_check(session.state.economy.balance == before-int(TUNING.PARTS.ecu_1.cost),"GUI ECU purchase debits the real wallet once")
	if not await _press_part("neon_cyan"): _finish(1); return
	for style in ["paint_ocean","finish_satin","wheels_bronze"]:
		if not await _press_part(style): _finish(1); return
	var expected := {"ecu":"ecu_1","neon":"neon_cyan","paint":"paint_ocean","finish":"finish_satin","wheels":"wheels_bronze"}
	_check(car._paint.materials[0].albedo_color == Color("285968"),"purchased paint reaches real vehicle")
	_check(is_equal_approx(car._paint.materials[0].roughness,.58),"purchased satin finish reaches real vehicle")
	var appearance: RefCounted = car.get_meta("tuning_appearance")
	_check(not appearance._rims.is_empty() and appearance._rims[0].albedo_color == Color("a58450"),"purchased bronze reaches real rims")
	_check(car.get_meta("desert_parts") == expected,"GUI purchases install both parts on the parked car")
	_check(car.get_meta("desert_powertrain") == car.handling.drive,"installed part uses the actual free-driving powertrain")
	_check(car.get_node_or_null("DesertCarNeon") != null,"neon part adds the underglow kit to the real car")
	# Peça bloqueada por vitórias não pode ser comprada, nem por tecla.
	var locked: Button = panel.button_for_part("ecu_3")
	_check(locked != null and locked.disabled,"ECU de competição fica bloqueada com poucas vitórias")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("maciota_tuning.png"))
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
	if not _check(not session.modal and not panel.visible and not world.player.input_locked,"cancel closes the overlay and releases input together"): _finish(1); return
	var balance: int = session.state.economy.balance
	if not _check(session.save_game(),"actual session writes the workshop state to the isolated SaveStore"): _finish(1); return
	var disk := STORE.read_valid(path)
	if not _check(not disk.is_empty(),"saved JSON passes native GameState validation"): _finish(1); return
	_check(GARAGE.vehicle(disk.world,CAR_ID,"sport_coupe").parts == expected,"tuning is persisted by car identity")
	_check(GARAGE.valid(disk.world.desert_garage,disk.economy),"saved garage validates against the wallet receipts")
	var old_instance := world.get_instance_id()
	session.load_game()
	var deadline := Time.get_ticks_msec()+80000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.get_instance_id() != old_instance:
			world = current_scene as Node3D
			break
	if not _check(is_instance_valid(world) and world.get_instance_id() != old_instance,"load_game replaces the actual Main scene"): _finish(1); return
	if not await _ready_world(): _finish(1); return
	session = world.session
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	await _frames(40)
	car = world.driving.car
	_check(session.state.place_id == "maciota","cold reload restores the real garage interior")
	_check(car != null and car.vehicle_id == CAR_ID,"the same car is restored after the cold reload")
	_check(car != null and car.get_meta("desert_parts",{}) == expected,"tuning survives the cold reload on the car")
	_check(car._paint.materials[0].albedo_color == Color("285968") and is_equal_approx(car._paint.materials[0].roughness,.58),"paint and finish survive cold reload")
	_check(session.state.economy.balance == balance,"reload never recharges purchases")
	if not _check(await session.leave_place(),"real garage exit restores the exterior"): _finish(1); return
	await _frames(50)
	car = world.driving.car
	_check(car != null and car.get_meta("desert_parts",{}) == expected,"tuning is still on the car in the street")
	_finish(0 if failures.is_empty() else 1)

func _open_mechanic() -> bool:
	var point: Vector3 = world.session.room.interaction_points["mechanic"]
	if not _check(world.session.position_clear(point),"mechanic interaction point is physically clear"): return false
	world.player.teleport(point)
	await _frames(3)
	var near: Dictionary = world.session.nearest()
	print("MACIOTA_WORKSHOP nearest=",JSON.stringify(near)," player=",world.player.global_position," point=",point)
	if not _check(near.get("id","") == "mechanic","real proximity selects the mechanic"): return false
	return _check(await world.session.interact(),"real interaction opens the mechanic menu")

func _press_menu(prefix: String) -> bool:
	for child in world.session.column.get_children():
		if child is Button and child.text.begins_with(prefix): return await _press_button(child)
	return _check(false,"menu button exists: "+prefix)

func _press_part(id: String) -> bool:
	var panel: Node = world.session.maciota_workshop.panel
	var button: Button = panel.button_for_part(id)
	if button == null: return _check(false,"part button exists: "+id)
	if not await _press_button(button): return false
	if panel._pending == id:
		button = panel.button_for_part(id)
		if button == null: return _check(false,"confirmation button exists: "+id)
		return await _press_button(button)
	return true

func _press_button(button: Button) -> bool:
	if not _check(button.is_visible_in_tree() and not button.disabled,"GUI button usable: "+button.text): return false
	# O FullSession adia o foco inicial para o primeiro botão do menu; deixa isso terminar.
	await _frames(2)
	button.grab_focus()
	var parent := button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button); break
		parent = parent.get_parent()
	await process_frame
	if not _check(button.has_focus(),"requested GUI button owns focus before input: "+button.text): return false
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	Input.parse_input_event(accept)
	await process_frame
	accept = InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = false
	Input.parse_input_event(accept)
	await _frames(3)
	return true

func _finish(code: int) -> void:
	var launch := root.get_node_or_null("V2Launch")
	if launch != null: launch.selected_path = old_launch_path
	print("MACIOTA_WORKSHOP_SESSION ","PASS" if code == 0 else "FAIL"," failures=",failures.size()," evidence=",folder)
	quit(code)

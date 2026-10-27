extends SceneTree
## Peças de carroceria no carro vivo: Main de verdade, save isolado, entra dirigindo na
## oficina do Digo e navega pelo painel real (menu → Carroceria → peça). Cada peça é
## mostrada pela própria prévia do painel e pela câmera de serviço que o slot escolhe.
## Não mede FPS. Uso: --path . --script <este> -- --car=desert_coyote
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STATE := preload("res://runtime/GameState.gd")
const DIGO := preload("res://systems/campaign/DigoProgress.gd")
const DRIVE := preload("res://runtime/desert/DigoWorkshopDrive.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const ID := "capture_digo_aero_car"
var world: Node3D
var failures: Array[String] = []
var old_path := ""
var car_id := "desert_coyote"
var destination := "res://evidence/digo-aero-live-20261027"
var captures: Array = []

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("DIGO_AERO timeout"); _finish(3))
	_run.call_deferred()

func _check(ok: bool, label: String) -> bool:
	print("DIGO_AERO ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
	return ok

func _frames(count: int) -> void:
	for frame in count: await physics_frame

func _capture(label: String) -> void:
	world.diagnostic_label.hide()
	var settings := root.get_node_or_null("V2Settings")
	if settings != null and is_instance_valid(settings.get("_fps_layer")): settings.get("_fps_layer").visible = false
	var watermark := root.get_node_or_null("BuildWatermark")
	if watermark is CanvasLayer: watermark.visible = false
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	var path := destination.path_join(car_id+"_"+label+".png")
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK,"capture saved "+label)
	captures.append(path)

func _activate_button(button: Button) -> void:
	button.grab_focus()
	await process_frame
	for pressed in [true,false]:
		var event := InputEventAction.new()
		event.action = "ui_accept"
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await _frames(2)

func _boot_complete() -> bool:
	if not is_instance_valid(world) or world.get("session") == null or world.get("production") == null: return false
	var curtain := world.get_node_or_null("LoadingCurtain")
	return world.session.ready_for_play and world.production.ready_for_play and (curtain == null or curtain.is_queued_for_deletion())

func _seed() -> Dictionary:
	var front: Vector3 = preload("res://world/desert/DesertLayout.gd").WORKSHOP+Vector3(0,0,13)
	var state := STATE.new()
	if not state.restore_snapshot(FIXTURE.full_snapshot(front+Vector3(2.2,.08,0),true)): return {}
	state.set_location("desert")
	state.checkpoint_id = "desert_digo"
	state.world_state.pedestrian = {"region":"desert","position":[front.x+2.2,.08,front.z]}
	DIGO.complete_desert_race(state.world_state,DIGO.DESERT_RACE_ID,true)
	state.economy.grant_reward("capture_digo_aero_funds",200000)
	state.world_state.vehicles = [{"archetype":car_id,"vehicle_id":ID,"was_driven":true,"position":[front.x,.12,front.z],"yaw":0.0,"health":float(preload("res://runtime/FleetCatalog.gd").spec(car_id).durability),"region":"desert","equipment":{}}]
	return state.snapshot()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--car="): car_id = argument.trim_prefix("--car=")
	if DisplayServer.get_name() == "headless":
		push_error("Captura precisa de janela")
		_finish(2); return
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	var path := FIXTURE.write_fixture(FIXTURE.output_dir("digo-aero-live"),"checkpoint.json",_seed())
	if not _check(not path.is_empty(),"fixture save valid"): _finish(1); return
	var launch := root.get_node_or_null("V2Launch")
	old_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec()+90000
	while Time.get_ticks_msec() < deadline and not _boot_complete(): await physics_frame
	if not _check(_boot_complete(),"Main boot completed"): _finish(1); return
	var session = world.session
	var car: CharacterBody3D = world.driving.car
	world.gameplay.god_mode = true
	if not _check(world.driving.occupied and car.vehicle_id == ID and car.archetype == car_id,"driver starts in "+car_id): _finish(1); return
	# Pedal analógico real atravessa o portão, como no test_digo_drive_workshop.
	deadline = Time.get_ticks_msec()+30000
	while Time.get_ticks_msec() < deadline and session.state.place_id != DRIVE.PLACE:
		var speed: float = absf(car.speed)
		if speed < .8: Input.action_press("accelerate",.18)
		elif speed > 1.3: Input.action_release("accelerate")
		await physics_frame
	Input.action_release("accelerate")
	if not _check(session.state.place_id == DRIVE.PLACE,"drove into the workshop"): _finish(1); return
	deadline = Time.get_ticks_msec()+10000
	while Time.get_ticks_msec() < deadline and session.desert.workshop_drive._busy: await physics_frame
	var tuning: Node = session.desert.tuning_panel
	if not _check(tuning.visible and session.modal,"live service panel open"): _finish(1); return
	await _capture("00-menu")
	var body_button: Button
	for button in tuning._cards.get_children():
		if button is Button and button.get_meta("menu_key","") == "Carroceria": body_button = button
	var utility := TUNING.is_utility(car_id)
	if not _check(is_instance_valid(body_button),"visual menu shows Carroceria"): _finish(1); return
	await _activate_button(body_button)
	await _capture("01-carroceria")
	var shown := 0
	for slot in ["skirts","front_lip","diffuser","spoiler"]:
		for id in TUNING.PARTS:
			if str(TUNING.PARTS[id].slot) != slot or not TUNING.compatible(str(id),car_id): continue
			var button: Button = tuning.button_for_part(str(id))
			if not _check(is_instance_valid(button),"card for "+str(id)): continue
			# O foco é o que o jogador faz ao percorrer os cartões: dispara prévia e câmera do slot.
			button.grab_focus()
			await _frames(4)
			var appearance: RefCounted = car.get_meta("tuning_appearance") if car.has_meta("tuning_appearance") else null
			var built := false
			if appearance != null:
				var kits: RefCounted = appearance._kits
				built = is_instance_valid(kits.spoiler) if slot == "spoiler" else is_instance_valid(kits.aero.nodes.get(slot))
			_check(built,str(id)+" previewed on the live car")
			await _capture("%02d-%s" % [10+shown,str(id)])
			shown += 1
	_check(shown >= (1 if utility else 8),"captured the body kit options offered to "+car_id)
	if "--diagnose-rear" in OS.get_cmdline_user_args(): _diagnose_rear(session.desert.workshop_drive,car)
	var file := FileAccess.open(ProjectSettings.globalize_path(destination.path_join(car_id+"_manifest.json")),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"scope":"Main real, save isolado, oficina do Digo, carro dirigido para dentro; prévia do painel. Sem FPS.","car":car_id,"captures":captures,"failures":failures},"\t"))
	_finish(0 if failures.is_empty() else 1)

## Repete as contas da vista traseira da oficina e diz qual condição recusa cada pose.
func _diagnose_rear(helper: Node, car: CharacterBody3D) -> void:
	helper._rear_inspection = true
	var target: Vector3 = car.global_position+Vector3(0,.1,0)
	for angle in [-.65,.45,-.45,0.0]:
		var desired: Vector3 = car.global_position+Vector3(sin(angle)*.6,3.0,-clampf(6.8/helper._zoom,6.2,7.4))
		var local: Vector3 = helper.session.room.to_local(desired)
		local.x = clampf(local.x,-1.25,1.25)
		local.z = clampf(local.z,-7.5,-5.5)
		desired = helper.session.room.to_global(local)
		var corridor: bool = helper._camera_corridor_clear(target,desired)
		var visible: bool = helper._car_visible_from(desired)
		helper._camera.global_position = desired
		helper._camera.look_at(target,Vector3.UP)
		helper._camera.look_at(target-helper._camera.global_basis.x*1.3,Vector3.UP)
		var fits: bool = helper._fit_car_in_preview(42.0)
		print("DIGO_AERO rear angle=",angle," corridor=",corridor," visible=",visible," fits=",fits," car_local=",helper.session.room.to_local(car.global_position)," half_length=",car.half_length," yaw=",car.rotation.y)

func _finish(code: int) -> void:
	var launch := root.get_node_or_null("V2Launch")
	if launch != null and not old_path.is_empty(): launch.selected_path = old_path
	print("DIGO_AERO failures=",failures)
	quit(code)

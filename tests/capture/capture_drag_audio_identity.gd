extends SceneTree
## Main/.NET real, embarque comum e passada física de 800 m. Save isolado.
## Buses privados de gravação repassam para os buses ORIGINAIS de SFX/Music; nenhuma mudança
## global de ganho durante a rodada. Captura as contribuições do motor separadamente.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
var world
var output := ""
var records: Dictionary = {}
var labels: Array[Dictionary] = []
var failures: Array[String] = []
var clock := 0.0
var recording := false
var route_clock := 0.0
var last_phase := ""
var steps: Array[Dictionary] = []

class InputShield extends Node:
	func _input(_event: InputEvent) -> void: get_viewport().set_input_as_handled()
	func _physics_process(_delta: float) -> void:
		for action in InputMap.get_actions(): Input.action_release(action)

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("DRAG_AUDIO_CAPTURE timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("DRAG_AUDIO_CAPTURE ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func recorder(label: String, bus: String, send := "") -> void:
	if not send.is_empty():
		AudioServer.add_bus()
		var new_index := AudioServer.get_bus_count()-1
		AudioServer.set_bus_name(new_index,bus)
		AudioServer.set_bus_send(new_index,send)
	var index := AudioServer.get_bus_index(bus)
	var effect := AudioEffectRecord.new()
	effect.format=AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(index,effect)
	records[label]={"bus":bus,"index":index,"effect":effect}

func route(node: Node, bus: String) -> void:
	for child in node.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D: child.bus=bus
		route(child,bus)

func mark(label: String) -> void:
	labels.append({"label":label,"seconds":clock})
	print("DRAG_AUDIO_CAPTURE_MARK ",label," ",clock)

func _process(delta: float) -> bool:
	if not recording: return false
	clock+=delta
	route_clock-=delta
	if route_clock>0 or not is_instance_valid(world): return false
	route_clock=.1
	var race = world.session.desert.drag
	if race.active and race.racers.size()==2:
		for index in 2: route(race.racers[index].sound,"DragProbePlayer" if index==0 else "DragProbeRival")
		if race.phase!=last_phase:
			last_phase=race.phase
			mark(last_phase)
		steps.append({"seconds":clock,"phase":race.phase,"player_x":race.racers[0].car.global_position.x,"rival_x":race.racers[1].car.global_position.x,
			"player_rpm":race.racers[0].drive.rpm,"rival_rpm":race.racers[1].drive.rpm,
			"player_role":race.racers[0].sound.race_role,"rival_role":race.racers[1].sound.race_role})
	return false

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args() or not OS.get_environment("HARBOR_NO_CSHARP").is_empty(): quit(2); return
	output=FIXTURE.output_dir("drag-audio-identity")
	print("DRAG_AUDIO_CAPTURE_OUTPUT ",output)
	root.size=Vector2i(1280,720)
	var at := LAYOUT.drag_staging_point()+Vector3(0,.1,0)
	var data: Dictionary = FIXTURE.full_snapshot(at,true)
	data.region_id="desert"
	data.world.pedestrian={"region":"desert","position":[at.x,at.y,at.z]}
	var path := FIXTURE.write_fixture(output,"checkpoint.json",data)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("menu_save_path",path)
	root.add_child(world)
	current_scene=world
	var shield := InputShield.new()
	shield.process_physics_priority=-100
	root.add_child(shield)
	for tick in 4800:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.production.startup_streaming_settled: break
	if world.session==null or not world.session.ready_for_play: quit(1); return
	world.dispatch.router.nearest_edge(at)
	check(world.dispatch.router._native!=null,"native C# route backend is active")
	var session=world.session
	var race=session.desert.drag
	world.gameplay.god_mode=true
	session.weather.set_process(false)
	session.weather.time_of_day=.9
	session.weather._update()
	race.open_meet.enabled=false
	var car=world.production.spawn_vehicle("desert_mirage",at+Vector3(0,0,-6),-PI*.5)
	if not is_instance_valid(car): quit(1); return
	car.set_meta("radio_index",-1)
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
	for tick in 4: await physics_frame
	check(world.driving.interact(),"ordinary boarding starts")
	for tick in 600:
		await physics_frame
		if world.driving.occupied and not world.driving.is_body_transition_active() and not car.input_locked: break
	check(world.driving.occupied and not car.input_locked,"ordinary boarding returns control")
	var life=session.desert.meet_life
	var score=life.score
	await create_timer(5.0).timeout
	check(is_instance_valid(score) and score.snapshot().voices==2,"original score is active in the real paddock")
	recorder("mix","Master")
	recorder("player","DragProbePlayer","SFX")
	recorder("rival","DragProbeRival","SFX")
	recorder("patio","DragProbePatio","Music")
	recorder("pulso","DragProbePulso","Music")
	score.players[0].bus=&"DragProbePatio"
	score.players[1].bus=&"DragProbePulso"
	for row in records.values(): row.effect.set_recording_active(true)
	recording=true
	mark("patio")
	await create_timer(8.0).timeout
	if not race.perform("start"):
		check(false,"start: "+race.start_block_reason())
		await finish(); return
	race._rng.seed=2247
	race._rival_wait=.32
	for index in 2: route(race.racers[index].sound,"DragProbePlayer" if index==0 else "DragProbeRival")
	var saw_far_score := false
	while race.active and clock<100.0:
		race._throttle_override=.54 if race.phase=="staging" else 1.0
		race._nitro_override=race.phase=="racing"
		if race.phase=="racing" and race.racers[0].drive.rpm>=race.racers[0].drive.ideal_shift_rpm: race.request_shift()
		if race.phase=="racing" and race.racers[0].car.global_position.distance_to(LAYOUT.drag_meet_center())>260.0:
			saw_far_score=score.snapshot().voices==2 and score.mode=="racing"
		await physics_frame
	check(not race.last_result.is_empty() and not race.active,"real 800 m pass crosses and brakes to completion")
	check(saw_far_score,"both score stems survive after the crowd unloads")
	mark("results")
	await create_timer(5.0).timeout
	check(score.mode=="results" and score.snapshot().voices==2,"score resolves into the real results screen")
	var returned: bool = await race.return_to_entry()
	check(returned,"return uses the checked entry location")
	session.close_menu()
	mark("return")
	await create_timer(7.0).timeout
	check(score.mode=="patio" and score.snapshot().voices==2,"return restores the original paddock arrangement")
	check(clock>=30.0,"real mix capture exceeds thirty seconds")
	await finish()

func finish() -> void:
	recording=false
	# Congela as cinco capturas antes de exportar qualquer WAV, para que o tempo do sistema de arquivos
	# não estique as caudas dos arquivos posteriores.
	for row in records.values(): row.effect.set_recording_active(false)
	for label in records:
		var row: Dictionary=records[label]
		var stream: AudioStreamWAV=row.effect.get_recording()
		if stream!=null: stream.save_to_wav(output.path_join(label+".wav"))
		var index := AudioServer.get_bus_index(row.bus)
		for effect_index in range(AudioServer.get_bus_effect_count(index)-1,-1,-1):
			if AudioServer.get_bus_effect(index,effect_index)==row.effect: AudioServer.remove_bus_effect(index,effect_index)
	var report := {"engine":Engine.get_version_info().string,"scene":"Main.tscn","duration":clock,"marks":labels,"steps":steps,"failures":failures,
		"capture_contract":"Private per-source buses forward to unchanged SFX/Music. Source stems captured before parent bus gains; Master capture includes full mix. Not a performance benchmark or a subjective listening review."}
	var file := FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if is_instance_valid(world): world.queue_free()
	await process_frame
	await process_frame
	for name in ["DragProbePlayer","DragProbeRival","DragProbePatio","DragProbePulso"]:
		var index := AudioServer.get_bus_index(name)
		if index>=0: AudioServer.remove_bus(index)
	print("DRAG_AUDIO_CAPTURE_DONE failures=",failures.size()," output=",output)
	quit(0 if failures.is_empty() else 1)

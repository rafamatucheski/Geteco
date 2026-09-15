extends SceneTree

const ENGINE := preload("res://audio/VehicleEngineSound.gd")
var controller = ENGINE.new()
var motor: AudioStreamPlayer2D
var vehicle_id := "sedan_classic"
var drive_active := false
var elapsed := 0.0
var speed := 0.0

func _initialize() -> void: run.call_deferred()

func _process(delta: float) -> bool:
	if drive_active:
		elapsed += delta
		var throttle := 1.0 if elapsed < 6.2 else 0.0
		if throttle > 0:
			speed = minf(400.0, speed + 880.0 * controller.drive_force(speed, 500.0) * delta)
		else:
			speed = maxf(0.0, speed - 90.0 * delta)
		controller.update(motor, speed, 400.0, throttle, delta, vehicle_id)
	return false

func run() -> void:
	var sport_only := "sport-only" in OS.get_cmdline_user_args()
	var vehicles := ["sport_coupe"] if sport_only else ["sedan_classic", "sport_coupe"]
	var city := root.get_node("CityAudioManager")
	city.set_process(false)
	for child in city.get_children():
		if child is AudioStreamPlayer: child.stop()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	motor = AudioStreamPlayer2D.new()
	motor.bus = &"SFX"
	world.add_child(motor)
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var bus := AudioServer.get_bus_index(&"SFX")
	var slot := AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, recorder)
	for id in vehicles: ENGINE.prewarm(id)
	recorder.set_recording_active(true)
	for id in vehicles:
		vehicle_id = id
		controller.bind(motor, id)
		speed = 0.0
		elapsed = 0.0
		drive_active = true
		await create_timer(8.0).timeout
		drive_active = false
		motor.stop()
		controller.stop()
		await create_timer(0.4).timeout
	if sport_only:
		finish_capture(recorder, bus, slot, world, "D:/geteco/artifacts/boxer-sport-preview.wav", 8.0)
		return
	var shot := AudioStreamPlayer.new()
	shot.bus = &"SFX"
	world.add_child(shot)
	for kind in ["pistol", "shotgun", "sawed_off", "ak47"]:
		shot.stream = ProceduralAudio.get_gunshot_stream(kind)
		shot.volume_db = WeaponCatalog.get_audio_volume_db(kind)
		for take in 3:
			shot.play()
			await create_timer(0.8 if kind != "ak47" else 0.18).timeout
		await create_timer(0.4).timeout
	var pool := preload("res://audio/combat/CombatImpactAudio.gd").new()
	world.add_child(pool)
	for material in [&"flesh", &"metal", &"concrete", &"wood", &"glass"]:
		pool.play_impact(Vector2.ZERO, material, 30)
		await create_timer(0.65).timeout
	await create_timer(0.5).timeout
	finish_capture(recorder, bus, slot, world, "D:/geteco/artifacts/driving-combat-audio.wav", 28.0)

func finish_capture(recorder: AudioEffectRecord, bus: int, slot: int, world: Node, path: String, minimum: float) -> void:
	recorder.set_recording_active(false)
	var wav := recorder.get_recording()
	var error := wav.save_to_wav(path)
	AudioServer.remove_bus_effect(bus, slot)
	print("DRIVING_COMBAT_CAPTURE error=", error, " seconds=", wav.get_length())
	world.queue_free()
	await process_frame
	quit(0 if error == OK and wav.get_length() >= minimum else 1)

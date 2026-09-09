extends SceneTree

const ENGINE := preload("res://audio/VehicleEngineSound.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var audio := AudioStreamPlayer2D.new()
	root.add_child(audio)
	var engine := ENGINE.new()
	for i in 60:
		engine.update(audio, 0, 500, 0, 1.0 / 60.0, "sedan_classic")
	var idle_pitch := audio.pitch_scale
	var idle_db := audio.volume_db
	for i in 60:
		engine.update(audio, 0, 500, 1, 1.0 / 60.0, "sedan_classic")
	check(audio.pitch_scale > idle_pitch and audio.volume_db > idle_db, "Throttle changes the engine even before the vehicle moves")
	for i in 60:
		engine.update(audio, 0, 500, 0, 1.0 / 60.0, "sedan_classic")
	check(absf(audio.pitch_scale - idle_pitch) < 0.02, "Releasing throttle settles back to idle")
	# Primeira marcha agora estica ate 30% da maxima (150 de 500), nao 22%.
	engine.update(audio, 130, 500, 1, 0.1, "sedan_classic")
	check(engine.gear == 1, "First gear stretches past a quarter of top speed")
	engine.update(audio, 165, 500, 1, 0.1, "sedan_classic")
	check(engine.gear == 2, "Acceleration shifts into second gear")
	engine.update(audio, 140, 500, 1, 0.1, "sedan_classic")
	check(engine.gear == 2, "Gear hysteresis avoids chatter near threshold")
	var road_engine := ENGINE.new()
	var road_speed := 0.0
	var changes := 0
	var last_gear := 1
	var first_shift_time := 0.0
	for frame in 1200:
		road_speed = minf(ENGINE.road_top_speed(500.0), road_speed + 880.0 * road_engine.drive_force(road_speed, 500.0) / 60.0)
		road_engine.update(audio, road_speed, ENGINE.road_top_speed(500.0), 1.0, 1.0/60.0, "sedan_classic")
		if road_engine.gear > last_gear:
			changes += 1
			if changes == 1: first_shift_time = frame / 60.0
			check(road_engine.shift_remaining > 0.0, "Upshift creates a torque and RPM interruption")
		last_gear = road_engine.gear
	check(changes == 4, "Acceleration passes through five gears")
	check(first_shift_time > 0.38, "First gear lasts long enough to be heard (%.2fs)" % first_shift_time)
	# O ponto do pedido: o topo da primeira marcha nao pode soar como velocidade
	# maxima. Antes chegava a 97% do pitch maximo, o que fazia o motor "estourar"
	# logo na largada e as marchas seguintes repetirem o mesmo som.
	var ladder_engine := ENGINE.new()
	var ladder: Array = []
	for gear_top in [0.30, 0.48, 0.64, 0.80, 1.0]:
		for i in 120:
			ladder_engine.update(audio, 400.0 * gear_top, 400.0, 1.0, 1.0 / 60.0, "sedan_classic")
		ladder.append(audio.pitch_scale)
	var rising := true
	for i in range(1, ladder.size()):
		if ladder[i] <= ladder[i - 1] + 0.03:
			rising = false
	check(rising, "Each gear tops out higher than the one before: %s" % str(ladder))
	check(ladder[0] < ladder[ladder.size() - 1] * 0.85, "First gear tops well below top speed pitch: %s" % str(ladder))
	check(road_speed <= 400.0, "Road top speed is reduced by twenty percent")
	check(ENGINE.get_stream("street") == ENGINE.get_stream("street"), "Engine loops share cached resources")
	check(ENGINE.get_stream("street").data != ENGINE.get_stream("sport").data, "Sport engines have distinct timbre")
	check(ENGINE.get_stream("diesel").data != ENGINE.get_stream("sport").data, "Diesels have distinct timbre")
	var hud = load("res://HUD.tscn").instantiate()
	root.add_child(hud)
	hud.show_vehicle_name("Sedan Premier 2.0")
	check(hud.vehicle_name_label.visible and hud.vehicle_name_label.text == "Sedan Premier 2.0", "Entry name appears")
	hud.show_vehicle_name("Infernus GT Turbo")
	check(hud.vehicle_name_label.text == "Infernus GT Turbo", "New entry replaces the previous name")
	await create_timer(4.4).timeout
	check(not hud.vehicle_name_label.visible, "Vehicle name disappears automatically")
	hud.show_vehicle_name("Infernus GT Turbo")
	check(hud.vehicle_name_label.visible, "Entering the same car again shows its name again")
	hud.queue_free()
	audio.queue_free()
	await process_frame
	print("VEHICLE_ENGINE_AND_NAME failures=%d" % failures)
	quit(1 if failures else 0)

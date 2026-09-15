extends SceneTree

const MODEL := preload("res://world/harbor/campaign/MaciotaM8SedanModel.gd")
const ENGINE := preload("res://audio/VehicleEngineSound.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1

func run() -> void:
	var bench := Node3D.new()
	root.add_child(bench)
	var model := MODEL.new()
	bench.add_child(model)
	await process_frame
	check(model.get_meta("paint", "") == "full_black", "Maciota uses full-black paint")
	check(model.get_meta("vehicle_name", "") == "Maciota M8 Competition", "Maciota model identifies the new sedan")
	check(model.wheels.size() == 4, "Maciota sedan has four wheels")
	check(model.doors.size() == 4, "Maciota sedan has four door panels")
	check(model.occupants.size() == 2, "Maciota sedan keeps both occupants")
	var layers := ENGINE.get_layer_streams("m8_v8", "maciota_m8")
	check(layers.size() == 5, "M8 V8 has five engine timbre layers")
	check(ENGINE.family_for_vehicle("maciota_m8") == "m8_v8", "Maciota binds to the M8 V8 sound profile")
	var audio := AudioStreamPlayer2D.new()
	root.add_child(audio)
	var engine := ENGINE.new()
	engine.bind(audio, "maciota_m8")
	for i in 720:
		engine.update(audio, float(i) / 720.0 * 150.0, 220.0, .75, 1.0 / 60.0, "maciota_m8")
	check(engine.gear > 1 and engine.engine_rpm > 1000.0, "M8 V8 progresses through the gearbox")
	for i in 90:
		engine.update(audio, 0.0, 220.0, 0.0, 1.0 / 60.0, "maciota_m8")
	check(engine.gear == 1 and engine.engine_rpm < 1000.0, "M8 V8 returns to idle after stopping")
	audio.queue_free()
	bench.queue_free()
	await process_frame
	print("MACIOTA_M8 failures=", failures)
	quit(0 if failures == 0 else 1)

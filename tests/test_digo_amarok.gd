extends SceneTree
const CAR := preload("res://gameplay/digo/DigoAmarok.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const LIGHTS := preload("res://gameplay/VehicleLightProfiles.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var spec := FLEET.spec("digo_amarok_2014")
	check(spec.get("tuning_stage",0)==2 and spec.get("drivetrain","")=="4x4","cold catalogue stage2 4x4")
	check(not FLEET.all().has("digo_amarok_2014"),"personal car absent from random traffic")
	check(LIGHTS.family("digo_amarok_2014")=="xenon","xenon profile")
	var car := CAR.new()
	root.add_child(car)
	car.set_physics_process(false)
	check(car.wheels.size()==4,"four animated wheels")
	check(car.visual.get_meta("body_doors",0)==4,"four door pickup")
	check(car.shape.shape.size.is_equal_approx(Vector3(2.12,1.86,5.22)),"pickup collision size")
	check(not car.door_layout(-1).is_empty(),"driver door supports boarding")
	var sound = car.get_node("DigoAmarokExhaust")
	sound.set_physics_process(false)
	check(CAR.install_audio(car)==sound,"restored attachment is idempotent")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,3,7)
	camera.make_current()
	sound.tick(.05)
	check(not sound.rumble.playing and not sound.release.playing,"parked engine remains silent")
	car.controlled = true
	car.speed = 18
	car.throttle_input = 1
	for i in 20: sound.tick(.05)
	check(sound.rumble.playing,"diesel exhaust runs with engine")
	car.throttle_input = 0
	sound.tick(.05)
	check(sound.release.playing,"loaded lift off produces two-pulse turbo release")
	car.engine_disabled = true
	sound.tick(.05)
	check(not sound.rumble.playing and not sound.release.playing,"disabled engine silences all custom audio")
	car.engine_disabled = false
	camera.position = Vector3(0,3,100)
	sound.tick(.05)
	check(not sound.rumble.playing,"distant exhaust culled")
	var equipment := preload("res://gameplay/VehicleEquipment.gd").new()
	equipment.configure(car,root)
	car.add_child(equipment)
	check(equipment.lamps.size()==2,"both xenon headlight mounts exist")
	check(equipment.profile.family=="xenon","actual equipment receives xenon profile")
	equipment.headlights_on = true
	equipment._refresh()
	check(equipment.lamps.all(func(item: Dictionary): return item.lamp.visible),"both player xenon projectors illuminate")
	car.free()
	camera.free()
	await process_frame
	print("DIGO_AMAROK_RESULT checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

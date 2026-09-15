extends SceneTree
const CAR := preload("res://world/harbor/monaliza/MonalizaCar.gd")
const ENGINE := preload("res://audio/VehicleEngineSound.gd")
var failures := 0
class FlutterProbe extends "res://world/harbor/monaliza/MonalizaCar.gd":
	var flutter_gears: Array[int] = []
	var flutter_during_cut := false
	func _play_shift_flutter(pressure: float) -> void:
		super._play_shift_flutter(pressure)
		flutter_gears.append(_engine_sound.gear)
		flutter_during_cut = flutter_during_cut or _engine_sound.shift_remaining > 0.0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func reset_drive(car) -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	car.velocity = Vector2.ZERO
	car.position = Vector2.ZERO
	car.rotation = 0.0
	car._drive_input_armed = true
	car.boost_pressure = 0.0
	car._pending_shift_pressure = 0.0
	car._last_audio_gear = 1
	car.flutter_gears.clear()
	car.flutter.stop()
	car._engine_sound.bind(car.engine_audio, "monaliza")
	car.is_driven_by_player = true
	car.unlocked = true

func time_to_200(car) -> float:
	Input.action_press("move_up")
	for i in 1200:
		car._physics_process(1.0 / 60.0)
		if car.velocity.length() >= 200.0: return float(i + 1) / 60.0
	return 20.0

func run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := FlutterProbe.new()
	world.add_child(car)
	car.set_physics_process(false)
	reset_drive(car)
	car.max_speed = 560.0
	car.acceleration = 460.0
	var before := time_to_200(car)
	reset_drive(car)
	car.restore_factory_handling()
	var after := time_to_200(car)
	print("MONALIZA_ACCELERATION 0_to_200_px_s before=%.3fs after=%.3fs" % [before, after])
	check(after < before * 0.5 and after > 0.6, "responsive launch with progressive acceleration")
	reset_drive(car)
	Input.action_press("move_up")
	var shift_times: Array[float] = []
	var previous_gear := 1
	for i in 600:
		car._physics_process(1.0 / 60.0)
		if car._engine_sound.gear > previous_gear:
			shift_times.append(float(i + 1) / 60.0)
		previous_gear = car._engine_sound.gear
	check(shift_times.size() == 6, "full acceleration traverses all seven gears")
	if shift_times.size() == 6:
		check(shift_times[1] - shift_times[0] > 0.35, "second gives the engine time to pull before shifting")
		check(shift_times[2] - shift_times[1] > 0.50, "third holds a longer acceleration sweep")
	print("MONALIZA_SHIFT_TIMES seconds=", shift_times)
	print("MONALIZA_FLUTTER after_gears=", car.flutter_gears)
	check(car.flutter_gears == [2, 3, 4, 5, 6, 7], "loaded acceleration plays one flutter after each upshift")
	check(not car.flutter_during_cut, "flutter starts after the gear finishes engaging")
	check(car.velocity.length() > 350.0 and car.velocity.length() <= ENGINE.road_top_speed(car.max_speed) + 0.1, "highway speed rises without bypassing road speed limit")
	check(car._engine_sound.gear == 7, "seventh engages before road top speed")
	check(car._engine_sound.engine_rpm > 5400.0 and car._engine_sound.engine_rpm < 5800.0, "top speed leaves audible RPM reserve below the 7920 RPM redline")
	var cruise_min := INF
	var cruise_max := 0.0
	var stable_gear := true
	for i in 180:
		car._physics_process(1.0 / 60.0)
		cruise_min = minf(cruise_min, car._engine_sound.engine_rpm)
		cruise_max = maxf(cruise_max, car._engine_sound.engine_rpm)
		stable_gear = stable_gear and car._engine_sound.gear == 7 and car._engine_sound.shift_remaining <= 0.0
	check(stable_gear and cruise_max - cruise_min < 5.0, "sustained top speed has no gear hunting or limiter pulsing")
	check(car.flutter_gears.size() == 6, "holding seventh never repeats the shift flutter")
	print("MONALIZA_CRUISE gear=", car._engine_sound.gear, " rpm=", car._engine_sound.engine_rpm, " speed=", car.velocity.length())
	check(car._engine_sound._layer_players.back().playing, "high RPM uses the exclusive high layer")
	check(car.engine_audio.stream == ENGINE.get_layer_streams("monaliza", "monaliza")[0], "live controller retains layered engine without single-loop override")
	# At 93% the seventh holds; at 89% it reduces once to sixth. Hysteresis must
	# use the shift schedule, not the unreachable theoretical gear top speeds.
	var top: float = ENGINE.road_top_speed(car.max_speed)
	for i in 60: car._engine_sound.update(car.engine_audio, top * 0.93, top, 1.0, 1.0 / 60.0, "monaliza")
	check(car._engine_sound.gear == 7, "small speed changes do not hunt between sixth and seventh")
	for i in 60: car._engine_sound.update(car.engine_audio, top * 0.89, top, 1.0, 1.0 / 60.0, "monaliza")
	check(car._engine_sound.gear == 6, "larger speed loss downshifts once for a responsive overtake")
	Input.action_release("move_up")
	car._physics_process(1.0 / 60.0)
	check(car.release.playing, "loaded turbo releases once on lift-off")
	check(car.flutter_gears.size() == 6, "lift-off does not trigger the shift flutter")
	car.velocity = Vector2(300.0, 0.0)
	for i in 30: car._physics_process(1.0 / 60.0)
	print("MONALIZA_COAST speed_after_half_second=", car.velocity.length())
	check(car.velocity.length() >= 235.0, "lift-off rolls instead of acting as a hard brake")
	Input.action_press("move_down")
	for i in 10: car._physics_process(1.0 / 60.0)
	check(car.velocity.length() < 30.0, "explicit braking still stops decisively")
	Input.action_release("move_down")
	car.is_driven_by_player = false
	for i in 90: car._physics_process(1.0 / 60.0)
	check(not car.spool.playing and not car.release.playing and not car.ignition.playing and not car.flutter.playing, "auxiliary sounds stop after exit")
	var child_count := car.get_child_count()
	car._trigger_backfire()
	check(car.get_child_count() == child_count, "lift-off never spawns the generic exhaust bang")
	car.acceleration *= 0.5
	car.max_speed *= 0.45
	car.restore_factory_handling()
	check(car.acceleration == VehicleCatalog.get_vehicle_spec("monaliza").acceleration, "garage handling restoration cannot restore the old slow tune")
	for kind in ["turbo_release", "turbo_shift", "ignition"]:
		var wav := CAR.MONALIZA_AUDIO.stream(kind)
		check(wav.data.decode_s16(0) == 0 and wav.data.decode_s16(wav.data.size() - 2) == 0, kind + " begins and ends at exact silence")
	for wav in ENGINE.get_layer_streams("monaliza", "monaliza") + [car.spool.stream]:
		var guarded: bool = wav.data.size() / 2 >= wav.loop_end + ENGINE.GUARD
		for i in ENGINE.GUARD:
			guarded = guarded and wav.data.decode_s16((wav.loop_end + i) * 2) == wav.data.decode_s16(i * 2)
		check(guarded, "loop carries correct interpolation samples past loop_end")
	world.queue_free()
	await process_frame
	print("MONALIZA_DRIVETRAIN failures=", failures)
	quit(1 if failures else 0)

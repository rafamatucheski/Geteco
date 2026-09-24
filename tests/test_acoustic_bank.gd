extends SceneTree
const ENGINE := preload("res://audio/VehicleEngineSound.gd")
const BANK := preload("res://audio/acoustic/AcousticBank.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var voice := AudioStreamPlayer2D.new()
	root.add_child(voice)
	var controller := ENGINE.new()
	for family in BANK.ENGINES:
		var layers := ENGINE.get_layer_streams(family)
		check(layers.size() >= 6, "Dense RPM palette: " + family)
		for layer in layers:
			check(layer.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Loop enabled: " + family)
			check(layer.loop_end == 22050 and layer.data.size() == 44116, "Guard and loop boundary: " + family)
			var data: PackedByteArray = layer.data
			for i in 8:
				check(data.decode_s16(i*2) == data.decode_s16((22050+i)*2), "Seam guard: " + family)
	for id in ["sedan_classic", "sport_coupe", "muscle_classic", "cargo_flatbed_truck"]:
		controller.bind(voice,id)
		for frame in 720:
			controller.update(voice,400.0*frame/719.0,400.0,1.0,1.0/60.0,id)
			var active := 1 if voice.playing else 0
			for layer in controller._layer_players:
				if layer.playing: active += 1
			check(active <= 2 and active > 0, "At most two active RPM voices: " + id)
		controller.update(voice,0.0,400.0,0.0,1.0/60.0,id)
		check(controller.gear == 1, "Hard stop resets transmission: " + id)
	controller.bind(voice,"sedan_classic")
	var speed := 0.0
	var at_97 := 0.0
	var shifts: Array[float] = []
	var previous := 1
	for frame in 1800:
		speed = minf(400.0,speed+880.0*controller.drive_force(speed,500.0)/60.0)
		controller.update(voice,speed,400.0,1.0,1.0/60.0,"sedan_classic")
		if controller.gear > previous: shifts.append(frame/60.0)
		previous = controller.gear
		if at_97 == 0.0 and speed >= 388.0: at_97=frame/60.0
	check(shifts.size()==5 and shifts[0] > .3, "Six gears with readable first gear")
	check(at_97 > 5.0 and at_97 < 25.0, "Sustained acceleration without unreachable maximum")
	print("ACOUSTIC_DRIVE shifts=",shifts," seconds_to_97_percent=",at_97)
	for kind in BANK.EVENTS:
		var event := preload("res://audio/combat/CombatAudioBank.gd").sound(kind) as AudioStreamRandomizer
		check(event != null and event.streams_count == 5,"Five integrated takes: "+kind)
		check(event.get_stream(0) == BANK.EVENTS[kind][0], "New bank actually selected: "+kind)
	controller.stop()
	print("ACOUSTIC_BANK failures=",failures)
	quit(0 if failures==0 else 1)

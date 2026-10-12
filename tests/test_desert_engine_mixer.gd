extends SceneTree
## Audible pitch must follow the physical RPM through bank/gear transitions.
const AUDIO := preload("res://audio/desert_cars/DesertCarAudio.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
var checks := 0
var failures: Array[String] = []

class Car extends Node3D:
	var controlled := true
	var traffic := false
	var external_input := false
	var speed := 0.0
	var health := 100.0
	var engine_disabled := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	for id in CARS.IDS:
		var car := Car.new()
		root.add_child(car)
		var drive := DRIVE.new()
		drive.configure(id)
		var sound := AUDIO.new()
		sound.bind(car,drive)
		car.add_child(sound)
		sound.set_process(false)
		var nominal: Array = PROFILE.NOMINAL[drive.spec.engine_family]
		for rpm in [900.0,1500.0,2400.0,3600.0,drive.redline]:
			drive.rpm = rpm
			for tick in 30: sound._process(.1)
			for slot in 2:
				var player: AudioStreamPlayer3D = sound._layers[slot]
				var cycles := float(nominal[sound._indices[slot]])*player.pitch_scale
				check(absf(cycles-rpm/120.0) < .01,id+": both layers match physical RPM "+str(rpm))
		for band in range(1,6):
			drive.rpm = float(nominal[band])*120.0-.1
			for i in 30: sound._process(.1)
			var slot := sound._indices.find(band)
			var player: AudioStreamPlayer3D = sound._layers[slot]
			var stream: AudioStream = player.stream
			var level := player.volume_db
			drive.rpm += 10.0
			sound._process(1.0/60.0)
			check(sound._audible_rpm > float(nominal[band])*120.0,id+": audible RPM actually crosses band "+str(band))
			check(sound._indices[slot] == band and player.stream == stream,id+": common sample retained crossing band "+str(band))
			check(player.volume_db > level-1.0,id+": common sample not muted at boundary "+str(band))
		if id in ["desert_bison","desert_coyote","desert_coyote_drag"]:
			drive.rpm = 900.0
			for i in 30: sound._process(.1)
			check(is_instance_valid(sound._recorded_idle) and sound._recorded_idle.playing,id+": real idle recording active")
			check(sound._recorded_idle.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED,id+": real idle follows driver mix")
			drive.rpm = 2400.0
			for i in 30: sound._process(.1)
			check(not sound._recorded_idle.playing,id+": idle recording fades out before high revs")
		# Reverse engagement/braking may jump physical RPM, but both audible
		# bands must glide together and settle back to the authoritative value.
		drive.rpm = 900.0
		for tick in 30: sound._process(.1)
		drive.rpm = 3000.0
		drive.throttle = 1.0
		sound._process(1.0/60.0)
		check(sound._audible_rpm > 900.0 and sound._audible_rpm < 1300.0,id+": engagement has no instant pitch jump")
		check(sound._audible_load > 0.0 and sound._audible_load < .2,id+": throttle gain ramps in")
		for tick in 30: sound._process(.1)
		drive.rpm = 900.0
		drive.throttle = 0.0
		sound._process(1.0/60.0)
		check(sound._audible_rpm > 2700.0 and sound._audible_rpm < 3000.0,id+": braking lets revs fall progressively")
		for tick in 30: sound._process(.1)
		check(absf(sound._audible_rpm-900.0)<.01,id+": braking settles at idle")
		drive.turbo_pressure = 1.0
		sound._blowoff_cooldown = 0.0
		sound._play_shift()
		check(sound._shift.playing == (bool(drive.spec.get("factory_turbo",false)) and str(drive.spec.engine_family) != "diesel"),id+": blowoff only with gasoline turbo pressure")
		drive.nitro_active = true
		sound._process(.1)
		check(car.find_child("Nitro",true,false) == null,id+": injection has no air brake loop")
		car.engine_disabled = true
		sound._process(.1)
		check(sound._layers.all(func(p): return not p.playing) and not sound._shift.playing,id+": disabled vehicle stops engine and transients")
		check(not is_instance_valid(sound._recorded_idle) or not sound._recorded_idle.playing,id+": disabled vehicle stops field recording")
		car.free()
	print("DESERT_ENGINE_MIXER checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

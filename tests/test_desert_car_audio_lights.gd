extends SceneTree
## Regression: all authored desert cars need independent headlights and an
## audible driver's engine, including the normal elevated gameplay camera.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
var failures: Array[String] = []
var checks := 0

class State extends RefCounted:
	var world_state := {"time": .9, "weather": 0}
class Production extends RefCounted:
	var state := State.new()
class World extends Node3D:
	var production := Production.new()
	var player := Node3D.new()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world := World.new()
	root.add_child(world)
	world.add_child(world.player)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,25.3,25.3)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	for id in CATALOG.ids():
		var car := VEHICLE.new()
		car.archetype = id
		world.add_child(car)
		car.set_physics_process(false)
		car.controlled = true
		var equipment: Node = car.ensure_equipment(world)
		check(equipment.lens_materials.size() == 2, id+": two independently bound headlight lenses")
		check(equipment.lamps.size() == 2, id+": two actual projectors")
		check(equipment.lamps.any(func(e): return e.side == -1 and e.lamp.position.x < -.2), id+": left projector mounted at left lens")
		check(equipment.lamps.any(func(e): return e.side == 1 and e.lamp.position.x > .2), id+": right projector mounted at right lens")
		check(not equipment.tail_materials.is_empty(), id+": rear lamps bound")
		check(equipment.toggle_headlights(), id+": driver can switch headlights on")
		check(equipment.lamps.all(func(e): return e.lamp.visible), id+": both beams on")
		check(equipment.lens_materials.all(func(e): return e.material.emission_enabled), id+": front lenses glow")
		equipment.broken_left = true
		equipment._refresh()
		check(equipment.lens_materials.any(func(e): return e.side < 0 and not e.material.emission_enabled), id+": left damage extinguishes left lens")
		check(equipment.lens_materials.any(func(e): return e.side > 0 and e.material.emission_enabled), id+": left damage preserves right lens")
		equipment.broken_left = false
		car.brake_input = true
		equipment._refresh()
		check(equipment.tail_materials.all(func(m): return m.emission_enabled and m.emission_energy_multiplier > 2), id+": brake lights work")
		car.brake_input = false
		var sound: Node = car.get_node("DesertCarAudio")
		for i in 30: sound._process(.05)
		check(sound._bank.size() == 7 and sound._layers.all(func(p): return p.playing), id+": loaded engine bands play")
		check(sound._layers.all(func(p): return p.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED and p.max_distance == 0 and p.panning_strength == 0), id+": driver audio is foreground like the existing fleet")
		# The same listener used by drag must hear the motor above tire squeal.
		sound.drivetrain.wheelspin = 1.0
		for i in 20: sound._process(.05)
		check(sound._tire.playing and sound._tire.volume_db <= -27.9 and sound._tire.max_db <= -24.0 and sound._tire.unit_size <= 4.0, id+": wheelspin remains below the engine with bounded near-listener gain")
		var tires: Node = car.effects.tire_effects
		tires._update_skid_audio(true, 20.0, 0.0)
		check(not is_instance_valid(tires.skid_audio) or not tires.skid_audio.playing, id+": powertrain wheelspin does not stack a second longitudinal squeal")
		car.brake_input = true
		tires._update_skid_audio(true, 20.0, 0.0)
		check(is_instance_valid(tires.skid_audio) and tires.skid_audio.playing, id+": braking retains its tire sound during wheelspin")
		check(tires.skid_audio.volume_db <= -22.0 and tires.skid_audio.max_db <= -22.0 and tires.skid_audio.unit_size <= 4.0, id+": generic skid has a bounded close-listener mix")
		var expected_bus: StringName = &"Vehicles" if AudioServer.get_bus_index("Vehicles") >= 0 else &"Master"
		check(sound._tire.bus == expected_bus and tires.skid_audio.bus == expected_bus, id+": engine and tire effects share the independent Vehicles control")
		car.brake_input = false
		tires._update_skid_audio(true, 20.0, 10.0)
		check(tires.skid_audio.playing, id+": lateral drift remains audible during wheelspin")
		sound.drivetrain.wheelspin = 0.0
		for i in 20: sound._process(.05)
		tires._update_skid_audio(true, 20.0, 0.0)
		check(not sound._tire.playing and tires.skid_audio.playing, id+": generic tire voice resumes when powertrain wheelspin stops")
		tires._update_skid_audio(false, 0.0, 0.0)
		# A detached cinematic/drag camera must not mute the occupied car.
		camera.position = Vector3(0,100,100)
		for i in 6: sound._process(.05)
		check(sound._layers.all(func(p): return p.playing), id+": distant camera does not mute driver")
		car.controlled = false
		car.traffic = true
		for i in 6: sound._process(.05)
		check(sound._layers.all(func(p): return not p.playing), id+": distant traffic remains culled")
		camera.position = Vector3(0,25.3,25.3)
		car.speed = 9
		for i in 6: sound._process(.05)
		check(sound._layers.all(func(p): return p.playing and p.max_distance > 0 and p.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED), id+": nearby NPC engine remains spatial")
		check(sound.drivetrain.rpm > 1500, id+": moving NPC revs")
		car.engine_disabled = true
		sound._process(.05)
		check(sound._layers.all(func(p): return not p.playing), id+": disabled engine goes silent")
		car.engine_disabled = false
		car.traffic = false
		car.speed = 0
		sound.drivetrain.rpm = 750
		sound._process(.05)
		equipment._refresh()
		check(sound._layers.all(func(p): return not p.playing), id+": parked car is silent")
		check(equipment.lamps.all(func(e): return not e.lamp.visible), id+": parked headlights off")
		car.free()
	world.free()
	await process_frame
	print("DESERT_AUDIO_LIGHTS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

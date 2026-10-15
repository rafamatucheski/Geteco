extends SceneTree
const EQUIPMENT := preload("res://gameplay/VehicleEquipment.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for id in ["coupe", "police_cruiser", "medic_box", "rescue_pumper"]:
		var car := VEHICLE.new()
		car.archetype = id
		world.add_child(car)
		car.set_physics_process(false)
		var equipment := EQUIPMENT.new()
		equipment.configure(car, world)
		car.add_child(equipment)
		check(not equipment.toggle_headlights() and not equipment.honk(), id + " unoccupied input blocked")
		car.controlled = true
		check(equipment.toggle_headlights() and equipment.lamps.size() == 2 and equipment.lamps[0].lamp.visible, id + " physical paired beams")
		check(equipment.npc_beam.shadow_enabled, id + " traffic beam cannot cross opaque bodywork")
		check(equipment.lamps.all(func(item): return item.lamp.shadow_enabled), id + " driver beams are blocked by solid obstacles")
		check(equipment._budget_request().decal == null, id + " driver has no emissive road patch behind obstacles")
		var emergency: bool = id != "coupe"
		check(equipment.toggle_siren() == emergency, id + " original lightbar availability")
		if emergency:
			check(equipment.beacons.size() == 2 and equipment.siren_audio.playing, id + " actual beacons and positional siren")
		check(equipment.honk(), id + " original horn oscillator")
		var state := equipment.snapshot()
		check(equipment.restore_state(state), id + " save round trip")
		check(not equipment.restore_state({"headlights": 1, "siren": false}), id + " invalid save rejected")
		equipment.set_input_enabled(false)
		check(not equipment.toggle_headlights() and not equipment.honk() and not equipment.toggle_siren(), id + " modal blocks controls")
		car.controlled = false
		equipment._refresh()
		check(not equipment.lamps[0].lamp.visible and not equipment.horn_audio.playing and not equipment.siren_audio.playing, id + " exit stops equipment")
		check(equipment.lamps.all(func(item): return not (item.lamp.shadow_enabled and item.lamp.is_visible_in_tree())), id + " exit leaves no active headlight shadow source")
		car.controlled = true
		car.health = 0
		equipment._refresh()
		check(not equipment.lamps[0].lamp.visible and not equipment.siren_audio.playing, id + " destroyed has no equipment")
		car.free()
	var audio := preload("res://gameplay/VehicleEquipmentAudio.gd")
	check(audio.horn_stream().get_length() > 0.3 and audio.horn_stream().get_length() < 2.0, "recorded car horn, short honk")
	check(audio.siren_stream().loop_mode == AudioStreamWAV.LOOP_FORWARD and audio.siren_stream().get_length() > 3.0 and audio.siren_stream().loop_end > 0, "recorded siren loops forward")
	world.free()
	await process_frame
	print("VEHICLE_EQUIPMENT ", checks, " checks failures=", failures)
	quit(0 if failures.is_empty() else 1)

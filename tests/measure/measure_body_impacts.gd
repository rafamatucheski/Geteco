extends "res://tests/measure/measure_vehicle_bailout.gd"
## Rendered production world; repeatable staged contacts and moving dismounts.
## Placement is a diagnostic fixture; car collision, flight, damage and help are real.
var victim: CharacterBody3D
var launched := 0
var completed := 0
var seen_flight := false
var contacts_before := 0

func _process(delta: float) -> bool:
	if started != 0 and is_instance_valid(victim):
		if victim.has_meta("street_flying") and not seen_flight:
			seen_flight = true
			launched += 1
		if seen_flight and not victim.has_meta("street_flying"):
			completed += 1
			seen_flight = false
	if started != 0 and Time.get_ticks_usec() >= next_exit:
		if is_instance_valid(victim): victim.queue_free()
		victim = preload("res://scripts/Actor.gd").new()
		victim.identity = attempts % 6
		victim.controlled_automatically = true
		world.add_child(victim)
		victim.teleport(home * Vector3(0, 0, -world.driving.car.half_length - .65))
		world.get_node("StreetPhysics")._people_cache.append(victim)
		seen_flight = false
	return super._process(delta)

func finish() -> void:
	var f := FileAccess.open(evidence_dir.path_join(label+"-impacts.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"launched":launched,"completed":completed,"notes":"Staged pedestrians; production car sweeps and live city systems. 9 m/s dismount repeated every 6 seconds."},"\t"))
	f.close()
	print("BODY_IMPACTS launched=",launched," completed=",completed)
	await super.finish()

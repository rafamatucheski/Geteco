extends RefCounted
## Called after Vehicle._ready and after tuning/save restore. Shared core remains
## unchanged for all existing non-desert vehicles.
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const HANDLING := preload("res://gameplay/desert_cars/DesertHandling.gd")
const AUDIO := preload("res://audio/desert_cars/DesertCarAudio.gd")

static func attach(car: CharacterBody3D, parts: Dictionary = {}) -> bool:
	if not is_instance_valid(car): return false
	# Existing player cars may enter Digo's programme explicitly. Do not invoke
	# this automatically for unrelated traffic/police archetypes.
	var profile := CATALOG.profile_for_vehicle(car)
	var clean := TUNING.clean_parts(parts)
	car.set_meta("desert_car_id",profile)
	car.set_meta("desert_parts",clean)
	var s := TUNING.tuned_spec(profile,clean)
	s["installed_parts"] = clean
	var handling := HANDLING.new()
	handling.configure(s)
	car.handling = handling
	car.set_meta("desert_powertrain",handling.drive)
	car.max_forward_speed = minf(float(s.max_speed)/16.0,float(s.street_cap_mps))
	car.drive_acceleration = float(s.acceleration)/160.0
	var condition := float(car.health)/maxf(1.0,float(car.max_health))
	if not car.has_meta("desert_base_max_health"): car.set_meta("desert_base_max_health",float(car.max_health))
	var durability_ratio := float(s.durability)/maxf(1.0,float(CATALOG.spec(profile).durability))
	car.max_health = float(car.get_meta("desert_base_max_health"))*durability_ratio
	car.health = car.max_health*condition
	var previous := car.get_node_or_null("DesertCarAudio")
	if previous != null:
		car.remove_child(previous)
		previous.queue_free()
	var audio := AUDIO.new()
	audio.bind(car,handling.drive)
	car.add_child(audio)
	# Visual kits belong to authored race variants, never to a legacy car that
	# merely borrows one of the desert mechanical profiles for tuning.
	preload("res://gameplay/desert_cars/DesertCarNeon.gd").install(car,CATALOG.spec(car.archetype))
	return true

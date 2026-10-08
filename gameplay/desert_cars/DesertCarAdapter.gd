extends RefCounted
## Called after Vehicle._ready and after tuning/save restore. Shared core remains
## unchanged for all existing non-desert vehicles.
const CATALOG := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const HANDLING := preload("res://gameplay/desert_cars/DesertHandling.gd")
const AUDIO := preload("res://audio/desert_cars/DesertCarAudio.gd")

## Perfil mecânico do carro: o próprio, se for do jogo base com ficha; senão o do
## deserto escolhido pelo nome.
static func profile_of(car: Node) -> String:
	var archetype := str(car.get("archetype"))
	return archetype if STREET.has(archetype) else CATALOG.profile_for_vehicle(car)

static func attach(car: CharacterBody3D, parts: Dictionary = {}) -> bool:
	if not is_instance_valid(car): return false
	# Existing player cars may enter Digo's programme explicitly. Do not invoke
	# this automatically for unrelated traffic/police archetypes.
	# Carro do jogo base com perfil próprio usa a mecânica dele, não a de um carro do
	# deserto escolhido pelo nome; o som e o visual originais ficam como estão.
	var own_profile: bool = STREET.has(str(car.get("archetype")))
	var profile: String = profile_of(car)
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
	var durability_ratio := float(s.durability)/maxf(1.0,float(TUNING.base_spec(profile).durability))
	car.max_health = float(car.get_meta("desert_base_max_health"))*durability_ratio
	car.health = car.max_health*condition
	_apply_neon(car,s)
	preload("res://gameplay/desert_cars/TuningAppearance.gd").apply_vehicle(car,clean)
	if own_profile: return true
	var previous := car.get_node_or_null("DesertCarAudio")
	if previous != null:
		car.remove_child(previous)
		previous.queue_free()
	var audio := AUDIO.new()
	audio.bind(car,handling.drive)
	car.add_child(audio)
	return true

## Neon: carros de edição já nascem com o kit; qualquer carro pode ganhar um pela peça.
## O kit guarda a cor ao ser criado, então trocar de peça refaz o nó.
static func _apply_neon(car: CharacterBody3D, s: Dictionary) -> void:
	var neon = preload("res://gameplay/desert_cars/DesertCarNeon.gd")
	var existing := car.get_node_or_null("DesertCarNeon")
	var wanted: String = str(s.get("neon_color","")) if float(s.get("neon_strength",0.0)) > 0.0 else ""
	if existing != null and wanted != "" and existing.get("color") != Color(wanted):
		car.remove_child(existing)
		existing.queue_free()
	elif existing != null and wanted == "" and car.get_meta("desert_neon_from_part",false):
		car.remove_child(existing)
		existing.queue_free()
	if wanted == "": return
	var from_part: bool = not TUNING.clean_parts(s.get("installed_parts",{})).get("neon","").is_empty()
	var spec := s.duplicate(true)
	spec["size"] = s.get("size",s.get("bounds_size",[1.8,1.4,4.2]))
	car.set_meta("desert_neon_from_part",from_part)
	neon.install(car,spec)

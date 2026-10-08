extends "res://scripts/Vehicle.gd"
## Uses the shared Vehicle physics, including engine_disabled, braking and damage.
## Service collisions never accuse Dante; controlled means an occupied vehicle.
func _init() -> void:
	player_damage_attribution = false

func _wreck_expires() -> bool:
	# The convoy retires its finite fleet out of sight, including destroyed cars.
	if get_meta("armored_transport", false): return false
	return super._wreck_expires()

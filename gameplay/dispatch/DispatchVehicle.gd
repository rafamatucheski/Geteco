extends "res://scripts/Vehicle.gd"
## Uses the shared Vehicle physics, including engine_disabled, braking and damage.
## Service collisions never accuse Dante; controlled means an occupied vehicle.
func _init() -> void:
	player_damage_attribution = false

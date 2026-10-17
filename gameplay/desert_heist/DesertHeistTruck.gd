extends "res://scripts/Vehicle.gd"

func _init() -> void:
	archetype="desert_cargo_truck"
	player_damage_attribution=false

func _wreck_expires() -> bool:
	return false

func _ready() -> void:
	super._ready()
	# O teto do contêiner também é sólido; a base genérica limita altura a 3,6 m.
	var hull := shape.shape as BoxShape3D
	hull.size.y=3.8
	shape.position.y=1.9
	rotation_shape.size.y=3.65
	body_height=3.8

func door_point() -> Vector3:
	return to_global(Vector3(0,0,half_length+1.1))

func set_cargo_open(opened: bool, empty := false) -> void:
	if is_instance_valid(visual):
		preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd").set_cargo_open(visual,opened)
		preload("res://gameplay/desert_heist/DesertCargoTruckVisual.gd").set_loot_visible(visual,opened and not empty)

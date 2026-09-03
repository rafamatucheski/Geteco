class_name PoliceLoot
extends Node

## Attach to a police/NPC scene or call drop_now() from that NPC's death code.
## The component makes one deterministic roll and spawns a world WeaponPickup.

@export_range(0.0, 1.0, 0.05) var weapon_drop_chance := 0.38
@export_range(0.0, 1.0, 0.05) var armor_drop_chance := 0.12
@export var dropped_weapon: StringName = &"pistol"
@export_range(4, 60, 1) var minimum_ammo := 8
@export_range(4, 60, 1) var maximum_ammo := 20
@export var weapon_pickup_scene: PackedScene = preload("res://city_demo/scenes/pickups/WeaponPickup.tscn")
@export var armor_pickup_scene: PackedScene = preload("res://city_demo/scenes/pickups/BodyArmorPickup.tscn")

var _has_dropped := false

func drop_now(world: Node = null) -> void:
	if _has_dropped:
		return
	_has_dropped = true
	var host := world if world != null else get_tree().current_scene
	if host == null:
		return
	var origin := _owner_position()
	if randf() <= weapon_drop_chance and weapon_pickup_scene != null:
		var weapon := weapon_pickup_scene.instantiate()
		weapon.weapon_id = dropped_weapon
		weapon.ammo_amount = randi_range(minimum_ammo, maximum_ammo)
		weapon.global_position = origin + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		host.call_deferred("add_child", weapon)
	if randf() <= armor_drop_chance and armor_pickup_scene != null:
		var armor := armor_pickup_scene.instantiate()
		armor.global_position = origin + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		host.call_deferred("add_child", armor)

func _owner_position() -> Vector2:
	if owner is Node2D:
		return (owner as Node2D).global_position
	var parent := get_parent()
	if parent is Node2D:
		return (parent as Node2D).global_position
	return Vector2.ZERO

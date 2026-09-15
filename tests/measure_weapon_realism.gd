extends "res://tests/measure_city_scenarios.gd"
## Rendered production scene, same deterministic sequence before and after.
var _next_weapon_shot := 0
var _weapon_shots := 0

func _report_render() -> void:
	super._report_render()
	if not _tracking or Time.get_ticks_msec() < _next_weapon_shot: return
	_next_weapon_shot = Time.get_ticks_msec() + 140
	var ids := ["pistol", "shotgun", "ak47", "rpg", "flamethrower"]
	var id: String = ids[(_weapon_shots / 40) % ids.size()]
	if _subject.active_weapon_id != id:
		_subject.weapon_inventory[id] = true
		_subject.equip_weapon(id)
	_subject.weapon_ammo[id] = {"clip": 100, "reserve": 100}
	_subject.fire_cooldown = 0.0
	_subject._shoot_towards(_subject.global_position + Vector2(600, -160))
	_weapon_shots += 1

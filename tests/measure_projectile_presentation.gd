extends "res://tests/measure_city_scenarios.gd"
## Same production checkpoint, deterministic sustained fire, isolated saves.
var _next_shot := 0
var _shot_index := 0

func _report_render() -> void:
	super._report_render()
	if not _tracking or Time.get_ticks_msec() < _next_shot:
		return
	_next_shot = Time.get_ticks_msec() + 120
	var weapons := ["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
	var weapon: String = weapons[(_shot_index / 30) % weapons.size()]
	_subject.active_weapon_id = weapon
	_subject.weapon_ammo[weapon] = {"clip": 100, "reserve": 100}
	_subject.fire_cooldown = 0.0
	_subject._shoot_towards(_subject.global_position + Vector2(600, -160))
	_shot_index += 1

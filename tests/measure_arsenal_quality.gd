extends "res://tests/measure_city_scenarios.gd"
## Same complete arsenal sequence in the rendered production checkpoint.
const IDS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife", "bat", "axe", "knuckles"]
var _arsenal_started := 0
var _next_action := 0

func _report_render() -> void:
	super._report_render()
	if not _tracking: return
	var now := Time.get_ticks_msec()
	if _arsenal_started == 0: _arsenal_started = now
	var id: String = IDS[mini((now - _arsenal_started) / 2000, IDS.size() - 1)]
	if _subject.active_weapon_id != id:
		_subject.weapon_inventory[id] = true
		_subject.equip_weapon(id)
	if now >= _next_action:
		_next_action = now + 500
		_subject.combat_pose.on_attack(id)

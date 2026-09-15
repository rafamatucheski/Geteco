extends "res://tests/measure_city_scenarios.gd"
var _next_punch := 0
func _report_render() -> void:
	super._report_render()
	if not _tracking: return
	if _subject.active_weapon_id != "knuckles":
		_subject.weapon_inventory["knuckles"] = true
		_subject.equip_weapon("knuckles")
	var now := Time.get_ticks_msec()
	if now >= _next_punch:
		_next_punch = now + 400
		_subject.combat_pose.on_attack("knuckles")

extends "res://tests/measure_city_scenarios.gd"
var _melee_clock := 0.0
var _melee_ready := false

func _report_render() -> void:
	super._report_render()
	if not is_instance_valid(_subject): return
	if not _melee_ready:
		_melee_ready = true
		_subject.personal_loadout_enabled = false
		_subject.weapon_inventory.axe = true
		_subject.weapon_inventory.bat = true
		_subject.equip_weapon("axe")
	_melee_clock += 1.0 / 60.0
	if "--running" in OS.get_cmdline_user_args():
		Input.action_press("sprint")
		var right := int(_melee_clock) % 2 == 0
		Input.action_release("move_left" if right else "move_right")
		Input.action_press("move_right" if right else "move_left")
	var id := "axe" if int(_melee_clock / 5.0) % 2 == 0 else "bat"
	if _subject.active_weapon_id != id: _subject.equip_weapon(id)
	if _subject.combat_pose.action_age > 1.4: _subject.combat_pose.on_attack(id)

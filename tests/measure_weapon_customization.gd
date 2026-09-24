extends "res://tests/measure_city_scenarios.gd"
## Same production checkpoint, seeds and sample windows as the city baseline.
## Add --flashlight to measure the active accessory. --capture saves gameplay.
var _configured := false
func _report_render() -> void:
	super._report_render()
	if _configured or not is_instance_valid(_subject): return
	_configured = true
	_subject.personal_loadout_enabled = false
	_subject.weapon_inventory["pistol"] = true
	_subject.equip_weapon("pistol")
	if OS.get_cmdline_user_args().has("--flashlight"):
		_subject.money = 1000
		_subject.customize_weapon("pistol", "install")
		_subject.weapon_flashlight.toggle()

extends "res://tests/measure_city_scenarios.gd"
## A/B accessory cost in the rendered production scene. Both runs include
## the revised audio and RPG effects; this is not a historical VFX baseline.
const CUSTOM = preload("res://guns/WeaponCustomization.gd")
const IDS := ["pistol", "magnum", "shotgun", "ak47", "hunting_rifle", "rpg"]
var configured := false
var customized := false
var next_shot := 0
var shot_index := 0
var actual_shots := {}

func _report_render() -> void:
	super._report_render()
	if not is_instance_valid(_subject): return
	if not configured:
		configured = true
		customized = OS.get_cmdline_user_args().has("--customized")
		_subject.personal_loadout_enabled = false
		_subject.money = 1000000
		for id in IDS:
			_subject.weapon_inventory[id] = true
			if customized:
				for part in ["flashlight", "laser_green", "suppressor", "extended", "vertical_grip", "stabilized_stock", "scope_2x", "sand"]:
					if CUSTOM.supports(id,part): _subject.customize_weapon_part(id,CUSTOM.PARTS[part].slot,part)
		root.get_node("GameInput").touch_aim = Vector2(600,-160).normalized()
		Input.action_press("aim")
	if not _tracking or Time.get_ticks_msec() < next_shot: return
	next_shot = Time.get_ticks_msec()+500
	var id: String = IDS[(shot_index / 10) % IDS.size()]
	if _subject.active_weapon_id != id:
		_subject.equip_weapon(id)
		if customized and CUSTOM.installed(_subject.weapon_customization,id):
			_subject.weapon_flashlight.toggle()
	_subject.weapon_ammo[id] = {"clip":100,"reserve":100}
	_subject.fire_cooldown = 0.0
	_subject._shoot_towards(_subject.global_position+Vector2(600,-160))
	if int(_subject.weapon_ammo[id].clip) < 100: actual_shots[id] = int(actual_shots.get(id,0))+1
	shot_index += 1

func _sample(output: String, label: String, seconds: float, car: Node2D) -> void:
	await super._sample(output,label,seconds,car)
	if _sample_failed: return
	var path := output.path_join(label+".json")
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	report["customized"] = customized
	report["actual_shots"] = actual_shots
	report["comparison_scope"] = "Accessory A/B; revised RPG/audio present in both"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if label != "warmup":
		Input.action_release("aim")
		if actual_shots.size() != IDS.size():
			_sample_failed = true
			push_error("Not every weapon fired during the production sample")

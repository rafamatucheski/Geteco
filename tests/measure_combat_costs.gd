extends "res://tests/measure_city_scenarios.gd"
var cost_file: FileAccess
func _report_render() -> void:
	if cost_file == null:
		var folder := "D:/geteco/artifacts/combat-60fps-0912/profile"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("out_dir="): folder = arg.trim_prefix("out_dir=")
		cost_file = FileAccess.open(folder.path_join("costs.jsonl"), FileAccess.WRITE)
	cost_file.store_line(JSON.stringify(preload("res://tests/CombatCostProbe.gd").take()))
	super._report_render()

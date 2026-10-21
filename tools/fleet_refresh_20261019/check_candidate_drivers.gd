extends "res://tests/test_seated_driver.gd"
## Run the existing complete driver/hand/exit contracts against candidate scenes
## without installing them or changing the production catalog on disk.
func _initialize() -> void:
	for id: String in preload("res://tools/fleet_refresh_20261019/build_current.gd").FAMILIES:
		preload("res://runtime/RedesignedFleet.gd")._scenes[id]=load("res://artifacts/car-fleet-implementation-20261019/candidates/"+id+".scn")
	super._initialize()

func selected_ids() -> Array:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): return Array(arg.trim_prefix("--ids=").split(","))
	return preload("res://tools/fleet_refresh_20261019/build_current.gd").FAMILIES.keys()

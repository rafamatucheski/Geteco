extends "res://tests/test_seated_driver_flow.gd"
## Same production boarding/driving/exit flow, with a process-local model A/B.
## --baseline selects legacy models without changing the saved fleet or files.
func _initialize() -> void:
	preload("res://runtime/RedesignedFleet.gd").enabled = not "--baseline" in OS.get_cmdline_user_args()
	print("REDESIGNED_FLOW baseline=", not preload("res://runtime/RedesignedFleet.gd").enabled)
	super._initialize()

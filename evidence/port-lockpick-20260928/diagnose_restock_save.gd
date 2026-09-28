extends SceneTree
func _initialize() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://evidence/port-lockpick-20260928/restock-save.json.tmp"))
	print("CARGO_JSON ",preload("res://gameplay/urban_v1/PortContainerState.gd").validate_snapshot(data.world.port_containers))
	print("WALLET_JSON ",preload("res://systems/economy/Economy.gd").validate_snapshot(data.economy))
	var state = load("res://runtime/GameState.gd").new()
	var valid: bool = state.restore_snapshot(data)
	print("FULL_JSON ",valid)
	if valid:
		quit()
		return
	for key in data.world.keys():
		var probe: Dictionary = data.duplicate(true)
		probe.world.erase(key)
		if state.restore_snapshot(probe): print("INVALID_WORLD_KEY ",key," ",data.world[key])
	quit()

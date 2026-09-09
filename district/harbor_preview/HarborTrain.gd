extends "res://district/rail/AmbientTrain.gd"

## Independent per-piece tunnel clipping. Parent visibility never changes,
## since that would hide wagons still outside alongside a buried locomotive.
func _update_pose() -> void:
	super._update_pose()
	if not is_instance_valid(_rail_line):
		return
	var state: Dictionary = _rail_line.get_track_state_at_offset(_progress)
	self_modulate.a = float(state.opacity)
	z_as_relative = false
	z_index = int(state.z_index)
	for index in _freight_visuals.size():
		var wagon_state: Dictionary = _rail_line.get_track_state_at_offset(_wagon_offset(index))
		var wagon := _freight_visuals[index]
		wagon.self_modulate.a = float(wagon_state.opacity)
		wagon.z_as_relative = false
		wagon.z_index = int(wagon_state.z_index)
	if is_instance_valid(_train_audio):
		_train_audio.volume_db = -17.0 if bool(state.above_ground) else -60.0


func _wagon_offset(index: int) -> float:
	return fposmod(_progress - ENGINE_LENGTH * 0.5 - WAGON_LENGTH * 0.5 - COUPLER_GAP - float(index) * WAGON_STEP, maxf(1.0, _route_length))


func get_rail_state() -> Dictionary:
	var result := super.get_rail_state()
	var pieces: Array[Dictionary] = []
	if is_instance_valid(_rail_line):
		pieces.append(_rail_line.get_track_state_at_offset(_progress))
		for index in _freight_visuals.size():
			pieces.append(_rail_line.get_track_state_at_offset(_wagon_offset(index)))
	result["pieces"] = pieces
	result["locomotive_opacity"] = self_modulate.a
	return result

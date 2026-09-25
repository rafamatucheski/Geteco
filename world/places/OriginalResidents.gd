extends RefCounted
static var _source: Array = []
static func for_place(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _source.is_empty():
		_source = JSON.parse_string(FileAccess.get_file_as_string("res://world/places/OriginalResidentData.json"))
	for record in _source:
		if record.place_id != id: continue
		# The catalog asks once per place; parse once, but never share mutable
		# appearance/dialogue records between separate room instances.
		var item: Dictionary = record.duplicate(true)
		item["local_position"] = Vector3(item.position[0],item.position[1],item.position[2])
		item["source_position"] = item.local_position
		item["dialogue_id"] = item.id
		for key in item.appearance:
			if str(key).ends_with("_color"): item.appearance[key] = Color(item.appearance[key])
		result.append(item)
	return result
static func create_model(definition: Dictionary) -> Node3D:
	var model = load(definition.model).new()
	for key in definition.appearance: model.set(key,definition.appearance[key])
	model.character_name = definition.name
	return model

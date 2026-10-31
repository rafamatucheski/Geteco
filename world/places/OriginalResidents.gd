extends RefCounted
static var _source: Array = []
static func for_place(id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# As lojas da montanha têm o próprio atendente, posto no corredor de funcionários
	# atrás do balcão. Mantém o catálogo de atendimento original fora deste escopo.
	var shops := {
		"mountain_outfitters": ["Nina", -4.1, Color("426777"), true],
		"mountain_boutique": ["Clara", 4.1, Color("87947d"), true],
		"mountain_village_outfitters": ["Bento", 0.0, Color("995344"), false],
	}
	if shops.has(id):
		var shop: Array = shops[id]
		result.append({"id": id + "_attendant", "name": shop[0], "place_id": id,
			"model": "res://world/places/MountainShopResidentModel.gd",
			"appearance": {"coat_color": shop[2], "pants_color": Color("303b42"), "is_female": shop[3], "winter": true},
			"local_position": Vector3(shop[1], 0, -3.85), "dialogue_id": id + "_attendant"})
		return result
	if _source.is_empty():
		_source = JSON.parse_string(FileAccess.get_file_as_string("res://world/places/OriginalResidentData.json"))
	for record in _source:
		if record.place_id != id: continue
		# O catálogo pergunta uma vez por lugar; interpreta uma vez, mas nunca divide registros
		# mutáveis de aparência/diálogo entre instâncias de cômodo separadas.
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

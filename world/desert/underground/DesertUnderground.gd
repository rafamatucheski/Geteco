extends RefCounted
## Entradas subterrâneas do deserto: o equivalente dos bueiros da cidade, mas de deserto. Coordenadas em metros do
## mundo do deserto (sem pixels de origem). Todas ficam em chão plano e livre (conferido com `_decoration_clear`).
## `descent` diz à `SewerHatchDescent` como o Dante entra: "ladder" (escada vertical sob uma tampa) ou "walk"
## (anda para dentro, descendo `drop` ao longo de `length`).
const ROOT := "res://world/desert/underground/"
const SITES := [
	{"id": "desert_under_culvert", "name": "Galeria da Rodovia", "exterior": Vector3(-500,0,-887), "kind": "culvert",
		"size": Vector2(40, 10), "model": "DesertCulvertGallery", "spawn": Vector3(-17.0, 0, 0),
		"descent": {"style": "walk", "length": 3.4, "drop": 0.0, "approach": 2.2, "doors": true}},
	{"id": "desert_under_well", "name": "Poço de Santa Lua", "exterior": Vector3(-470,0,-460), "kind": "well",
		"size": Vector2(20, 20), "model": "DesertMoonWell", "spawn": Vector3(-6.2, 0, -5.8),
		"descent": {"style": "ladder"}},
	{"id": "desert_under_cellar", "name": "Adega do Horizonte", "exterior": Vector3(-322,0,-594), "kind": "cellar",
		"size": Vector2(22, 13), "model": "DesertMotelCellar", "spawn": Vector3(-8.2, 0, -3.2),
		"descent": {"style": "walk", "length": 2.8, "drop": 2.0, "approach": 2.4, "doors": true}},
	{"id": "desert_under_mine", "name": "Poço 3 da Serra Bruta", "exterior": Vector3(-350,0,-1020), "kind": "vent",
		"size": Vector2(32, 18), "model": "DesertMineVent", "spawn": Vector3(-13.6, 0, -6.4),
		"descent": {"style": "ladder"}},
]

static func ids() -> Array[String]:
	var list: Array[String] = []
	for site_data in SITES: list.append(site_data.id)
	return list

static func is_underground(id: String) -> bool:
	for site_data in SITES:
		if site_data.id == id: return true
	return false

static func site(id: String) -> Dictionary:
	for entry in SITES:
		if entry.id == id: return entry
	return {}

## Definições no formato do `PlaceCatalog` (região "desert"), com recompensas e moradores já preenchidos.
static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in SITES:
		var script = load(ROOT + entry.model + ".gd")
		var exterior: Vector3 = entry.exterior
		var size: Vector2 = entry.size
		# Escada/poço: entra-se por cima da tampa; galeria e adega: pela frente (sul) da boca.
		var entrance: Vector3 = exterior if str(entry.descent.style) == "ladder" else exterior + Vector3(0, 0, float(entry.descent.approach))
		var rewards: Array = []
		for item in script.REWARDS: rewards.append(item.duplicate(true))
		var residents: Array = []
		for resident in script.RESIDENTS:
			var record: Dictionary = resident.duplicate(true)
			record["model"] = "res://world/places/sewers/SewerHomelessModel.gd"
			record["place_id"] = entry.id
			record["dialogue_id"] = resident.id
			residents.append(record)
		result.append({"id": entry.id, "original_name": entry.name, "region": "desert", "model": ROOT + entry.model + ".gd", "source_id": ROOT + entry.model + ".gd",
			"exterior_position": exterior, "entry_position": entrance, "return_position": entrance + Vector3(0, 0, 1.2),
			"spawn": entry.spawn, "exit": entry.spawn, "camera_target": Vector3(0, 0.7, 0),
			"camera_size": maxf(size.x * 0.82, size.y * 1.25), "size": size, "variant": 0, "service": "desert_underground",
			"reward": rewards[0].duplicate(true) if not rewards.is_empty() else {}, "rewards": rewards, "npcs": residents, "resident_talk": true,
			"npc_model": "", "npc_point": Vector3.ZERO, "integration_status": "native_geometry_pending_validation"})
		if entry.id == "desert_under_culvert":
			result[-1].exit = Vector3(-19.0, 0, 0)
			result[-1].camera_size = 13.5
			result[-1].camera_target = Vector3(-12.0, .7, 0)
		load("res://world/editing/WorldManholes.gd").update_definition(result[-1])
	return result

## Registros para o `DesertRegion` (uma entrada por chunk que contém a estrutura externa).
static func records() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var editing = load("res://world/editing/WorldManholes.gd")
	for entry in SITES:
		var at: Vector2 = editing.position_of(entry.id)
		list.append({"kind": "desert_underground", "position": Vector3(at.x, entry.exterior.y, at.y), "rotation": float(editing.rotation_of(entry.id)), "data": entry})
	return list

static func build_record(chunk: Node3D, record: Dictionary) -> void:
	var exterior := preload("res://world/desert/underground/DesertUndergroundExterior.gd").new()
	exterior.setup(record.data)
	exterior.position = record.position
	exterior.rotation.y = float(record.get("rotation", 0.0))
	chunk.add_child(exterior)

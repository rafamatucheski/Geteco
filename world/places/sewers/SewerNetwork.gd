extends RefCounted
## Bueiros de Harbor. O primeiro (`harbor_sewer`, Esgoto) é o da V1; os outros seguem o mesmo padrão:
## tampa deslizante na calçada, descida pela escada, sala própria com recompensas e moradores.
## Posições em pixels de origem (16 px = 1 m), na calçada ao lado de uma via de `OriginalWorldData.json`,
## longe de prédios e do resto dos pontos de acesso.
const PLACES_ROOT := "res://world/places/sewers/"
const ORIGINAL_ID := "harbor_sewer"
const OPENING_SIZE := 18.0

## `size` = sala em metros (centrada na origem); `spawn` = pé da escada (também a saída).
const SITES := [
	{"id": "sewer_market", "name": "Beco do Mercado", "point": Vector2(1650, 1160), "size": Vector2(16, 10),
		"model": "SewerMarketDrain", "spawn": Vector3(-6.2, 0, -2.0)},
	{"id": "sewer_quay", "name": "Dreno do Cais", "point": Vector2(3090, 1800), "size": Vector2(18, 11),
		"model": "SewerQuayDrain", "spawn": Vector3(-7.2, 0, -3.3)},
	{"id": "sewer_warehouse", "name": "Galeria do Armazém", "point": Vector2(2500, 2290), "size": Vector2(24, 14),
		"model": "SewerWarehouseGallery", "spawn": Vector3(-9.6, 0, -4.6)},
	{"id": "sewer_pipe", "name": "Cano Entupido", "point": Vector2(1500, 2032), "size": Vector2(10, 7),
		"model": "SewerPipeClog", "spawn": Vector3(-3.2, 0, -1.5)},
	{"id": "sewer_cistern", "name": "Cisterna Velha", "point": Vector2(5300, 1160), "size": Vector2(44, 26),
		"model": "SewerCisternHall", "spawn": Vector3(-19.5, 0, -10.7)},
	{"id": "sewer_port", "name": "Dreno do Porto", "point": Vector2(3230, 3000), "size": Vector2(32, 20),
		"model": "SewerPortCache", "spawn": Vector3(-12.6, 0, -7.0)},
]

static func extra_ids() -> Array[String]:
	var site_ids: Array[String] = []
	for site_data in SITES: site_ids.append(site_data.id)
	return site_ids

static func ids() -> Array[String]:
	var all: Array[String] = [ORIGINAL_ID]
	all.append_array(extra_ids())
	return all

static func is_manhole(id: String) -> bool:
	return id == ORIGINAL_ID or is_extra(id) or preload("res://world/desert/underground/DesertUnderground.gd").is_underground(id)

static func is_extra(id: String) -> bool:
	for site_data in SITES:
		if site_data.id == id: return true
	return false

static func site(id: String) -> Dictionary:
	for entry in SITES:
		if entry.id == id: return entry
	return {}

## Recortes da calçada/rua em pixels de origem (o do Esgoto original mais os novos).
static func openings(original: Rect2) -> Array[Rect2]:
	var list: Array[Rect2] = [original]
	for entry in SITES:
		list.append(Rect2(entry.point - Vector2.ONE * OPENING_SIZE * 0.5, Vector2.ONE * OPENING_SIZE))
	return list

## Linhas no formato de `PlaceCatalog.definitions()`.
static func rows() -> Array:
	var result: Array = []
	for entry in SITES:
		result.append([entry.id, entry.name, "harbor", entry.point, "@sewers/" + entry.model, entry.size, 0.0, 0.0, "sewer"])
	return result

## Completa a definição (recompensas, moradores, câmera) depois que o catálogo montou o básico.
static func decorate(definition: Dictionary) -> void:
	var entry := site(str(definition.id))
	if entry.is_empty(): return
	definition.spawn = entry.spawn
	definition.exit = entry.spawn
	var model = load(PLACES_ROOT + entry.model + ".gd")
	var rewards: Array = []
	for item in model.REWARDS: rewards.append(item.duplicate(true))
	definition["rewards"] = rewards
	definition["reward"] = rewards[0].duplicate(true) if not rewards.is_empty() else {}
	var residents: Array = []
	for resident in model.RESIDENTS:
		var record: Dictionary = resident.duplicate(true)
		record["model"] = PLACES_ROOT + "SewerHomelessModel.gd"
		record["place_id"] = definition.id
		record["dialogue_id"] = resident.id
		residents.append(record)
	definition["npcs"] = residents
	definition.camera_target = Vector3(0, 0.7, 0)

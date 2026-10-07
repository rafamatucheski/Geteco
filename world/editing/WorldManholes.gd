@tool
extends RefCounted
## Bueiros e entradas subterrâneas (Harbor e deserto) no editor do mundo. Cada um vira uma linha "manhole/<id>" que
## move e gira a estrutura externa (tampa, poço, alçapão, boca da galeria) e leva junto o ponto de acesso, o ponto de
## volta e o recorte da calçada. A sala de dentro não muda: a edição só mexe no lado de fora.
## A leitura segue `WorldServiceBuildings`: o documento ao vivo do editor (meta) ou o `world_edits.json` do disco.
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const UNDER := preload("res://world/desert/underground/DesertUnderground.gd")
const PATH := "res://world/editing/world_edits.json"
const ORIGINAL_BASE := Vector2(1182.0, 2114.0) / 16.0
const ORIGINAL_NAME := "Esgoto"
static var _disk_stamp := -1
static var _disk_document: Dictionary = {}

static func region_of(id: String) -> String:
	return "desert" if UNDER.is_underground(id) else "harbor"

static func ids(region_id: String) -> Array[String]:
	if region_id == "desert": return UNDER.ids()
	if region_id == "harbor": return SEWERS.ids()
	return []

static func is_editable(id: String) -> bool:
	return SEWERS.is_manhole(id)

static func label(id: String) -> String:
	if id == SEWERS.ORIGINAL_ID: return ORIGINAL_NAME
	var site: Dictionary = SEWERS.site(id) if SEWERS.is_extra(id) else UNDER.site(id)
	return str(site.get("name", id))

## Posição original, em metros (x, z).
static func base_position(id: String) -> Vector2:
	if id == SEWERS.ORIGINAL_ID: return ORIGINAL_BASE
	if SEWERS.is_extra(id): return SEWERS.site(id).point / 16.0
	var exterior: Vector3 = UNDER.site(id).exterior
	return Vector2(exterior.x, exterior.z)

static func changes(region_id: String) -> Dictionary:
	if Engine.has_meta("geteco_world_edit_document"): return Engine.get_meta("geteco_world_edit_document").get("regions", {}).get(region_id, {})
	var stamp := FileAccess.get_modified_time(PATH)
	if stamp != _disk_stamp:
		_disk_stamp = stamp
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else {}
		_disk_document = parsed if parsed is Dictionary else {}
	return _disk_document.get("regions", {}).get(region_id, {})

static func row_for(id: String) -> Dictionary:
	var row: Variant = changes(region_of(id)).get("manhole/" + id, {})
	return row if row is Dictionary and not row.get("deleted", false) else {}

## Posição atual (editada ou original), em metros.
static func position_of(id: String) -> Vector2:
	var row := row_for(id)
	if row.has("position"): return Vector2(float(row.position[0]), float(row.position[1]))
	return base_position(id)

static func rotation_of(id: String) -> float:
	return deg_to_rad(float(row_for(id).get("rotation", 0.0)))

## Linhas do catálogo do editor para a região.
static func catalog(region_id: String) -> Dictionary:
	var result := {}
	for id in ids(region_id):
		var key := "manhole/" + id
		var base := base_position(id)
		result[key] = {"id": key, "type": "manhole", "place_id": id, "label": label(id), "position": [base.x, base.y], "rotation": 0.0, "locked": false}
		if region_id == "desert": result[key]["editor_region"] = "desert"
	return result

## Leva a estrutura externa e os pontos de acesso do lugar para a posição/rotação editadas.
static func update_definition(definition: Dictionary) -> void:
	var id := str(definition.get("id", ""))
	if not is_editable(id): return
	var row := row_for(id)
	if row.is_empty() or not row.has("position"): return
	var base: Vector3 = definition.exterior_position
	var destination := Vector3(float(row.position[0]), base.y, float(row.position[1]))
	var turn := deg_to_rad(float(row.get("rotation", 0.0)))
	var basis := Basis(Vector3.UP, turn)
	definition.editor_base_exterior = base
	definition.editor_rotation = turn
	for key in ["exterior_position", "entry_position", "return_position"]:
		if definition.has(key): definition[key] = destination + basis * (definition[key] - base)

## Recortes da calçada/rua em pixels de origem, onde a estrutura está agora (Harbor).
static func harbor_openings() -> Array[Rect2]:
	var list: Array[Rect2] = []
	for id in SEWERS.ids():
		var center := position_of(id) * 16.0
		list.append(Rect2(center - Vector2.ONE * SEWERS.OPENING_SIZE * 0.5, Vector2.ONE * SEWERS.OPENING_SIZE))
	return list

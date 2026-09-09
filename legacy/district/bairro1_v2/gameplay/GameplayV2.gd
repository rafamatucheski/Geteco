class_name Bairro1V2Gameplay
extends Node2D

## Registro de conteúdo do vertical slice. As atividades e pistas ficam em
## dados estáveis para que roteiro, UI e missões possam consumi-los sem criar
## novas coordenadas fixas. A posição vem dos marcadores do LayoutV2.

signal clue_discovered(clue_id: StringName)
signal activity_started(activity_id: StringName)

const ACTIVITIES := {
	&"market_delivery": {
		"title": "Entrega do mercado",
		"anchor": &"MarketEntrance",
		"loop": "Levar uma encomenda curta pelo eixo comercial.",
	},
	&"park_match": {
		"title": "Pelada no parque",
		"anchor": &"ParkEntrance",
		"loop": "Participar de uma atividade social e ouvir um rumor.",
	},
	&"garage_favor": {
		"title": "Favor na oficina",
		"anchor": &"GarageEntrance",
		"loop": "Recuperar uma peça pelo beco e retornar à oficina.",
	},
}

const CLUES := {
	&"park_shortcut": {"anchor": &"ParkEntrance", "hint": "Um entregador fala de um atalho pelo parque."},
	&"football_witness": {"anchor": &"ParkEntrance", "hint": "Jogadores viram uma discussão perto da quadra."},
	&"mural_code": {"anchor": &"MarketEntrance", "hint": "O mural do beco esconde uma marca repetida."},
	&"market_missing_goods": {"anchor": &"MarketEntrance", "hint": "Feirantes comentam sobre caixas desaparecidas."},
	&"terminal_schedule": {"anchor": &"TerminalStop", "hint": "A fila do ônibus sabe quando alguém passou."},
	&"laundromat_rumor": {"anchor": &"MarketEntrance", "hint": "A lavanderia é o ponto de fofoca do bairro."},
	&"viaduct_watch": {"anchor": &"PortApproach", "hint": "O viaduto oferece uma boa rota de observação."},
	&"canal_fisher": {"anchor": &"PortApproach", "hint": "Um pescador conhece o passado do galpão."},
	&"rail_underpass": {"anchor": &"RailUnderpass", "hint": "A passagem sob a ferrovia evita a avenida."},
	&"warehouse_loading": {"anchor": &"WarehouseEntrance", "hint": "Há uma carga fora de hora no galpão."},
}

var _discovered_clues: Dictionary = {}
var _active_activity: StringName = &""
var _pending_anchors: Dictionary = {}


func _ready() -> void:
	_build_content_markers()
	call_deferred("_resolve_content_positions")


func get_activity(activity_id: StringName) -> Dictionary:
	return ACTIVITIES.get(activity_id, {}).duplicate(true)


func get_activity_count() -> int:
	return ACTIVITIES.size()


func get_clue_count() -> int:
	return CLUES.size()


func get_clue(clue_id: StringName) -> Dictionary:
	var clue: Dictionary = CLUES.get(clue_id, {})
	if clue.is_empty():
		return {}
	var result := clue.duplicate(true)
	result["discovered"] = _discovered_clues.has(clue_id)
	return result


func get_discovered_clue_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for clue_id: StringName in _discovered_clues:
		ids.append(String(clue_id))
	return ids


func discover_clue(clue_id: StringName) -> bool:
	if not CLUES.has(clue_id) or _discovered_clues.has(clue_id):
		return false
	_discovered_clues[clue_id] = true
	clue_discovered.emit(clue_id)
	return true


func start_activity(activity_id: StringName) -> bool:
	if not ACTIVITIES.has(activity_id):
		return false
	_active_activity = activity_id
	activity_started.emit(activity_id)
	return true


func get_active_activity() -> StringName:
	return _active_activity


func _build_content_markers() -> void:
	for activity_id: StringName in ACTIVITIES:
		var definition: Dictionary = ACTIVITIES[activity_id]
		_create_content_marker("Activity_" + String(activity_id).to_pascal_case(), activity_id, definition["anchor"] as StringName, "activity")
	for clue_id: StringName in CLUES:
		var definition: Dictionary = CLUES[clue_id]
		_create_content_marker("Clue_" + String(clue_id).to_pascal_case(), clue_id, definition["anchor"] as StringName, "clue")


func _create_content_marker(node_name: String, content_id: StringName, anchor_name: StringName, content_type: String) -> void:
	var marker := Marker2D.new()
	marker.name = node_name
	marker.add_to_group("bairro1_v2_" + content_type)
	marker.set_meta("content_id", content_id)
	marker.set_meta("anchor_name", anchor_name)
	add_child(marker)
	_pending_anchors[marker.get_instance_id()] = anchor_name


func _resolve_content_positions() -> void:
	var district_root := get_parent()
	if district_root == null or not district_root.has_method("get_marker"):
		return
	for child in get_children():
		var marker := child as Marker2D
		if marker == null or not marker.has_meta("anchor_name"):
			continue
		var anchor := district_root.call("get_marker", marker.get_meta("anchor_name")) as Marker2D
		if anchor != null:
			marker.global_position = anchor.global_position

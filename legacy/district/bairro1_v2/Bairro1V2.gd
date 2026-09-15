@tool
class_name Bairro1V2
extends Node2D

## Raiz de integração do Bairro 1 V2.
##
## Esta cena não substitui o distrito legado por conta própria. Ela monta os
## módulos novos quando estiverem disponíveis, mantendo o porto como uma
## dependência estável. Assim Claude e Antigravity podem trabalhar em cenas
## independentes sem editar esta raiz.

const PORT_SCENE_PATH := "res://missions/district_one/PortMarkedCarSet.tscn"
const RAIL_SCENE_PATH := "res://geodata/rail/DistrictRailLine.tscn"
const HIGHWAY_SCENE_PATH := "res://legacy/district/highway/District1HighwayExit.tscn"
const PORT_POSITION := Vector2(3340, 2150)
## Entrada oeste do porto, no mesmo Y da guarita. O LayoutV2 mantém suas
## próprias coordenadas; só esta raiz conhece o encaixe físico do módulo.
const PORT_ACCESS_POSITION := PORT_POSITION + Vector2(0, 320)
const LAYOUT_PORT_APPROACH_LOCAL := Vector2(1260, 365)
const LAYOUT_POSITION := PORT_ACCESS_POSITION - LAYOUT_PORT_APPROACH_LOCAL
const ROAD_RENDER_LAYER := 0
const PORT_RENDER_LAYER := 2
const LANDMARK_RENDER_LAYER := 4
const GAMEPLAY_RENDER_LAYER := 8

const CONTRIBUTOR_MODULES := [
	{"node_name": &"LayoutV2", "scene_path": "res://legacy/district/bairro1_v2/layout/LayoutV2.tscn", "position": LAYOUT_POSITION},
	{"node_name": &"LandmarksV2", "scene_path": "res://legacy/district/bairro1_v2/landmarks/LandmarksV2.tscn"},
]
const GAMEPLAY_MODULE := {"node_name": &"GameplayV2", "scene_path": "res://legacy/district/bairro1_v2/gameplay/GameplayV2.tscn"}

## Só ativar após Claude e Antigravity entregarem cenas que passam no teste
## individual. Isso impede que trabalho em andamento quebre o preview V2.
@export var load_contributor_modules := false
## Layout pode ser revisado independentemente. Landmarks só são ligados após
## passarem no gate visual da planta correspondente.
@export var load_landmarks_module := false
@export var include_existing_infrastructure := false
@export var log_missing_optional_modules := false

var _missing_modules: PackedStringArray = []


func _ready() -> void:
	_ensure_module(GAMEPLAY_MODULE)
	if load_contributor_modules:
		_ensure_contributor_modules()
	_ensure_port()
	if include_existing_infrastructure:
		_ensure_existing_infrastructure()
	call_deferred("_apply_presentation_contract")
	if not Engine.is_editor_hint():
		add_to_group("district_one_v2")
		call_deferred("_validate_composition")


func get_marker(marker_name: StringName) -> Marker2D:
	var marker := find_child(String(marker_name), true, false)
	return marker as Marker2D


func get_missing_modules() -> PackedStringArray:
	return _missing_modules.duplicate()


func _ensure_contributor_modules() -> void:
	_missing_modules.clear()
	for module: Dictionary in CONTRIBUTOR_MODULES:
		if module["node_name"] == &"LandmarksV2" and not load_landmarks_module:
			continue
		_ensure_module(module)


func _ensure_module(module: Dictionary) -> void:
	var node_name := module["node_name"] as StringName
	if get_node_or_null(NodePath(node_name)) != null:
		return
	var scene_path := String(module["scene_path"])
	if not ResourceLoader.exists(scene_path):
		_missing_modules.append(scene_path)
		if log_missing_optional_modules:
			push_warning("Bairro1V2: optional module is not available yet: %s" % scene_path)
		return
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Bairro1V2: could not load module: %s" % scene_path)
		return
	var module_instance := packed_scene.instantiate()
	module_instance.name = node_name
	if module.has("position") and module_instance is Node2D:
		(module_instance as Node2D).position = module["position"] as Vector2
	add_child(module_instance)


func _ensure_port() -> void:
	if get_node_or_null("PortMarkedCarSet") != null:
		return
	var port_scene := load(PORT_SCENE_PATH) as PackedScene
	if port_scene == null:
		push_error("Bairro1V2: preserved port scene is unavailable")
		return
	var port := port_scene.instantiate()
	port.name = "PortMarkedCarSet"
	port.position = PORT_POSITION
	add_child(port)


func _ensure_existing_infrastructure() -> void:
	_ensure_scene("DistrictRailLine", RAIL_SCENE_PATH)
	_ensure_scene("District1HighwayExit", HIGHWAY_SCENE_PATH)


func _ensure_scene(node_name: StringName, scene_path: String) -> void:
	if get_node_or_null(NodePath(node_name)) != null:
		return
	if not ResourceLoader.exists(scene_path):
		push_warning("Bairro1V2: infrastructure scene is unavailable: %s" % scene_path)
		return
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Bairro1V2: could not load infrastructure: %s" % scene_path)
		return
	var instance := packed_scene.instantiate()
	instance.name = node_name
	add_child(instance)


## Contrato de apresentação do modo normal. A geometria e as curvas de rota
## seguem ativas para tráfego, mas Path2D não deve poluir a imagem do jogador.
## A ferramenta de editor ainda pode mostrar gizmos quando selecionada; isso
## não é conteúdo renderizado do jogo.
func _apply_presentation_contract() -> void:
	var layout := get_node_or_null("LayoutV2") as Node2D
	if layout != null:
		layout.z_index = ROAD_RENDER_LAYER
		var road_network := layout.get_node_or_null("RoadNetwork") as Node2D
		if road_network != null:
			road_network.z_index = ROAD_RENDER_LAYER
			road_network.set("show_junction_debug", false)
			for route_path in road_network.find_children("", "Path2D", true, false):
				(route_path as CanvasItem).visible = false
	var port := get_node_or_null("PortMarkedCarSet") as Node2D
	if port != null:
		port.z_index = PORT_RENDER_LAYER
	var landmarks := get_node_or_null("LandmarksV2") as Node2D
	if landmarks != null:
		landmarks.z_index = LANDMARK_RENDER_LAYER
	var gameplay := get_node_or_null("GameplayV2") as Node2D
	if gameplay != null:
		gameplay.z_index = GAMEPLAY_RENDER_LAYER


func _validate_composition() -> void:
	assert(get_node_or_null("PortMarkedCarSet") != null, "Bairro1V2 must preserve PortMarkedCarSet")
	assert(get_node_or_null("GameplayV2") != null, "Bairro1V2 gameplay module is missing")

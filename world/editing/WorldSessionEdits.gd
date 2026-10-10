extends Node
## Lugares montados pela sessão (Vértice, Posto do Tonico, Torque, portão norte, descida, saída do
## forte...), fora das regiões. O jogo os cria onde precisa; este nó só observa a árvore e, quando
## um deles aparece, transforma o que ele construiu em peças (`WorldUnits`) e aplica o documento.
## Só é instalado quando o documento tem linhas desses lugares: sem edição, custo zero.
const UNITS := preload("res://world/editing/WorldUnits.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
## script do lugar -> [região, chave estável]
const PLACES := {
	"res://gameplay/urban_v1/VerticeCompany.gd": ["harbor", "vertice"],
	"res://gameplay/urban_v1/FreightOutskirts.gd": ["harbor", "woodland"],
	"res://gameplay/urban_v1/TruckersVillageVisuals.gd": ["harbor", "truckers_village"],
	"res://world/places/classic_meet/ClassicMeetSite.gd": ["harbor", "torque"],
	"res://world/north_gateway/NorthGatewayScenery.gd": ["harbor", "north_gateway"],
	"res://world/regions/WorldConnection3D.gd": ["harbor", "connection"],
	"res://activities/mountain_downhill/MountainDownhillProps.gd": ["mountain", "downhill"],
	"res://gameplay/urban_v1/fort/MountainFortExit3D.gd": ["mountain", "fort_exit"],
}
## Quadros depois de o nó entrar na árvore em que se tenta de novo (construtores fatiados).
const PASSES := [3, 90, 400]
var changes: Dictionary = {}
var watched: Array[Dictionary] = []

## Devolve o nó pronto ou null se o documento não mexe em nenhum lugar de sessão.
static func install(tree: SceneTree, parent: Node, document: Dictionary) -> Node:
	var rows := {}
	for area in document.get("regions", {}):
		for id in document.regions[area]:
			if str(id).begins_with(UNITS.PREFIX + area + "/s_") or str(id).begins_with(UNITS.PREFIX + area + "/session_"): rows[id] = document.regions[area][id]
	if rows.is_empty(): return null
	var watcher: Node = load("res://world/editing/WorldSessionEdits.gd").new()
	watcher.name = "WorldSessionEdits"
	watcher.changes = rows
	parent.add_child(watcher)
	tree.node_added.connect(watcher._node_added)
	# O que já está na árvore (lugar criado antes do documento ser lido).
	for node in tree.root.find_children("*", "Node3D", true, false): watcher._node_added(node)
	return watcher

static func place_of(node: Node) -> Array:
	var script: Script = node.get_script()
	while script != null:
		if PLACES.has(script.resource_path): return PLACES[script.resource_path]
		script = script.get_base_script()
	return []

func _node_added(node: Node) -> void:
	if not node is Node3D or place_of(node).is_empty(): return
	for entry in watched:
		if entry.node == node: return
	watched.append({"node": node, "frame": Engine.get_process_frames(), "pass": 0})
	set_process(true)

func _process(_delta: float) -> void:
	for index in range(watched.size() - 1, -1, -1):
		var entry: Dictionary = watched[index]
		if not is_instance_valid(entry.node):
			watched.remove_at(index)
			continue
		if Engine.get_process_frames() - int(entry.frame) < PASSES[int(entry["pass"])]: continue
		var place := place_of(entry.node)
		UNITS.finalize_session(entry.node, str(place[0]), str(place[1]), changes, Callable())
		entry["pass"] = int(entry["pass"]) + 1
		if int(entry["pass"]) >= PASSES.size(): watched.remove_at(index)
	if watched.is_empty(): set_process(false)

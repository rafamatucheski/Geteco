extends RefCounted
## Posição NaN/infinita que chegaria a geometria transparente (crash de 29/10).
##
## Três partidas livres crasharam com c0000005 em GetecoV2.exe+0x279942d: RenderForwardClustered::_render_scene,
## ordenação da lista alfa por prioridade e profundidade. O minidump do .NET mostrou o laço 16 posições antes do
## começo do vetor comparando a prioridade 0x7f (render_priority -1 + 128): só sangue no chão, rastro de sangue e
## decal de chão do CityLook usam -1. Profundidade NaN deixa a comparação incoerente, a inserção sem guarda sai do
## vetor e o release lê lixo; no binário de depuração o motor recusaria a transformação. O sangue não gera NaN
## sozinho, copia a posição de quem sangra: quem chama descarta a marca e este registro diz de onde veio.
## Nas duas primeiras partidas o crash veio depois de 11–12 s sem quadro, coerente com um corpo de física em NaN.
const MAX_REPORTS := 6
const SCAN_REPORTS := 2
static var _reports := 0

static func finite_basis(basis: Basis) -> bool:
	return basis.x.is_finite() and basis.y.is_finite() and basis.z.is_finite()

## Uma linha "NON_FINITE {json}" no log (no máximo MAX_REPORTS por sessão). Nas SCAN_REPORTS primeiras, uma
## varredura única da árvore lista os Node3D com posição não finita (custa dezenas de ms, só neste caso de erro).
static func report(kind: String, value: Variant, source: Node = null) -> void:
	if _reports >= MAX_REPORTS: return
	_reports += 1
	var entry := {"kind": kind, "value": str(value), "frame": Engine.get_process_frames()}
	if is_instance_valid(source): entry["source"] = str(source.get_path()) if source.is_inside_tree() else str(source.name)
	if _reports <= SCAN_REPORTS:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null: entry["non_finite_nodes"] = _scan(tree.root)
	print("NON_FINITE ", JSON.stringify(entry))

static func _scan(root: Node) -> Array:
	var found: Array = []
	var pending: Array[Node] = [root]
	while not pending.is_empty() and found.size() < 12:
		var node: Node = pending.pop_back()
		if node is Node3D and node.is_inside_tree():
			var spatial := node as Node3D
			if not spatial.global_position.is_finite() or not finite_basis(spatial.global_basis):
				found.append("%s (%s)" % [str(spatial.get_path()), spatial.get_class()])
				# O filho herda o NaN do pai: basta o mais alto de cada ramo.
				continue
		pending.append_array(node.get_children())
	return found

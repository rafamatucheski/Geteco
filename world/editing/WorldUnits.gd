extends RefCounted
## Edição de TUDO que o mundo constrói: pedra, poste, fio, cerca, placa, banco, árvore do
## cenário... Os geradores não sabem do editor; aqui o nó pronto vira uma "peça"
## (`WorldEditPieces`) com identidade estável, e o documento de edição só diz onde ela fica.
##
## Dois níveis, sempre sem custo quando não há nada editado nem prévia:
## - registro (Harbor/Montanha): tudo que um registro de região constrói vira UMA peça
##   `piece/<região>/<tipo>/<hash>`; trocar de chunk usa a clonagem de registros de
##   `WorldEditPieces.prepare`.
## - chunk: o que o chunk constrói fora de registros (pedras, vegetação, mobiliário) vira
##   peças `piece/unit/<região>/<cx>_<cz>/<nome>~<x>_<z>`; a peça fica no chunk de origem.
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const PREFIX := "piece/unit/"
## Acima disto o nó é um conjunto (prédio, vila): desce para os filhos.
const MAX_VISUALS := 64
const MAX_SPAN := 64.0
## MultiMesh que o gerador marca com `world_unit_explode` (as pedras e os seixos da montanha)
## vira uma malha por instância. Os demais (capim, vegetação, lotes do renderizador) seguem em
## lote e não são peças: o renderizador dummy da prévia não devolve as transformações de
## instância, então posição e identidade nunca dependem delas (prévia e jogo precisam concordar).
const EXPLODE_META := "world_unit_explode"
const GENERIC_NAMES := ["Node3D", "MeshInstance3D", "StaticBody3D", "Node", "Object", "Mesh Instance3D", "Static Body3D", "Node 3D"]
## Registros que já têm editor próprio (objetos do catálogo) ou ligação física com o terreno.
const SKIP_RECORD_KINDS := ["building", "tree", "mountain_road_lamp", "road", "lake", "environmental_parity", "editor_ground", "editor_prop", "editor_light", "editor_added"]
const GROUND_NAMES := ["Land", "Ocean", "Terrain", "Surface", "Ground", "Water", "Sea", "Floor", "OriginalPort", "SouthPortConcrete", "Chunk"]

static func preview_active() -> bool:
	return bool(Engine.get_meta("geteco_live_preview_build", false))

## Interruptor de A/B: com GETECO_WORLD_UNITS_OFF=1 nada daqui roda (medir/atribuir regressões).
static func disabled() -> bool:
	return OS.has_environment("GETECO_WORLD_UNITS_OFF")

## Linhas de peça deste documento que o chunk precisa aplicar (só as `piece/unit/`).
static func unit_changes(changes: Dictionary) -> Dictionary:
	var result := {}
	for id in changes:
		if str(id).begins_with(PREFIX): result[id] = changes[id]
	return result

static func ground_of(region: Node) -> Callable:
	var terrain: Variant = region.get("terrain")
	if terrain != null: return Callable(terrain, "surface_height_at")
	return Callable()

## Peça de chunk movida para outra célula continua filha do chunk de origem. Para ela não sumir
## quando o jogador está só no destino, o destino "puxa" a origem: {célula destino: [origens]}.
## `cell_size` é o lado da célula da região (64 em Harbor/montanha, 96 no deserto).
static func pull_map(region_id: String, changes: Dictionary, cell_size: float) -> Dictionary:
	var result := {}
	for id in changes:
		var row: Dictionary = changes[id]
		if row.get("deleted", false) or not row.get("position") is Array: continue
		var origin_id := str(row.get("clone_of", id))
		var bits := origin_id.split("/")
		if bits.size() < 5 or bits[0] != "piece" or bits[1] not in ["unit", "pl"] or bits[2] != region_id: continue
		var cell_bits := bits[3].split("_")
		if cell_bits.size() != 2 or not cell_bits[0].is_valid_int() or not cell_bits[1].is_valid_int(): continue
		var origin := Vector2i(int(cell_bits[0]), int(cell_bits[1]))
		var target := Vector2i(floori(float(row.position[0]) / cell_size), floori(float(row.position[1]) / cell_size))
		if target == origin: continue
		if not result.has(target): result[target] = []
		if origin not in result[target]: result[target].append(origin)
	return result

# ---------------------------------------------------------------- registros

static func record_eligible(record: Dictionary) -> bool:
	if str(record.kind) in SKIP_RECORD_KINDS or record.has("editor_id"): return false
	return DATA.record_id(record).is_empty()

static func record_key(record: Dictionary) -> String:
	if not record.has("world_key"): record["world_key"] = PIECES.record_key(record)
	return str(record.world_key)

## `first_child`: quantos filhos o chunk já tinha antes de o registro ser montado.
static func group_record(region: Node3D, chunk: Node3D, record: Dictionary, first_child: int) -> void:
	if disabled(): return
	var nodes: Array = []
	for node in chunk.get_children().slice(first_child):
		if node is Node3D: nodes.append(node)
	if nodes.is_empty():
		return
	for node in nodes:
		# Já editável por outro caminho (Neko, Cobra, objetos do catálogo): não duplicar.
		if node.has_meta("editor_id") or node.has_meta("world_edit_piece_id") or not PIECES.collect(node).is_empty():
			_skip(nodes)
			return
	var key := record_key(record)
	var stats := {"count": 0, "box": AABB(), "has": false, "dynamic": false, "claimed": false}
	for node in nodes: _measure(node, stats, true)
	var pivot := Vector3(chunk.global_position.x, chunk.global_position.y, chunk.global_position.z)
	if stats.has: pivot = Vector3((stats.box as AABB).get_center().x, chunk.global_position.y, (stats.box as AABB).get_center().z)
	var group := PIECES.group(chunk, nodes, "%s/%s/%s" % [region.region_id, record.kind, key.substr(0, 20)], _label(str(record.kind)), false, pivot)
	group.set_meta("world_edit_auto", true)
	group.set_meta("world_edit_source", key)
	var all_changes: Variant = region.get("_piece_changes")
	if all_changes is Dictionary: PIECES.spawn_clones(group, all_changes, ground_of(region))

static func _skip(nodes: Array) -> void:
	for node in nodes: node.set_meta("world_unit_skip", true)

# ------------------------------------------------------------------- chunk

## Chamado quando o chunk terminou de ser construído.
static func finalize_chunk(region: Node3D, chunk: Node3D, cell: Vector2i, changes: Dictionary, ground: Callable) -> void:
	_finalize(chunk, str(region.region_id), "%d_%d" % [cell.x, cell.y], changes, ground)

## Lugar montado pela sessão (Vértice, Torque...): o nó do lugar faz o papel de chunk.
static func finalize_session(place: Node3D, region_id: String, key: String, changes: Dictionary, ground: Callable) -> void:
	_finalize(place, region_id, "s_" + key, changes, ground)

static func _finalize(holder: Node3D, region_id: String, tag: String, changes: Dictionary, ground: Callable) -> void:
	if disabled(): return
	var preview := preview_active()
	var prefix := "%s%s/%s/" % [PREFIX, region_id, tag]
	var wanted := {}
	if not preview:
		for id in changes:
			if str(id).begins_with(prefix): wanted[id] = true
			# Cópia de uma peça deste chunk: a origem precisa virar peça mesmo sem edição própria.
			elif str(changes[id].get("clone_of", "")).begins_with(prefix): wanted[str(changes[id].clone_of)] = true
		if wanted.is_empty(): return
	_explode_multimeshes(holder)
	for unit in collect_units(holder, region_id, tag):
		if not preview and not wanted.has(unit.id): continue
		var box: AABB = unit.box
		var group := PIECES.group(holder, [unit.node], str(unit.id).trim_prefix("piece/"), str(unit.label), false, Vector3(box.get_center().x, holder.global_position.y, box.get_center().z))
		group.set_meta("world_edit_auto", true)
		group.set_meta("world_edit_source", "unit/%s/%s" % [region_id, tag])
		PIECES.spawn_clones(group, changes, ground)
		PIECES.apply_one(group, changes, ground)

## Troca cada MultiMesh pequeno por uma MeshInstance3D por instância e leva junto a colisão
## que o gerador pôs no mesmo ponto (as pedras da montanha têm um StaticBody3D cada).
static func _explode_multimeshes(node: Node) -> void:
	for child in node.get_children():
		if not child is Node3D or _claimed(child): continue
		if child is MultiMeshInstance3D and child.has_meta(EXPLODE_META) and child.multimesh != null and child.multimesh.mesh != null:
			_explode(child)
		else: _explode_multimeshes(child)

static func _explode(source: MultiMeshInstance3D) -> void:
	var parent := source.get_parent()
	var multimesh := source.multimesh
	var transforms: Array = source.get_meta("preview_instance_transforms", [])
	var bodies: Array = []
	for sibling in parent.get_children():
		if sibling is CollisionObject3D: bodies.append(sibling)
	var base_name := str(source.name)
	for index in multimesh.instance_count:
		var local: Transform3D = transforms[index] if index < transforms.size() else multimesh.get_instance_transform(index)
		var instance := MeshInstance3D.new()
		instance.name = base_name
		# Irmãos de mesmo nome ganham "@MeshInstance3D@n": o rótulo precisa sobreviver a isso.
		instance.set_meta("world_unit_label", _readable(base_name))
		instance.mesh = multimesh.mesh
		instance.material_override = source.material_override
		instance.cast_shadow = source.cast_shadow
		parent.add_child(instance)
		instance.global_transform = source.global_transform * local
		for body in bodies:
			if is_instance_valid(body) and body.get_parent() == parent and body.global_position.distance_to(instance.global_position) < .02:
				body.reparent(instance, true)
				bodies.erase(body)
				break
	parent.remove_child(source)
	source.free()

static func collect_units(chunk: Node3D, region_id: String, tag: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_walk(chunk, region_id, tag, result, {})
	return result

static func _walk(parent: Node, region_id: String, tag: String, result: Array, seen: Dictionary) -> void:
	for child in parent.get_children():
		if not child is Node3D or not child.visible or child.is_queued_for_deletion(): continue
		if _claimed(child): continue
		if child is MultiMeshInstance3D: continue # lote: nunca é peça por si só
		var stats := {"count": 0, "box": AABB(), "has": false, "dynamic": false, "claimed": false}
		_measure(child, stats, true)
		if stats.count == 0: continue
		if not stats.has: continue # só lotes de MultiMesh: sem malha própria não há onde ancorar
		var box: AABB = stats.box
		var unit_ok: bool = not stats.dynamic and not stats.claimed and stats.count <= MAX_VISUALS and box.size.x <= MAX_SPAN and box.size.z <= MAX_SPAN and not _ground_like(child, box)
		if unit_ok:
			var label := _node_label(child)
			var base_id := "%s%s/%s/%s~%d_%d" % [PREFIX, region_id, tag, _slug(label), roundi(box.get_center().x * 10.0), roundi(box.get_center().z * 10.0)]
			var id := base_id
			var serial := int(seen.get(base_id, 0))
			seen[base_id] = serial + 1
			if serial > 0: id += "~%d" % serial
			result.append({"node": child, "id": id, "label": label, "box": box})
		elif stats.count > 1 or stats.claimed or stats.dynamic:
			_walk(child, region_id, tag, result, seen)

static func _claimed(node: Node) -> bool:
	return node.has_meta("world_edit_piece_id") or node.has_meta("editor_id") or node.has_meta("world_unit_skip")

static func _ground_like(node: Node, box: AABB) -> bool:
	for prefix in GROUND_NAMES:
		if str(node.name).begins_with(prefix): return true
	return box.size.x > 40.0 and box.size.z > 40.0

static func _measure(node: Node, stats: Dictionary, root := false) -> void:
	if node is Node3D and not node.visible: return
	if not root and _claimed(node):
		stats.claimed = true
		return
	if node is CharacterBody3D or node is RigidBody3D or node is AnimationPlayer or node is AnimationTree or node is Skeleton3D or node is GPUParticles3D or node is Camera3D:
		stats.dynamic = true
		return
	if node is MeshInstance3D and node.mesh != null:
		stats.count += 1
		_expand(stats, node.global_transform * node.mesh.get_aabb())
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
		stats.count += 1
	for child in node.get_children(): _measure(child, stats)

static func _expand(stats: Dictionary, box: AABB) -> void:
	var world := box
	if stats.has:
		world = (stats.box as AABB).merge(box)
	stats.box = world
	stats.has = true

static func _node_label(node: Node) -> String:
	var text := str(node.get_meta("world_unit_label", "")) if node.has_meta("world_unit_label") else _readable(str(node.name))
	if text.is_empty() or text in GENERIC_NAMES: text = _descendant_label(node)
	if text.is_empty(): text = "Objeto"
	return text

## Primeiro nome com sentido entre os descendentes ("Node3D" > "Sandstone").
static func _descendant_label(node: Node) -> String:
	for child in node.get_children():
		var text := _readable(str(child.name))
		if not text.is_empty() and text not in GENERIC_NAMES: return text
		var deeper := _descendant_label(child)
		if not deeper.is_empty(): return deeper
	return ""

static func _readable(name: String) -> String:
	if name.begins_with("@"): return ""
	var words: Array[String] = []
	var current := ""
	for index in name.length():
		var letter := name[index]
		if letter == "_" or letter == " " or letter == "-":
			if not current.is_empty(): words.append(current)
			current = ""
			continue
		if not current.is_empty() and letter == letter.to_upper() and letter != letter.to_lower() and current[-1] != current[-1].to_upper(): 
			words.append(current)
			current = ""
		current += letter
	if not current.is_empty(): words.append(current)
	var kept: Array[String] = []
	for word in words:
		if word.is_valid_int() or word == "Lit": continue
		kept.append(word)
	return " ".join(kept).strip_edges()

static func _slug(label: String) -> String:
	var result := ""
	for index in label.length():
		var letter := label[index]
		result += letter if letter.unicode_at(0) < 128 and (letter.is_valid_identifier() or letter.is_valid_int()) else "_"
	return result

static func _label(kind: String) -> String:
	return kind.replace("_", " ").capitalize()

# ---------------------------------------------------------------- catálogo

## Linhas para o editor: uma por peça automática construída em `root`. Posição e caixa são
## as de ANTES das edições (o editor aplica o delta do documento por cima).
static func manifest(root: Node) -> Array:
	var rows: Array = []
	for group in PIECES.collect(root):
		if not group.has_meta("world_edit_auto") or not group.has_meta("world_edit_base"): continue
		var base: Dictionary = group.get_meta("world_edit_base")
		var bounds: AABB = base.bounds
		var pivot := Vector2(float(base.pivot[0]), float(base.pivot[1]))
		var color := _tint(group)
		var width := maxf(bounds.size.x, .25)
		var depth := maxf(bounds.size.z, .25)
		var start := Vector2(bounds.position.x, bounds.position.z)
		var quad := [[start.x, start.y], [start.x + width, start.y], [start.x + width, start.y + depth], [start.x, start.y + depth]]
		var margin := (pivot - (start + Vector2(width, depth) * .5)).abs()
		rows.append({
			"id": "piece/" + str(group.get_meta("world_edit_piece_id")), "type": "piece", "kind": "unit", "auto": true,
			"label": str(group.get_meta("world_edit_label", "Peça")), "locked": false, "rotation": 0.0,
			"position": [pivot.x, pivot.y], "size": [width + 2.0 * margin.x, depth + 2.0 * margin.y],
			"selection_height": bounds.end.y, "ground": bounds.size.y < .4,
			"source_record": str(group.get_meta("world_edit_source", "")),
			"parts": [[start.x, start.y, width, depth, bounds.end.y, color, quad]],
		})
	return rows

static func _tint(node: Node) -> String:
	if node is MeshInstance3D and node.mesh != null:
		var material: Material = node.material_override
		if material == null and node.mesh.get_surface_count() > 0: material = node.get_active_material(0)
		if material is BaseMaterial3D: return material.albedo_color.to_html(false)
	for child in node.get_children():
		var found := _tint(child)
		if found != "9db7c4": return found
	return "9db7c4"

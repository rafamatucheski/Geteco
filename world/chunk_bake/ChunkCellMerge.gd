extends RefCounted
## Fusão geral por trecho, estilo reVC: a geometria estática de cada objeto do trecho vira uma malha por
## material e por célula de 8×4×8 m. A ponte da fundição tinha 196 malhas soltas e o cais do Northstar ~280,
## os trechos com 2.100–2.600 draw calls no export (logs de 13–14/10).
##
## Compatível com o corte do túnel e com o reveal das fachadas porque os dois escolhem peça a peça pela
## caixa no mundo: um lote pequeno, de uma célula e de uma faixa só (chão abaixo de 0,5 m ou volume), é
## escolhido quase igual às peças que juntou. Nada que se mexe, quebra, acende ou abre entra.
##
## As fontes ficam escondidas, não apagadas: o id das peças do editor de mundo depende do nome e da posição
## delas, e geradores podem guardar referência a uma malha. Desligar: GETECO_CELL_MERGE=0.
const TUNNEL_CUTAWAY := preload("res://world/urban_detail/TunnelCutaway.gd")
## Com cache de shader frio a fusão travava (travessia porto -> serra: 9 quadros acima de 250 ms, pico de
## 1,3 s). Com as fatias de 2 ms, o pré-aquecimento das variantes da família e o lote de material original sem
## cor no vértice, a mesma travessia fria ficou igual a sem fusão: 0 acima de 250 ms, máximo 136 ms (15/10).
static var enabled := OS.get_environment("GETECO_CELL_MERGE") != "0"
## Por região, para isolar travadas de cache frio (15/10): GETECO_CELL_MERGE_MOUNTAIN=0 / _DESERT=0 / _HARBOR=0.
static var region_enabled := {
	"harbor": OS.get_environment("GETECO_CELL_MERGE_HARBOR") != "0",
	"mountain": OS.get_environment("GETECO_CELL_MERGE_MOUNTAIN") != "0",
	"desert": OS.get_environment("GETECO_CELL_MERGE_DESERT") != "0",
}
const FINISHED := &"chunk_cell_merge_finished"
const MERGED_SOURCE := &"chunk_cell_merged_source"
const BATCH := &"chunk_cell_batch"
## Célula do lote. Perto do túnel do canal o corte escolhe peças pela caixa, então o lote fica pequeno; longe
## dele só o frustum vê a caixa e a célula pode ser grande. Com 8×4×8 m o cais sobrava em 171 lotes.
const CELL_NEAR_TUNNEL := Vector3(16.0, 8.0, 16.0)
const CELL_FAR := Vector3(32.0, 8.0, 32.0)
const THIN_SHADOW := 0.05
const TINY_SHADOW_VOLUME := 0.02
## Nomes que apontam para peça viva: abre, gira, acende, quebra ou é trocada por outro sistema.
const PROTECTED_NAMES := ["door", "shutter", "gate", "hatch", "leaf", "glass", "window_glass", "sign", "nameplate",
	"lamp", "light", "neon", "flag", "water", "wheel", "rotor", "propeller", "hook", "rope", "cable", "boom_arm"]
## Metas de sistemas que guardam o nó e o tratam sozinho (quebráveis, interior, saque, acesso).
const PROTECTED_METAS := [&"street_fragile_registered", &"interior_solid_id", &"loot_container", &"door_leaf", &"port_lootable"]
const REMOVABLE_SCRIPTS := ["LootablePortContainer.gd", "PortContainerLoot.gd"]
## Escopos inteiros que outro sistema cuida: prédios com acesso/reveal e o próprio túnel.
const PROTECTED_GROUPS := [&"harbor_building", &"v2_walkin_facade", &"harbor_building_facade", &"exterior_reveal_building", &"canal_tunnel"]

## Dois quadros depois do marco do trecho: geradores com fusão própria (ponte, D2) terminam antes. Em jogo a
## fusão roda em fatias de SLICE_BUDGET_USEC: montar os lotes em GDScript custava centenas de ms num quadro só
## na vila da serra (travessia com cache frio de 15/10: 9 quadros acima de 250 ms, que o pré-aquecimento de
## shader não resolveu).
## Testes, censo e coletor de variantes zeram (fusão inteira de uma vez): não medem tempo de quadro.
static var slice_budget_usec := 2000
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## LOD gerado em runtime nos lotes (desligado por padrão; ver ChunkMeshLod.gd).
const PROC_LOD := preload("res://world/chunk_bake/ChunkMeshLod.gd")
const GPU_RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
## Trecho descartado fica na árvore, escondido, sendo desmontado folha a folha: a fusão tem de parar já
## (crash de 16/10 na ponte: folhas órfãs ainda válidas em _add_mesh e holder liberado em _commit_batch).
static func _chunk_alive(chunk: Variant) -> bool:
	return is_instance_valid(chunk) and (chunk as Node).is_inside_tree() and not GPU_RELEASE.is_retired(chunk)

static func finish_chunk_later(chunk: Node3D) -> void:
	if not enabled or not _chunk_alive(chunk): return
	var reference: WeakRef = weakref(chunk)
	for frame in 2:
		await chunk.get_tree().process_frame
		if not _chunk_alive(reference.get_ref()): return
	await _run(chunk, slice_budget_usec)

## Estado da fatia é por execução, não estático: com teleporte rápido dois trechos fundem ao mesmo tempo (um
## cedeu o quadro, o outro começou) e o estado compartilhado fazia o primeiro olhar o trecho do segundo. Ele
## seguia num trecho já liberado (SCRIPT ERROR em _merge_scope, _sum e get_children na auditoria de 15/10).
class Slice:
	## Começo do span do log (0 com o rastreio desligado) e, separado, o relógio do orçamento: com o rastreio
	## desligado `began` é 0 e a fatia cedia o quadro a cada peça (uma peça por quadro).
	var began := 0
	var budget_began := 0
	var reference: WeakRef
	var budget_usec := 0

static func _run(chunk: Node3D, budget_usec: int) -> Dictionary:
	var report := {"sources": 0, "batches": 0, "scopes": 0}
	if not enabled or chunk.has_meta(FINISHED) or not chunk.has_meta("vegetation_ready_frame") or not _chunk_alive(chunk): return report
	if Engine.get_meta("geteco_live_preview_build", false): return report
	# str(): o region_id das regiões pode ser StringName, e "is String" deixava o interruptor sem efeito.
	var region_id := str(chunk.get_parent().get("region_id")) if chunk.get_parent() != null else ""
	if not bool(region_enabled.get(region_id, true)): return report
	chunk.set_meta(FINISHED, true)
	var slice := Slice.new()
	slice.began = STALL_WORK.begin()
	slice.budget_began = Time.get_ticks_usec()
	slice.reference = weakref(chunk)
	slice.budget_usec = budget_usec
	# Um lote por trecho, entre objetos: as ~35 pilhas de carga do Northstar são objetos separados e, fundidas
	# só por dentro, sobravam 239 lotes. Prédios com acesso/reveal ficam com a fusão por prédio deles.
	var candidates: Array = []
	for child in chunk.get_children():
		if child is MeshInstance3D: candidates.append(child)
		elif child is Node3D and _scope_allowed(child as Node3D): candidates.append_array(child.get_children())
	_sum(report, await _merge_scope(chunk, candidates, false, slice))
	# Prédios só com reveal (cabanas da serra: 220 malhas cada, poços do porto): o reveal escolhe peça a peça
	# dentro do prédio pela caixa e troca o material pela cor dele, então o lote fica dentro do prédio, em
	# célula pequena e com o material original, sem cor no vértice.
	var reveal_scopes: Array = []
	if is_instance_valid(slice.reference.get_ref()):
		for child in chunk.get_children():
			if child is Node3D and _reveal_scope_allowed(child as Node3D): reveal_scopes.append(child)
	for scope in reveal_scopes:
		if not is_instance_valid(scope) or not is_instance_valid(slice.reference.get_ref()): continue
		_sum(report, await _merge_scope(scope as Node3D, scope.get_children(), true, slice))
	if not _chunk_alive(slice.reference.get_ref()): return report
	STALL_WORK.finish_slow("chunk.cell_merge", slice.began, 1500)
	# Os materiais da família nascem depois do pré-aquecimento do corte do túnel: sem isto, a primeira
	# entrada no túnel compilava uma cópia com alfa por família (pico de 1,1 s na captura de 14/10).
	if report.batches > 0 and chunk.get_parent() != null:
		var area := Rect2()
		var first := true
		var materials := {}
		for batch in chunk.find_children("CellBatch*", "MeshInstance3D", true, false):
			var box: AABB = batch.global_transform * batch.get_aabb()
			var rect := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
			area = rect if first else area.merge(rect)
			first = false
			var material: Material = batch.mesh.surface_get_material(0)
			if material != null: materials[material.get_instance_id()] = material
		TUNNEL_CUTAWAY.prime_materials(materials.values(), chunk.get_parent(), area)
	return report

## Cede o quadro quando a fatia passou do orçamento. Devolve false se o trecho sumiu enquanto esperava.
static func _yield_if_due(slice: Slice) -> bool:
	if slice.budget_usec <= 0 or Time.get_ticks_usec() - slice.budget_began < slice.budget_usec: return true
	var chunk: Variant = slice.reference.get_ref()
	if not _chunk_alive(chunk): return false
	STALL_WORK.finish_slow("chunk.cell_merge", slice.began, 1500)
	await (chunk as Node).get_tree().process_frame
	slice.began = STALL_WORK.begin()
	slice.budget_began = Time.get_ticks_usec()
	var still: Variant = slice.reference.get_ref()
	return _chunk_alive(still)

## Arrays por malha e superfície. Eram lidas uma vez por trecho, mas cada leitura espera a GPU (a fatia de
## 176 ms da ponte no release de 16/10): agora vêm do cache entre trechos, por parâmetros nas primitivas.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static func _arrays_of(mesh: Mesh, surface: int) -> Array:
	return MESH_ARRAYS.arrays_of(mesh, surface)

## Registro em cache sai do trecho e volta em outro: as fontes reaparecem porque o lote ficou no trecho velho.
## O trecho novo funde de novo quando termina de montar.
static func restore_sources(record: Node) -> void:
	if record is MeshInstance3D and record.has_meta(MERGED_SOURCE):
		record.remove_meta(MERGED_SOURCE)
		(record as MeshInstance3D).visible = true
	for mesh in record.find_children("*", "MeshInstance3D", true, false):
		if not mesh.has_meta(MERGED_SOURCE): continue
		mesh.remove_meta(MERGED_SOURCE)
		mesh.visible = true

static func _sum(report: Dictionary, merged: Dictionary) -> void:
	if merged.is_empty(): return
	if merged.batches > 0: report.scopes += 1
	report.sources += merged.sources
	report.batches += merged.batches

static func _scope_allowed(scope: Node3D) -> bool:
	# A registered prop may be a plain Node3D with several mesh children (saguaro).
	# Starting traversal at its children bypassed _protected(root), leaving a fixed
	# batch standing after FragileProps hid the source and spawned the falling pieces.
	if scope.has_meta("street_fragile_registered"): return false
	if scope.has_meta(BATCH) or scope.get_node_or_null("BuildingAccess") != null: return false
	if scope.has_meta("place_id") and not str(scope.get_meta("place_id", "")).is_empty(): return false
	for group in PROTECTED_GROUPS:
		if scope.is_in_group(group): return false
	# Objeto que o jogo tira do trecho (saque) deixaria o lote no lugar dele.
	var script := scope.get_script() as Script
	if script != null and script.resource_path.get_file() in REMOVABLE_SCRIPTS: return false
	if String(scope.name).to_lower().contains("loot"): return false
	return not _is_dynamic(scope)

const REVEAL_CELL := Vector3(8.0, 4.0, 8.0)
const REVEAL_ONLY_GROUP := &"exterior_reveal_building"
## Prédio com reveal mas sem acesso, lugar ou fachada de entrar: nada guarda referência às malhas dele.
static func _reveal_scope_allowed(scope: Node3D) -> bool:
	if not scope.is_in_group(REVEAL_ONLY_GROUP) or scope.has_meta(BATCH): return false
	if scope.get_node_or_null("BuildingAccess") != null or not scope.find_children("BuildingAccess", "", true, false).is_empty(): return false
	if scope.has_meta("place_id") and not str(scope.get_meta("place_id", "")).is_empty(): return false
	for group in scope.get_groups():
		if group != REVEAL_ONLY_GROUP and not String(group).begins_with("_"): return false
	return not _is_dynamic(scope)

## Nó que se mexe ou é dono de algo que se mexe: o lote ficaria parado no lugar antigo.
static func _is_dynamic(node: Node) -> bool:
	if node is RigidBody3D or node is CharacterBody3D or node is AnimatableBody3D or node is Area3D: return true
	if node is Skeleton3D or node is BoneAttachment3D or node is AnimationPlayer or node is AnimationTree: return true
	if node is PathFollow3D or node is Camera3D: return true
	# Gerador que só esperava o trecho ficar pronto já desligou o próprio processo; quem continua
	# processando (animação, guincho, sinal) mexe em algo e fica de fora.
	return node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input()

static func _merge_scope(scope: Node3D, candidates: Array, exact: bool, slice: Slice) -> Dictionary:
	var groups := {}
	var to_scope := scope.global_transform.affine_inverse()
	var report := {"sources": 0, "batches": 0}
	if not await _collect(candidates, scope, to_scope, groups, exact, slice): return report
	if not _chunk_alive(slice.reference.get_ref()) or not is_instance_valid(scope): return report
	# Superfícies de cada fonte ainda sem lote. A fonte só some quando todas tiverem: uma malha com superfícies
	# em famílias (grupos) diferentes sumia em parte ao sair o primeiro lote e só voltava inteira quando o
	# grupo da outra superfície era montado, quadros depois (buraco visível no meio da fusão fatiada).
	var pending_surfaces := {}
	for key in groups:
		for entry in groups[key]:
			if not is_instance_valid(entry.node): continue
			var id: int = entry.node.get_instance_id()
			pending_surfaces[id] = int(pending_surfaces.get(id, 0)) + 1
	var holder: Node3D = null
	for key in groups:
		# Cada lote é atômico: a fonte só some quando o lote dela já existe, então ceder entre lotes não
		# deixa buraco nem desenho em dobro.
		if not await _yield_if_due(slice) or not is_instance_valid(scope) or not scope.is_inside_tree(): return report
		# Grupo de um só também vira lote.
		# Enquanto a fatia esperava, uma fonte pode ter sido liberada ou saído do escopo (registro que volta ao
		# cache e entra em outro trecho): fica fora do lote, senão o lote desenharia peça que não está mais aqui.
		var valid_entries: Array = []
		for entry in groups[key]:
			if is_instance_valid(entry.node) and scope.is_ancestor_of(entry.node): valid_entries.append(entry)
		if valid_entries.is_empty(): continue
		# Lote limitado por vértices, não pelo grupo: um grupo grande (célula de 32 m da vila) era um lote só,
		# montado e enviado à placa de uma vez. Partes menores, mesma geometria.
		for entries: Array in await _split_by_vertices(valid_entries, slice):
			if not is_instance_valid(scope) or not scope.is_inside_tree(): return report
			var mesh: ArrayMesh = await _build_batch(entries, exact, slice)
			# O holder é folha do trecho: a desmontagem pode liberá-lo enquanto o trabalhador monta o lote.
			if not _chunk_alive(slice.reference.get_ref()) or not is_instance_valid(scope) or not scope.is_inside_tree(): return report
			if not is_instance_valid(holder): holder = null
			holder = _commit_batch(scope, holder, entries, mesh, pending_surfaces, report)
	return report

## Põe o lote na árvore e esconde as fontes que ficaram com todas as superfícies em lote. Devolve o holder.
static func _commit_batch(scope: Node3D, holder: Node3D, entries: Array, mesh: ArrayMesh, pending_surfaces: Dictionary, report: Dictionary) -> Node3D:
	if mesh == null or not is_instance_valid(scope) or not scope.is_inside_tree(): return holder
	# A montagem também cede o quadro entre peças: se alguma fonte sumiu nesse meio-tempo, o lote teria a
	# geometria dela. Descarta o lote e deixa as fontes que sobraram como estão (só perde a fusão do grupo).
	if entries.any(func(entry): return not is_instance_valid(entry.node) or not scope.is_ancestor_of(entry.node)): return holder
	var first: MeshInstance3D = entries[0].node
	if holder == null:
		holder = Node3D.new()
		holder.name = "CellMergeBatches"
		holder.set_meta(BATCH, true)
		scope.add_child(holder)
	var batch := MeshInstance3D.new()
	batch.name = "CellBatch"
	batch.mesh = mesh
	batch.set_meta(BATCH, true)
	batch.layers = first.layers
	batch.cast_shadow = entries[0].shadow
	batch.gi_mode = first.gi_mode
	batch.visibility_range_begin = first.visibility_range_begin
	batch.visibility_range_begin_margin = first.visibility_range_begin_margin
	var range_end := 0.0
	var range_margin := 0.0
	for entry in entries:
		range_end = maxf(range_end, entry.node.visibility_range_end)
		range_margin = maxf(range_margin, entry.node.visibility_range_end_margin)
	batch.visibility_range_end = range_end
	batch.visibility_range_end_margin = range_margin
	batch.visibility_range_fade_mode = first.visibility_range_fade_mode
	holder.add_child(batch)
	report.batches += 1
	for entry in entries:
		var source: MeshInstance3D = entry.node
		var id := source.get_instance_id()
		pending_surfaces[id] = int(pending_surfaces.get(id, 1)) - 1
		if int(pending_surfaces[id]) > 0 or source.has_meta(MERGED_SOURCE): continue
		source.set_meta(MERGED_SOURCE, true)
		source.visible = false
		report.sources += 1
	return holder

## Teto de vértices por lote. 16.384 vértices com tangente e cor são ~1 MB enviados num add_surface; a média
## dos lotes fica bem abaixo disso, só a célula densa (vila, cais) chegava a dezenas de milhares.
const MAX_BATCH_VERTICES := 16384
## Acima disto a montagem das arrays do lote vai para um trabalhador (laços por vértice de tangente, cor e
## normal não uniforme em GDScript); abaixo, o custo de esperar um quadro pelo trabalhador não compensa.
const WORKER_MIN_VERTICES := 2048

static func _split_by_vertices(entries: Array, slice: Slice) -> Array:
	var parts: Array = []
	var current: Array = []
	var count := 0
	for entry in entries:
		if not await _yield_if_due(slice): return []
		var vertices: PackedVector3Array = _arrays_of(entry.mesh, entry.surface)[Mesh.ARRAY_VERTEX]
		if not current.is_empty() and count + vertices.size() > MAX_BATCH_VERTICES:
			parts.append(current)
			current = []
			count = 0
		current.append(entry)
		count += vertices.size()
	if not current.is_empty(): parts.append(current)
	return parts

## Varre em profundidade cedendo o quadro pelo orçamento: na vila da serra (~1.200 malhas, centenas de
## materiais novos, cada um com a lista de propriedades lida em _family) a coleta inteira cabia num quadro só
## (travessia de 15/10: fatias de 58-183 ms com orçamento de 2 ms). Devolve false se o trecho sumiu; o grupo
## revalida as fontes antes de montar.
static func _collect(candidates: Array, scope: Node3D, to_scope: Transform3D, groups: Dictionary, exact: bool, slice: Slice) -> bool:
	var stack: Array = candidates.duplicate()
	stack.reverse()
	while not stack.is_empty():
		if not await _yield_if_due(slice) or not is_instance_valid(scope): return false
		var child: Variant = stack.pop_back()
		if not is_instance_valid(child): continue
		# Folha tirada pela desmontagem e guardada pela fila de vídeo: válida, mas fora da árvore e do escopo.
		if not (child as Node).is_inside_tree() or not scope.is_ancestor_of(child): continue
		if child.has_meta(BATCH) or child.has_meta(MERGED_SOURCE): continue
		if not child is Node3D or not (child as Node3D).visible: continue
		if _is_dynamic(child) or _protected(child): continue
		if child is MeshInstance3D:
			_add_mesh(child as MeshInstance3D, scope, to_scope, groups, exact)
			continue
		# Corpos estáticos guardam visuais como filhos; eles não se mexem.
		var children: Array = child.get_children()
		children.reverse()
		stack.append_array(children)
	return true

static func _protected(node: Node) -> bool:
	var label := String(node.name).to_lower()
	for word in PROTECTED_NAMES:
		if label.contains(word): return true
	for meta in PROTECTED_METAS:
		if node.has_meta(meta): return true
	for group in node.get_groups():
		if not String(group).begins_with("_"): return true
	return false

static func _add_mesh(mesh_node: MeshInstance3D, scope: Node3D, to_scope: Transform3D, groups: Dictionary, exact := false) -> void:
	var mesh := mesh_node.mesh
	if mesh == null or mesh_node.skin != null or mesh_node.transparency != 0.0 or mesh_node.material_overlay != null: return
	# Filho só de colisão continua valendo com o visual escondido; qualquer visual filho sumiria junto.
	if not mesh_node.find_children("*", "VisualInstance3D", true, false).is_empty(): return
	var surfaces: Array = []
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: return
		var material := mesh_node.get_active_material(surface) as StandardMaterial3D
		if material == null or not _material_allowed(material): return
		surfaces.append(material)
	var bounds: AABB = mesh_node.global_transform * mesh_node.get_aabb()
	var center := bounds.get_center()
	var size: Vector3 = REVEAL_CELL if exact else (CELL_NEAR_TUNNEL if TUNNEL_CUTAWAY.corridor_rect().has_point(Vector2(center.x, center.z)) else CELL_FAR)
	var cell := Vector3i(floori(center.x / size.x), floori(center.y / size.y), floori(center.z / size.z))
	# O corte do túnel trata "chão" (topo abaixo de 0,5 m) diferente de volume: não podem ir juntos.
	var flat := bounds.end.y < TUNNEL_CUTAWAY.FLAT_TOP
	var transform := to_scope * mesh_node.global_transform
	# Folha fina (marcação, estêncil, faixa colada na lateral) ou peça minúscula não faz sombra visível.
	var shadow := mesh_node.cast_shadow
	if bounds.size[bounds.size.min_axis_index()] <= THIN_SHADOW or bounds.size.x * bounds.size.y * bounds.size.z < TINY_SHADOW_VOLUME:
		shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for surface in surfaces.size():
		if _family(surfaces[surface]).is_empty(): return
		if surfaces[surface].normal_enabled and _arrays_of(mesh, surface)[Mesh.ARRAY_TANGENT] == null: return
	for surface in surfaces.size():
		var material: StandardMaterial3D = surfaces[surface]
		var family := ("m%d" % material.get_instance_id()) if exact else _family(material)
		# A P5 dá a cada detalhe um alcance próprio (40 m + metade da caixa); faixas de 10 m deixam juntar, e o
		# lote usa o maior alcance do grupo: nada some antes do que sumia.
		var range_band := ceili(mesh_node.visibility_range_end / 10.0) if mesh_node.visibility_range_end > 0.0 else 0
		var key := "%s|%s|%s|%d|%d|%d|%.2f|%d|%d" % [cell, flat, family, mesh_node.layers, shadow,
			mesh_node.gi_mode, mesh_node.visibility_range_begin, range_band, mesh_node.visibility_range_fade_mode]
		if not groups.has(key): groups[key] = []
		groups[key].append({"node": mesh_node, "mesh": mesh, "surface": surface, "transform": transform, "material": material, "shadow": shadow})

## Família: tudo do material menos a cor. Peças que só mudam de cor (cada contêiner, cada mesa) entram no
## mesmo lote com a cor gravada no vértice, como o "prelit" do reVC. Os materiais das fontes não mudam.
static var _families := {}
static var _family_materials := {}
const FAMILY_SKIP := ["albedo_color", "resource_name", "resource_path", "resource_local_to_scene", "resource_scene_unique_id", "script"]
static func _family(material: StandardMaterial3D) -> String:
	var id := material.get_instance_id()
	if _families.has(id) and _families[id].ref.get_ref() == material: return _families[id].key
	var parts := PackedStringArray()
	for property in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or String(property.name) in FAMILY_SKIP: continue
		var value: Variant = material.get(property.name)
		parts.append("%s=%s" % [property.name, str(value.get_instance_id()) if value is Object else var_to_str(value)])
	# Detalhe na segunda camada de UV depende de outra UV que o lote não leva: fica fora.
	var key := "" if material.detail_enabled and material.detail_uv_layer == BaseMaterial3D.DETAIL_UV_2 else "|".join(parts).sha256_text()
	if _families.size() > 8192: _families.clear()
	_families[id] = {"key": key, "ref": weakref(material)}
	if not key.is_empty() and not _family_materials.has(key):
		var shared := material.duplicate() as StandardMaterial3D
		# Material que já usava cor no vértice mantém o espaço de cor dele: forçar sRGB numa cor linear
		# escureceu os pinheiros e as árvores da serra (captura de 14/10).
		if not material.vertex_color_use_as_albedo: shared.vertex_color_is_srgb = true
		shared.vertex_color_use_as_albedo = true
		shared.albedo_color = Color(1, 1, 1, material.albedo_color.a)
		_family_materials[key] = shared
		preload("res://world/chunk_bake/FamilyShaderVariants.gd").note(shared)
	return key

## Lote com posição, normal, tangente, UV e cor por vértice, no espaço do escopo. No thread principal só a
## leitura das arrays de origem (cedendo o quadro entre peças) e o commit; a montagem das arrays (_assemble,
## conta pura) vai para um WorkerThreadPool quando o lote é grande. Com o orçamento zerado (testes, censo)
## tudo roda aqui, de uma vez.
static func _build_batch(entries: Array, exact: bool, slice: Slice) -> ArrayMesh:
	var family_material: StandardMaterial3D = entries[0].material if exact else _family_materials.get(_family(entries[0].material))
	if family_material == null: return null
	var use_tangent := family_material.normal_enabled
	var parts: Array = []
	var total := 0
	for entry in entries:
		if not await _yield_if_due(slice): return null
		var arrays: Array = _arrays_of(entry.mesh, entry.surface)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if source_vertices.is_empty(): continue
		var source: StandardMaterial3D = entry.material
		var tint := source.albedo_color
		var keep_colors: bool = source.vertex_color_use_as_albedo and arrays[Mesh.ARRAY_COLOR] != null
		# Material original: a cor do vértice só importa se ele já a usava; senão vai branco, sem efeito.
		if exact: tint = Color.WHITE
		# Família com cor linear: a cor do material (sRGB) entra convertida, como o shader faria com albedo_color.
		elif not family_material.vertex_color_is_srgb: tint = tint.srgb_to_linear()
		parts.append({"arrays": arrays, "transform": entry.transform, "tint": tint, "keep_colors": keep_colors})
		total += source_vertices.size()
	if parts.is_empty(): return null
	var built := {}
	if slice.budget_usec > 0 and total >= WORKER_MIN_VERTICES:
		var task := WorkerThreadPool.add_task(Callable(_script(), "_assemble").bind(parts, use_tangent, built), false, "cell merge batch")
		await _await_task(task, slice)
	else:
		_assemble(parts, use_tangent, built)
	# O commit (envio à placa) começa numa fatia nova se esta já gastou o orçamento.
	if not await _yield_if_due(slice): return null
	if not built.has("indices"): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built.vertices
	arrays[Mesh.ARRAY_NORMAL] = built.normals
	if use_tangent: arrays[Mesh.ARRAY_TANGENT] = built.tangents
	arrays[Mesh.ARRAY_TEX_UV] = built.uvs
	# Material original (prédio com reveal) que não usa cor no vértice: sem atributo de cor. Material conhecido
	# com formato de vértice novo é um pipeline novo, compilado no primeiro desenho: era o que travava na serra
	# (cabanas, 15/10), e o pré-aquecimento das variantes da família não cobre o material original.
	if not exact or family_material.vertex_color_use_as_albedo: arrays[Mesh.ARRAY_COLOR] = built.colors
	arrays[Mesh.ARRAY_INDEX] = built.indices
	# LOD do lote (GETECO_PROC_LOD=1): simplificação só no trabalhador; aqui só entram os índices prontos.
	var lods := {}
	if PROC_LOD.wanted((built.indices as PackedInt32Array).size(), slice.budget_usec):
		var generated := {}
		var lod_task := WorkerThreadPool.add_task(Callable(PROC_LOD, "generate").bind(arrays, generated), false, "cell merge lod")
		await _await_task(lod_task, slice)
		if not await _yield_if_due(slice): return null
		if generated.has("lods"):
			arrays = generated.arrays
			lods = generated.lods
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	mesh.surface_set_material(0, family_material)
	return mesh

static var _self_script: Script
static func _script() -> Script:
	if _self_script == null: _self_script = load("res://world/chunk_bake/ChunkCellMerge.gd")
	return _self_script

## Espera o trabalhador cedendo quadros (o span da fatia não inclui a espera). Toda tarefa é esperada até o
## fim, mesmo se o trecho sumiu: o chamador revalida depois.
static func _await_task(task: int, slice: Slice) -> void:
	if not WorkerThreadPool.is_task_completed(task):
		STALL_WORK.finish_slow("chunk.cell_merge", slice.began, 1500)
		var tree := Engine.get_main_loop() as SceneTree
		while not WorkerThreadPool.is_task_completed(task): await tree.process_frame
		slice.began = STALL_WORK.begin()
		slice.budget_began = Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(task)

## Conta pura (segura num trabalhador): transforma posição, normal, UV e cor em bloco e reindexa. O laço em
## GDScript por vértice (tangente, cor do vértice, escala não uniforme) era o grosso do custo da fusão.
static func _assemble(parts: Array, use_tangent: bool, out: Dictionary) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for part: Dictionary in parts:
		var arrays: Array = part.arrays
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var count_vertices := source_vertices.size()
		var transform: Transform3D = part.transform
		var normal_basis := transform.basis.inverse().transposed()
		var tint: Color = part.tint
		var source_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var source_tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
		var source_uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var source_colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var base := vertices.size()
		vertices.append_array(transform * source_vertices)
		if source_normals == null:
			var up := PackedVector3Array()
			up.resize(count_vertices)
			up.fill(Vector3.UP)
			normals.append_array(up)
		elif _uniform_rotation(transform.basis):
			# Rotação com escala uniforme: a base das normais ortonormalizada dá o mesmo resultado do
			# normalized() por vértice (normais de origem unitárias), em bloco.
			normals.append_array(Transform3D(normal_basis.orthonormalized(), Vector3.ZERO) * (source_normals as PackedVector3Array))
		else:
			for normal in (source_normals as PackedVector3Array): normals.append((normal_basis * normal).normalized())
		if source_uvs != null: uvs.append_array(source_uvs)
		else:
			var zero := PackedVector2Array()
			zero.resize(count_vertices)
			uvs.append_array(zero)
		# Cor do vértice em sRGB como albedo_color; a cor do vértice original multiplica se o material a usava.
		if bool(part.keep_colors):
			for color in (source_colors as PackedColorArray): colors.append(tint * color)
		else:
			var flat := PackedColorArray()
			flat.resize(count_vertices)
			flat.fill(tint)
			colors.append_array(flat)
		if use_tangent:
			for index in count_vertices:
				var tangent := (transform.basis * Vector3(source_tangents[index * 4], source_tangents[index * 4 + 1], source_tangents[index * 4 + 2])).normalized()
				tangents.append_array([tangent.x, tangent.y, tangent.z, source_tangents[index * 4 + 3]])
		# Escala negativa inverte a ordem dos triângulos; sem corrigir, a face some pelo culling.
		var flip := transform.basis.determinant() < 0.0
		var source_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = source_indices.size() if source_indices != null else count_vertices
		var start := indices.size()
		indices.resize(start + count)
		if source_indices != null:
			var source_list: PackedInt32Array = source_indices
			if flip:
				for index in range(0, count, 3):
					indices[start + index] = base + source_list[index]
					indices[start + index + 1] = base + source_list[index + 2]
					indices[start + index + 2] = base + source_list[index + 1]
			else:
				for index in count: indices[start + index] = base + source_list[index]
		else:
			for index in range(0, count, 3):
				indices[start + index] = base + index
				indices[start + index + 1] = base + (index + 2 if flip else index + 1)
				indices[start + index + 2] = base + (index + 1 if flip else index + 2)
	out.vertices = vertices
	out.normals = normals
	out.tangents = tangents
	out.uvs = uvs
	out.colors = colors
	out.indices = indices

## Base de rotação com escala uniforme (positiva ou espelhada): normal transformada só muda de tamanho.
static func _uniform_rotation(basis: Basis) -> bool:
	var scale := basis.get_scale().abs()
	if scale.x <= 0.0 or not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.y, scale.z): return false
	var unit := Basis(basis.x / scale.x, basis.y / scale.y, basis.z / scale.z)
	return is_zero_approx(unit.x.dot(unit.y)) and is_zero_approx(unit.y.dot(unit.z)) and is_zero_approx(unit.x.dot(unit.z))

## Quais atributos a superfície tem (UV2, cor, tangente...): SurfaceTool só junta superfícies de mesmo formato.
## PrimitiveMesh não expõe o formato; as arrays dizem. Cache por recurso: centenas de caixas iguais.
static var _formats := {}
static func _surface_format(mesh: Mesh, surface: int) -> int:
	if mesh is ArrayMesh: return (mesh as ArrayMesh).surface_get_format(surface)
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if _formats.has(key): return _formats[key]
	var arrays := mesh.surface_get_arrays(surface)
	var format := 0
	for index in arrays.size():
		if arrays[index] != null: format |= 1 << index
	if _formats.size() > 4096: _formats.clear()
	_formats[key] = format
	return format

static func _material_allowed(material: StandardMaterial3D) -> bool:
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.emission_enabled or material.next_pass != null: return false
	if material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or material.get_meta("city_window", false): return false
	# Mapeamento no mundo (triplanar) depende da posição do nó: igual em lote porque os vértices vão no mundo do
	# escopo; mapeamento local mudaria. Fica de fora.
	if material.uv1_triplanar and not material.uv1_world_triplanar: return false
	if material.uv2_triplanar and not material.uv2_world_triplanar: return false
	return true

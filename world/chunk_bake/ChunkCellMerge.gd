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
static func finish_chunk_later(chunk: Node3D) -> void:
	if not enabled or not chunk.is_inside_tree(): return
	var reference: WeakRef = weakref(chunk)
	for frame in 2:
		await chunk.get_tree().process_frame
		if not is_instance_valid(reference.get_ref()): return
	await _run(chunk, slice_budget_usec)

static var _slice_began := 0
static var _slice_reference: WeakRef

static func _run(chunk: Node3D, budget_usec: int) -> Dictionary:
	var report := {"sources": 0, "batches": 0, "scopes": 0}
	if not enabled or chunk.has_meta(FINISHED) or not chunk.has_meta("vegetation_ready_frame"): return report
	if Engine.get_meta("geteco_live_preview_build", false): return report
	var region_id: Variant = chunk.get_parent().get("region_id") if chunk.get_parent() != null else null
	if region_id is String and not bool(region_enabled.get(region_id, true)): return report
	chunk.set_meta(FINISHED, true)
	_slice_began = STALL_WORK.begin()
	_slice_reference = weakref(chunk)
	# Um lote por trecho, entre objetos: as ~35 pilhas de carga do Northstar são objetos separados e, fundidas
	# só por dentro, sobravam 239 lotes. Prédios com acesso/reveal ficam com a fusão por prédio deles.
	var candidates: Array = []
	for child in chunk.get_children():
		if child is MeshInstance3D: candidates.append(child)
		elif child is Node3D and _scope_allowed(child as Node3D): candidates.append_array(child.get_children())
	_sum(report, await _merge_scope(chunk, candidates, false, budget_usec))
	# Prédios só com reveal (cabanas da serra: 220 malhas cada, poços do porto): o reveal escolhe peça a peça
	# dentro do prédio pela caixa e troca o material pela cor dele, então o lote fica dentro do prédio, em
	# célula pequena e com o material original, sem cor no vértice.
	var reveal_scopes: Array = []
	if is_instance_valid(_slice_reference.get_ref()):
		for child in chunk.get_children():
			if child is Node3D and _reveal_scope_allowed(child as Node3D): reveal_scopes.append(child)
	for scope in reveal_scopes:
		if not is_instance_valid(scope): continue
		_sum(report, await _merge_scope(scope as Node3D, scope.get_children(), true, budget_usec))
	_arrays.clear()
	if not is_instance_valid(_slice_reference.get_ref()): return report
	STALL_WORK.finish_slow("chunk.cell_merge", _slice_began, 1500)
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
static func _yield_if_due(budget_usec: int) -> bool:
	if budget_usec <= 0 or Time.get_ticks_usec() - _slice_began < budget_usec: return true
	var chunk := _slice_reference.get_ref() as Node
	if not is_instance_valid(chunk) or not chunk.is_inside_tree(): return false
	STALL_WORK.finish_slow("chunk.cell_merge", _slice_began, 1500)
	await chunk.get_tree().process_frame
	_slice_began = STALL_WORK.begin()
	var still := _slice_reference.get_ref() as Node
	return is_instance_valid(still) and still.is_inside_tree()

## Arrays por malha e superfície, lidos uma vez por trecho: cabanas e contêineres repetem a mesma malha.
static var _arrays := {}
static func _arrays_of(mesh: Mesh, surface: int) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(), surface]
	if not _arrays.has(key): _arrays[key] = mesh.surface_get_arrays(surface)
	return _arrays[key]

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
	if merged.batches > 0: report.scopes += 1
	report.sources += merged.sources
	report.batches += merged.batches

static func _scope_allowed(scope: Node3D) -> bool:
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

static func _merge_scope(scope: Node3D, candidates: Array, exact := false, budget_usec := 0) -> Dictionary:
	var groups := {}
	var to_scope := scope.global_transform.affine_inverse()
	_collect(candidates, scope, to_scope, groups, exact)
	var report := {"sources": 0, "batches": 0}
	var holder: Node3D = null
	for key in groups:
		# Cada grupo é atômico: a fonte só some quando o lote dela já existe, então ceder entre grupos não
		# deixa buraco nem desenho em dobro.
		if not await _yield_if_due(budget_usec) or not is_instance_valid(scope): return report
		# Grupo de um só também vira lote: a fonte só some se todas as superfícies dela tiverem lote.
		var entries: Array = groups[key]
		var mesh := _build_batch(entries, exact)
		if mesh == null: continue
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
			if source.has_meta(MERGED_SOURCE): continue
			source.set_meta(MERGED_SOURCE, true)
			source.visible = false
			report.sources += 1
	return report

static func _collect(candidates: Array, scope: Node3D, to_scope: Transform3D, groups: Dictionary, exact := false) -> void:
	for child in candidates:
		if child.has_meta(BATCH) or child.has_meta(MERGED_SOURCE): continue
		if not child is Node3D or not (child as Node3D).visible: continue
		if _is_dynamic(child) or _protected(child): continue
		if child is MeshInstance3D:
			_add_mesh(child as MeshInstance3D, scope, to_scope, groups, exact)
			continue
		# Corpos estáticos guardam visuais como filhos; eles não se mexem.
		if child.get_child_count() > 0 and not child is MeshInstance3D: _collect(child.get_children(), scope, to_scope, groups, exact)

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

## Lote com posição, normal, tangente, UV e cor por vértice, no espaço do escopo.
static func _build_batch(entries: Array, exact := false) -> ArrayMesh:
	var family_material: StandardMaterial3D = entries[0].material if exact else _family_materials.get(_family(entries[0].material))
	if family_material == null: return null
	var use_tangent := family_material.normal_enabled
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for entry in entries:
		var arrays: Array = _arrays_of(entry.mesh, entry.surface)
		var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if source_vertices.is_empty(): continue
		var transform: Transform3D = entry.transform
		var normal_basis := transform.basis.inverse().transposed()
		var source: StandardMaterial3D = entry.material
		var tint := source.albedo_color
		var source_normals: Variant = arrays[Mesh.ARRAY_NORMAL]
		var source_tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
		var source_uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var source_colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var keep_colors: bool = source.vertex_color_use_as_albedo and source_colors != null
		# Material original: a cor do vértice só importa se ele já a usava; senão vai branco, sem efeito.
		if exact: tint = Color.WHITE
		# Família com cor linear: a cor do material (sRGB) entra convertida, como o shader faria com albedo_color.
		elif not family_material.vertex_color_is_srgb: tint = tint.srgb_to_linear()
		var base := vertices.size()
		for index in source_vertices.size():
			vertices.append(transform * source_vertices[index])
			normals.append((normal_basis * source_normals[index]).normalized() if source_normals != null else Vector3.UP)
			uvs.append(source_uvs[index] if source_uvs != null else Vector2.ZERO)
			# Cor do vértice em sRGB como albedo_color; a cor do vértice original multiplica se o material a usava.
			colors.append(tint * source_colors[index] if keep_colors else tint)
			if use_tangent:
				var tangent := (transform.basis * Vector3(source_tangents[index * 4], source_tangents[index * 4 + 1], source_tangents[index * 4 + 2])).normalized()
				tangents.append_array([tangent.x, tangent.y, tangent.z, source_tangents[index * 4 + 3]])
		# Escala negativa inverte a ordem dos triângulos; sem corrigir, a face some pelo culling.
		var flip := transform.basis.determinant() < 0.0
		var source_indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = source_indices.size() if source_indices != null else source_vertices.size()
		for index in range(0, count, 3):
			var a: int = source_indices[index] if source_indices != null else index
			var b: int = source_indices[index + 1] if source_indices != null else index + 1
			var c: int = source_indices[index + 2] if source_indices != null else index + 2
			if flip: indices.append_array([base + a, base + c, base + b])
			else: indices.append_array([base + a, base + b, base + c])
	if vertices.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if use_tangent: arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	# Material original (prédio com reveal) que não usa cor no vértice: sem atributo de cor. Material conhecido
	# com formato de vértice novo é um pipeline novo, compilado no primeiro desenho: era o que travava na serra
	# (cabanas, 15/10), e o pré-aquecimento das variantes da família não cobre o material original.
	if not exact or family_material.vertex_color_use_as_albedo: arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, family_material)
	return mesh

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

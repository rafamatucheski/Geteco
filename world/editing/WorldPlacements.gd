extends RefCounted
## Mobiliário urbano em lote (hidrante, lixeira, semáforo, banco, poste de calçada...): o gerador
## monta cada tipo num único MultiMesh. Aqui cada posição vira uma peça editável SEM mexer no
## lote depois de pronto: a edição troca a posição na lista de colocações ANTES do MultiMesh
## nascer, então a colisão, a derrubada pelo carro e a mancha de luz seguem a nova posição.
##
## Identidade: `piece/pl/<região>/<cx>_<cz>/<tipo>~<x>_<z>` com a posição ORIGINAL em
## decímetros; não depende de ler instâncias do MultiMesh (o renderizador dummy da prévia não as
## devolve). A peça fica no chunk de origem, como `WorldUnits`.
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
const UNITS := preload("res://world/editing/WorldUnits.gd")
const PREFIX := "piece/pl/"
const LAMP := "sidewalk_lamp"
const KINDS := ["signal_pole", "stop_sign", "hydrant", "trash_can", "news_box", "mailbox", "phone_booth", "bench_seat", "dumpster", "trash_bags", "planter"]
const LABELS := {"signal_pole": "Semáforo", "stop_sign": "Placa de pare", "hydrant": "Hidrante", "trash_can": "Lixeira", "news_box": "Banca de jornal", "mailbox": "Caixa de correio",
	"phone_booth": "Orelhão", "bench_seat": "Banco", "dumpster": "Caçamba", "trash_bags": "Sacos de lixo", "planter": "Jardineira", "sidewalk_lamp": "Poste de calçada"}

static func _changes(region: Node) -> Dictionary:
	var all: Variant = region.get("_piece_changes")
	if not all is Dictionary: return {}
	var result := {}
	for id in all:
		if str(id).begins_with(PREFIX) or str(all[id].get("clone_of","")).begins_with(PREFIX): result[id] = all[id]
	return result

static func active(region: Node) -> bool:
	if region == null or UNITS.disabled() or region.get("region_id") == null: return false
	return UNITS.preview_active() or not _changes(region).is_empty()

static func _cell(chunk: Node3D) -> Vector2i:
	var bits := str(chunk.name).trim_prefix("Chunk_").split("_")
	return Vector2i(int(bits[0]), int(bits[1])) if bits.size() == 2 else Vector2i.ZERO

## Edita as listas em lugar (`batches[tipo]` = Array de Transform3D globais).
static func edit_batches(region: Node, chunk: Node3D, batches: Dictionary) -> void:
	if not active(region): return
	for kind in KINDS:
		if batches.has(kind): batches[kind] = _edit(region, chunk, kind, batches[kind])

## Postes de calçada: devolve a lista tipada que `_sidewalk_lamps` usa.
static func edit_lamps(region: Node, chunk: Node3D, transforms: Array[Transform3D]) -> Array[Transform3D]:
	if not active(region): return transforms
	var edited: Array[Transform3D] = []
	edited.assign(_edit(region, chunk, LAMP, transforms))
	return edited

static func _edit(region: Node, chunk: Node3D, kind: String, source: Array) -> Array:
	var changes := _changes(region)
	var cell := _cell(chunk)
	var preview := UNITS.preview_active()
	var seen := {}
	var result: Array = []
	var records: Array = chunk.get_meta("world_pl", []) if preview else []
	for original: Transform3D in source:
		var base_id := "%s%s/%d_%d/%s~%d_%d" % [PREFIX, region.region_id, cell.x, cell.y, kind, roundi(original.origin.x * 10.0), roundi(original.origin.z * 10.0)]
		var id := base_id
		var serial := int(seen.get(base_id, 0))
		seen[base_id] = serial + 1
		if serial > 0: id += "~%d" % serial
		# Cópias nascem da forma original, mesmo que a origem tenha sido movida ou excluída.
		var copies: Array = []
		for clone_id in changes:
			var clone_row: Dictionary = changes[clone_id]
			if str(clone_row.get("clone_of", "")) == id and not clone_row.get("deleted", false): copies.append([clone_id, _transform(original, clone_row)])
		var row: Dictionary = changes.get(id, {})
		var edited := original
		var kept := true
		if not row.is_empty():
			if row.get("deleted", false): kept = false
			else: edited = _transform(original, row)
		if kept:
			result.append(edited)
			if preview: records.append({"kind": kind, "id": id, "original": original, "edited": edited})
		for copy in copies:
			result.append(copy[1])
			if preview: records.append({"kind": kind, "id": copy[0], "original": original, "edited": copy[1]})
	if preview: chunk.set_meta("world_pl", records)
	return result

static func _transform(original: Transform3D, row: Dictionary) -> Transform3D:
	var stretch: Array = row.get("stretch", [1.0, 1.0])
	var basis := Basis(Vector3.UP, deg_to_rad(float(row.get("rotation", 0.0)))) * original.basis
	basis = basis * Basis.from_scale(Vector3(float(stretch[0]), float(row.get("height_stretch", 1.0)), float(stretch[1])))
	return Transform3D(basis, Vector3(float(row.position[0]), original.origin.y + float(row.get("lift", 0.0)), float(row.position[1])))

# ---------------------------------------------------------------- prévia

## Só no auxiliar da prévia, com a região pronta: troca cada instância dos lotes editáveis por
## malhas soltas, cada uma numa peça (é o que a visão 3D consegue selecionar e arrastar).
static func explode_preview(region: Node) -> void:
	for chunk in region.get_children():
		if not chunk is Node3D or not chunk.has_meta("world_pl"): continue
		var by_kind := {}
		for entry in chunk.get_meta("world_pl"):
			if not by_kind.has(entry.kind): by_kind[entry.kind] = []
			by_kind[entry.kind].append(entry)
		chunk.remove_meta("world_pl")
		for kind in by_kind:
			var sources: Array[MultiMeshInstance3D] = []
			for name in (["CityLook_sidewalk_lamp", "CityLook_sidewalk_lamp_head"] if kind == LAMP else ["CityLook_" + kind]):
				var found := chunk.get_node_or_null(name)
				if found is MultiMeshInstance3D: sources.append(found)
			if sources.is_empty(): continue
			var entries: Array = by_kind[kind]
			for index in entries.size():
				var entry: Dictionary = entries[index]
				var parts: Array = []
				for source in sources:
					if index >= source.multimesh.instance_count: continue
					var mesh := MeshInstance3D.new()
					mesh.name = str(source.name)
					mesh.mesh = source.multimesh.mesh
					mesh.material_override = source.material_override
					mesh.cast_shadow = source.cast_shadow
					chunk.add_child(mesh)
					mesh.global_transform = entry.edited
					parts.append(mesh)
				if parts.is_empty(): continue
				var edited: Transform3D = entry.edited
				var group := PIECES.group(chunk, parts, str(entry.id).trim_prefix("piece/"), str(LABELS.get(kind, kind)), false, Vector3(edited.origin.x, chunk.global_position.y, edited.origin.z))
				group.set_meta("world_edit_auto", true)
				group.set_meta("world_edit_source", "placement/%s" % region.region_id)
				# O documento fala em posição ORIGINAL + delta: a base é onde o gerador pôs a peça.
				var original: Transform3D = entry.original
				var shift := original.origin - edited.origin
				var base: Dictionary = group.get_meta("world_edit_base")
				base.pivot = [original.origin.x, original.origin.z]
				base.bounds = AABB((base.bounds as AABB).position + Vector3(shift.x, 0, shift.z), (base.bounds as AABB).size)
				group.set_meta("world_edit_base", base)
				# Já nasceu com a edição aplicada: nunca reaplicar o documento por cima.
				group.set_meta("world_edit_origin", group.global_transform)
			for source in sources:
				chunk.remove_child(source)
				source.free()

extends SceneTree
## Clones vÃªm de WorldEditPieces.prepare real; lifecycle usa NativeRegion real.
const REGION := preload("res://world/regions/NativeRegion.gd")
const PIECES := preload("res://world/editing/WorldEditPieces.gd")
var checks := 0
var failures := 0


func _initialize() -> void:
	_run()
	print("%s REGION_CACHE_PIECE_VARIANTS checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REGION_CACHE_PIECE_VARIANTS: " + label)


func _chunk(owner: REGION, record: Dictionary) -> Node3D:
	var chunk := Node3D.new()
	owner.add_child(chunk)
	owner._build_record_cached(chunk, record)
	return chunk


func _run() -> void:
	var owner := REGION.new() # Fora da Ã¡rvore: sem mundo, renderizaÃ§Ã£o ou _ready.
	var record := {"kind": "harbor_public_realm", "zone_id": "union_plaza", "position": Vector3.ZERO}
	owner._record(Vector3.ZERO, record)
	var source_key: String = PIECES.record_key(record)
	var doc := {"regions": {"harbor": {
		"piece/cache/a": {"id": "piece/cache/a", "type": "piece", "source_record": source_key, "position": [128.0, 0.0], "rotation": 0.0},
		"piece/cache/b": {"id": "piece/cache/b", "type": "piece", "source_record": source_key, "position": [256.0, 0.0], "rotation": 0.0},
	}}}
	var had_meta := Engine.has_meta("geteco_world_edit_document")
	var previous = Engine.get_meta("geteco_world_edit_document") if had_meta else null
	Engine.set_meta("geteco_world_edit_document", doc)
	PIECES.prepare(owner, Engine.get_meta("geteco_world_edit_document").regions.harbor)
	if had_meta: Engine.set_meta("geteco_world_edit_document", previous)
	else: Engine.remove_meta("geteco_world_edit_document")
	var clone_a: Dictionary = owner.records[Vector2i(2, 0)][0]
	var clone_b: Dictionary = owner.records[Vector2i(4, 0)][0]
	_check(clone_a.kind == clone_b.kind and clone_a.position == clone_b.position, "prepare criou clones com mesmo kind+position")
	_check(clone_a.editor_piece_only == ["piece/cache/a"] and clone_b.editor_piece_only == ["piece/cache/b"], "clones produtivos tÃªm seleÃ§Ãµes distintas")
	_check(PIECES.record_key(clone_a) == source_key and PIECES.record_key(clone_b) == source_key, "identidade de origem produtiva preservada")
	var unchanged := {"kind": "harbor_public_realm", "position": Vector3.ZERO}
	var original_key := "%s|%s|%s" % [owner.region_id, str(unchanged.kind), str(Vector3.ZERO)]
	_check(owner._record_cache_key(unchanged) == original_key, "key sem ediÃ§Ã£o mantÃ©m formato anterior")
	var chunk_a := _chunk(owner, clone_a)
	var chunk_b := _chunk(owner, clone_b)
	var a: WeakRef = weakref(chunk_a.get_child(0))
	var b: WeakRef = weakref(chunk_b.get_child(0))
	var key_a: String = a.get_ref().get_meta("record_cache_key")
	var key_b: String = b.get_ref().get_meta("record_cache_key")
	_check(key_a != key_b and owner._record_cache.size() == 2, "variantes tÃªm entradas independentes")
	_check(a.get_ref().get_parent() == chunk_a and b.get_ref().get_parent() == chunk_b, "dois grupos permanecem ativos")
	owner._retire_chunk(chunk_a)
	owner._exit_tree()
	_check(a.get_ref().get_parent() == null and b.get_ref().get_parent() == chunk_b, "retire A preserva B")
	chunk_a = _chunk(owner, clone_a)
	_check(is_same(chunk_a.get_child(0), a.get_ref()), "reuso detached conserva identidade da variante A")
	_check(owner._record_cache.size() == 2, "reuso nÃ£o amplia nÃºmero de variantes")
	# Mesmo key ainda ativo: novo grupo substitui entry sem destruir grupo ativo.
	var replacement_chunk := _chunk(owner, clone_a)
	var replacement: WeakRef = weakref(replacement_chunk.get_child(0))
	_check(not is_same(replacement.get_ref(), a.get_ref()) and a.get_ref().get_parent() == chunk_a, "supersede conserva grupo antigo ainda parentado")
	owner._detach_cached_records(chunk_a)
	_check(a.get_ref().get_parent() == chunk_a, "superseded nÃ£o vira Ã³rfÃ£o no detach")
	owner._retire_chunk(chunk_a)
	owner._exit_tree()
	_check(a.get_ref() == null, "retire normal destrÃ³i grupo superseded")
	_check(is_instance_valid(replacement.get_ref()) and is_instance_valid(b.get_ref()), "retire antigo nÃ£o afeta novos grupos")
	owner._detach_cached_records(replacement_chunk)
	# Grupo invÃ¡lido com raiz detached vÃ¡lida: reconstruÃ§Ã£o limpa apenas esse resto.
	var stale := Node3D.new()
	owner._record_cache[key_a].append(stale)
	stale.free()
	var rebuilt_chunk := _chunk(owner, clone_a)
	var rebuilt: WeakRef = weakref(rebuilt_chunk.get_child(0))
	_check(replacement.get_ref() == null and is_instance_valid(rebuilt.get_ref()), "replace limpa raiz detached antiga antes de reconstruir")
	_check(b.get_ref().get_parent() == chunk_b, "replace nunca libera variante B ativa")
	owner._detach_cached_records(rebuilt_chunk)
	owner._detach_cached_records(chunk_b)
	var cache: Dictionary = owner._record_cache
	owner.free()
	_check(rebuilt.get_ref() == null and b.get_ref() == null and cache.is_empty(), "destruiÃ§Ã£o final limpa variantes detached rastreadas")

@tool
extends RefCounted
## The coroutine belongs to this script, so closing the editor cannot resume a freed Node.
static func run(reference: WeakRef,tree: SceneTree,area: String,rows: Array) -> void:
	var editor = reference.get_ref()
	if not is_instance_valid(editor) or not editor.is_inside_tree(): return
	if not editor.catalog.has(area) or rows.is_empty(): return
	editor.unit_index_generation += 1
	var token: int = editor.unit_index_generation
	editor._merging_units = true
	editor._refresh_controls()
	editor._report("Indexando objetos 2D. A câmera e a navegação continuam disponíveis.")
	var source_interior := str(editor.active_interior)
	var source_generation: int = editor.environment_generation
	var started := Time.get_ticks_usec()
	var batch_started := started
	var batch_count := 0
	var changed := 0
	var index_ok := true
	for row in rows:
		if editor._merge_unit(area,row):
			var id := str(row.id)
			var effective: Dictionary = editor._effective_row(area,id)
			if effective.is_empty(): editor.canvas.objects.erase(id)
			else: editor.canvas.objects[id] = effective
			batch_count += 1
			changed += 1
		if Time.get_ticks_usec()-batch_started > 2000 or batch_count >= 128:
			batch_count = 0
			await tree.process_frame
			editor = reference.get_ref()
			if not is_instance_valid(editor) or editor.unit_index_generation != token: return
			if not editor.is_inside_tree() or str(editor.active_interior) != source_interior or editor.environment_generation != source_generation:
				editor._merging_units = false
				if editor.is_inside_tree(): editor._refresh_controls()
				return
			batch_started = Time.get_ticks_usec()
	if changed > 0:
		var indexed: bool = await preload("res://addons/geteco_world_editor/WorldMapContextIndex.gd").build(weakref(editor.canvas),tree,3000,Callable(editor,"_unit_index_progress").bind(token))
		editor = reference.get_ref()
		if not is_instance_valid(editor) or editor.unit_index_generation != token: return
		if not editor.is_inside_tree() or str(editor.active_interior) != source_interior or editor.environment_generation != source_generation:
			editor._merging_units = false
			if editor.is_inside_tree(): editor._refresh_controls()
			return
		if not indexed:
			index_ok = false
			editor._report("A indexação 2D mudou durante a carga; atualize a visão 3D para terminar de registrar os objetos.","error")

		editor._update_locations()
		editor._refresh_controls()
		editor._select(editor.canvas.selected_id)
	editor.canvas.queue_redraw()
	editor._merging_units = false
	editor._refresh_controls()
	if index_ok: editor._report("Objetos 2D prontos · %d peças indexadas." % rows.size())
	print("WORLD_EDITOR_UNIT_INDEX ",JSON.stringify({"rows":rows.size(),"changed":changed,"total_ms":(Time.get_ticks_usec()-started)/1000.0}))

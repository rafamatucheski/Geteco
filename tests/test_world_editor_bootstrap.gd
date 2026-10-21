extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
var checks := 0
var failures: Array[String] = []
var announced := false
var ready_parts := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var ui := UI.new()
	ui.deferred_bootstrap = true
	ui.edits_path = "res://.godot/bootstrap_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.draft_path = ui.edits_path+".draft"
	ui.ready_to_edit.connect(func():
		announced = true
		ready_parts = ui.canvas.context_parts.size())
	root.add_child(ui)
	check(not ui.initialized and not announced,"Native startup first presents an incomplete loading state")
	check(not ui.save(),"Saving is unavailable until the world index is ready")
	ui._commit(DATA.new_entity("tree",Vector2(50,110)))
	check(ui.document.regions.harbor.is_empty(),"Pending startup cannot accept speculative world mutations")
	var started := Time.get_ticks_usec()
	var frames := 0
	var saw_progress := false
	while not ui.initialized and Time.get_ticks_usec()-started < 20000000:
		await process_frame
		frames += 1
		if ui.status.text.contains("Indexando mapa 2D"): saw_progress = true
	check(ui.initialized and announced,"Deferred bootstrap completes and announces readiness")
	var expected_parts := 0
	for row in ui.canvas.objects.values():
		if row.type in ["context","piece"]: expected_parts += row.get("parts",[]).size()
	check(ready_parts > 0 and ready_parts == expected_parts,"Readiness is emitted only after the entire 2D context index exists")
	check(saw_progress and frames > 4,"Initial context indexing reports progress and yields frames")
	check(not ui.save_button.disabled,"Save becomes available after initialization")
	check(not FileAccess.file_exists(ui.edits_path),"Loading and blocked edits do not publish a world file")
	ui.free()
	await process_frame
	print("WORLD_EDITOR_BOOTSTRAP checks=",checks," failures=",failures.size()," frames=",frames)
	quit(0 if failures.is_empty() else 1)

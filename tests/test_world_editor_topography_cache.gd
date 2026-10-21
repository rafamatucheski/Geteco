extends SceneTree
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const PREVIEW := preload("res://addons/geteco_world_editor/WorldLivePreview.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var ui := UI.new()
	ui.background_topography_enabled = false
	ui.edits_path = "res://.godot/topography_cache_%d_%d.json" % [OS.get_process_id(),Time.get_ticks_usec()]
	ui.draft_path = ui.edits_path+".draft"
	root.add_child(ui)
	var original: Dictionary = ui.document.duplicate(true)
	var signature: String = PREVIEW.terrain_revision(ui.document,"harbor")
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color(.4,.5,.3,1))
	var tiles: Array = [{"texture":ImageTexture.create_from_image(image),"bounds":[-247,-147,155,112],"source_ids":[]}]
	var view: int = ui.view_mode.selected
	var center: Vector2 = ui.canvas.center
	ui._topography_ready("harbor",signature,tiles)
	check(ui.topography_installed.get("harbor","") == signature,"Matching terrain revision installs the real topography layer")
	check(ui.view_mode.selected == view and ui.canvas.center == center and not is_instance_valid(ui.live_preview),"Background topography preserves the chosen 2D view and camera")
	ui._topography_ready("harbor","stale-revision",tiles)
	check(ui.topography_installed.harbor == signature,"An obsolete worker response cannot replace current terrain")
	for index in 8: ui._topography_ready("harbor","old-%d" % index,tiles)
	check(ui.topography_cache.size() == 6 and ui.topography_cache_order.size() == 6,"Topography revision cache has a bounded memory footprint")
	ui.active_interior = "bank"
	check(not ui._topography_interest(),"Exterior terrain worker does not start for an interior")
	ui.active_interior = ""
	ui.canvas.center = Vector2(-176,-96)
	check(ui._topography_interest(),"Navigating to motocross requests terrain without opening 3D")
	ui.canvas.center = Vector2(45,110)
	ui.region = "mountain"
	check(ui._topography_interest(),"Choosing Mountain requests its complete terrain automatically")
	ui.region = "desert"
	check(ui._topography_interest(),"Choosing Desert requests real canyon topography automatically without enabling height sculpting")
	check(ui.document == original and not FileAccess.file_exists(ui.edits_path),"Topography does not edit or publish the world document")
	ui.background_topography_enabled = true
	var visible_preview := Control.new()
	root.add_child(visible_preview)
	ui.live_preview = visible_preview
	ui._queue_topography()
	check(not is_instance_valid(ui.topography_loader),"Visible 3D preview prevents a second region worker from starting")
	var mountain_signature: String = PREVIEW.terrain_revision(ui.document,"mountain")
	var partial_tiles: Array = [{"texture":tiles[0].texture,"bounds":tiles[0].bounds,"source_ids":[],"coverage_radius":0}]
	ui._live_topography_ready("mountain",mountain_signature,partial_tiles)
	check(not ui.topography_installed.has("mountain"),"Nearby 3D topography cannot certify complete regional coverage")
	partial_tiles[0].coverage_radius = -1
	ui._live_topography_ready("mountain",mountain_signature,partial_tiles)
	check(ui.topography_installed.get("mountain","") == mountain_signature,"Full-region 3D topography is reused without a background worker")
	visible_preview.free()
	ui.background_topography_enabled = false
	ui.region = "harbor"
	ui.canvas.region = "harbor"
	var unit := {"id":"piece/topography_fixture","type":"piece","source_record":"harbor/fixture","auto":true,"position":[-176,-96],"size":[2,2],"rotation":0,"parts":[[-177,-97,2,2,1,"778866"]],"label":"Fixture native unit"}
	var unit_tiles: Array = [{"texture":tiles[0].texture,"bounds":tiles[0].bounds,"source_ids":[],"coverage_radius":-1,"units":[unit],"foreground":{}}]
	ui._topography_ready("harbor",signature,unit_tiles)
	for frame in 2000:
		if ui.topography_unit_jobs.is_empty(): break
		await process_frame
	check(ui.topography_unit_jobs.is_empty() and ui.canvas.objects.has(unit.id),"Topography-only response indexes native units without opening 3D")
	check(ui.status.text.begins_with("Objetos 2D prontos"),"Completed indexing replaces the loading status with an explicit ready message")
	if ui.canvas.objects.has(unit.id):
		var moved: Dictionary = ui.canvas.objects[unit.id].duplicate(true)
		moved.position = [-172,-96]
		ui._commit(moved)
		check(ui.canvas.objects[unit.id].position == [-172,-96],"A native unit supplied by the 2D worker can be moved")
		ui._select(unit.id)
		ui._delete()
		check(not ui.canvas.objects.has(unit.id) and ui.document.regions.harbor[unit.id].deleted,"Deleting a topography unit removes its selectable geometry and records the draft")
		check(not ui.canvas.terrain_topography_foregrounds.harbor.has(unit.id),"Static foreground contains no duplicate ghost of the editable unit")
		ui._topography_ready("harbor",signature,unit_tiles)
		check(not ui.canvas.objects.has(unit.id),"Reapplying a cached topography response cannot resurrect a deleted native unit")
	ui.free()
	await process_frame
	print("WORLD_EDITOR_TOPOGRAPHY_CACHE checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

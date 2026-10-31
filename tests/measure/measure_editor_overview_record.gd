extends SceneTree
## Arnês de atribuição independente. Não altera o canvas de produção nem o mundo autoral.
const UI := preload("res://addons/geteco_world_editor/WorldEditor.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")

class ProfileRoad:
	extends "res://addons/geteco_world_editor/WorldRoadDrawing.gd"
	var configure_ms := 0.0
	func configure(rows: Array) -> void:
		var began := Time.get_ticks_usec()
		super.configure(rows)
		configure_ms += float(Time.get_ticks_usec()-began)/1000.0

class ProfileCanvas:
	extends "res://addons/geteco_world_editor/WorldMapCanvas.gd"
	var context_ms := 0.0
	var polygon_ms := 0.0
	var polygon_calls := 0
	var misses := 0
	func _overview_mesh(excluded := "") -> ArrayMesh:
		var began := Time.get_ticks_usec()
		var result := super._overview_mesh(excluded)
		context_ms += float(Time.get_ticks_usec()-began)/1000.0
		return result
	func _polygon_mesh(points: PackedVector2Array) -> ArrayMesh:
		polygon_calls += 1
		if not polygon_ok.has(hash(points)): misses += 1
		var began := Time.get_ticks_usec()
		var result := super._polygon_mesh(points)
		polygon_ms += float(Time.get_ticks_usec()-began)/1000.0
		return result

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440,900)
	var editor := UI.new()
	editor.edits_path = "res://.godot/overview_attribution_%d.json" % OS.get_process_id()
	editor.draft_path = editor.edits_path+".draft"
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor._switch_region("harbor")
	editor._set_view_mode(0)
	# Copia só o estado do script para um subtipo instrumentado antes do primeiro desenho.
	# Tabelas de objetos/malhas mantêm os dados exatos de produção; sem reconstrução do mapa inteiro.
	var original: Control = editor.canvas
	var canvas := ProfileCanvas.new()
	for property in original.get_property_list():
		if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and property.name not in ["road_drawing","overview_layer"]:
			canvas.set(property.name,original.get(property.name))
	canvas.road_drawing = ProfileRoad.new()
	canvas.road_ready = false
	canvas.context_overview_dirty = true
	canvas.polygon_ok.clear()
	canvas.polygon_meshes.clear()
	canvas.polygon_mesh_order.clear()
	canvas.overview_layer_key = []
	canvas.size_flags_horizontal = original.size_flags_horizontal
	canvas.size_flags_vertical = original.size_flags_vertical
	canvas.custom_minimum_size = original.custom_minimum_size
	var parent := original.get_parent()
	var slot := original.get_index()
	parent.remove_child(original)
	parent.add_child(canvas)
	parent.move_child(canvas,slot)
	editor.canvas = canvas
	original.free()
	editor._fit_world()
	for frame in 5: await process_frame
	var road_ms: float = float(canvas.road_drawing.get("configure_ms"))
	var report := {"record_ms":canvas.overview_rebuild_ms,"context_mesh_ms":canvas.context_ms,"road_configure_ms":road_ms,"polygon_lookup_and_build_ms":canvas.polygon_ms,"commands_and_inventory_residual_ms":canvas.overview_rebuild_ms-canvas.context_ms-road_ms-canvas.polygon_ms,"polygon_calls":canvas.polygon_calls,"polygon_cache_misses":canvas.misses,"mesh_commands":canvas.overview_command_count,"records":canvas.overview_record_count,"objects":canvas.objects.size(),"official_unchanged":DATA.disk_hash()==official}
	print("OVERVIEW_FIRST_RECORD_ATTRIBUTION ",JSON.stringify(report))
	editor.free()
	quit(0 if report.official_unchanged else 1)

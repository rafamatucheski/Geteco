extends SceneTree
## Capturas do editor do mundo com os bueiros: mapa 2D com o filtro "Bueiros" e a seleção de um deles.
const DATA := preload("res://world/editing/WorldEditData.gd")
func _initialize() -> void: _run.call_deferred()
func shot(name: String) -> void:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/world-editor-manholes/%s.png" % name))
func _run() -> void:
	root.size = Vector2i(1440, 900)
	var ui := preload("res://addons/geteco_world_editor/WorldEditor.gd").new()
	ui.edits_path = "res://.godot/manholes_cap_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui.canvas.filter_type = "manhole"
	ui._select("manhole/sewer_market")
	ui.canvas.center = Vector2(110, 80)
	ui.canvas.zoom = 3.2
	ui._refresh()
	await shot("harbor_filtro_bueiros")
	ui.canvas.filter_type = "all"
	ui._select("manhole/harbor_sewer")
	ui.canvas.center = DATA.point([73.9, 132.1])
	ui.canvas.zoom = 9.0
	ui._refresh()
	await shot("harbor_esgoto_selecionado")
	ui._set_array("position", 0, 80.0)
	ui._set_value("rotation", 40.0)
	await shot("harbor_esgoto_movido")
	ui._switch_region("desert")
	await process_frame
	ui.canvas.filter_type = "manhole"
	ui._select("manhole/desert_under_cellar")
	ui.canvas.center = Vector2(-330, -930)
	ui.canvas.zoom = 4.0
	ui._refresh()
	await shot("deserto_adega_selecionada")
	quit()

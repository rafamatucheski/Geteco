extends "res://tests/test_world_editor_live_preview.gd"
## Visão 3D com o mapa inteiro do Harbor e edição de vias pela própria visão 3D.
func click(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = pressed
	return event

func wait_built(previous: int, seconds: int) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var panel = ui.live_preview
		if panel.applied_revision > previous and panel.applied_revision == panel.revision and panel.submitted == panel.desired: return true
	push_error("Prévia não terminou: " + ui.live_preview.message.text)
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440, 900)
	ui = UI.new()
	ui.edits_path = "res://.godot/big3d_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui.canvas.center = Vector2(380, 100)
	ui._set_view_mode(1)
	if not await settled(0): ui.free(); quit(1); return
	var panel = ui.live_preview
	var edit = panel.edit_control
	var small: int = edit.meshes.size()
	# Mapa inteiro.
	var previous: int = panel.applied_revision
	var began := Time.get_ticks_msec()
	panel.reach_menu.select(3)
	panel.reach_menu.item_selected.emit(3)
	if not await wait_built(previous, 480): ui.free(); quit(1); return
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	print("MAPA_INTEIRO segundos=%.1f malhas=%d (antes %d) pecas=%d" % [seconds, edit.meshes.size(), small, edit.groups.size()])
	check(edit.meshes.size() > small * 5, "o mapa inteiro tem muito mais malhas que a fatia (%d × %d)" % [edit.meshes.size(), small])
	var containers := 0
	for id in edit.groups:
		if "container" in str(ui.canvas.objects.get(id, {}).get("label", "")).to_lower(): containers += 1
	check(containers >= 14, "os contêineres do navio são peças individuais (%d)" % containers)
	# Editar em alcance grande não reconstrói tudo.
	var revision: int = panel.revision
	var any_piece: String = ""
	for id in edit.groups:
		if str(id).begins_with("piece/unit/"): any_piece = str(id); break
	ui._select(any_piece)
	var row: Dictionary = ui.canvas.objects[any_piece].duplicate(true)
	var before_x: float = (edit.groups[any_piece][0] as Node3D).global_position.x
	row.position[0] += 3.0
	ui._commit(row)
	await process_frame
	check(panel.revision == revision, "editar não reconstrói o mapa")
	check(absf((edit.groups[any_piece][0] as Node3D).global_position.x - before_x - 3.0) < .2, "a alteração aparece na cena na hora (+3 m)")
	# Via pela visão 3D.
	var road := {}
	for id in ui.canvas.objects:
		var r: Dictionary = ui.canvas.objects[id]
		if r.type == "road" and not r.get("pathway", false) and str(r.get("editor_region", "")) == "harbor" and r.points.size() >= 2 and float(r.width) >= 6.0:
			road = r
			break
	check(not road.is_empty(), "há via do Harbor no mapa")
	var mid := (DATA.point(road.points[0]) + DATA.point(road.points[1])) * .5
	panel.focus = Vector3(mid.x, 0, mid.y)
	panel.view_size = 40.0
	panel._pose()
	await process_frame
	await process_frame
	var at: Vector2 = panel.camera.unproject_position(Vector3(mid.x, panel.focus.y, mid.y))
	ui.canvas.selected_id = ""
	edit.input_event(click(at, true))
	edit.input_event(click(at, false))
	check(ui.canvas.selected_id == road.id, "clicar na via na visão 3D seleciona a via (%s)" % ui.canvas.selected_id)
	var handle: Vector2 = panel.camera.unproject_position(Vector3(float(road.points[0][0]), panel.focus.y + .25, float(road.points[0][1])))
	check(edit.road_handle_at(handle) == 0, "o ponto 0 da via tem alça na visão 3D")
	var before: Array = ui.canvas.objects[road.id].points[0].duplicate()
	edit.input_event(click(handle, true))
	var motion := InputEventMouseMotion.new()
	motion.position = handle + Vector2(30, 0)
	edit.input_event(motion)
	edit.input_event(click(handle + Vector2(30, 0), false))
	var edited: Dictionary = ui.document.regions.harbor.get(road.id, {})
	check(not edited.is_empty() and edited.points[0] != before, "arrastar a alça move o ponto da via e grava no documento")
	# Exclusão de via pelo teclado.
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	del.pressed = true
	edit.input_event(del)
	check(ui.document.regions.harbor[road.id].get("deleted", false), "Delete exclui a via selecionada na visão 3D")
	check(DATA.disk_hash() == official, "mundo oficial intacto")
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-units")
	root.get_texture().get_image().save_png("res://evidence/editor-units/mapa-inteiro.png")
	ui.free()
	print("EDITOR_BIG ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)

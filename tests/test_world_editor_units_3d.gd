extends "res://tests/test_world_editor_live_preview.gd"
## Editor de verdade (janela renderizada): poste e fio do deserto, pedra automática e a
## ligação prévia -> catálogo -> seleção 3D -> documento -> reconstrução.
func nearest(label: String, around: Vector2) -> String:
	var best := ""
	var best_distance := INF
	for id in ui.canvas.objects:
		var row: Dictionary = ui.canvas.objects[id]
		if row.type != "piece" or label.to_lower() not in str(row.get("label", "")).to_lower(): continue
		var distance := DATA.point(row.position).distance_to(around)
		if distance < best_distance:
			best_distance = distance
			best = str(id)
	return best

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	var official := DATA.disk_hash()
	root.size = Vector2i(1440, 900)
	ui = UI.new()
	ui.edits_path = "res://.godot/units3d_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	ui._switch_region("desert")
	var focus := Vector2(354.5, -740)
	ui.canvas.center = focus
	ui._set_view_mode(1)
	if not await settled(0): ui.free(); quit(1); return
	var edit = ui.live_preview.edit_control
	var pole := nearest("Poste de energia", focus)
	check(not pole.is_empty(), "poste do deserto está no mapa")
	check(not ui.canvas.objects[pole].get("locked", true), "poste do deserto não está mais protegido")
	check(edit.groups.has(pole), "poste é indexado para edição 3D")
	var wire := nearest("Rede elétrica", focus)
	check(not wire.is_empty() and edit.groups.has(wire), "fio é indexado para edição 3D")
	var automatic := ""
	for id in ui.canvas.objects:
		if ui.canvas.objects[id].get("auto", false) and edit.groups.has(id):
			automatic = str(id)
			break
	check(not automatic.is_empty(), "peças automáticas (pedra/cacto...) chegaram da prévia ao mapa: %s" % automatic.substr(0, 60))
	# Arrastar o poste na visão 3D.
	var original: Vector3 = (edit.groups[pole][0] as Node3D).global_position
	var at: Vector2 = ui.live_preview.camera.unproject_position(original + Vector3(0.1, 1.5, 0))
	var picked: String = edit.pick(at)
	check(picked == pole, "clicar no poste seleciona o poste (%s)" % picked.substr(0, 50))
	edit.select_id(pole)
	var revision: int = ui.live_preview.revision
	edit.mode = 0
	edit.begin(at)
	check(edit.dragging, "arraste do poste começa")
	edit.update_drag(at + Vector2(40, 10))
	edit.finish()
	check(ui.document.regions.desert.has(pole), "mover o poste grava no documento")
	var row: Dictionary = ui.document.regions.desert[pole]
	check(row.type == "piece" and DATA.point(row.position).distance_to(DATA.point(ui.canvas.objects[pole].position)) < .001, "linha do poste é uma peça com posição")
	if not await settled(revision): ui.free(); quit(1); return
	var moved: Node3D = (edit.groups[pole][0] as Node3D)
	check(moved.global_position.distance_to(original) > 1.0, "poste mudou de lugar na visão 3D após reconstruir")
	# Excluir e restaurar o fio.
	revision = ui.live_preview.applied_revision
	edit.select_id(wire)
	edit.input_event(_key(KEY_DELETE))
	check(ui.document.regions.desert.get(wire, {}).get("deleted", false), "excluir o fio grava exclusão")
	if not await settled(revision): ui.free(); quit(1); return
	check(not edit.groups.has(wire), "fio some da visão 3D")
	ui._restore_id(wire)
	check(not ui.document.regions.desert.has(wire), "restaurar o fio remove a exclusão")
	# Peça automática: alterar e ver no 3D.
	revision = ui.live_preview.applied_revision
	if not await settled(revision): ui.free(); quit(1); return
	if not automatic.is_empty():
		var rock_before: Vector3 = (edit.groups[automatic][0] as Node3D).global_position
		ui.canvas.selected_id = automatic
		ui._set_array("position", 0, float(ui.canvas.objects[automatic].position[0]) + 5.0)
		check(ui.document.regions.desert.has(automatic), "alterar peça automática grava no documento")
		revision = ui.live_preview.applied_revision
		if not await settled(revision): ui.free(); quit(1); return
		var rock_after: Node3D = (edit.groups[automatic][0] as Node3D)
		check(absf(rock_after.global_position.x - (rock_before.x + 5.0)) < .1, "peça automática foi 5 m para o lado na prévia (%.2f -> %.2f)" % [rock_before.x, rock_after.global_position.x])
	# Duplicar o poste pela interface: a cópia aparece na prévia ao lado da mãe.
	revision = ui.live_preview.applied_revision
	ui._select(pole)
	ui._duplicate()
	var clone_id := ""
	for id in ui.document.regions.desert:
		if str(id).begins_with("piece/clone/"): clone_id = str(id)
	check(not clone_id.is_empty() and ui.document.regions.desert[clone_id].clone_of == pole, "duplicar o poste grava uma cópia ligada à origem")
	if not await settled(revision): ui.free(); quit(1); return
	check(edit.groups.has(clone_id) and edit.groups.has(pole), "cópia e origem existem na visão 3D")
	check(ui.canvas.objects.has(clone_id) and not ui.canvas.objects[clone_id].get("locked", true), "cópia aparece no mapa, editável")
	check(DATA.save_document(ui.document, "", ui.edits_path).is_empty(), "documento com peças salva")
	check(DATA.disk_hash() == official, "mundo oficial intacto")
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-units")
	root.get_texture().get_image().save_png("res://evidence/editor-units/desert-units.png")
	ui.free()
	print("EDITOR_UNITS ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

extends "res://tests/test_world_editor_live_preview.gd"
## Harbor no editor de verdade: mobiliário urbano em lote (poste de calçada) selecionado e
## arrastado na visão 3D, depois a reconstrução mostra a nova posição.
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
	ui.edits_path = "res://.godot/units3d_harbor_%d.json" % OS.get_process_id()
	ui.draft_path = ui.edits_path + ".draft"
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var focus := Vector2(45, 110)
	ui.canvas.center = focus
	ui._set_view_mode(1)
	if not await settled(0): ui.free(); quit(1); return
	var edit = ui.live_preview.edit_control
	var lamp := nearest("Poste de calçada", focus)
	check(not lamp.is_empty() and edit.groups.has(lamp), "poste de calçada do Harbor é peça indexada na visão 3D")
	var hydrant := nearest("Hidrante", focus)
	check(not hydrant.is_empty() and edit.groups.has(hydrant), "hidrante é peça indexada")
	var restaurant := nearest("Harbor Restaurant", focus)
	check(not restaurant.is_empty() and edit.groups.has(restaurant), "registro de região (terraço) é peça")
	var original: Vector3 = (edit.groups[lamp][0] as Node3D).global_position
	var at: Vector2 = ui.live_preview.camera.unproject_position(original + Vector3(0.05, 1.2, 0))
	var picked: String = edit.pick(at)
	check(picked == lamp, "clicar no poste seleciona o poste (%s)" % picked.substr(0, 60))
	edit.select_id(lamp)
	var revision: int = ui.live_preview.revision
	edit.mode = 0
	edit.begin(at)
	check(edit.dragging, "arraste do poste começa")
	edit.update_drag(at + Vector2(50, 0))
	edit.finish()
	check(ui.document.regions.harbor.has(lamp), "mover o poste grava no documento")
	if not await settled(revision): ui.free(); quit(1); return
	var moved: Node3D = edit.groups[lamp][0]
	check(moved.global_position.distance_to(original) > 1.0, "poste mudou de lugar após reconstruir (%s -> %s)" % [str(original), str(moved.global_position)])
	# Botão "Jogar aqui": abre o jogo de verdade perto do poste selecionado e não grava nada.
	ui._select(lamp)
	var saves_before := FileAccess.get_modified_time(ProjectSettings.globalize_path("user://GetecoV2/saves/slot_01.json")) if FileAccess.file_exists("user://GetecoV2/saves/slot_01.json") else 0
	ui._play_here()
	check(ui.play_pid > 0 and ui.status.text.begins_with("Jogo aberto"), "Jogar aqui abre o jogo (%s)" % ui.status.text.substr(0, 90))
	var waited := 0
	while waited < 25 and OS.is_process_running(ui.play_pid):
		await create_timer(1.0).timeout
		waited += 1
	check(OS.is_process_running(ui.play_pid), "o jogo continua rodando depois de %d s (carregou sem fechar)" % waited)
	OS.kill(ui.play_pid)
	check(FileAccess.file_exists("res://.godot/world_play_edits_%d.json" % OS.get_process_id()), "documento temporário com as alterações não salvas foi gravado")
	check(DATA.save_document(ui.document, "", ui.edits_path).is_empty(), "documento salva")
	check(DATA.disk_hash() == official, "mundo oficial intacto")
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://evidence/editor-units")
	root.get_texture().get_image().save_png("res://evidence/editor-units/harbor-units.png")
	ui.free()
	print("EDITOR_UNITS_HARBOR ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)

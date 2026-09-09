extends SceneTree

## Teste específico da tela "Colecionáveis" do menu de pausa (Headless).
## Não depende do Player.gd real nem de HarborGame.tscn — instancia
## PauseMenu.tscn isolado com um Player mínimo e falso (só o grupo "player"
## + a propriedade collectibles_found), pra validar unicamente a leitura de
## Player.collectibles_found + CollectibleCatalog.gd feita por
## ui/PauseMenu.gd, sem herdar dependências de outros sistemas em progresso.
##
## Cobre:
## 1. Estado vazio (nada encontrado) — tudo "???", progresso 0/6.
## 2. Estado parcial — achados conhecidos mostram nome/região reais, o resto
##    continua "???", progresso correto.
## 3. IDs desconhecidos (save de outra árvore/versão) são preservados como
##    linha "achado registrado", não descartados, e não contam no
##    denominador do catálogo conhecido.
## 4. Fechar a tela (botão e Esc) devolve o foco e não deixa a modal visível.

const PAUSE_MENU_SCENE := "res://ui/PauseMenu.tscn"
const COLLECTIBLE_CATALOG := preload("res://CollectibleCatalog.gd")

var failures: Array[String] = []
var step_results: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _report(step_name: String, ok: bool, details: String = "") -> void:
	step_results[step_name] = ok
	if ok:
		print("  [PASS] %s %s" % [step_name, ("- " + details) if details != "" else ""])
	else:
		print("  [FAIL] %s - %s" % [step_name, details])
		failures.append("%s: %s" % [step_name, details])

## Player mínimo: só o grupo "player" e collectibles_found, sem toda a
## complexidade do Player.gd real (armas, câmera, veículo...). Suficiente
## porque a tela só lê essa única propriedade.
func _make_fake_player(found: Array) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar collectibles_found: Array = []\n"
	script.reload()
	var p := Node.new()
	p.name = "FakePlayer"
	p.set_script(script)
	p.set("collectibles_found", found.duplicate())
	p.add_to_group("player")
	return p

func _open_pause_and_collectibles(pause_menu: Node) -> Dictionary:
	pause_menu.pause_game()
	var btn: Button = pause_menu.get_node_or_null("%BtnCollectibles")
	btn.pressed.emit()
	return {
		"modal": pause_menu.get_node_or_null("%CollectiblesModal"),
		"progress": pause_menu.get_node_or_null("%CollectiblesProgressLabel"),
		"list": pause_menu.get_node_or_null("%CollectiblesList"),
		"btn_close": pause_menu.get_node_or_null("%BtnCloseCollectibles"),
		"btn_open": btn,
	}

func _row_texts(row: Node) -> Dictionary:
	# PanelContainer > HBoxContainer > [VBoxContainer(title,region), status_label]
	var hbox := row.get_child(0)
	var vbox := hbox.get_child(0)
	var status := hbox.get_child(1)
	return {
		"title": (vbox.get_child(0) as Label).text,
		"region": (vbox.get_child(1) as Label).text,
		"status": (status as Label).text,
	}

func _run() -> void:
	print("=================================================================")
	print("=== TESTE: TELA DE COLECIONÁVEIS NO MENU DE PAUSA (HEADLESS) ===")
	print("=================================================================")

	var known_ids: Array = COLLECTIBLE_CATALOG.get_all_ids()
	_report("Catálogo carregado", known_ids.size() > 0, "%d IDs conhecidos" % known_ids.size())

	# =================================================================
	# CASO 1: estado vazio — nada encontrado
	# =================================================================
	print("\n--- [CASO 1] Nada encontrado ainda ---")
	var scene1 := (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(scene1)
	var fake1 := _make_fake_player([])
	root.add_child(fake1)
	await process_frame

	var ctx1 := _open_pause_and_collectibles(scene1)
	await process_frame

	var modal1_open: bool = ctx1["modal"] != null and ctx1["modal"].visible
	_report("Modal abre com o botão", modal1_open)

	var progress1: Label = ctx1["progress"]
	_report("Progresso mostra 0 do total", progress1 != null and progress1.text.begins_with("0 de %d" % known_ids.size()), "texto: '%s'" % (progress1.text if progress1 else "N/A"))

	var list1: VBoxContainer = ctx1["list"]
	var row_count1 := list1.get_child_count() if list1 else 0
	_report("Uma linha por colecionável conhecido", row_count1 == known_ids.size(), "%d linhas (esperado %d)" % [row_count1, known_ids.size()])

	var all_hidden := true
	var all_not_found := true
	if list1:
		for row in list1.get_children():
			var texts := _row_texts(row)
			if texts["title"] != "???" or texts["region"] != "???":
				all_hidden = false
			if texts["status"] != "NÃO ENCONTRADO":
				all_not_found = false
	_report("Nenhum achado revela nome/região sem ter sido encontrado", all_hidden)
	_report("Todas as linhas marcadas como não encontradas", all_not_found)

	# Fechar pelo botão devolve o foco e esconde a modal
	ctx1["btn_close"].pressed.emit()
	await process_frame
	_report("Fechar pelo botão esconde a modal", not ctx1["modal"].visible)
	_report("Fechar pelo botão devolve o foco ao botão que abriu", ctx1["btn_open"].has_focus())

	scene1.queue_free()
	fake1.queue_free()
	await process_frame

	# =================================================================
	# CASO 2: parcialmente coletado
	# =================================================================
	print("\n--- [CASO 2] Parcialmente coletado ---")
	var found2 := [String(known_ids[0]), String(known_ids[1])]
	var scene2 := (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(scene2)
	var fake2 := _make_fake_player(found2)
	root.add_child(fake2)
	await process_frame

	var ctx2 := _open_pause_and_collectibles(scene2)
	await process_frame

	var progress2: Label = ctx2["progress"]
	_report("Progresso conta só os encontrados", progress2.text.begins_with("2 de %d" % known_ids.size()), "texto: '%s'" % progress2.text)

	var found_titles := []
	var list2: VBoxContainer = ctx2["list"]
	for row in list2.get_children():
		var texts := _row_texts(row)
		if texts["status"] == "ENCONTRADO":
			found_titles.append(texts["title"])
	var expected_names := []
	for cid in found2:
		expected_names.append(String(COLLECTIBLE_CATALOG.get_entry(cid).get("name", cid)))
	var names_match := found_titles.size() == 2 and expected_names.all(func(n): return found_titles.has(n))
	_report("Achados coletados mostram nome real (não '???')", names_match, "encontrados: %s" % str(found_titles))

	# Escape fecha a modal igual ao botão
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	scene2._unhandled_input(esc)
	await process_frame
	_report("Esc fecha a modal de colecionáveis", not ctx2["modal"].visible)

	scene2.queue_free()
	fake2.queue_free()
	await process_frame

	# =================================================================
	# CASO 3: IDs desconhecidos (save de outra versão do mapa) preservados
	# =================================================================
	print("\n--- [CASO 3] IDs desconhecidos preservados, não descartados ---")
	var legacy_id := "col_navio_01" # id da árvore legada Main.tscn/CityDemo.gd
	var totally_unknown_id := "id_que_nao_existe_em_nenhum_catalogo"
	var found3 := [legacy_id, totally_unknown_id]
	var scene3 := (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(scene3)
	var fake3 := _make_fake_player(found3)
	root.add_child(fake3)
	await process_frame

	var ctx3 := _open_pause_and_collectibles(scene3)
	await process_frame

	var progress3: Label = ctx3["progress"]
	_report("Progresso conhecido não conta os desconhecidos", progress3.text.begins_with("0 de %d" % known_ids.size()), "texto: '%s'" % progress3.text)

	var list3: VBoxContainer = ctx3["list"]
	var preserved_rows := 0
	var has_legacy_header := false
	for child in list3.get_children():
		if child is Label and "REGISTROS PRESERVADOS" in (child as Label).text:
			has_legacy_header = true
		elif child is PanelContainer:
			var texts := _row_texts(child)
			if texts["status"] == "ENCONTRADO" and texts["title"] == "Achado registrado":
				preserved_rows += 1
	_report("Cabeçalho de registros preservados aparece", has_legacy_header)
	_report("Os 2 IDs desconhecidos viram linhas preservadas (não descartados)", preserved_rows == 2, "%d linhas preservadas" % preserved_rows)

	var total_rows3 := list3.get_child_count() - 1 # -1 pelo cabeçalho de legado
	_report("Lista tem conhecidos + desconhecidos, nada sumiu", total_rows3 == known_ids.size() + 2, "%d linhas (esperado %d)" % [total_rows3, known_ids.size() + 2])

	scene3.queue_free()
	fake3.queue_free()
	await process_frame

	_finish()

func _finish() -> void:
	print("\n=================================================================")
	print("=== RESULTADOS: TELA DE COLECIONÁVEIS NO MENU DE PAUSA ===")
	print("=================================================================")
	for step in step_results.keys():
		print("  [%s] %s" % ["PASS" if step_results[step] else "FAIL", step])
	print("-----------------------------------------------------------------")
	if failures.is_empty():
		print("=== SUCESSO: TODOS OS CASOS PASSARAM! (EXIT 0) ===")
		quit(0)
	else:
		printerr("=== FALHAS DETECTADAS (%d) ===" % failures.size())
		for f in failures:
			printerr("  - %s" % f)
		quit(1)

extends SceneTree
## Menu -> normal startup must keep one curtain and one slideshow clock.
## Calls presentation only; never prepares a slot or writes a personal save.
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	root.get_node("V2Launch").direct_start_consumed = true
	var menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await menu.sky.begin_continue()
	var original = menu.sky.curtain
	original.set_stage(.25, "Etapa em andamento")
	var art = original._root.get_node("Artwork")
	var first_index: int = art.current_index
	var target: float = original._target
	await menu._show_loading("slot_01", true)
	var transferred = root.get_node_or_null("LoadingCurtain")
	check(transferred == original, "novo jogo transfere a mesma cortina do menu")
	check(menu.sky.curtain == null, "menu deixa de ser dono da cortina transferida")
	check(original._root.get_node("Artwork") == art and art.current_index == first_index,
		"troca de dono preserva a arte e seu relógio")
	check(original._root.modulate.a == 1.0 and original._target >= target,
		"transferência mantém cobertura opaca e não reinicia a barra")
	menu.sky.cancel_continue()
	menu.queue_free()
	await process_frame
	check(is_instance_valid(original) and original.get_parent() == root,
		"cancelamento e remoção do menu não destroem a cortina transferida")
	await original.lift(1)
	await process_frame
	check(not is_instance_valid(original), "cortina transferida libera e limpa a apresentação")
	# Also cover callers with no earlier menu curtain (direct startup).
	menu = load("res://ui/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await menu._show_loading("rachas", true)
	var fresh = root.get_node_or_null("LoadingCurtain")
	check(fresh != null and fresh.variant == 2 and fresh._root.get_node("Artwork").current_index == 7,
		"partida direta cria uma única cortina com a arte da região")
	menu.queue_free()
	fresh.queue_free()
	await process_frame
	check(root.get_node_or_null("LoadingCurtain") == null, "nenhuma cortina ficou na raiz")
	print("LOADING_MENU_HANDOFF ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

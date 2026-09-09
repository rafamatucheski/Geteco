extends SceneTree
## Testes do apresentador isolado de dicas contextuais (ui/tutorial_preview/).
## Cobre: catálogo PT/EN completo, fila (uma dica por vez, FIFO), bloqueio
## (modal/combate/direção veloz informados pelo chamador), dispensa (manual,
## por tecla configurável, por tempo esgotado) e ausência de repetição
## durante a sessão -- e finaliza o processo (quit) ao final.
##
## Rodar (headless, não precisa de renderer para estas verificações lógicas):
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --headless --path "D:/geteco/game" --script res://tests/test_tutorial_preview.gd

const PRESENTER := preload("res://ui/tutorial_preview/TutorialHintPresenter.gd")
const CATALOG := preload("res://ui/tutorial_preview/TutorialHintCatalog.gd")

var failures := 0
var presenter: TutorialHintPresenter

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		print("ok   - ", message)
	else:
		failures += 1
		push_error("FAIL - " + message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	presenter = PRESENTER.new()
	world.add_child(presenter)
	await process_frame

	_test_catalog()
	await _test_queue_and_no_repeat_within_queue()
	await _test_timeout_duration()
	await _test_blocking_states()
	await _test_dismiss_key()
	_test_reset_preview()

	world.queue_free()
	await process_frame
	print("TUTORIAL_PREVIEW_TEST failures=", failures)
	quit(0 if failures == 0 else 1)

# ==========================================
# CATÁLOGO: os 7 contextos pedidos, PT + EN
# ==========================================
func _test_catalog() -> void:
	var expected_ids: Array[String] = [
		"first_trunk", "loadout_capacity", "cold_shelter",
		"thermal_shop", "tunnel", "rare_item", "police_search",
	]
	check(CATALOG.ids() == expected_ids, "Catálogo cobre exatamente os 7 contextos pedidos, na ordem")
	for id in expected_ids:
		var pt := CATALOG.get_hint(id, "pt")
		var en := CATALOG.get_hint(id, "en")
		check(not String(pt.get("title", "")).is_empty() and not String(pt.get("body", "")).is_empty(), "Texto PT presente e não vazio para '%s'" % id)
		check(not String(en.get("title", "")).is_empty() and not String(en.get("body", "")).is_empty(), "Texto EN presente e não vazio para '%s'" % id)
		check(pt.get("title") != en.get("title"), "PT e EN têm textos distintos (traduzidos de verdade) para '%s'" % id)
	check(CATALOG.get_hint("does_not_exist").is_empty(), "id desconhecido no catálogo retorna Dictionary vazio")
	check(not CATALOG.has_hint("does_not_exist") and CATALOG.has_hint("tunnel"), "has_hint() distingue id válido de inválido")

# ==========================================
# FILA (uma dica por vez, FIFO) + recusa de duplicata na fila
# ==========================================
func _test_queue_and_no_repeat_within_queue() -> void:
	check(not presenter.is_showing(), "Nenhuma dica ativa no início")

	var ok1 := presenter.request_hint("first_trunk")
	check(ok1, "request_hint() aceita um id válido, nunca visto")
	check(presenter.is_showing() and presenter.get_active_hint_id() == "first_trunk", "Sem nada bloqueando, a dica pedida fica ativa imediatamente")

	presenter.request_hint("loadout_capacity")
	presenter.request_hint("cold_shelter")
	check(presenter.get_pending_hints() == ["loadout_capacity", "cold_shelter"], "Pedidos feitos com uma dica já ativa entram na fila, em ordem (FIFO)")
	check(presenter.get_active_hint_id() == "first_trunk", "A dica ativa não é trocada enquanto outra está em exibição (uma por vez)")

	var requeue_active := presenter.request_hint("first_trunk")
	check(not requeue_active, "Pedir de novo a dica que já está ativa é recusado")
	var requeue_pending := presenter.request_hint("loadout_capacity")
	check(not requeue_pending, "Pedir de novo uma dica que já está na fila é recusado (sem duplicar)")
	check(presenter.get_pending_hints() == ["loadout_capacity", "cold_shelter"], "A fila não ganhou duplicata")

	presenter.dismiss_hint()
	await process_frame
	check(presenter.get_active_hint_id() == "loadout_capacity", "Ao dispensar, a próxima da fila assume automaticamente")
	check(presenter.get_pending_hints() == ["cold_shelter"], "A fila avança (quem apareceu sai dela)")

	var repeat_seen := presenter.request_hint("first_trunk")
	check(not repeat_seen, "Uma dica já mostrada nesta sessão não pode ser pedida de novo (sem repetição)")
	check(presenter.has_seen("first_trunk") and not presenter.has_seen("cold_shelter"), "has_seen() reflete exatamente o que já foi mostrado")
	check(not presenter.request_hint("nao_existe_id"), "id desconhecido é recusado por request_hint()")

	presenter.dismiss_hint()
	await process_frame
	check(presenter.get_active_hint_id() == "cold_shelter", "Segunda dispensa também avança a fila corretamente")
	presenter.dismiss_hint()
	await process_frame
	check(not presenter.is_showing() and presenter.get_pending_hints().is_empty(), "Fila e dica ativa esvaziadas para os próximos testes")
	presenter.set_hint_duration(30.0) # bem longo: só a dispensa manual/tecla deve valer daqui pra frente

# ==========================================
# DURAÇÃO LIMITADA (a dica some sozinha e libera a fila)
# ==========================================
func _test_timeout_duration() -> void:
	presenter.set_hint_duration(0.3)
	presenter.request_hint("thermal_shop")
	presenter.request_hint("tunnel")
	check(presenter.get_active_hint_id() == "thermal_shop", "Dica ativa antes do tempo esgotar")
	await create_timer(0.6).timeout
	check(presenter.get_active_hint_id() != "thermal_shop", "Dica some sozinha depois da duração configurada (timeout), sem precisar de dismiss_hint()")
	check(presenter.get_active_hint_id() == "tunnel", "Depois do timeout, a próxima da fila aparece automaticamente")
	check(presenter.has_seen("thermal_shop"), "Uma dica que expirou por timeout também conta como 'vista' (não repete)")
	presenter.dismiss_hint()
	await process_frame
	presenter.set_hint_duration(30.0) # volta a ser bem longo para o resto dos testes

# ==========================================
# BLOQUEIO: modal, combate e direção veloz informados pelo chamador
# ==========================================
func _test_blocking_states() -> void:
	# Começa de uma sessão limpa: os testes anteriores já "viram" algumas das
	# 7 ids do catálogo, e este teste precisa de 3 ids livres (uma por
	# cenário de bloqueio) -- reset_preview() é a própria API pública sendo
	# testada, então isso também serve como mais uma verificação dela.
	presenter.reset_preview()
	check(not presenter.is_showing() and presenter.get_pending_hints().is_empty(), "Nada ativo/pendente antes de testar bloqueio")

	# --- combate ---
	presenter.set_combat_active(true)
	check(presenter.is_blocked(), "is_blocked() reflete o estado de combate informado pelo chamador")
	var queued_during_combat := presenter.request_hint("rare_item")
	check(queued_during_combat, "Pedido durante combate é aceito (fica na fila) em vez de aparecer na hora")
	check(not presenter.is_showing(), "Nenhuma dica é exibida durante combate")
	check(presenter.get_pending_hints() == ["rare_item"], "O pedido feito durante combate fica esperando na fila")
	presenter.set_combat_active(false)
	await process_frame
	check(not presenter.is_blocked(), "is_blocked() volta a false quando o combate termina")
	check(presenter.is_showing() and presenter.get_active_hint_id() == "rare_item", "Assim que o combate termina, a dica que esperava na fila aparece sozinha")
	presenter.dismiss_hint()
	await process_frame

	# --- modal ---
	presenter.set_modal_active(true)
	presenter.request_hint("police_search")
	check(not presenter.is_showing(), "Nenhuma dica é exibida com um modal ativo")
	presenter.set_modal_active(false)
	await process_frame
	check(presenter.get_active_hint_id() == "police_search", "Dica em fila aparece assim que o modal fecha")
	presenter.dismiss_hint()
	await process_frame

	# --- direção veloz (todas as ids restantes já usadas: usar o único id que sobrou) ---
	check(not presenter.has_seen("loadout_capacity"), "id ainda não usado disponível para o teste de direção veloz")
	presenter.set_fast_driving_active(true)
	presenter.request_hint("loadout_capacity")
	check(not presenter.is_showing(), "Nenhuma dica é exibida durante direção veloz")
	presenter.set_fast_driving_active(false)
	await process_frame
	check(presenter.get_active_hint_id() == "loadout_capacity", "Dica em fila aparece assim que a direção veloz termina")
	presenter.dismiss_hint()
	await process_frame

# ==========================================
# DISPENSA por tecla configurável (recebida por parâmetro, não inventada aqui)
# ==========================================
func _test_dismiss_key() -> void:
	presenter.reset_preview()
	var action_name := "__tutorial_preview_test_dismiss__"
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F9
		InputMap.action_add_event(action_name, ev)

	presenter.set_dismiss_action(action_name)
	presenter.set_hint_duration(30.0)
	presenter.request_hint("first_trunk")
	check(presenter.is_showing(), "Dica ativa, pronta para testar a dispensa por tecla")

	var key_down := InputEventKey.new()
	key_down.physical_keycode = KEY_F9
	key_down.pressed = true
	Input.parse_input_event(key_down)
	await process_frame
	await process_frame
	check(not presenter.is_showing(), "A action configurada pelo chamador (não uma tecla fixa deste arquivo) dispensa a dica ativa")

	# Uma action não registrada no InputMap não deve travar nem gerar erro.
	presenter.request_hint("loadout_capacity")
	presenter.set_dismiss_action("__action_nao_registrada__")
	var stray_key := InputEventKey.new()
	stray_key.physical_keycode = KEY_ESCAPE
	stray_key.pressed = true
	Input.parse_input_event(stray_key)
	await process_frame
	check(presenter.is_showing(), "Uma dismiss_action não registrada no InputMap é ignorada com segurança (não derruba a dica por engano)")
	presenter.dismiss_hint()
	await process_frame

	InputMap.erase_action(action_name)

# ==========================================
# reset_preview(): limpa fila, estado e histórico "visto nesta sessão"
# ==========================================
func _test_reset_preview() -> void:
	presenter.set_dismiss_action("")
	presenter.set_combat_active(true)
	presenter.request_hint("cold_shelter")
	check(presenter.get_pending_hints() == ["cold_shelter"], "Fila com um pedido pendente antes do reset")

	presenter.reset_preview()
	check(presenter.get_pending_hints().is_empty(), "reset_preview() esvazia a fila")
	check(not presenter.is_showing(), "reset_preview() encerra qualquer dica ativa")
	check(not presenter.is_blocked(), "reset_preview() também limpa os estados de bloqueio informados pelo chamador")
	check(not presenter.has_seen("first_trunk") and not presenter.has_seen("cold_shelter"), "reset_preview() limpa o histórico de 'visto nesta sessão'")

	var replay_ok := presenter.request_hint("first_trunk")
	check(replay_ok, "Depois de reset_preview(), uma dica antes vista pode ser pedida de novo")
	check(presenter.is_showing() and presenter.get_active_hint_id() == "first_trunk", "E aparece normalmente")
	presenter.dismiss_hint()

extends SceneTree
## Catálogo e bancada da Ammu-Nation sobre a sessão real (economia, customização
## e Gameplay de produção). Cobre os itens 30, 32 e 33 do vídeo de 24/09:
## descrição/estado seguem a opção selecionada, preço e posse não se misturam e
## compra indisponível não mexe no saldo. Rode com --no-save --skip-arrival;
## --capture grava telas em evidence/claude-arsenal-ui-20260924 (fora do headless).

const CATALOG := preload("res://runtime/HarborAmmunationCatalog.gd")

var world: Node3D
var session: Node
var economy
var catalog
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail := "") -> bool:
	checks += 1
	print(("ARSENAL_UI PASS " if ok else "ARSENAL_UI FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok: failures.append(label)
	return ok

func set_balance(value: int) -> void:
	var data: Dictionary = economy.snapshot()
	data.balance = value
	economy.restore_snapshot(data)

func select(id: String) -> void:
	catalog.selection = catalog.stock.find(id)
	catalog.change_selection(0)

func action(name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	for _i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://evidence/claude-arsenal-ui-20260924")
	DirAccess.make_dir_recursive_absolute(directory)
	var error := root.get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	check(error == OK, "captura gravada: " + label, error_string(error))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--no-save" in args or not "--skip-arrival" in args:
		push_error("ARSENAL_UI recusa rodar sem --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for _i in 900:
		if world.session != null and world.session.ready_for_play and world.production.ready_for_play: break
		await physics_frame
	if not check(world.session != null and world.session.ready_for_play, "sessão inicia"):
		quit(1)
		return
	session = world.session
	economy = session.state.economy
	check(world.production.no_save, "fixture não usa save pessoal")
	var original_economy: Dictionary = economy.snapshot()
	var original_custom: Dictionary = session.world.gameplay.customization.duplicate(true)

	catalog = CATALOG.new()
	catalog.configure(session)
	root.add_child(catalog)
	catalog.open_catalog()
	await process_frame

	# Item 33: preço de tabela x posse.
	var data: Dictionary = economy.snapshot()
	data.weapons.erase("pistol")
	data.weapons.erase("smg")
	economy.restore_snapshot(data)
	set_balance(0)
	select("pistol")
	check("ITEM INICIAL • $0" in catalog.caption.text and not catalog.buy.disabled, "pistola não possuída mostra item inicial de custo zero", catalog.caption.text + " / " + catalog.buy.text)
	economy.grant_weapon("pistol")
	catalog.refresh()
	check("JÁ POSSUI" in catalog.caption.text and not "$" in catalog.caption.text, "pistola possuída mostra posse, não $0", catalog.caption.text)
	check(catalog.buy.disabled and catalog.buy.text == "JÁ POSSUI", "compra de arma possuída fica desabilitada", catalog.buy.text)
	await capture("catalogo-pistola-possuida")
	economy.grant_weapon("smg")
	select("smg")
	check("JÁ POSSUI" in catalog.caption.text and not "1200" in catalog.caption.text, "SMG possuída não exibe preço de tabela como se estivesse à venda", catalog.caption.text)

	# Compra indisponível: rótulo e retorno claros, saldo intacto.
	set_balance(100)
	select("shotgun")
	var price := int(catalog.data().price)
	check(catalog.buy.disabled and catalog.buy.text == "SALDO INSUFICIENTE • $%d" % price, "saldo curto explica o bloqueio no botão", catalog.buy.text)
	check("Faltam $%d" % (price - 100) in catalog.feedback.text, "feedback informa quanto falta", catalog.feedback.text)
	catalog.purchase()
	check(economy.balance == 100 and not economy.owns_weapon("shotgun"), "compra bloqueada não altera saldo nem inventário")

	# Navegação: abas por clique e teclado.
	catalog.category_buttons[1].pressed.emit()
	var tabs: Array = catalog.category_buttons.map(func(b): return b.button_pressed)
	check(catalog.stock[catalog.selection] == "shotgun" and tabs == [false, true, false, false, false], "aba ARMAS LONGAS seleciona escopeta e só ela fica marcada", str(tabs))
	check(catalog.handle_input(action("ui_right")) and catalog.stock[catalog.selection] == "sawed_off", "seta direita avança item")
	check(catalog.handle_input(action("ui_left")) and catalog.stock[catalog.selection] == "shotgun", "seta esquerda volta item")
	await capture("catalogo-saldo-insuficiente")

	# Item 30: bancada distingue instalado, prévia e compra.
	select("pistol")
	set_balance(100)
	catalog.open_workbench()
	var bench = catalog.workbench
	check(bench.visible and not catalog.panel.visible, "bancada abre no lugar do catálogo")
	bench.select_slot("muzzle")
	check(bench.candidate == "none" and "instalado agora" in bench.status.text, "sem acessório instalado aparece como instalado", bench.status.text)
	check(not "Silenciador" in bench.detail.text, "opção original não descreve o silenciador", bench.detail.text)
	check(bench.apply_button.disabled and bench.apply_button.text == "JÁ INSTALADO", "opção instalada não oferece ação", bench.apply_button.text)
	bench.select_candidate("suppressor")
	check("Silenciador:" in bench.detail.text and "Prévia: Silenciador" in bench.status.text and "Instalado agora: Original" in bench.status.text, "prévia do silenciador descreve a peça e mantém o instalado visível", bench.status.text)
	check(bench.apply_button.disabled and "SALDO INSUFICIENTE" in bench.apply_button.text and "faltam $550" in bench.status.text, "peça cara com saldo curto fica bloqueada e diz quanto falta", bench.apply_button.text + " / " + bench.status.text)
	await capture("bancada-previa-silenciador-saldo-curto")
	bench.apply_selection()
	check(economy.balance == 100 and not session.world.gameplay.customization.get("pistol", {}).get("parts", {}).has("muzzle"), "aplicar bloqueado não gasta nem instala")
	set_balance(1000)
	bench.select_candidate("suppressor")
	check(not bench.apply_button.disabled and bench.apply_button.text == "COMPRAR E INSTALAR • $650", "com saldo, oferece compra com custo", bench.apply_button.text)
	var before_buy: int = economy.balance
	var before_keys: Array = economy.snapshot().transactions.keys()
	bench.apply_selection()
	# A primeira peça pode liberar a conquista "armed_up" (+$100): recompensas
	# novas entram na conta para o débito da peça continuar exato.
	var transactions: Dictionary = economy.snapshot().transactions
	var rewards := 0
	for key in transactions:
		if key not in before_keys and str(key).begins_with("reward:"): rewards += int(transactions[key].amount)
	var receipt: Dictionary = transactions.get("spend:weapon_part:pistol:suppressor", {})
	check(int(receipt.get("amount", 0)) == 650 and economy.balance == before_buy - 650 + rewards and bench.candidate == "suppressor" and bench.apply_button.text == "JÁ INSTALADO", "compra debita $650 uma vez e instala o silenciador", "balance=%d->%d rewards=%d" % [before_buy, economy.balance, rewards])
	var none_button: Button = bench.options.get_child(0)
	check(none_button.text == "ORIGINAL / SEM ACESSÓRIO" and "INSTALADO" in bench.options.get_child(1).text, "lista marca a peça instalada, não a original")
	none_button.pressed.emit()
	check(bench.apply_button.text == "REMOVER SILENCIADOR" and "sem custo" in bench.status.text and not "Silenciador:" in bench.detail.text, "prévia sem acessório oferece remoção gratuita sem descrever silenciador", bench.apply_button.text + " / " + bench.status.text)
	await capture("bancada-previa-original")
	check(catalog.handle_input(action("ui_cancel")) and not bench.visible and catalog.panel.visible, "ESC volta da bancada ao catálogo")
	var closes := [0]
	catalog.close_requested.connect(func(): closes[0] += 1)
	check(catalog.handle_input(action("ui_cancel")) and closes[0] == 1, "ESC no catálogo pede fechamento")

	catalog.dismiss()
	economy.restore_snapshot(original_economy)
	session.world.gameplay.customization = original_custom
	print("ARSENAL_UI RESULT %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

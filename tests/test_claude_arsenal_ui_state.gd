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

func wait_for_session() -> bool:
	var started := Time.get_ticks_msec()
	var deadline := started + 120000
	while Time.get_ticks_msec() < deadline:
		var current_curtain := root.get_node_or_null("LoadingCurtain")
		if world.session != null and world.session.ready_for_play and world.production.ready_for_play and current_curtain == null:
			return check(true, "sessão inicia", "%d ms; cortina liberada" % (Time.get_ticks_msec() - started))
		await process_frame
	var curtain := root.get_node_or_null("LoadingCurtain")
	var stage := str(curtain.get("stage_message")) if curtain != null else "sem cortina"
	return check(false, "sessão inicia", "120 s; etapa=%s; session_ready=%s; production_ready=%s" % [stage, world.session != null and world.session.ready_for_play, world.production.ready_for_play])

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
	# O Main pré-aquece as regiões e levanta a cortina de carregamento de forma assíncrona.
	# Uma contagem de quadros de física expira durante esse trabalho; usa o orçamento
	# finito de início em tempo de parede da sessão viva existente e exige admissão real.
	if not await wait_for_session():
		quit(1)
		return
	session = world.session
	economy = session.state.economy
	check(world.production.no_save, "fixture não usa save pessoal")
	# As asserções abaixo exercitam de propósito a apresentação em português.
	# Define só o locale de tradução deste processo; nunca grava configurações do usuário.
	var original_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("pt_BR")
	var original_economy: Dictionary = economy.snapshot()
	var original_custom: Dictionary = session.world.gameplay.customization.duplicate(true)
	var original_belt: Dictionary = session.world.gameplay.belt_flashlight.snapshot()

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
	check("ITEM INICIAL • R$0" in catalog.caption.text and not catalog.buy.disabled, "pistola não possuída mostra item inicial de custo zero", catalog.caption.text + " / " + catalog.buy.text)
	check(economy.grant_weapon("pistol"), "fixture recebe pistola pelo contrato real da economia")
	catalog.refresh()
	check("JÁ POSSUI" in catalog.caption.text and not "R$" in catalog.caption.text, "pistola possuída mostra posse, não R$0", catalog.caption.text)
	check(catalog.buy.disabled and catalog.buy.text == "JÁ POSSUI", "compra de arma possuída fica desabilitada", catalog.buy.text)
	await capture("catalogo-pistola-possuida")
	# Pistolas e SMGs usam o único slot pessoal de arma curta. A MP5
	# começa com 180 balas; _grid_register_weapon só admite o excedente dela
	# enquanto can_carry_weapon(id) é true. Uma mochila sozinha não torna uma segunda
	# arma de slot carregável. Guarda a pistola pela API real de transferência
	# para que a MP5 ocupe esse slot, mantendo a posse das duas armas.
	check(economy.grid_equip_bag("backpack"), "fixture equipa mochila para reserva excedente")
	check(economy.grid_store_weapon("pistol", "trunk"), "fixture guarda pistola no porta-malas e libera slot curto")
	check(economy.personal_loadout().get("curta", "") == "", "slot curto está livre antes de receber SMG")
	check(economy.grant_weapon("smg"), "fixture recebe SMG com espaço real para reserva")
	select("smg")
	check("JÁ POSSUI" in catalog.caption.text and not "1200" in catalog.caption.text, "SMG possuída não exibe preço de tabela como se estivesse à venda", catalog.caption.text)

	# Compra indisponível: rótulo e retorno claros, saldo intacto.
	set_balance(100)
	select("shotgun")
	var price := int(catalog.data().price)
	check(catalog.buy.disabled and catalog.buy.text == "SALDO INSUFICIENTE • R$%d" % price, "saldo curto explica o bloqueio no botão", catalog.buy.text)
	check("Faltam R$%d" % (price - 100) in catalog.feedback.text, "feedback informa quanto falta", catalog.feedback.text)
	catalog.purchase()
	check(economy.balance == 100 and not economy.owns_weapon("shotgun"), "compra bloqueada não altera saldo nem inventário")

	# Navegação: abas por clique e teclado.
	catalog.category_buttons[1].pressed.emit()
	var tabs: Array = catalog.category_buttons.map(func(b): return b.button_pressed)
	check(catalog.stock[catalog.selection] == "shotgun" and tabs == [false, true, false, false, false, false], "aba ARMAS LONGAS seleciona escopeta e só ela fica marcada", str(tabs))
	# Lista visual usa o catálogo de armas real; uma linha clicada muda a prévia.
	var smg_row: Button = null
	var list_has_only_weapons := true
	for row in catalog.item_list.get_children():
		var row_id: String = catalog.stock[int(row.get_meta("stock_index"))]
		list_has_only_weapons = list_has_only_weapons and row_id in preload("res://gameplay/WeaponCatalog.gd").WEAPONS
		if row_id == "smg": smg_row = row
	check(list_has_only_weapons and not catalog.item_list.get_children().is_empty(), "lista de armas longas oferece somente armas reais, sem rodas nem peças mecânicas")
	if check(smg_row != null, "SMG disponível na lista visual da categoria"):
		smg_row.pressed.emit()
		check(catalog.stock[catalog.selection] == "smg" and smg_row.button_pressed, "acionar linha da SMG atualiza seleção e destaque")
		check("SMG" in catalog.caption.text or "MP5" in catalog.caption.text, "linha selecionada atualiza título da prévia", catalog.caption.text)
	select("shotgun")
	check(catalog.handle_input(action("weapon_next")) and catalog.stock[catalog.selection] == "sawed_off", "ação de próxima arma avança item")
	check(catalog.handle_input(action("weapon_previous")) and catalog.stock[catalog.selection] == "shotgun", "ação de arma anterior volta item")
	await capture("catalogo-saldo-insuficiente")

	# Utilitários são separados das armas e usam as mesmas transações de produção.
	var selected_weapon: int = catalog.selection
	catalog.category_buttons[5].pressed.emit()
	check(catalog.utilities_active and catalog.category_buttons[5].button_pressed, "aba Utilitários é a sexta categoria")
	check(not catalog.weapon_body.is_visible_in_tree() and catalog.utilities_body.is_visible_in_tree(), "Utilitários oculta catálogo, prévia e comparação de arma")
	check(catalog.preview.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Utilitários suspende renderização da arma oculta")
	check(not catalog.ammo_button.visible and not catalog.workbench_button.visible, "Utilitários não mistura munição e edição de arma")
	check(catalog.lockpick_button.is_visible_in_tree() and catalog.belt_flashlight_button.is_visible_in_tree() and catalog.customize_button.is_visible_in_tree(), "gazua, cinto e lanterna tática ficam somente em Utilitários")
	# Confere o ícone em toda linha de utilitário, incluindo os pixels da textura. Uma contagem
	# total de descendentes sozinha não estabelece que os três cartões têm ícones.
	var utility_icons_valid := true
	var utility_icon_details: Array[String] = []
	for utility_action: Button in [catalog.lockpick_button,catalog.belt_flashlight_button,catalog.customize_button]:
		var row_icons: Array[TextureRect] = []
		for child: Node in utility_action.get_parent().get_children():
			if child is TextureRect: row_icons.append(child)
		var row_valid := row_icons.size() == 1
		if row_valid:
			var utility_icon: TextureRect = row_icons[0]
			row_valid = utility_icon.is_visible_in_tree() and utility_icon.texture != null
			if row_valid:
				var icon_image: Image = utility_icon.texture.get_image()
				if icon_image != null and icon_image.is_compressed(): icon_image.decompress()
				row_valid = icon_image != null and icon_image.get_used_rect().has_area()
		utility_icons_valid = utility_icons_valid and row_valid
		utility_icon_details.append("%s: icons=%d valid=%s" % [utility_action.text,row_icons.size(),row_valid])
	check(utility_icons_valid, "cada utilitário tem ícone reconhecível", "; ".join(utility_icon_details) + " recursive=%d" % catalog.utilities_body.find_children("*","TextureRect",true,false).size())
	var picks_before := int(economy.inventory.get("lockpick",0))
	set_balance(0)
	catalog.refresh()
	check(catalog.lockpick_button.disabled, "gazua sem saldo fica indisponível")
	catalog.purchase_lockpick()
	check(economy.balance == 0 and int(economy.inventory.get("lockpick",0)) == picks_before, "gazua sem saldo não altera dinheiro nem inventário")
	set_balance(1000)
	catalog.refresh()
	catalog.purchase_lockpick()
	check(economy.balance == 925 and int(economy.inventory.get("lockpick",0)) == picks_before+1, "Utilitários compra gazua pelo preço real de R$75")
	catalog.purchase_belt_flashlight()
	check(session.world.gameplay.belt_flashlight.owned and catalog.belt_flashlight_button.disabled, "lanterna de cinto comprada fica equipada e sem compra duplicada")
	for index in catalog.utility_weapon_selector.item_count:
		if catalog.utility_weapon_selector.get_item_metadata(index) == "pistol": catalog._utility_weapon_changed(index); break
	check(catalog.selection == selected_weapon and catalog.utility_weapon_id == "pistol", "seletor da lanterna preserva a arma selecionada no catálogo")
	catalog.customize_flashlight()
	check(preload("res://gameplay/WeaponCustomization.gd").installed(session.world.gameplay.customization,"pistol") and catalog.customize_button.text == "Remover", "Utilitários compra e instala lanterna tática real")
	var balance_after_lamp: int = economy.balance
	catalog.customize_flashlight()
	check(not preload("res://gameplay/WeaponCustomization.gd").installed(session.world.gameplay.customization,"pistol") and catalog.customize_button.text == "Instalar", "remoção da lanterna preserva a peça comprada")
	catalog.customize_flashlight()
	check(economy.balance == balance_after_lamp and preload("res://gameplay/WeaponCustomization.gd").installed(session.world.gameplay.customization,"pistol"), "reinstalar lanterna comprada não cobra novamente")
	await capture("catalogo-utilitarios")
	check(catalog.handle_input(action("weapon_next")) and catalog.utilities_active and catalog.selection == selected_weapon, "atalho de próxima arma em Utilitários só muda o seletor de lanterna")
	catalog.category_buttons[1].pressed.emit()
	check(not catalog.utilities_active and catalog.weapon_body.is_visible_in_tree() and catalog.preview.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "voltar para armas restaura prévia")
	check(not catalog.lockpick_button.is_visible_in_tree() and not catalog.belt_flashlight_button.is_visible_in_tree() and not catalog.customize_button.is_visible_in_tree(), "rodapé de armas deixa utilitários na própria aba")

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
	check(bench.apply_button.disabled and "SALDO INSUFICIENTE" in bench.apply_button.text and "faltam R$550" in bench.status.text, "peça cara com saldo curto fica bloqueada e diz quanto falta", bench.apply_button.text + " / " + bench.status.text)
	await capture("bancada-previa-silenciador-saldo-curto")
	bench.apply_selection()
	check(economy.balance == 100 and not session.world.gameplay.customization.get("pistol", {}).get("parts", {}).has("muzzle"), "aplicar bloqueado não gasta nem instala")
	set_balance(1000)
	bench.select_candidate("suppressor")
	check(not bench.apply_button.disabled and bench.apply_button.text == "COMPRAR E INSTALAR • R$650", "com saldo, oferece compra com custo", bench.apply_button.text)
	var before_buy: int = economy.balance
	var before_keys: Array = economy.snapshot().transactions.keys()
	bench.apply_selection()
	# A primeira peça pode liberar a conquista "armed_up" (+R$100): recompensas
	# novas entram na conta para o débito da peça continuar exato.
	var transactions: Dictionary = economy.snapshot().transactions
	var rewards := 0
	for key in transactions:
		if key not in before_keys and str(key).begins_with("reward:"): rewards += int(transactions[key].amount)
	var receipt: Dictionary = transactions.get("spend:weapon_part:pistol:suppressor", {})
	check(int(receipt.get("amount", 0)) == 650 and economy.balance == before_buy - 650 + rewards and bench.candidate == "suppressor" and bench.apply_button.text == "JÁ INSTALADO", "compra debita R$650 uma vez e instala o silenciador", "balance=%d->%d rewards=%d" % [before_buy, economy.balance, rewards])
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
	session.world.gameplay.belt_flashlight.restore(original_belt)
	TranslationServer.set_locale(original_locale)
	print("ARSENAL_UI RESULT %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

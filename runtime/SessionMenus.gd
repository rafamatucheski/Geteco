extends RefCounted
## Painel modal da FullSession: menus (diário, inventário, lojas, personalização, mapa) e o diálogo em
## cartão. Separado em 31/10 para o FullSession.gd caber na leitura. O estado (panel, column, modal,
## lines, menu_closed...) continua na sessão, onde HUD, sistemas e testes o leem; cada função antiga da
## sessão virou delegação de uma linha, então quem chama por nome (inclusive has_method) não muda.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem _menu, close_menu,
## _present_dialogue_line... numa subclasse da sessão e o despacho tem de continuar igual.

const DIALOGUE_CARD := preload("res://ui/dialogue/DialogueCard.gd")
const JOURNAL_ARCS := preload("res://runtime/JournalArcs.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _menu(title: String) -> void:
	if is_instance_valid(g.room) and g.room.has_method("dismiss_game") and g.room.get("game_active") == true:
		g.room.dismiss_game()
		if g.menu_closed == Callable(g.room,"dismiss_game"): g.menu_closed = Callable()
	if is_instance_valid(g.equipment_wheel): g.equipment_wheel.cancel()
	if g.building_social != null and g.building_social.active: g.building_social.close()
	if g.arcade != null and g.arcade.active: g.arcade.close()
	g.clear_speech()
	if is_instance_valid(g.dialogue_card): g.dialogue_card.hide()
	if is_instance_valid(g.dialogue_voice): g.dialogue_voice.stop()
	if g.panel.has_meta("modal_preferred_size"): g.panel.remove_meta("modal_preferred_size")
	if g.panel.has_meta("modal_dock_right"): g.panel.remove_meta("modal_dock_right")
	var previous_map: Node = g.world.hud.get_node_or_null("MapUI")
	if is_instance_valid(previous_map):
		previous_map.queue_free()
		g.menu_closed = Callable()
	if g.field_inventory != null and g.field_inventory.ui.visible:
		g.field_inventory.dismiss()
		g.menu_closed = Callable()
	g._service_menu_open = false
	if g.storefronts != null and g.storefronts.is_open(): g.storefronts.dismiss()
	for child in g.column.get_children():
		g.column.remove_child(child)
		child.queue_free()
	g.modal = true
	g.dialogue_open = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	g.world.player.input_locked = true
	if g.world.driving.occupied: g.world.driving.car.input_locked = true
	g.panel.show()
	g.panel.custom_minimum_size = Vector2(620,440)
	# Telas compactas de conversa soltam este mínimo antigo só para elas mesmas.
	g.column.get_parent().custom_minimum_size = Vector2(580,400)
	g.column.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	g.column.get_parent().focus_mode = Control.FOCUS_NONE
	g.column.get_parent().follow_focus = false
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size",26)
	g.column.add_child(label)

func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(action)
	var previous: Button = null
	for child in g.column.get_children():
		if child is Button: previous = child
	g.column.add_child(button)
	if previous != null:
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		previous.focus_next = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_previous = button.get_path_to(previous)
	else:
		Callable(g, "_focus_menu_button").call_deferred(weakref(button))

func _focus_menu_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as Control
	if not is_instance_valid(button) or button.is_queued_for_deletion(): return
	if g.modal and button.is_inside_tree() and button.get_parent() == g.column and button.is_visible_in_tree():
		button.grab_focus()

func close_menu() -> void:
	if g.dialogue_voice != null: g.dialogue_voice.stop()
	g._dialogue_source.clear()
	if is_instance_valid(g.dialogue_card): g.dialogue_card.hide()
	g.clear_speech()
	g._service_menu_open = false
	if g.storefronts != null and g.storefronts.is_open(): g.storefronts.dismiss()
	if g.menu_closed.is_valid(): g.menu_closed.call()
	g.menu_closed = Callable()
	g.modal = false
	g.dialogue_open = false
	g.panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	g.world.player.input_locked = g.world.gameplay.health <= 0 or g.is_transition_blocked() or (g.desert != null and g.desert.busy()) or (g.passenger_transport != null and g.passenger_transport.riding) or (g.motocross != null and g.motocross.mounted) or (g.skate != null and g.skate.controls_locked())
	if g.fishing != null and g.fishing.controls_locked(): g.world.player.input_locked = true
	if g.amusement_park != null and g.amusement_park.active: g.world.player.input_locked = true
	if is_instance_valid(g.world.driving.car): g.world.driving.car.input_locked = g.is_transition_blocked() or (g.desert != null and g.desert.controls_locked())

func show_dialogue(dialogue_lines: Array, on_done := Callable()) -> void:
	g.lines = dialogue_lines.duplicate(true)
	g.dialogue_done = on_done
	g._advance_dialogue()

func interrupt_dialogue() -> void:
	# Recovery discards unfinished words without completing their mission callback.
	g.lines.clear()
	g.dialogue_done = Callable()
	g.dialogue_open = false
	g._dialogue_source.clear()
	if is_instance_valid(g.dialogue_voice): g.dialogue_voice.stop()
	if is_instance_valid(g.dialogue_card): g.dialogue_card.hide()
	g.clear_speech()
	if g.arrival != null: g.arrival.cancel_dialogue()

func _advance_dialogue() -> void:
	if g.dialogue_voice != null: g.dialogue_voice.stop()
	if g.lines.is_empty():
		g.close_menu()
		if g.dialogue_done.is_valid(): g.dialogue_done.call()
		return
	var line: Dictionary = g.lines.pop_front()
	var continuing_service: bool = g._service_menu_open
	g._menu(str(line.get("speaker","")))
	g._service_menu_open = continuing_service
	g.dialogue_open = true
	g._dialogue_source = line.duplicate(true)
	g._present_current_dialogue(true)

func _present_current_dialogue(restart_audio: bool) -> void:
	var line: Dictionary = g._dialogue_source.duplicate(true)
	var speaker := str(line.get("voice_persona", str(line.get("speaker", "")).to_lower().split(" · ")[0]))
	var shown := VOICE.presentation(str(line.get("voice_text", line.get("message", ""))), speaker, "", "", str(line.get("character_id", "")), str(line.get("voice_section", "")))
	line["message"] = str(shown.message)
	if g.dialogue_voice != null and not (g.arrival != null and g.arrival.active):
		if restart_audio:
			g.dialogue_voice.stop()
			g.dialogue_voice.stream = shown.stream
			g.dialogue_voice.volume_db = VOICE.playback_volume(g.dialogue_voice.stream, -8.0 if speaker in ["maciota", "caller"] else 0.0)
			if g.dialogue_voice.stream != null: g.dialogue_voice.play()
	g._present_dialogue_line(line)

func _present_dialogue_line(line: Dictionary) -> void:
	g.panel.hide()
	if not is_instance_valid(g.dialogue_card):
		g.dialogue_card = DIALOGUE_CARD.new()
		g.world.hud.add_child(g.dialogue_card)
		g.dialogue_card.advance_requested.connect(Callable(g, "_advance_dialogue"))
	g.dialogue_card.configure(str(line.get("speaker","")), str(line.get("message","")), g.get_node_or_null("/root/GameInput"))
	g.dialogue_card.focus_advance.call_deferred()

func cancel_mission() -> bool:
	if g.state.campaign.active_id.is_empty(): return false
	if not g.mission_world.cancel_attempt():
		g.show_message("Libere uma área para descarregar o guincho antes de cancelar.")
		g.save_game()
		return false
	g.close_menu()
	g.save_game()
	return true

func show_maciota_menu() -> void:
	g._menu("Maciota")
	g._compact_menu_size(Vector2(360, 310))
	g._button("Ver missões", Callable(g, "show_journal"))
	g._button("Informações", Callable(g, "show_journal_information"))
	g._button("Encerrar conversa", Callable(g, "close_menu"))
	g._menu_information("Guia do HUD em Configurações → Ajuda.", 13)
	g._fit_compact_menu(g.column.get_child(0), Vector2(360, 310))

func _compact_menu_size(extent: Vector2) -> void:
	g.panel.set_meta("modal_preferred_size", extent)
	g.column.get_parent().custom_minimum_size = Vector2.ZERO
	g.column.get_parent().horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.column.get_parent().follow_focus = true
	g.panel.custom_minimum_size = extent
	g.panel.size = extent

func _fit_compact_menu(identity: Node, maximum: Vector2) -> void:
	# Espera a quebra de linha na nova largura. Limita o resultado, mantendo a
	# rolagem existente para registros longos; menus curtos não devem reservar espaço vazio.
	await g.get_tree().process_frame
	await g.get_tree().process_frame
	if not is_instance_valid(identity) or identity.get_parent() != g.column or not g.panel.visible: return
	# A moldura compartilhada de painel/margem tem 84 px; deixa 16 px para o foco e a quebra final.
	var extent: Vector2 = Vector2(maximum.x, minf(maximum.y, g.column.get_combined_minimum_size().y + 100.0))
	g.panel.set_meta("modal_preferred_size", extent)
	g.panel.custom_minimum_size = extent
	g.panel.size = extent
	g.panel.position = ((g.panel.get_viewport_rect().size - g.panel.size) * .5).round()

## Texto só de leitura nunca pode parecer nem se comportar como ação de missão.
func _menu_information(text: String, font_size := 16, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", preload("res://ui/GameStyle.gd").TEXT if font_size >= 16 else preload("res://ui/GameStyle.gd").MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		label.focus_mode = Control.FOCUS_ALL
		var reading_focus := StyleBoxFlat.new()
		reading_focus.bg_color = Color.TRANSPARENT
		reading_focus.border_color = preload("res://ui/GameStyle.gd").ACCENT
		reading_focus.border_width_left = 2
		label.add_theme_stylebox_override("focus", reading_focus)
	(parent if parent != null else g.column).add_child(label)
	return label

func show_journal_information() -> void:
	g._menu("Informações")
	g._compact_menu_size(Vector2(480, 360))
	g.column.get_parent().follow_focus = true
	var records := VBoxContainer.new()
	records.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records.add_theme_constant_override("separation", 14)
	g.column.add_child(records)
	var village: Dictionary = {}
	if g.urban_operations != null and is_instance_valid(g.urban_operations.village_quest): village = g.urban_operations.village_quest.data
	var entries: Array = JOURNAL_ARCS.lines(g.state.world_state, g.state.campaign.snapshot(), village)
	for line in entries: g._menu_information(str(line), 16, records)
	if entries.is_empty(): g._menu_information("Nenhuma informação registrada ainda.", 16, records)
	var secret_file: Variant = g.urban_operations.get("secret_file") if g.urban_operations != null else null
	if is_instance_valid(secret_file) and secret_file.available():
		g._button("Arquivo de Vicente", secret_file.open_from_journal)
	g._button("Ver missões", Callable(g, "show_journal"))
	g._button("Fechar", Callable(g, "close_menu"))
	# Lê o primeiro registro antes de navegar pelas ações abaixo dos registros.
	var scroll: ScrollContainer = g.column.get_parent()
	if records.get_child_count() > 0: records.get_child(0).grab_focus.call_deferred()
	scroll.set_deferred("scroll_vertical", 0)
	g._fit_compact_menu(g.column.get_child(0), Vector2(480, 360))

func show_journal() -> void:
	if g.mountain_activities != null and g.mountain_activities.busy():
		g.mountain_activities.show_journal()
		return
	g._menu("Missões")
	g._compact_menu_size(Vector2(480, 360))
	if g.mountain_activities != null: g._button("Atividades da montanha", g.mountain_activities.show_journal)
	if g.state.campaign.active_id != "":
		g._menu_information("OBJETIVO ATUAL", 13)
		g._menu_information(g.mission_world.objective())
		g._button("Cancelar missão",Callable(g, "cancel_mission"))
	else:
		for id in g.state.campaign.available_missions():
			g._button(str(MISSIONS.MISSIONS[id].title),func():
				if g.state.intro.stage != "complete": g.show_message("Converse primeiro com Maciota."); g.close_menu(); return
				if not g.mission_world.begin(id):
					g.close_menu()
					return
				if not g.dialogue_open: g.close_menu())
	# Cadeia da Helena: escolher a linha põe objetivo e marcador nela. As histórias de JournalArcs e o
	# arquivo de Vicente ficam em "Informações" (show_journal_information).
	if g.helena_act1 != null and g.state.campaign.active_id == "":
		for entry in g.helena_act1.journal_entries():
			var act1_id: String = entry.id
			g._button(entry.text, func():
				g.helena_act1.focus(act1_id)
				g.close_menu())
	g._button("Informações", Callable(g, "show_journal_information"))
	g._button("Voltar",Callable(g, "close_menu"))
	g._fit_compact_menu(g.column.get_child(0), Vector2(480, 360))

func show_inventory() -> void:
	if g.field_inventory != null:
		g.field_inventory.open()
		return
	g._menu(String(TranslationServer.translate("Inventário · R$ %d"))%g.state.economy.balance)
	for id in WEAPONS.ORDER:
		if g.state.owns_weapon(id):
			var stored: bool = not g.state.economy.can_carry_weapon(id)
			g._button(str(WEAPONS.WEAPONS[id].label)+(" · No porta-malas" if stored else ""),func():
				if not g.state.economy.can_carry_weapon(id):
					g.close_menu()
					g.show_message("Selecione esta arma no porta-malas da Monaliza.")
					return
				g.close_menu()
				g.state.equip_weapon(id))
	if g.state.economy.inventory.get("first_aid",0)>0:
		g._button("Usar primeiros socorros",func():
			if g.world.gameplay.heal(40): g.state.economy.consume_item("first_aid")
			g.close_menu(); g.save_game())
	g._button("Configurações",Callable(g, "show_settings"))
	g._button("Voltar",Callable(g, "close_menu"))

func show_services(service: String) -> void:
	if g._service_threatened(): return
	g._show_services_available(service)
	g._service_menu_open = g.modal
	if g.modal and g.panel.visible: preload("res://ui/ShopPresentation.gd").apply(g.panel)

func _show_services_available(service: String) -> void:
	if service == "supermarket":
		preload("res://runtime/SupermarketShop.gd").open(g)
		return
	if service == "ski_rental":
		g.mountain_progression.show_services()
		return
	if g.services.perform(service): return
	if service in ["weapons","ammunation","gunshop"]:
		if g.state.place_id == "harbor_ammunation" and g.storefronts.open_weapons(): return
		g._show_shop("weapon")
		return
	if service == "clothing":
		if g.state.place_id == "harbor_clothing" and g.storefronts.open_clothing(): return
		g._show_shop("outfit")
		return
	# O reparo de veículo pertence ao serviço físico. O Maciota é tratado acima
	# por Services.perform(); o Northgate admite o carro ocupado na baia
	# externa. Este recurso nunca pode cobrar nem limpar o estado de procurado remotamente.
	if service == "garage":
		g.show_message("Use a bancada da garagem para cuidar da Monaliza.")
		return
	if service == "auto_service":
		g.show_message("Leve o veículo até a baia externa da Northgate.")
		return

func _show_shop(category: String) -> void:
	g._menu("R$ %d"%g.state.economy.balance)
	for item in g.state.economy.storefront(category):
		if category == "weapon" and item.id == "katana" and not item.unlocked: continue
		var label := str(item.get("name",item.get("label",item.id)))
		g._button(label+(" · Equipar" if item.owned else " · R$ %d"%item.price),func():
			if not item.owned:
				var result: Dictionary = g.state.economy.purchase(category,item.id,g._transaction())
				if not result.ok: g.show_message("Compra indisponível: "+str(result.reason)); g.close_menu(); return
			if category == "weapon": g.state.equip_weapon(item.id)
			else: preload("res://runtime/OutfitDisguise.gd").equip(g, item.id, true)
			g.close_menu(); g.save_game())
	if category == "weapon":
		g._button("Personalizar arma equipada",Callable(g, "_show_customization"))
		g._button("Munição para arma equipada",func():
			var purchased: bool = g.state.economy.buy_ammo(g.state.equipped_weapon,30,g._transaction())
			g.show_message("Munição comprada." if purchased else "Compra indisponível.")
			g.close_menu(); g.save_game())
		if g.world.gameplay.armor >= 100:
			g._button("Proteção completa",func():
				g.show_message("O colete já está completo.")
				g.close_menu())
		else:
			g._button("Colete · R$ 500",func():
				var result: Dictionary = g.state.economy.purchase_body_armor(g.world.gameplay.armor,100,g._transaction())
				if result.ok:
					g.world.gameplay.armor = int(result.armor)
					g.show_message("Colete equipado.")
				else:
					g.show_message("Proteção completa." if result.reason == "protection_full" else "Compra indisponível.")
				g.close_menu()
				if result.ok: g.save_game())
	g._button("Voltar",Callable(g, "close_menu"))
	preload("res://ui/ShopPresentation.gd").apply(g.panel)

func _show_customization() -> void:
	var catalog = preload("res://gameplay/WeaponCustomization.gd")
	var id: String = g.state.equipped_weapon
	if id == "katana":
		g._show_saber_customization()
		return
	g._menu("Personalizar · "+str(WEAPONS.WEAPONS[id].label))
	for part in catalog.PARTS:
		if not catalog.supports(id,part): continue
		var data: Dictionary = catalog.PARTS[part]
		var owned: bool = catalog.owns(g.world.gameplay.customization,id,part)
		var selected: bool = catalog.selected(g.world.gameplay.customization,id,data.slot) == part
		var suffix := " · Remover" if selected else (" · Instalar" if owned else " · R$ %d"%data.price)
		g._button(str(data.label)+suffix,func():
			var ok: bool = g.world.gameplay.install_attachment(id,part,false) if selected else g.world.gameplay.buy_attachment(id,part)
			if not ok: g.show_message("Personalização indisponível.")
			g.save_game()
			g._show_customization())
	g._button("Voltar",func(): g._show_shop("weapon"))
	preload("res://ui/ShopPresentation.gd").apply(g.panel)

func _show_saber_customization() -> void:
	g._menu("Katana")
	g.panel.hide()
	var custom_panel := preload("res://runtime/TakeshiSaberPanel.gd").new()
	custom_panel.configure(g)
	g.world.hud.add_child(custom_panel)
	custom_panel.closed.connect(func(): g._show_shop("weapon"))
	g.menu_closed = func():
		if is_instance_valid(custom_panel): custom_panel.queue_free()

func _transaction() -> String:
	g.action_serial += 1
	return "%d_%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec(),g.action_serial]

func show_settings() -> void:
	g.close_menu()
	g.world.pause_panel.pause_game()
	g.world.pause_panel.open_settings()

func show_controls() -> void:
	g.show_settings()
	g.world.pause_panel.settings._select_tab(2)

func show_map() -> void:
	g._menu("Mapa")
	var map = preload("res://ui/v2/WorldMap.gd").new()
	map.controller = g.controller
	g.world.hud.add_child(map)
	g.panel.hide()
	g.menu_closed = map.queue_free

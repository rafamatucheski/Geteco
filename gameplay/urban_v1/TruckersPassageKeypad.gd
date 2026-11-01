extends RefCounted
## Teclado numérico do porão (código da Casa 1) e do cofre do setor lacrado, separado de
## TruckersVillageSecretPassage.gd em 01/11 só para o dono caber na leitura. O estado (_keypad_buffer,
## _keypad_code, _keypad_vault, _shelf_revealed) continua no dono, porque testes leem e chamam esses
## nomes lá (`passage._keypad_buffer`, `passage._submit_keypad()`); o dono mantém cada função antiga
## como delegação de uma linha. `g` fica como Node3D, e não como o script do dono, para não criar
## preload cíclico; até as chamadas entre funções deste arquivo passam por `g.` (inclusive o
## Callable dos botões, `g._keypad_press`), para o despacho continuar igual ao de antes.

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _open_keypad() -> void:
	g._keypad_vault = false
	g._show_keypad()

func _open_vault_keypad() -> void:
	if not g._power_active("power_sealed_sector"):
		g._show_message("O teclado está sem energia.")
		return
	var missing: int = 4-g._vault_digits_found()
	if missing > 0:
		g._show_message(String(TranslationServer.translate("Faltam %d dígitos do código. Procure no quartel: %s"))%[missing,g._vault_hint()])
		return
	g._keypad_vault = true
	g._show_keypad()

func _show_keypad() -> void:
	if g.session == null or not g.session.has_method("menu") or g.session.get("column") == null:
		return
	g._keypad_buffer = ""
	g.session.menu("Teclado")
	var display := Label.new()
	display.name = "KeypadEntry"
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.add_theme_font_size_override("font_size",28)
	display.text = g._keypad_mask()
	g.session.column.add_child(display)
	var grid := GridContainer.new()
	grid.name = "NumericKeypad"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.session.column.add_child(grid)
	var first: Button = null
	for value in ["1","2","3","4","5","6","7","8","9","⌫","0","OK"]:
		var button := Button.new()
		button.text = value
		button.custom_minimum_size = Vector2(86,42)
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(g._keypad_press.bind(value,display))
		grid.add_child(button)
		if first == null: first = button
	if first != null: first.grab_focus.call_deferred()
	if g.session.has_method("button"):
		g.session.button("Cancelar",g.session.close_menu)

func _keypad_press(value: String,display: Label) -> void:
	if value == "⌫":
		g._keypad_buffer = g._keypad_buffer.left(maxi(0,g._keypad_buffer.length()-1))
	elif value == "OK":
		g._submit_keypad()
		return
	elif g._keypad_buffer.length() < g._active_code().length():
		g._keypad_buffer += value
	if is_instance_valid(display):
		display.text = g._keypad_mask()

func _keypad_mask() -> String:
	var marks := PackedStringArray()
	for index in g._active_code().length():
		marks.append("●" if index < g._keypad_buffer.length() else "•")
	return " ".join(marks)

func _active_code() -> String:
	return g.VAULT_CODE if g._keypad_vault else g._keypad_code

func _submit_keypad() -> void:
	if g._keypad_vault:
		g._submit_vault_keypad()
		return
	if g._keypad_buffer != g._keypad_code:
		g._keypad_buffer = ""
		g._show_message("Código incorreto.")
		var display = g.session.column.get_node_or_null("KeypadEntry") if g.session != null else null
		if display is Label: display.text = g._keypad_mask()
		return
	if g.progression == null or not g.progression.unlock_keypad():
		g._show_message("Teclado bloqueado.")
		return
	g._shelf_revealed = true
	if g.session.has_method("close_menu"): g.session.close_menu()
	if is_instance_valid(g.tunnel): g.tunnel.set_enabled(true)
	g._emit_state_changed()
	g._show_message("Passagem liberada.")

func _submit_vault_keypad() -> void:
	if g._keypad_buffer != g.VAULT_CODE:
		g._keypad_buffer = ""
		g._show_message("Código incorreto.")
		var display = g.session.column.get_node_or_null("KeypadEntry") if g.session != null else null
		if display is Label: display.text = g._keypad_mask()
		return
	if g.progression == null or not g.progression.unlock_final_door():
		g._show_message("O cofre continua trancado.")
		return
	if g.session.has_method("close_menu"): g.session.close_menu()
	g.tunnel.set_vault_open(true,true)
	g._emit_state_changed()
	g._show_message("A porta do cofre se abre.")

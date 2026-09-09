class_name TutorialHintPresenter
extends CanvasLayer
## Apresentador Godot isolado de dicas contextuais discretas, para a prévia
## de tutorial em ui/tutorial_preview/. Sem integração ao save real, ao HUD
## real ou a qualquer outro sistema do jogo -- a Astra decide como e quando
## conectar isto de verdade.
##
## API proposta (exatamente como pedido):
##   request_hint(id: String) -> bool   -- pede para mostrar a dica `id`
##   dismiss_hint() -> void             -- dispensa a dica ativa agora
##   reset_preview() -> void            -- limpa sessão (fila, vistos, estado)
##
## Regras:
##   - Uma dica por vez: uma nova só aparece quando a atual for dispensada
##     (manual, tecla ou tempo esgotado) ou quando nenhuma estiver ativa.
##     Pedidos que chegam enquanto outra dica está ativa (ou o apresentador
##     está bloqueado) entram numa fila (FIFO) e aparecem na vez certa.
##   - Sem repetição durante a sessão: uma vez mostrada, a mesma `id` nunca
##     volta a aparecer até reset_preview() ser chamado.
##   - Duração limitada: cada dica some sozinha depois de `hint_duration`
##     segundos (configurável via set_hint_duration), a menos que seja
##     dispensada antes.
##   - Tecla de dispensar configurável: o chamador informa o nome de uma
##     action já registrada no InputMap via set_dismiss_action(). Nenhuma
##     tecla é inventada aqui -- se nenhuma action for informada (ou a
##     action informada não existir no InputMap), a dispensa por teclado
##     simplesmente não ocorre; dismiss_hint() e o timeout continuam
##     funcionando normalmente.
##   - Nunca interrompe o jogo: não pausa a árvore, não captura o mouse, não
##     é um modal -- é uma camada (CanvasLayer) com um aviso discreto.
##   - Estados de bloqueio informados pelo chamador (não inferidos por este
##     arquivo): set_modal_active(), set_combat_active(),
##     set_fast_driving_active(). Enquanto qualquer um estiver ativo,
##     nenhuma dica nova aparece -- pedidos ficam na fila e aparecem assim
##     que o estado voltar a ficar livre.

const CATALOG := preload("res://ui/tutorial_preview/TutorialHintCatalog.gd")

## Emitido quando uma dica passa a ficar visível.
signal hint_shown(id: String)
## Emitido quando a dica ativa é dispensada. `reason` é "manual", "key" ou "timeout".
signal hint_dismissed(id: String, reason: String)
## Emitido quando um pedido entra na fila (ainda não está visível).
signal hint_queued(id: String)
## Emitido quando um pedido é recusado. `reason` é "unknown_id", "already_seen" ou "already_queued".
signal hint_rejected(id: String, reason: String)

var hint_duration: float = 9.0
var locale: String = "pt"
var dismiss_action: String = ""

var _seen: Dictionary = {}
var _pending: Array[String] = []
var _active_id: String = ""

var _modal_active := false
var _combat_active := false
var _fast_driving_active := false

var _timer: Timer
var _box: PanelContainer
var _eyebrow_label: Label
var _title_label: Label
var _body_label: Label
var _key_label: Label
var _dismiss_button: Button

func _ready() -> void:
	layer = 5
	_build_ui()

# ==========================================
# API PROPOSTA
# ==========================================
func request_hint(id: String) -> bool:
	if not CATALOG.has_hint(id):
		hint_rejected.emit(id, "unknown_id")
		return false
	if _seen.has(id):
		hint_rejected.emit(id, "already_seen")
		return false
	if _active_id == id or _pending.has(id):
		hint_rejected.emit(id, "already_queued")
		return false
	_pending.append(id)
	hint_queued.emit(id)
	_try_present_next()
	return true

func dismiss_hint() -> void:
	_dismiss_active("manual")

func reset_preview() -> void:
	_seen.clear()
	_pending.clear()
	if _timer != null:
		_timer.stop()
		_timer.paused = false
	_active_id = ""
	_modal_active = false
	_combat_active = false
	_fast_driving_active = false
	if _box != null:
		_box.visible = false

# ==========================================
# CONFIGURAÇÃO (recebida do chamador, nada fixo aqui)
# ==========================================
func set_dismiss_action(action_name: String) -> void:
	dismiss_action = action_name
	_refresh_key_label()

func set_hint_duration(seconds: float) -> void:
	hint_duration = maxf(0.5, seconds)

func set_locale(locale_code: String) -> void:
	locale = locale_code
	if _active_id != "":
		_refresh_active_text()

# ==========================================
# ESTADOS INFORMADOS PELO CHAMADOR
# ==========================================
func set_modal_active(active: bool) -> void:
	_modal_active = active
	_sync_active_visibility()
	if not active:
		_try_present_next()

func set_combat_active(active: bool) -> void:
	_combat_active = active
	_sync_active_visibility()
	if not active:
		_try_present_next()

func set_fast_driving_active(active: bool) -> void:
	_fast_driving_active = active
	_sync_active_visibility()
	if not active:
		_try_present_next()

func is_blocked() -> bool:
	return _modal_active or _combat_active or _fast_driving_active

func _sync_active_visibility() -> void:
	# A hint already on screen must also disappear when danger/menu begins.
	if _box != null: _box.visible = _active_id != "" and not is_blocked()
	if _timer != null: _timer.paused = is_blocked()

# ==========================================
# CONSULTA (útil para integração e testes)
# ==========================================
func is_showing() -> bool:
	return _active_id != ""

func get_active_hint_id() -> String:
	return _active_id

func get_pending_hints() -> Array[String]:
	return _pending.duplicate()

func has_seen(id: String) -> bool:
	return _seen.has(id)

# ==========================================
# INTERNO
# ==========================================
func _try_present_next() -> void:
	if _active_id != "" or is_blocked() or _pending.is_empty():
		return
	var id: String = _pending.pop_front()
	if _seen.has(id):
		# Defensivo: não deveria acontecer (request_hint já bloqueia
		# duplicatas), mas evita travar a fila se ocorrer mesmo assim.
		_try_present_next()
		return
	_active_id = id
	_seen[id] = true
	_refresh_active_text()
	if _box != null:
		_box.visible = true
	hint_shown.emit(id)
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		add_child(_timer)
		_timer.timeout.connect(func(): _dismiss_active("timeout"))
	_timer.start(hint_duration)

func _dismiss_active(reason: String) -> void:
	if _active_id == "":
		return
	var dismissed_id := _active_id
	_active_id = ""
	if _timer != null:
		_timer.stop()
	if _box != null:
		_box.visible = false
	hint_dismissed.emit(dismissed_id, reason)
	_try_present_next()

func _refresh_active_text() -> void:
	var data := CATALOG.get_hint(_active_id, locale)
	if _eyebrow_label != null:
		_eyebrow_label.text = String(data.get("eyebrow", ""))
	if _title_label != null:
		_title_label.text = String(data.get("title", ""))
	if _body_label != null:
		_body_label.text = String(data.get("body", ""))
	_refresh_key_label()

func _refresh_key_label() -> void:
	if _key_label == null:
		return
	_key_label.text = ("[%s]" % dismiss_action) if dismiss_action != "" else ""
	_key_label.visible = dismiss_action != ""

func _unhandled_input(event: InputEvent) -> void:
	if _active_id == "" or dismiss_action == "" or is_blocked():
		return
	if not InputMap.has_action(dismiss_action):
		return
	if event.is_action_pressed(dismiss_action):
		_dismiss_active("key")

# ==========================================
# UI DISCRETA (canto da tela, não bloqueia o jogo)
# ==========================================
func _build_ui() -> void:
	_box = PanelContainer.new()
	_box.name = "TutorialHintBox"
	_box.visible = false
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_box.offset_left = 24
	_box.offset_bottom = -24
	_box.offset_right = 24 + 360
	_box.offset_top = -24 - 120
	add_child(_box)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.067, 0.106, 0.125, 0.92)
	style.border_color = Color(0.945, 0.757, 0.42)
	style.set_border_width_all(0)
	style.border_width_left = 3
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	_box.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_col)

	_eyebrow_label = Label.new()
	_eyebrow_label.add_theme_font_size_override("font_size", 11)
	_eyebrow_label.add_theme_color_override("font_color", Color(0.569, 0.843, 0.827))
	text_col.add_child(_eyebrow_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(0.945, 0.953, 0.933))
	text_col.add_child(_title_label)

	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 12)
	_body_label.add_theme_color_override("font_color", Color(0.659, 0.722, 0.729))
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(_body_label)

	_key_label = Label.new()
	_key_label.add_theme_font_size_override("font_size", 11)
	_key_label.add_theme_color_override("font_color", Color(0.659, 0.722, 0.729))
	_key_label.visible = false
	text_col.add_child(_key_label)

	var button_col := VBoxContainer.new()
	button_col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(button_col)

	_dismiss_button = Button.new()
	_dismiss_button.name = "DismissButton"
	_dismiss_button.text = "×"
	_dismiss_button.tooltip_text = "Dispensar"
	_dismiss_button.focus_mode = Control.FOCUS_NONE
	_dismiss_button.pressed.connect(dismiss_hint)
	button_col.add_child(_dismiss_button)

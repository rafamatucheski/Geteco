extends Control
## Instrumentos de pesca compactos. A captura em si continua visível na cena 3D.
signal catch_choice(action: String)
const RULES := preload("res://activities/fishing/FishingRules.gd")
const STYLE := preload("res://ui/GameStyle.gd")
const INK := Color("111c20ed")
const LINE := Color("87988b")
const TEXT := Color("f4f0e4")
const MUTED := Color("bac9c4")
const GOLD := Color("edc56e")
const WATER := Color("76cde2")
const SAFE := Color("8cdaa1")
const DANGER := Color("f07a61")
var state: Dictionary = {}
var _font: Font
var _strong: Font
var _style: StyleBoxFlat
var _track: StyleBoxFlat
var _result_style: StyleBoxFlat
var _result_reveal := 1.0
var _result_tween: Tween
var _keep_button: Button
var _release_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = STYLE.FONT
	_strong = STYLE.STRONG
	_style = _panel()
	_track = _panel()
	_track.bg_color = Color("263638")
	_track.border_color = Color("71837d")
	_track.set_corner_radius_all(4)
	_result_style = _panel()
	_result_style.border_color = GOLD
	_keep_button = _choice_button("KeepFish", "keep")
	_release_button = _choice_button("ReleaseFish", "release")
	_keep_button.focus_neighbor_right = _keep_button.get_path_to(_release_button)
	_keep_button.focus_next = _keep_button.get_path_to(_release_button)
	_keep_button.focus_previous = _keep_button.get_path_to(_release_button)
	_release_button.focus_neighbor_left = _release_button.get_path_to(_keep_button)
	_release_button.focus_next = _release_button.get_path_to(_keep_button)
	_release_button.focus_previous = _release_button.get_path_to(_keep_button)
	resized.connect(_sync_choices)
	_sync_choices()

func update_state(value: Dictionary) -> void:
	var previous := str(state.get("phase", ""))
	state = value
	if str(state.get("phase", "")) == "caught" and previous != "caught" and is_inside_tree():
		if _result_tween: _result_tween.kill()
		_result_reveal = 0.0
		_result_tween = create_tween()
		_result_tween.tween_method(_reveal_result, 0.0, 1.0, .24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sync_choices()
	if str(state.get("phase", "")) == "caught" and previous != "caught" and not _touch_active():
		_focus_choice.call_deferred()
	queue_redraw()

func _reveal_result(value: float) -> void:
	_result_reveal = value
	_sync_choices()
	queue_redraw()

func _touch_active() -> bool:
	return bool(state.get("touch", OS.has_feature("android") or "--touch-controls" in OS.get_cmdline_user_args()))

func _hud_scale() -> float:
	var compact := _touch_active() and size.x < size.y * 1.4
	return maxf(.01, minf(size.x / 720.0, size.y / 900.0) if compact else minf(size.x / 1280.0, size.y / 720.0))

func _choice_button(node_name: String, action: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", STYLE.STRONG)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("768680"))
	var normal := _panel()
	normal.bg_color = Color("253c38") if action == "keep" else Color("263136")
	normal.border_color = GOLD if action == "keep" else LINE
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3b5149")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("1b2528")
	disabled.border_color = Color("485953")
	button.add_theme_stylebox_override("disabled", disabled)
	var focus := _panel()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = TEXT
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(_emit_choice.bind(action))
	button.gui_input.connect(_choice_touch.bind(action))
	add_child(button)
	button.hide()
	return button

func _choice_touch(event: InputEvent, action: String) -> void:
	# O toque no jogo desliga a emulação de mouse, então o ScreenTouch nativo é suportado.
	if event is InputEventScreenTouch and event.pressed:
		_emit_choice(action)
		get_viewport().set_input_as_handled()

func _emit_choice(action: String) -> void:
	if str(state.get("phase", "")) != "caught": return
	if action == "keep" and not bool(state.get("keep_enabled", true)): return
	catch_choice.emit(action)

func activate_focused_choice() -> void:
	# O controle roteia ui_accept para cá antes das ligações de jogo sobrepostas.
	# Nunca deduz uma escolha padrão quando o foco está em outro lugar ou foi solto.
	if str(state.get("phase", "")) != "caught" or not is_inside_tree(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == _keep_button and _keep_button.is_visible_in_tree() and not _keep_button.disabled:
		_emit_choice("keep")
	elif focused == _release_button and _release_button.is_visible_in_tree() and not _release_button.disabled:
		_emit_choice("release")

func _focus_choice() -> void:
	if str(state.get("phase", "")) != "caught" or not is_instance_valid(_keep_button): return
	if _keep_button.disabled: _release_button.grab_focus()
	else: _keep_button.grab_focus()

func _catch_geometry() -> Dictionary:
	var scale_factor := _hud_scale()
	# Os alvos de escolha ficam com pelo menos 44 pixels físicos mesmo numa viewport de 640px.
	var unit := maxf(.8, scale_factor)
	var margin := maxf(12, 24 * scale_factor)
	var width := minf(maxf(220, 268 * scale_factor), maxf(1, size.x - margin * 2))
	var choosing := str(state.get("phase", "")) == "caught"
	var message := str(state.get("choice_message", "")) if choosing else ""
	var button_y := (104 + (42 if not message.is_empty() else 0)) * unit
	var button_height := maxf(44, 44 * unit)
	var height := button_y + button_height + 14 * unit if choosing else 104 * unit
	var summary_top := (244 if _touch_active() else 108) * scale_factor
	var at := Vector2(size.x - width - margin, summary_top + 126 * scale_factor)
	at.y += (1.0 - _result_reveal) * 12 * scale_factor
	var bottom_limit := size.y - (margin if _touch_active() else maxf(144, 144 * scale_factor))
	if at.y + height > bottom_limit:
		# Telas pequenas põem o cartão ao lado do resumo em vez de cobrir as ações de toque.
		at.x = maxf(margin, size.x - 292 * scale_factor - width - margin)
		at.y = minf(summary_top, maxf(margin, bottom_limit - height))
	var gap := 10 * unit
	var button_width := (width - 28 * unit - gap) * .5
	return {"at":at, "width":width, "height":height, "unit":unit, "keep":Rect2(at + Vector2(14 * unit, button_y), Vector2(button_width, button_height)), "release":Rect2(at + Vector2(14 * unit + button_width + gap, button_y), Vector2(button_width, button_height))}

func _sync_choices() -> void:
	if not is_instance_valid(_keep_button) or not is_instance_valid(_release_button): return
	var choosing := str(state.get("phase", "")) == "caught"
	_keep_button.visible = choosing
	_release_button.visible = choosing
	if not choosing:
		_keep_button.release_focus()
		_release_button.release_focus()
		return
	_keep_button.disabled = not bool(state.get("keep_enabled", true))
	_release_button.disabled = false
	var keep_key := str(state.get("action_key", "E"))
	var release_key := str(state.get("release_key", "R"))
	_keep_button.text = ("" if _touch_active() or keep_key.is_empty() else keep_key + "  ") + tr("Guardar")
	_release_button.text = ("" if _touch_active() or release_key.is_empty() else release_key + "  ") + tr("Soltar")
	var layout := _catch_geometry()
	_keep_button.position = layout.keep.position
	_keep_button.size = layout.keep.size
	_release_button.position = layout.release.position
	_release_button.size = layout.release.size
	var font_size := maxi(14, roundi(17 * float(layout.unit)))
	_keep_button.add_theme_font_size_override("font_size", font_size)
	_release_button.add_theme_font_size_override("font_size", font_size)
	if _keep_button.disabled and _keep_button.has_focus(): _release_button.grab_focus()

func _draw() -> void:
	if state.is_empty() or _font == null or size.x <= 0 or size.y <= 0: return
	var touch := _touch_active()
	var scale_factor := _hud_scale()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	var canvas := size / scale_factor
	var phase := str(state.get("phase", "ready"))
	# O jogo é dono de vida/dinheiro e dos controles de toque. Deixa esses canais livres.
	var summary_at := Vector2(canvas.x - 292, 244 if touch else 108)
	_draw_summary(summary_at)
	if phase in ["caught", "storing", "releasing"]:
		draw_set_transform(Vector2.ZERO)
		_draw_catch()
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	var strip_width := minf(540, canvas.x - 48)
	var strip_height := 78.0 if phase in ["reeling", "charging", "casting", "landing"] else 52.0
	var strip_at := Vector2((canvas.x - strip_width) * .5, canvas.y - (232 if touch else 118))
	if phase not in ["caught", "storing", "releasing"]: _draw_action_strip(Rect2(strip_at, Vector2(strip_width, strip_height)), phase)
	if phase == "reeling":
		var anchor: Vector2 = state.get("rod_screen", size * Vector2(.5, .53))
		var tension_at := anchor / scale_factor + Vector2(-78, -110)
		tension_at.x = clampf(tension_at.x, 36, canvas.x - 92)
		tension_at.y = clampf(tension_at.y, 140, maxf(140, strip_at.y - 204))
		_draw_tension(tension_at)
	_text(Vector2((canvas.x - strip_width) * .5, canvas.y - (128 if touch else 25)), str(state.get("cancel", "")), 15, MUTED, strip_width, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO)

func _draw_summary(at: Vector2) -> void:
	draw_style_box(_style, Rect2(at, Vector2(268, 112)))
	_text(at + Vector2(14, 27), str(state.get("title", "Pesca livre")), 21, TEXT, 240, HORIZONTAL_ALIGNMENT_LEFT, true)
	draw_line(at + Vector2(14, 37), at + Vector2(254, 37), Color("52635d"), 1)
	if bool(state.get("tournament", false)):
		var seconds := maxi(0, ceili(float(state.get("remaining", 0))))
		@warning_ignore("integer_division")
		var clock_text := "%02d:%02d" % [seconds / 60, seconds % 60]
		_text(at + Vector2(14, 66), clock_text, 24, GOLD if seconds <= 15 else TEXT, 100, HORIZONTAL_ALIGNMENT_LEFT, true)
		var rows: Array = state.get("ranking", [])
		var player_rank := 1
		for index in rows.size():
			if bool(rows[index].get("player", false)):
				player_rank = index + 1
				break
		# A colocação é numérica nos dois idiomas suportados.
		_text(at + Vector2(148, 66), "%d / %d" % [player_rank, maxi(1, rows.size())], 24, GOLD, 106, HORIZONTAL_ALIGNMENT_RIGHT, true)
	else:
		_text(at + Vector2(14, 64), tr("%d peixes nesta pescaria") % int(state.get("catches", 0)), 17, MUTED, 240)
	_text(at + Vector2(14, 94), tr("Maior peixe: ") + RULES.kg(int(state.get("best", 0))), 18, GOLD, 240)

func _draw_catch() -> void:
	var layout := _catch_geometry()
	var at: Vector2 = layout.at
	var unit: float = layout.unit
	var width: float = layout.width - 28 * unit
	draw_style_box(_result_style, Rect2(at, Vector2(layout.width, layout.height)))
	_text(at + Vector2(14, 27) * unit, str(state.get("catch_name", "Peixe capturado")), maxi(17, roundi(22 * unit)), TEXT, width, HORIZONTAL_ALIGNMENT_LEFT, true)
	_text(at + Vector2(14, 61) * unit, RULES.kg(int(state.get("catch_grams", 0))), maxi(23, roundi(29 * unit)), GOLD, width, HORIZONTAL_ALIGNMENT_LEFT, true)
	var caption := "Novo recorde" if bool(state.get("catch_record", false)) else "Peixe capturado"
	if str(state.get("phase", "")) == "storing": caption = "Guardando o peixe…"
	elif str(state.get("phase", "")) == "releasing": caption = "Soltando o peixe…"
	_text(at + Vector2(14, 88) * unit, caption, maxi(14, roundi(16 * unit)), GOLD if bool(state.get("catch_record", false)) else MUTED, width)
	var message := str(state.get("choice_message", ""))
	if str(state.get("phase", "")) == "caught" and not message.is_empty():
		draw_multiline_string(_font, at + Vector2(14, 112) * unit, tr(message), HORIZONTAL_ALIGNMENT_LEFT, width, maxi(14, roundi(16 * unit)), 2, DANGER)

func _draw_action_strip(rect: Rect2, phase: String) -> void:
	draw_style_box(_style, rect)
	var instruction := _instruction(phase)
	var color := TEXT
	if phase == "bite": color = GOLD
	elif phase in ["missed", "line_broke"]: color = DANGER
	elif phase == "reeling":
		if str(state.get("fight_hint", "")) == "run" or float(state.get("tension", 0)) >= .78: color = DANGER
		elif str(state.get("fight_hint", "")) == "recovery": color = SAFE
	var has_bar := phase in ["reeling", "charging", "casting", "landing"]
	if has_bar:
		var label := "RECOLHIMENTO"
		var value := float(state.get("progress", 0))
		var fill := WATER
		if phase in ["charging", "casting"]:
			label = "ARREMESSO"
			value = float(state.get("charge", 0))
			fill = GOLD
		elif phase == "landing":
			label = "Peixe capturado"
			value = float(state.get("landing", 0))
			fill = SAFE
		var label_width := 118.0
		_text(rect.position + Vector2(16, 27), label, 15, MUTED, label_width, HORIZONTAL_ALIGNMENT_LEFT, true)
		var track_rect := Rect2(rect.position + Vector2(label_width + 28, 15), Vector2(rect.size.x - label_width - 82, 13))
		draw_style_box(_track, track_rect)
		var fraction := clampf(value, 0, 1)
		if fraction > 0: draw_rect(Rect2(track_rect.position + Vector2(2, 2), Vector2((track_rect.size.x - 4) * fraction, 9)), fill)
		_text(rect.position + Vector2(rect.size.x - 48, 27), "%d%%" % roundi(fraction * 100), 15, TEXT, 36, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(rect.position + Vector2(16, 60 if has_bar else 32), instruction, 21 if phase == "bite" else 19, color, rect.size.x - 32, HORIZONTAL_ALIGNMENT_CENTER, true)

func _instruction(phase: String) -> String:
	match phase:
		"walking", "ready", "charging": return str(state.get("hint", "Prepare a vara"))
		"casting": return tr("Arremessando...")
		"waiting": return tr("Aguarde a boia afundar")
		"bite": return str(state.get("action_key", "")) + "  " + tr("FISGUE AGORA!")
		"hooking": return tr("Fisgado!")
		"landing": return tr("Retirando o peixe…")
		"reeling":
			if float(state.get("tension", 0)) >= .78 or str(state.get("fight_hint", "")) == "run": return tr("ARRANCADA · SOLTE A LINHA") if str(state.get("fight_hint", "")) == "run" else tr("Solte para aliviar a linha")
			if str(state.get("fight_hint", "")) == "recovery": return str(state.get("action_key", "")) + "  " + tr("PEIXE CANSOU · RECOLHA")
			return str(state.get("hint", "Recolha e alivie a linha"))
		"missed", "line_broke": return str(state.get("detail", "O peixe escapou"))
	return str(state.get("detail", ""))

func _draw_tension(at: Vector2) -> void:
	_text(at + Vector2(-24, -10), "TENSÃO", 15, TEXT, 90, HORIZONTAL_ALIGNMENT_CENTER, true, true)
	var body := Rect2(at, Vector2(26, 142))
	draw_style_box(_style, body.grow(3))
	var inside := Rect2(at + Vector2(3, 3), Vector2(20, 136))
	draw_rect(inside, Color("344442"))
	var green := Rect2(inside.position + Vector2(0, inside.size.y * .4), Vector2(20, inside.size.y * .48))
	var yellow := Rect2(inside.position + Vector2(0, inside.size.y * .22), Vector2(20, inside.size.y * .18))
	var red := Rect2(inside.position, Vector2(20, inside.size.y * .22))
	draw_rect(green, SAFE)
	draw_rect(yellow, GOLD)
	draw_rect(red, DANGER)
	# O hachurado deixa a zona de ruptura legível independente da cor.
	for index in 5:
		var y := red.position.y + 2 + index * 6
		draw_line(Vector2(red.position.x + 2, y + 4), Vector2(red.end.x - 2, y), Color("3b2526"), 2, true)
	var tension := clampf(float(state.get("tension", 0)), 0, 1)
	var marker_y := inside.end.y - inside.size.y * tension
	draw_line(Vector2(at.x - 3, marker_y), Vector2(at.x + 29, marker_y), Color("0b171c"), 5, true)
	draw_line(Vector2(at.x - 3, marker_y), Vector2(at.x + 29, marker_y), TEXT, 2, true)
	draw_colored_polygon(PackedVector2Array([Vector2(at.x - 12, marker_y - 5), Vector2(at.x - 5, marker_y), Vector2(at.x - 12, marker_y + 5)]), TEXT)
	_text(at + Vector2(-22, 168), "%d%%" % roundi(tension * 100), 18, DANGER if tension >= .78 else TEXT, 72, HORIZONTAL_ALIGNMENT_CENTER, true, true)

func _text(at: Vector2, value: String, font_size: int, color: Color, width: float, alignment := HORIZONTAL_ALIGNMENT_LEFT, strong := false, outline := false) -> void:
	var font := _strong if strong else _font
	var translated := tr(value)
	var actual_size := font_size
	while actual_size > 13 and font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_size).x > width:
		actual_size -= 1
	if outline: draw_string_outline(font, at, translated, alignment, width, actual_size, 4, Color("101a20"))
	draw_string(font, at, translated, alignment, width, actual_size, color)

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = INK
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0, 0, 0, .18)
	style.shadow_size = 3
	return style

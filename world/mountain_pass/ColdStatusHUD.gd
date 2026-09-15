class_name ColdStatusHUD
extends CanvasLayer

## HUD de Frio & Hipotermia:
## Exibe temperatura corporal como um vital compacto junto de vida/colete e
## mantém a vinheta de congelamento nas bordas conforme o frio aperta.
##
## Avisos da expedição continuam na coluna esquerda; como o frio saiu dessa
## pilha, get_stack_bottom_offset() agora devolve apenas sua margem segura.
const LEFT_STACK_TOP := 24.0
const COMPACT_WIDTH := 120.0
const BAR_WIDTH := 78.0
const BAR_HEIGHT := 5.0

@export var controller_path: NodePath
var controller: Node

var _frost_panel: Control
var _panel: PanelContainer
var _bar_fill: ColorRect
var _bar_bg: ColorRect
var _status_label: Label
var _temp_label: Label
var _vignette_alpha: float = 0.0
var _attached_to_player_hud := false
var _left_stack_top := LEFT_STACK_TOP
var _status_key := ""
var _temperature_band := -1

func _ready() -> void:
	layer = 105
	_build_ui()
	visibility_changed.connect(_on_layer_visibility_changed)
	
	if controller_path:
		controller = get_node_or_null(controller_path)
	if controller == null:
		var controllers := get_tree().get_nodes_in_group("cold_controller")
		if controllers.size() > 0:
			controller = controllers[0]
	
	if controller:
		controller.temperature_changed.connect(_on_temp_changed)
		controller.hypothermia_started.connect(_on_hypothermia_started)
		controller.hypothermia_ended.connect(_on_hypothermia_ended)
		_on_temp_changed(controller.current_temperature, controller.max_temperature)
	_panel.modulate.a = 0.0
	_panel.hide()
	_try_attach_to_player_hud()
	if not _attached_to_player_hud and not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)

func _build_ui() -> void:
	# 1. Overlay de Vinheta de Congelamento (Bordas da Tela)
	_frost_panel = Control.new()
	_frost_panel.name = "FrostVignette"
	_frost_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frost_panel)
	
	# Usar _draw no painel para renderizar a vinheta azul de gelo
	_frost_panel.draw.connect(_draw_frost_vignette)
	
	# 2. Vital térmico compacto. Ele nasce com um fallback no canto superior
	# direito e, assim que o HUD principal existe, é anexado logo abaixo do
	# colete por HUD.attach_vital_indicator().
	_panel = PanelContainer.new()
	_panel.name = "TemperatureVital"
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -144.0
	_panel.offset_top = 92.0
	_panel.offset_right = -24.0
	_panel.offset_bottom = 104.0
	_panel.custom_minimum_size = Vector2(COMPACT_WIDTH, 12.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_meta("preserve_panel_style", true)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color.TRANSPARENT
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.name = "CompactRow"
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	# Um único glifo comunica frio/aquecimento; a frase explicativa longa fica
	# a cargo do tutorial contextual, não de um card permanente.
	_status_label = Label.new()
	_status_label.name = "StateGlyph"
	_status_label.text = "❄"
	_status_label.custom_minimum_size = Vector2(10, 12)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", Color("9bcbe0"))
	_status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_status_label.add_theme_constant_override("outline_size", 2)
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.set_meta("ui_base_font", 10)
	row.add_child(_status_label)

	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(BAR_WIDTH, 12)
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_holder)

	# Barra fina, na mesma linguagem visual da vida e do colete.
	_bar_bg = ColorRect.new()
	_bar_bg.name = "BarBackground"
	_bar_bg.position.y = 3.0
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_bg.color = Color("08090b")
	bar_holder.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.name = "BarFill"
	_bar_fill.position.y = 3.0
	_bar_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar_fill.color = Color("6eb7d2")
	bar_holder.add_child(_bar_fill)

	var border := ReferenceRect.new()
	border.position.y = 3.0
	border.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	border.border_color = Color(0, 0, 0, 0.82)
	border.editor_only = false
	bar_holder.add_child(border)

	_temp_label = Label.new()
	_temp_label.name = "TempLabel"
	_temp_label.text = "100%"
	_temp_label.custom_minimum_size = Vector2(28, 12)
	_temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_temp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_temp_label.add_theme_color_override("font_color", Color("c9d9df"))
	_temp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_temp_label.add_theme_constant_override("outline_size", 2)
	_temp_label.add_theme_font_size_override("font_size", 10)
	_temp_label.set_meta("ui_base_font", 10)
	row.add_child(_temp_label)

## O vital térmico está na direita; a coluna esquerda fica livre para avisos
## curtos da expedição desde a margem segura do HUD.
func get_stack_bottom_offset() -> float:
	return _left_stack_top

func _try_attach_to_player_hud() -> void:
	if _attached_to_player_hud or not is_instance_valid(_panel):
		return
	var player_hud := get_tree().get_first_node_in_group("hud")
	if player_hud == null or not player_hud.has_method("attach_vital_indicator"):
		return
	player_hud.attach_vital_indicator(_panel)
	_attached_to_player_hud = _panel.get_parent() != self
	if _attached_to_player_hud and get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.disconnect(_on_scene_node_added)

func _on_scene_node_added(node: Node) -> void:
	if not node.has_method("attach_vital_indicator"):
		return
	if node.is_node_ready():
		_try_attach_to_player_hud.call_deferred()
	elif not node.ready.is_connected(_try_attach_to_player_hud):
		node.ready.connect(_try_attach_to_player_hud, CONNECT_ONE_SHOT)

func _on_layer_visibility_changed() -> void:
	# Once reparented into HUD, the compact row no longer inherits this
	# CanvasLayer's visibility, so mirror region streaming explicitly.
	if not is_instance_valid(_panel):
		return
	if not visible:
		_panel.hide()
		return
	var blocked := _is_cgi_playing()
	if controller != null and is_instance_valid(controller.player_target):
		blocked = blocked or controller.player_target.get("is_in_dialogue") == true
	if not blocked and controller != null and controller.should_show_status():
		_panel.modulate.a = maxf(_panel.modulate.a, 0.05)
		_panel.show()

func _exit_tree() -> void:
	if is_instance_valid(_panel) and _panel.get_parent() != self:
		_panel.queue_free()

## A CGI de abertura (cutscenes/opening/) roda numa CanvasLayer própria em
## layer=100 (HarborArrivalMission.gd:_opening_layer); nosso `layer=105`
## renderiza por cima dela se os dois chegarem a coexistir. Nenhum HUD deve
## aparecer sobre a CGI, então escondemos este bloco enquanto ela tocar.
func _is_cgi_playing() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var mission := scene.get_node_or_null("ArrivalMission")
	if mission == null:
		return false
	var opening_layer = mission.get("_opening_layer")
	return opening_layer != null and is_instance_valid(opening_layer)

func _process(delta: float) -> void:
	var cgi_playing := _is_cgi_playing()
	if controller != null and is_instance_valid(controller.player_target):
		cgi_playing = cgi_playing or controller.player_target.get("is_in_dialogue") == true
	var show_status: bool = visible and not cgi_playing and controller != null and controller.should_show_status()
	if _panel != null:
		var next_alpha := move_toward(_panel.modulate.a, 1.0 if show_status else 0.0, delta * 2.0)
		if not is_equal_approx(_panel.modulate.a, next_alpha):
			_panel.modulate.a = next_alpha
		var panel_visible := visible and not cgi_playing and _panel.modulate.a > 0.01
		if _panel.visible != panel_visible:
			_panel.visible = panel_visible
	if _frost_panel != null:
		var frost_visible := visible and not cgi_playing
		if _frost_panel.visible != frost_visible:
			_frost_panel.visible = frost_visible
	if cgi_playing:
		return
	if controller:
		_update_status_display()

func _update_status_display() -> void:
	var glyph := "❄"
	var glyph_color := Color("9bcbe0")
	var status_text := tr("COLD_STATUS_STABLE")
	var status_key := "stable"
	if controller.is_hypothermic:
		status_key = "hypothermia"
		glyph = "!"
		glyph_color = Color("e45b64")
		status_text = tr("COLD_STATUS_HYPOTHERMIA_CRITICAL")
	elif controller.sheltered:
		status_key = "sheltered"
		glyph = "↑"
		glyph_color = Color("dfb66d")
		status_text = tr("COLD_STATUS_SHELTERED")
	elif controller.is_near_heat_source:
		status_key = "fire"
		glyph = "↑"
		glyph_color = Color("dfb66d")
		status_text = tr("COLD_STATUS_HEATED_FIRE")
	elif controller.is_in_vehicle:
		status_key = "vehicle"
		glyph = "↑"
		glyph_color = Color("82c89a")
		status_text = tr("COLD_STATUS_HEATED_VEHICLE")
	elif controller.is_in_cold_zone() and controller.exposure_seconds <= controller.arrival_grace_seconds:
		status_key = "grace"
		status_text = "O frio aumenta aos poucos. Prepare um casaco."
	elif controller.has_thermal_suit or controller.outfit_protection>=0.35:
		var protection := roundi(maxf(controller.outfit_protection,0.8 if controller.has_thermal_suit else 0.0)*100)
		status_key = "protected_%d" % protection
		status_text = "PROTEÇÃO AO FRIO: %d%%" % protection
	elif controller.is_in_cold_zone():
		status_key = "freezing"
		status_text = tr("COLD_STATUS_FREEZING_WARNING")
	if status_key == _status_key:
		return
	_status_key = status_key
	_status_label.text = glyph
	_status_label.add_theme_color_override("font_color", glyph_color)
	# Keep the descriptive state available to tests/future accessibility hooks
	# without painting a second line of prose over gameplay.
	_panel.set_meta("cold_status_text", status_text)

func _on_temp_changed(cur: float, max_val: float) -> void:
	var ratio: float = clampf(cur / max_val, 0.0, 1.0)
	var next_width := BAR_WIDTH * ratio
	if not is_equal_approx(_bar_fill.size.x, next_width):
		_bar_fill.size.x = next_width
	var percentage_text := "%d%%" % int(ratio * 100.0)
	if _temp_label.text != percentage_text:
		_temp_label.text = percentage_text
	
	# Muda cor da barra conforme fica mais frio
	var band := 2 if ratio > 0.5 else (1 if ratio > 0.2 else 0)
	if band == _temperature_band:
		_update_vignette(ratio)
		return
	_temperature_band = band
	if band == 2:
		_bar_fill.color = Color("6eb7d2") # Azul gelo, sem neon
		_temp_label.add_theme_color_override("font_color", Color("c9d9df"))
	elif band == 1:
		_bar_fill.color = Color("b18bbd")
		_temp_label.add_theme_color_override("font_color", Color("d6c4dd"))
	else:
		_bar_fill.color = Color("d4555f")
		_temp_label.add_theme_color_override("font_color", Color("e8a2a8"))
	_update_vignette(ratio)

func _update_vignette(ratio: float) -> void:
	var next_alpha := (0.5 - ratio) * 1.6 if ratio < 0.5 else 0.0
	if is_equal_approx(_vignette_alpha, next_alpha):
		return
	_vignette_alpha = next_alpha
	_frost_panel.queue_redraw()

func _on_hypothermia_started() -> void:
	_vignette_alpha = 0.85
	_frost_panel.queue_redraw()

func _on_hypothermia_ended() -> void:
	_vignette_alpha = 0.0
	_frost_panel.queue_redraw()

func _draw_frost_vignette() -> void:
	if _vignette_alpha <= 0.01:
		return
	
	var vp_size: Vector2 = _frost_panel.get_viewport_rect().size
	var border_w: float = 60.0
	var col := Color(0.65, 0.85, 1.0, _vignette_alpha)
	var col_fade := Color(0.65, 0.85, 1.0, 0.0)
	
	# Bordas superior, inferior, esquerda e direita com gradiente de gelo
	# Superior
	_frost_panel.draw_rect(Rect2(0, 0, vp_size.x, border_w), col)
	# Inferior
	_frost_panel.draw_rect(Rect2(0, vp_size.y - border_w, vp_size.x, border_w), col)
	# Esquerda
	_frost_panel.draw_rect(Rect2(0, 0, border_w, vp_size.y), col)
	# Direita
	_frost_panel.draw_rect(Rect2(vp_size.x - border_w, 0, border_w, vp_size.y), col)

func set_stack_top(value: float) -> void:
	_left_stack_top = maxf(LEFT_STACK_TOP, value)

class_name ColdStatusHUD
extends CanvasLayer

## HUD de Frio & Hipotermia:
## Exibe barra de temperatura corporal, status de aquecimento (veículo/fogueira)
## e vinheta de congelamento com gelo nas bordas da tela conforme o frio aperta.
##
## Layout: este bloco fica na coluna esquerda (x=24), abaixo do card
## "OBJETIVO ATUAL" (CobraCampaignBridge.gd / HarborArrivalMission.gd, ambos
## fixos em Vector2(24,150), largura 400, altura variável ~76-100px quando o
## texto de objetivo quebra em 2-3 linhas -- não é editável por este script).
## BLOCK_TOP já inclui essa margem de segurança. MountainExpedition.gd
## empilha o readout de altitude e os avisos temporários logo abaixo deste
## bloco via get_stack_bottom_offset() -- ver ui/HUD_LAYOUT_NOTES.md.
const BLOCK_LEFT := 24.0
const BLOCK_TOP := 254.0
const BLOCK_WIDTH := 264.0
const BAR_WIDTH := 232.0

@export var controller_path: NodePath
var controller: Node

var _frost_panel: Control
var _panel: PanelContainer
var _bar_fill: ColorRect
var _bar_bg: ColorRect
var _status_label: Label
var _temp_label: Label
var _vignette_alpha: float = 0.0

func _ready() -> void:
	layer = 105
	_build_ui()
	
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

func _build_ui() -> void:
	# 1. Overlay de Vinheta de Congelamento (Bordas da Tela)
	_frost_panel = Control.new()
	_frost_panel.name = "FrostVignette"
	_frost_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frost_panel)
	
	# Usar _draw no painel para renderizar a vinheta azul de gelo
	_frost_panel.draw.connect(_draw_frost_vignette)
	
	# 2. Bloco de Temperatura / Proteção Térmica -- coluna esquerda, abaixo do
	# card de objetivo. Um painel de fundo (em vez de texto solto sobre o
	# mundo) garante contraste sobre neve/céu claros.
	_panel = PanelContainer.new()
	_panel.name = "ColdHUDPanel"
	_panel.position = Vector2(BLOCK_LEFT, BLOCK_TOP)
	_panel.custom_minimum_size = Vector2(BLOCK_WIDTH, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.08, 0.11, 0.80)
	panel_style.border_color = Color(0.55, 0.78, 0.95, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.border_width_left = 3
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	# Label de Temperatura
	_temp_label = Label.new()
	_temp_label.name = "TempLabel"
	_temp_label.text = tr("COLD_TEMPERATURE_LABEL") % 100
	_temp_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_temp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_temp_label.add_theme_constant_override("outline_size", 3)
	_temp_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_temp_label)

	var bar_holder := Control.new()
	bar_holder.custom_minimum_size = Vector2(BAR_WIDTH, 16)
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_holder)

	# Fundo da barra
	_bar_bg = ColorRect.new()
	_bar_bg.name = "BarBackground"
	_bar_bg.size = Vector2(BAR_WIDTH, 16)
	_bar_bg.color = Color(0.1, 0.15, 0.22, 0.85)
	bar_holder.add_child(_bar_bg)

	# Preenchimento da barra
	_bar_fill = ColorRect.new()
	_bar_fill.name = "BarFill"
	_bar_fill.size = Vector2(BAR_WIDTH, 16)
	_bar_fill.color = Color(0.25, 0.75, 1.0, 0.95)
	bar_holder.add_child(_bar_fill)

	# Borda sutil
	var border := ReferenceRect.new()
	border.size = Vector2(BAR_WIDTH, 16)
	border.border_color = Color(0.7, 0.9, 1.0, 0.7)
	border.editor_only = false
	bar_holder.add_child(border)

	# Label de Estado (AQUECIDO / CONGELANDO / PROTEGIDO)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = tr("COLD_STATUS_NORMAL")
	_status_label.custom_minimum_size = Vector2(BAR_WIDTH, 0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status_label.add_theme_constant_override("outline_size", 3)
	_status_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_status_label)

## Contrato para quem empilha mais UI abaixo deste bloco (hoje só
## MountainExpedition.gd, para o readout de altitude e os avisos
## temporários): topo livre logo abaixo do painel de temperatura/proteção
## térmica, já com uma margem de respiro.
func get_stack_bottom_offset() -> float:
	return maxf(BLOCK_TOP+96.0,_panel.position.y+maxf(96,_panel.size.y)) if is_instance_valid(_panel) else BLOCK_TOP+96.0

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

func _process(_delta: float) -> void:
	var cgi_playing := _is_cgi_playing()
	if _panel != null:
		_panel.visible = not cgi_playing
	if _frost_panel != null:
		_frost_panel.visible = not cgi_playing
	if cgi_playing:
		return
	if controller:
		_update_status_display()

func _update_status_display() -> void:
	if controller.sheltered:
		_status_label.text = tr("COLD_STATUS_SHELTERED")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	elif controller.is_near_heat_source:
		_status_label.text = tr("COLD_STATUS_HEATED_FIRE")
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	elif controller.is_in_vehicle:
		_status_label.text = tr("COLD_STATUS_HEATED_VEHICLE")
		_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	elif controller.has_thermal_suit or controller.outfit_protection>0:
		_status_label.text = "PROTEÇÃO AO FRIO: %d%%" % roundi(maxf(controller.outfit_protection,0.8 if controller.has_thermal_suit else 0.0)*100)
		_status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	elif controller.is_in_cold_zone():
		if controller.is_hypothermic:
			_status_label.text = tr("COLD_STATUS_HYPOTHERMIA_CRITICAL")
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.3))
		else:
			_status_label.text = tr("COLD_STATUS_FREEZING_WARNING")
			_status_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	else:
		_status_label.text = tr("COLD_STATUS_STABLE")
		_status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.9))

func _on_temp_changed(cur: float, max_val: float) -> void:
	var ratio: float = clampf(cur / max_val, 0.0, 1.0)
	_bar_fill.size.x = 200.0 * ratio
	_temp_label.text = tr("COLD_TEMPERATURE_LABEL") % int(ratio * 100.0)
	
	# Muda cor da barra conforme fica mais frio
	if ratio > 0.5:
		_bar_fill.color = Color(0.25, 0.75, 1.0, 0.95) # Azul gelo
	elif ratio > 0.2:
		_bar_fill.color = Color(0.4, 0.5, 0.9, 0.95)  # Roxo frio
	else:
		_bar_fill.color = Color(0.9, 0.2, 0.35, 0.95) # Vermelho congelando
	
	# Atualiza a vinheta de congelamento nas bordas da tela
	if ratio < 0.5:
		_vignette_alpha = (0.5 - ratio) * 1.6 # Vai até ~0.8 de opacidade no pico
	else:
		_vignette_alpha = 0.0
	
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
	if is_instance_valid(_panel): _panel.position.y = maxf(BLOCK_TOP,value)

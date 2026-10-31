extends RefCounted
## Só apresentação. Os botões existentes mantêm donos, sinais e regras.
const STYLE := preload("res://ui/GameStyle.gd")
const TEXT_SIZE := 18
static var _font: FontFile
static var _icons := {}

static func icon_texture(kind: String) -> Texture2D:
	if not _icons.has(kind):
		_icons[kind] = load("res://assets/ui/harbor-menu/"+kind+".svg")
	return _icons[kind]

static func font() -> FontFile:
	if _font == null:
		_font = STYLE.FONT.duplicate()
		_font.antialiasing = 1
		_font.generate_mipmaps = true
		_font.oversampling = 2.0
	return _font

static func typography(node: Node) -> void:
	if node is Control:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if node is Label or node is Button or node is LineEdit:
		node.add_theme_font_override("font",font())
		node.add_theme_font_size_override("font_size",TEXT_SIZE)
		node.add_theme_constant_override("outline_size",0)
		node.add_theme_constant_override("shadow_offset_x",0)
		node.add_theme_constant_override("shadow_offset_y",0)
	for child in node.get_children(): typography(child)

static func surface(fill: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.corner_detail = 12
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

static func button(control: Button, primary := false, icon := "") -> void:
	control.custom_minimum_size = Vector2(0, 44)
	control.alignment = HORIZONTAL_ALIGNMENT_LEFT
	control.add_theme_font_override("font", font())
	control.add_theme_font_size_override("font_size", TEXT_SIZE)
	control.add_theme_stylebox_override("normal", surface(STYLE.ACCENT if primary else Color(0.07,0.09,0.11,.72), STYLE.ACCENT if primary else Color("353c40")))
	control.add_theme_stylebox_override("hover", surface(STYLE.ACCENT if primary else Color("293034"), STYLE.ACCENT))
	control.add_theme_stylebox_override("pressed", surface(STYLE.ACCENT.darkened(.12), STYLE.ACCENT))
	control.add_theme_stylebox_override("focus", surface(Color.TRANSPARENT, STYLE.TEXT))
	control.add_theme_stylebox_override("disabled", surface(Color(0.07,0.09,0.11,.55), Color("30363b")))
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		control.add_theme_color_override(state, STYLE.INK if primary else STYLE.TEXT)
	control.add_theme_color_override("font_disabled_color", STYLE.MUTED.darkened(.25))
	if not icon.is_empty():
		control.icon = icon_texture(icon)
		control.expand_icon = true
		control.add_theme_constant_override("icon_max_width", 22)
		control.add_theme_constant_override("h_separation", 16)
		control.add_theme_color_override("icon_normal_color", STYLE.INK if primary else STYLE.TEXT)
		control.add_theme_color_override("icon_focus_color", STYLE.INK if primary else STYLE.TEXT)
		control.add_theme_color_override("icon_hover_color", STYLE.INK if primary else STYLE.TEXT)

static func pause(menu: CanvasLayer, developer: Button, guide: Button) -> void:
	var center: PanelContainer = menu.get_node("RootControl/CenterPanel")
	var old: Control = center.get_node("Margin")
	var actions := {}
	for name in ["BtnResume","BtnSaveGame","BtnLoadGame","BtnAchievements","BtnCollectibles","BtnSettings","BtnMainMenu","BtnQuit"]:
		actions[name] = menu.find_child(name,true,false)
	center.custom_minimum_size = Vector2.ZERO
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	center.add_theme_stylebox_override("panel", surface(Color("13191e"),STYLE.LINE))
	var margin := MarginContainer.new()
	margin.name = "HarborPauseLayout"
	margin.theme = STYLE.create_theme(TEXT_SIZE)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side, 20)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side, 20)
	center.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	column.add_child(STYLE.label("Harbor",TEXT_SIZE))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 250
	left.add_theme_constant_override("separation",14)
	columns.add_child(left)
	left.add_child(STYLE.label("Pausa",TEXT_SIZE))
	for entry in [["BtnResume","play"],["BtnSaveGame","save"],["BtnLoadGame","folder-open"]]:
		var action: Button = actions[entry[0]]
		action.reparent(left)
		button(action,entry[0]=="BtnResume",entry[1])
	columns.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 270
	right.add_theme_constant_override("separation",10)
	columns.add_child(right)
	right.add_child(STYLE.label("Progresso",TEXT_SIZE,STYLE.ACCENT))
	for entry in [["BtnAchievements","trophy"],["BtnCollectibles","map"]]:
		var action: Button = actions[entry[0]]
		action.reparent(right)
		button(action,false,entry[1])
	right.add_child(HSeparator.new())
	guide.reparent(right)
	button(guide,false,"book-open")
	actions.BtnSettings.reparent(right)
	button(actions.BtnSettings,false,"settings")
	right.add_child(HSeparator.new())
	for entry in [["BtnMainMenu","house"],["BtnQuit","log-out"]]:
		var action: Button = actions[entry[0]]
		action.reparent(right)
		button(action,false,entry[1])
	developer.reparent(right)
	button(developer)
	developer.add_theme_font_size_override("font_size",TEXT_SIZE)
	developer.add_theme_color_override("font_color",STYLE.MUTED)
	for child in right.get_children():
		if child is Button:
			child.add_theme_stylebox_override("normal", surface(Color.TRANSPARENT))
	var captions := {"BtnResume":"Continuar", "BtnSaveGame":"Salvar jogo", "BtnLoadGame":"Carregar jogo", "BtnAchievements":"Conquistas", "BtnCollectibles":"Colecionáveis", "BtnSettings":"Configurações", "BtnMainMenu":"Menu principal", "BtnQuit":"Sair do jogo"}
	for key in captions: actions[key].text = captions[key]
	typography(margin)
	old.hide()
	var root_control: Control = menu.get_node("RootControl")
	root_control.resized.connect(func(): _fit_pause(center,root_control.size))
	_fit_pause(center,root_control.size)

static func _fit_pause(panel: Control, viewport_size: Vector2) -> void:
	fit_panel(panel,viewport_size,Vector2(760,680))

static func fit_panel(panel: Control, viewport_size: Vector2, maximum := Vector2(1040,740)) -> void:
	var margin := 12.0 if viewport_size.x < 1000 else 24.0
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT,true)
	panel.size = Vector2(minf(maximum.x,viewport_size.x-margin*2),minf(maximum.y,viewport_size.y-margin*2))
	panel.position = (viewport_size-panel.size)*.5

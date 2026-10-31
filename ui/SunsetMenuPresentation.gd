extends Control
## Static presentation; MainMenu owns save routing, settings and scene changes.
const STYLE := preload("res://ui/GameStyle.gd")
const DISPLAY_FONT: FontFile = preload("res://assets/fonts/manrope/Manrope-SemiBold.ttf")
const BODY_FONT: FontFile = preload("res://assets/fonts/manrope/Manrope-Regular.ttf")
var buttons: Array[Button] = []
var background: ColorRect
var brand_accent: ColorRect
var resume_label: Label
var source_menu: Control
var artwork: TextureRect
var footer: Label
var main_content: Control
var wordmark: TextureRect

func install(menu: Control) -> void:
	source_menu = menu
	name = "SunsetPresentation"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.get_node("Background").hide()
	menu.get_node("CitySilhouette").hide()
	menu.get_node("MainLayout").hide()
	background = ColorRect.new()
	background.name = "StaticBackground"
	background.color = Color("101216")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	artwork = TextureRect.new()
	artwork.texture = preload("res://ui/art/menu_harbor_deepwater.png")
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(artwork)
	main_content = Control.new()
	main_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_content)
	menu.game_title.reparent(main_content)
	menu.game_title.hide()
	wordmark = TextureRect.new()
	var title_texture := AtlasTexture.new()
	title_texture.atlas = preload("res://ui/art/menu_harbor_wordmark.png")
	title_texture.region = Rect2(50, 130, 2070, 480)
	wordmark.texture = title_texture
	wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_content.add_child(wordmark)
	menu.game_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.game_title.add_theme_font_override("font", DISPLAY_FONT)
	menu.game_title.add_theme_color_override("font_color", STYLE.TEXT)
	menu.game_title.add_theme_constant_override("outline_size", 0)
	menu.game_title.add_theme_constant_override("shadow_offset_y", 0)
	menu.game_title.add_theme_constant_override("shadow_offset_x", 0)
	menu.sub_title.hide()
	brand_accent = ColorRect.new()
	brand_accent.color = STYLE.ACCENT
	brand_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand_accent)
	brand_accent.hide()
	buttons.assign([menu.btn_continue, menu.btn_new_game, menu.btn_load_game, menu.btn_settings, menu.btn_quit])
	var menu_font := FontVariation.new()
	menu_font.base_font = DISPLAY_FONT
	menu_font.spacing_glyph = 0
	for button in buttons:
		button.reparent(main_content)
		button.custom_minimum_size = Vector2.ZERO
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_override("font", menu_font)
		button.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .9))
		button.add_theme_constant_override("shadow_offset_y", 1)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		normal.content_margin_left = 12
		normal.content_margin_right = 12
		var active := normal.duplicate() as StyleBoxFlat
		active.bg_color = Color("eee5d0")
		var pressed := active.duplicate() as StyleBoxFlat
		pressed.bg_color = STYLE.ACCENT
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", active)
		button.add_theme_stylebox_override("focus", active)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_color", STYLE.TEXT)
		button.add_theme_color_override("font_hover_color", Color("111b23"))
		button.add_theme_color_override("font_focus_color", Color("111b23"))
		button.add_theme_color_override("font_pressed_color", Color("111b23"))
		button.add_theme_stylebox_override("disabled", normal)
	# Mantém a migração disponível na tela de save sem lotar o menu principal.
	menu.btn_import.reparent(menu.get_node("%LoadPanel").get_node("Margin/VBox/Actions"))
	menu.btn_import.custom_minimum_size = Vector2(180, 36)
	footer = Label.new()
	footer.text = "Enter / A  ·  Selecionar"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_override("font", BODY_FONT)
	footer.add_theme_color_override("font_color", STYLE.MUTED)
	main_content.add_child(footer)
	resized.connect(arrange)
	arrange()
	# Só a opacidade muda. O fundo opaco sempre cobre o mundo aquecendo.
	var intro := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for child in get_children():
		if child == background: continue
		child.modulate.a = 0.0
		intro.tween_property(child, "modulate:a", 1.0, .45)

func arrange() -> void:
	# Fixed upper bounds prevent ultrawide/4K displays from stretching menu actions.
	var width := minf(620,size.x-48)
	var height := minf(580,size.y-48)
	var origin := (size-Vector2(width,height))*.5
	wordmark.position = origin+Vector2(0,24)
	wordmark.size = Vector2(width,112)
	source_menu.game_title.position = wordmark.position
	source_menu.game_title.size = wordmark.size
	source_menu.game_title.add_theme_font_size_override("font_size",64)
	var menu_top := origin.y+height*.38
	var row := 0
	for button in buttons:
		if not button.visible: continue
		var button_width := minf(330,width)
		button.position = Vector2((size.x-button_width)*.5,menu_top+row*44)
		button.size = Vector2(button_width,40)
		button.add_theme_font_size_override("font_size",20)
		row += 1
	footer.position = Vector2(origin.x,origin.y+height-28)
	footer.size = Vector2(width,24)
	footer.add_theme_font_size_override("font_size",14)

func show_main(value: bool) -> void:
	main_content.visible = value
	if value: arrange()

func play_start_transition() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 0.0, .35)
	await tween.finished

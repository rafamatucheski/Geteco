extends Control
## Presentation only; MainMenu retains save, settings and scene routing.
var buttons: Array[Button] = []
var motion: Dictionary = {}
var background: TextureRect
var atmosphere: Control = null
var cover: ColorRect
var brand_accent: ColorRect
var resume_label: Label
var source_menu: Control

const DISPLAY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const MENU_ART: Texture2D = preload("res://ui/art/menu_harbor_bluehour.png")

func install(menu: Control) -> void:
	source_menu = menu
	name = "SunsetPresentation"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.get_node("Background").hide()
	menu.get_node("CitySilhouette").hide()
	menu.get_node("MainLayout").hide()
	background = TextureRect.new()
	background.name = "SunsetBackground"
	background.texture = MENU_ART
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	# A vinheta cria contraste sem esconder a nova arte autoral do porto.
	cover = ColorRect.new()
	cover.color = Color.WHITE
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cover_shader := Shader.new()
	cover_shader.code = "shader_type canvas_item; void fragment(){ float left=1.0-smoothstep(0.05,0.48,UV.x); float floor_fade=smoothstep(0.62,1.0,UV.y)*0.30; float a=clamp(left*0.84+floor_fade,0.0,0.88); COLOR=vec4(0.012,0.026,0.043,a); }"
	var cover_material := ShaderMaterial.new()
	cover_material.shader = cover_shader
	cover.material = cover_material
	add_child(cover)
	menu.game_title.reparent(self)
	menu.game_title.add_theme_font_override("font", DISPLAY_FONT)
	menu.game_title.add_theme_color_override("font_color", Color("f5f1e8"))
	menu.game_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.68))
	menu.game_title.add_theme_constant_override("shadow_offset_x", 0)
	menu.game_title.add_theme_constant_override("shadow_offset_y", 4)
	menu.game_title.add_theme_constant_override("outline_size", 1)
	menu.sub_title.hide()
	brand_accent = ColorRect.new()
	brand_accent.color = Color("ff914d")
	brand_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand_accent)
	buttons.assign([menu.btn_new_game, menu.btn_load_game, menu.btn_settings, menu.btn_quit])
	if menu.btn_continue.visible: buttons.push_front(menu.btn_continue)
	for button in buttons:
		button.reparent(self)
		button.custom_minimum_size = Vector2.ZERO
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_override("font", DISPLAY_FONT)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0,0,0,0)
		normal.content_margin_left = 14
		var active := normal.duplicate() as StyleBoxFlat
		active.bg_color = Color(1,0.45,0.18,0.12)
		active.border_width_left = 3
		active.border_color = Color("ff914d")
		var pressed := active.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(1,0.32,0.08,0.24)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", active)
		button.add_theme_stylebox_override("focus", active)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_color", Color("eee9df"))
		button.add_theme_color_override("font_hover_color", Color("ff914d"))
		button.add_theme_color_override("font_focus_color", Color("ff914d"))
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.mouse_entered.connect(func(): animate(button, true))
		button.mouse_exited.connect(func(): animate(button, button.has_focus()))
		button.focus_entered.connect(func(): animate(button, true))
		button.focus_exited.connect(func(): animate(button, button.is_hovered()))
		button.button_down.connect(func(): pulse(button))
		button.button_up.connect(func(): animate(button, button.has_focus() or button.is_hovered()))
	resized.connect(arrange)
	if not menu.latest_save.is_empty():
		resume_label = Label.new()
		resume_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		resume_label.add_theme_font_override("font", BODY_FONT)
		resume_label.add_theme_color_override("font_color",Color("a9b4bc"))
		resume_label.text = str(menu.latest_save.get("label", ""))
		add_child(resume_label)
	arrange()
	modulate.a = 0.0
	var intro_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(self, "modulate:a", 1.0, 0.55)
	for i in buttons.size():
		var btn := buttons[i]
		var target_x: float = btn.position.x
		btn.position.x = target_x - 28.0
		btn.modulate.a = 0.0
		intro_tween.tween_property(btn, "position:x", target_x, 0.42).set_delay(0.06 + i * 0.05)
		intro_tween.tween_property(btn, "modulate:a", 1.0, 0.36).set_delay(0.06 + i * 0.05)

func arrange() -> void:
	# Preserva o enquadramento e centraliza qualquer recorte em telas não 16:9.
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var art_size := background.texture.get_size()
	background.size = art_size*maxf(size.x/art_size.x,size.y/art_size.y)
	background.position = (size-background.size)*0.5
	cover.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	cover.position = Vector2.ZERO
	cover.size = size
	source_menu.game_title.position = Vector2(size.x*0.044, size.y*0.075)
	source_menu.game_title.size = size*Vector2(0.34,0.14)
	source_menu.game_title.add_theme_font_size_override("font_size", maxi(58,int(size.y*0.10)))
	brand_accent.position = Vector2(size.x*0.047, size.y*0.202)
	brand_accent.size = Vector2(size.x*0.075, maxf(3.0,size.y*0.006))
	var menu_top := size.y*0.385
	if resume_label != null:
		resume_label.position = Vector2(size.x*0.048,menu_top+size.y*(0.025+buttons.size()*0.072))
		resume_label.size = size*Vector2(0.25,0.09)
		resume_label.add_theme_font_size_override("font_size",maxi(14,int(size.y*0.019)))
	for i in buttons.size():
		var button := buttons[i]
		button.position = Vector2(size.x*0.036,menu_top+size.y*(0.02+i*0.072))
		button.size = size * Vector2(0.255, 0.060)
		button.add_theme_font_size_override("font_size", maxi(15, int(size.y * 0.027)))
		button.pivot_offset = Vector2(0,button.size.y*0.5)
		button.set_meta("base_x", button.position.x)

func animate(button: Button, active: bool) -> void:
	if motion.has(button): motion[button].kill()
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion[button] = tween
	var base_x: float = float(button.get_meta("base_x", button.position.x))
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if active else 1.0), 0.16)
	tween.tween_property(button, "position:x", base_x + (5.0 if active else 0.0), 0.16)

func pulse(button: Button) -> void:
	if motion.has(button): motion[button].kill()
	button.scale = Vector2.ONE * 0.97

## Transição cinematográfica disparada ao iniciar a partida (Novo Jogo / Continuar)
func play_start_transition() -> void:
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	for i in buttons.size():
		var btn := buttons[i]
		tween.tween_property(btn, "position:x", btn.position.x - 45.0, 0.35).set_delay(i * 0.03)
		tween.tween_property(btn, "modulate:a", 0.0, 0.28).set_delay(i * 0.03)
	if resume_label != null:
		tween.tween_property(resume_label, "modulate:a", 0.0, 0.25)
	if cover != null:
		tween.tween_property(cover, "modulate:a", 0.0, 0.30)
	tween.tween_property(background, "scale", Vector2(1.04, 1.04), 0.45)
	var curtain := ColorRect.new()
	curtain.color = Color(0, 0, 0, 0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(curtain)
	tween.tween_property(curtain, "color:a", 1.0, 0.38).set_delay(0.05)
	await tween.finished


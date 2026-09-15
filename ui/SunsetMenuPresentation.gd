extends Control
## Presentation only; MainMenu retains save, settings and scene routing.
var buttons: Array[Button] = []
var motion: Dictionary = {}
var background: TextureRect
var atmosphere: Control
var cover: ColorRect
var resume_label: Label
var source_menu: Control

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
	background.texture = preload("res://prototypes/menu_concept/dante_sunset_preview.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/SunsetAtmosphere.gdshader")
	background.material = mat
	atmosphere = preload("res://ui/SunsetAtmosphere.gd").new()
	add_child(atmosphere)
	# Painel translúcido elegante que destaca os botões sem ocultar a arte do porto.
	cover = ColorRect.new()
	cover.color = Color(0.04, 0.05, 0.08, 0.65)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cover)
	buttons.assign([menu.btn_new_game, menu.btn_load_game, menu.btn_settings, menu.btn_quit])
	if menu.btn_continue.visible: buttons.push_front(menu.btn_continue)
	for button in buttons:
		button.reparent(self)
		button.custom_minimum_size = Vector2.ZERO
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0,0,0,0)
		normal.content_margin_left = 16
		var active := normal.duplicate() as StyleBoxFlat
		active.bg_color = Color(1,0.32,0.08,0.10)
		active.border_width_left = 3
		active.border_color = Color("ff742c")
		var pressed := active.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(1,0.32,0.08,0.24)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", active)
		button.add_theme_stylebox_override("focus", active)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_color_override("font_color", Color("eadbc5"))
		button.add_theme_color_override("font_hover_color", Color("ff742c"))
		button.add_theme_color_override("font_focus_color", Color("ff742c"))
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
		resume_label.add_theme_color_override("font_color",Color("a9b4bc"))
		add_child(resume_label)
	arrange()
	modulate.a = 0.0
	var intro_tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	intro_tween.tween_property(self, "modulate:a", 1.0, 0.55)
	if not get_node("/root/SettingsManager").reduce_motion:
		for i in buttons.size():
			var btn := buttons[i]
			var target_x: float = btn.position.x
			btn.position.x = target_x - 28.0
			btn.modulate.a = 0.0
			intro_tween.tween_property(btn, "position:x", target_x, 0.42).set_delay(0.06 + i * 0.05)
			intro_tween.tween_property(btn, "modulate:a", 1.0, 0.36).set_delay(0.06 + i * 0.05)

func arrange() -> void:
	# Preserva proporções do porto e de Dante; recorta bordas excessivas.
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var art_size := background.texture.get_size()
	background.size = art_size*maxf(size.x/art_size.x,size.y/art_size.y)
	background.position = Vector2.ZERO
	atmosphere.size = background.size
	atmosphere.position = background.position
	var menu_top := minf(maxf(size.y*0.385,background.size.y*0.36),size.y-430)
	cover.position = Vector2(size.x*0.018,menu_top)
	cover.size = size * Vector2(0.30, 0.075*buttons.size()+0.05)
	if resume_label != null:
		cover.size.y += size.y*0.09
		resume_label.position = Vector2(size.x*0.048,menu_top+size.y*(0.02+buttons.size()*0.077))
		resume_label.size = size*Vector2(0.25,0.09)
		resume_label.add_theme_font_size_override("font_size",maxi(14,int(size.y*0.019)))
	cover.size.y = maxf(cover.size.y,background.size.y*0.715-menu_top)
	for i in buttons.size():
		var button := buttons[i]
		button.position = Vector2(size.x*0.035,menu_top+size.y*(0.02+i*0.077))
		button.size = size * Vector2(0.266, 0.065)
		button.add_theme_font_size_override("font_size", maxi(15, int(size.y * 0.027)))
		button.pivot_offset = Vector2(0,button.size.y*0.5)
		button.set_meta("base_x", button.position.x)

func animate(button: Button, active: bool) -> void:
	if get_node("/root/SettingsManager").reduce_motion: return
	if motion.has(button): motion[button].kill()
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion[button] = tween
	var base_x: float = float(button.get_meta("base_x", button.position.x))
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if active else 1.0), 0.16)
	tween.tween_property(button, "position:x", base_x + (5.0 if active else 0.0), 0.16)

func pulse(button: Button) -> void:
	if get_node("/root/SettingsManager").reduce_motion: return
	if motion.has(button): motion[button].kill()
	button.scale = Vector2.ONE * 0.97

## Transição cinematográfica disparada ao iniciar a partida (Novo Jogo / Continuar)
func play_start_transition() -> void:
	if get_node("/root/SettingsManager").reduce_motion:
		return
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

func _process(delta: float) -> void:
	if background != null and atmosphere != null:
		atmosphere.advance(delta, get_node("/root/SettingsManager").reduce_motion)
		background.material.set_shader_parameter("atmosphere_time", atmosphere.elapsed)
	if resume_label != null:
		var data: Dictionary = source_menu.latest_save
		resume_label.visible = not data.is_empty()
		if data.is_empty(): return
		resume_label.text = preload("res://ui/SavePresentation.gd").stage_name(data.summary.get("current_stage",""),get_node("/root/CampaignState"))+"\n"+data.date_string

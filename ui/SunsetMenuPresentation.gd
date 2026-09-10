extends Control
## Presentation only; MainMenu retains save, settings and scene routing.
var buttons: Array[Button] = []
var motion: Dictionary = {}
var background: TextureRect
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
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform bool reduce_motion = false;
void fragment() {
 vec2 uv = UV;
 float water = smoothstep(0.40,0.46,uv.y) * (1.0-smoothstep(0.58,0.72,uv.y));
 float right_side = smoothstep(0.28,0.44,uv.x);
 uv.x += sin(uv.y*170.0 + TIME*1.25)*0.00065*water*right_side*(reduce_motion ? 0.0 : 1.0);
 vec4 c = texture(TEXTURE,uv);
 float glow = pow(max(0.0,1.0-distance(uv,vec2(0.56,0.27))*3.0),3.0);
 c.rgb += vec3(1.0,0.39,0.10)*glow*(0.018+(reduce_motion ? 0.0 : 0.012*sin(TIME*0.65)));
 COLOR = c;
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	background.material = mat
	# Opaque UI plate replaces the labels baked into the concept illustration.
	cover = ColorRect.new()
	cover.color = Color("091018")
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
	create_tween().tween_property(self,"modulate:a",1.0,0.65)

func arrange() -> void:
	# Preserva logo e rosto nas proporções largas; recorta a borda inferior/direita.
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var art_size := background.texture.get_size()
	background.size = art_size*maxf(size.x/art_size.x,size.y/art_size.y)
	background.position = Vector2.ZERO
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

func animate(button: Button, active: bool) -> void:
	if get_node("/root/SettingsManager").reduce_motion: return
	if motion.has(button): motion[button].kill()
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion[button] = tween
	tween.tween_property(button,"scale",Vector2.ONE * (1.025 if active else 1.0),0.16)

func pulse(button: Button) -> void:
	if get_node("/root/SettingsManager").reduce_motion: return
	if motion.has(button): motion[button].kill()
	button.scale = Vector2.ONE * 0.97

func _process(_delta: float) -> void:
	if background != null:
		background.material.set_shader_parameter("reduce_motion",get_node("/root/SettingsManager").reduce_motion)
	if resume_label != null:
		var data: Dictionary = source_menu.latest_save
		resume_label.text = preload("res://ui/SavePresentation.gd").stage_name(data.summary.get("current_stage",""),get_node("/root/CampaignState"))+"\n"+data.date_string

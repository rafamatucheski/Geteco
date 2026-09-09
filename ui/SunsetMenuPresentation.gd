extends Control
## Presentation only; MainMenu retains save, settings and scene routing.
var buttons: Array[Button] = []
var motion: Dictionary = {}
var background: TextureRect
var cover: ColorRect

func install(menu: Control) -> void:
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
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
 vec2 uv = UV;
 float water = smoothstep(0.40,0.46,uv.y) * (1.0-smoothstep(0.58,0.72,uv.y));
 float right_side = smoothstep(0.28,0.44,uv.x);
 uv.x += sin(uv.y*170.0 + TIME*1.25)*0.00065*water*right_side;
 vec4 c = texture(TEXTURE,uv);
 float glow = pow(max(0.0,1.0-distance(uv,vec2(0.56,0.27))*3.0),3.0);
 c.rgb += vec3(1.0,0.39,0.10)*glow*(0.018+0.012*sin(TIME*0.65));
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
	buttons.assign([menu.btn_load_game, menu.btn_new_game, menu.btn_settings, menu.btn_quit])
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
	arrange()
	modulate.a = 0.0
	create_tween().tween_property(self,"modulate:a",1.0,0.65)

func arrange() -> void:
	cover.position = size * Vector2(0.018, 0.385)
	cover.size = size * Vector2(0.265, 0.35)
	for i in buttons.size():
		var button := buttons[i]
		button.position = size * Vector2(0.035, 0.415 + i*0.075)
		button.size = size * Vector2(0.232, 0.065)
		button.add_theme_font_size_override("font_size", maxi(15, int(size.y * 0.027)))
		button.pivot_offset = Vector2(0,button.size.y*0.5)

func animate(button: Button, active: bool) -> void:
	if motion.has(button): motion[button].kill()
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion[button] = tween
	tween.tween_property(button,"scale",Vector2.ONE * (1.025 if active else 1.0),0.16)

func pulse(button: Button) -> void:
	if motion.has(button): motion[button].kill()
	button.scale = Vector2.ONE * 0.97

extends Control
## Contextual race instruments. Native controls only; no extra render viewport.
const FONT := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
var position_label: Label
var lap_label: Label
var time_label: Label
var speed_label: Label
var state_label: Label
var message: Label
var integrity: ProgressBar
var race_card: Panel
var speed_card: Panel
var text: String = "":
	set(value):
		text = value
		if not is_instance_valid(message): return
		visible = not value.is_empty()
		message.text = value
		message.visible = visible
		race_card.hide()
		speed_card.hide()

func _ready() -> void:
	name = "MotocrossHUD"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_card = _panel(Vector2(470,94))
	race_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	race_card.offset_left = -235; race_card.offset_right = 235
	race_card.offset_top = 28; race_card.offset_bottom = 122
	position_label = _label(race_card,"",Vector2(18,11),48)
	_label(race_card,"POSIÇÃO",Vector2(20,66),12,Color("a4adb6"))
	lap_label = _label(race_card,"",Vector2(147,13),31)
	_label(race_card,"VOLTA",Vector2(149,56),13,Color("a4adb6"))
	time_label = _label(race_card,"",Vector2(280,13),31)
	_label(race_card,"TEMPO",Vector2(282,56),13,Color("a4adb6"))
	speed_card = _panel(Vector2(228,152))
	speed_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_card.offset_left = -252; speed_card.offset_right = -24
	speed_card.offset_top = -182; speed_card.offset_bottom = -30
	speed_label = _label(speed_card,"",Vector2(16,1),49)
	_label(speed_card,"km/h",Vector2(122,32),18,Color("bdc5cb"))
	# Let minimum font/theme sizes participate in layout instead of allowing
	# the integrity bar to grow over the exit action at a fixed Y coordinate.
	var details := VBoxContainer.new()
	details.position = Vector2(16,63)
	details.size.x = 195
	details.add_theme_constant_override("separation",8)
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_card.add_child(details)
	state_label = _label(details,"",Vector2.ZERO,17,Color("f3b96c"))
	integrity = ProgressBar.new()
	integrity.custom_minimum_size = Vector2(195,5)
	integrity.show_percentage = false
	integrity.add_theme_font_size_override("font_size",1)
	integrity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := StyleBoxFlat.new(); bar.bg_color = Color("e2a554")
	integrity.add_theme_stylebox_override("fill",bar)
	var back := StyleBoxFlat.new(); back.bg_color = Color("38434a")
	integrity.add_theme_stylebox_override("background",back)
	details.add_child(integrity)
	_label(details,"E  ·  SAIR DA PROVA",Vector2.ZERO,14,Color("e1e6ea"))
	message = _label(self,"",Vector2.ZERO,36)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.offset_left = -320; message.offset_right = 320
	message.offset_top = 142; message.offset_bottom = 252
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_shadow_color",Color.BLACK)
	message.add_theme_constant_override("shadow_offset_y",2)
	hide()

func present(place: int,count: int,lap: int,laps: int,seconds: float,bike) -> void:
	show(); message.hide(); race_card.show(); speed_card.show()
	position_label.text = "%d / %d"%[place,count]
	lap_label.text = "%02d / %02d"%[lap,laps]
	time_label.text = "%02d:%05.2f"%[int(seconds)/60,fmod(seconds,60)]
	speed_label.text = "%02d"%int(absf(bike.speed)*3.6)
	integrity.value = bike.health
	state_label.text = "RECUPERANDO" if bike.crash_state!="riding" else ("NO AR · %.1f s"%bike._air_time if bike._air_time>.12 else ("FREANDO" if bike._brake else ""))

func _panel(dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035,.052,.063,.91)
	style.border_color = Color("bd7b38")
	style.border_width_top = 3
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	return panel

func _label(parent: Node,caption: String,at: Vector2,size_px: int,color := Color("f0f3f4")) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",size_px)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

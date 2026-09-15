extends CanvasLayer
signal finished
var page := 0
var body: Label
var next: Button
var sound: AudioStreamPlayer
var was_paused := false

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	was_paused = get_tree().paused
	get_tree().paused = true
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.05, 0.75)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := PanelContainer.new()
	center.add_child(box)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111b20")
	style.set_content_margin_all(28)
	style.set_corner_radius_all(12)
	box.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	box.add_child(column)
	var title := Label.new()
	title.text = "MONALIZA"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("ffb565"))
	column.add_child(title)
	body = Label.new()
	body.custom_minimum_size.x = minf(480, get_viewport().get_visible_rect().size.x - 88)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 21)
	column.add_child(body)
	next = Button.new()
	column.add_child(next)
	next.pressed.connect(advance)
	sound = AudioStreamPlayer.new()
	sound.bus = &"SFX"
	sound.volume_db = -18
	sound.stream = preload("res://audio/rewards/mission_start.wav")
	add_child(sound)
	_show_page()

func _show_page() -> void:
	var en := TranslationServer.get_locale().begins_with("en")
	var messages := [
		"Monaliza is your main car. Take care of her: she'll accompany you on your journey." if en else "A Monaliza é o seu carro principal. Cuide dela: ela vai te acompanhar por aí.",
		"If she's destroyed, impounded by police while you're driving, or lost outside the playable world, recover her at Maciota's garage for $50. Your equipment is preserved." if en else "Se ela for destruída, apreendida pela polícia enquanto você dirige ou perdida fora da área do jogo, recupere-a na garagem do Maciota por $50. Seu equipamento fica preservado."
	]
	body.text = messages[page]
	next.text = ("Let's go!" if en else "Vamos nessa!") if page == messages.size() - 1 else ("Continue" if en else "Continuar")
	next.grab_focus()
	sound.play()

func advance() -> void:
	page += 1
	if page < 2:
		_show_page()
		return
	get_tree().paused = was_paused
	finished.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

extends PanelContainer
signal closed
const HONOR := preload("res://runtime/TakeshiHonor.gd")
var session
var picker: ColorPicker
var feedback: Label
var apply_button: Button

func configure(owner_session) -> void:
	session = owner_session
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -255
	offset_right = 255
	offset_top = -285
	offset_bottom = 285
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182323")
	style.set_content_margin_all(20)
	style.set_corner_radius_all(8)
	add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	add_child(box)
	var title := Label.new()
	title.text = "KATANA · SABRE DE LUZ"
	title.add_theme_font_size_override("font_size",23)
	box.add_child(title)
	picker = ColorPicker.new()
	picker.edit_alpha = false
	picker.can_add_swatches = false
	picker.sliders_visible = false
	picker.color_modes_visible = false
	picker.presets_visible = false
	picker.sampler_visible = false
	picker.add_theme_constant_override("sv_height", 200)
	picker.color = Color.html(HONOR.data(session.state.world_state).saber_color)
	box.add_child(picker)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	apply_button = Button.new()
	apply_button.custom_minimum_size.y = 42
	apply_button.pressed.connect(_apply)
	box.add_child(apply_button)
	var back := Button.new()
	back.text = "VOLTAR"
	back.custom_minimum_size.y = 38
	back.pressed.connect(func(): closed.emit(); queue_free())
	box.add_child(back)
	refresh()
	apply_button.grab_focus()

func refresh(message := "") -> void:
	var owned: bool = HONOR.data(session.state.world_state).saber_unlocked
	apply_button.text = "APLICAR COR" if owned else "TRANSFORMAR · $150000"
	apply_button.disabled = not session.state.economy.snapshot().weapons.has("katana") or (not owned and session.state.economy.balance < HONOR.SABER_PRICE)
	feedback.text = (message+"\n" if not message.is_empty() else "")+"Saldo: $%d"%session.state.economy.balance

func _apply() -> void:
	var result := HONOR.buy_saber(session.state,picker.color)
	if result.ok: session.save_game()
	refresh(result.reason)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		closed.emit()
		queue_free()

extends Control
## Caller owns modal state, pause, input locks and rebinding.

signal back_requested

const PALETTE := preload("MenuTheme.gd")
const ACTION := preload("MenuAction.gd")
const VOLUME := preload("MenuVolume.gd")

var body := VBoxContainer.new()
var title_label := Label.new()
var context_label := Label.new()
var footer := VBoxContainer.new()
var scroll := ScrollContainer.new()
var card := PanelContainer.new()
var focus_order: Array[Control] = []
var previous_focus: WeakRef

func _init() -> void:
	theme = PALETTE.create()
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(card)
	var stack := VBoxContainer.new()
	card.add_child(stack)
	title_label.theme_type_variation = "MenuTitle"
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title_label)
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	context_label.add_theme_color_override("font_color", PALETTE.MUTED)
	context_label.hide()
	stack.add_child(context_label)
	stack.add_child(HSeparator.new())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	stack.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	stack.add_child(footer)
	resized.connect(_layout)
	hide()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout()

func _layout() -> void:
	var inset := 16.0 if size.x < 700 else 32.0
	var card_size := Vector2(minf(760, size.x - inset * 2), size.y - inset * 2)
	card.position = (size - card_size) * 0.5
	card.size = card_size

func begin(title_text: String) -> void:
	if not visible:
		var focus_owner := get_viewport().gui_get_focus_owner()
		previous_focus = weakref(focus_owner) if focus_owner != null else null
	for container in [body, footer]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	focus_order.clear()
	title_label.text = title_text
	scroll.scroll_vertical = 0
	show()

func set_context(label_text: String) -> void:
	context_label.text = label_text
	context_label.visible = not label_text.is_empty()

func add_action(label_text: String, action: Callable, unavailable := false) -> Button:
	var button := ACTION.new()
	body.add_child(button)
	button.configure(label_text, action, unavailable)
	if not button.disabled: focus_order.append(button)
	return button

func add_volume(value: float, on_changed: Callable) -> HSlider:
	var row := VOLUME.new()
	body.add_child(row)
	row.configure(value, on_changed)
	focus_order.append(row.slider)
	return row.slider

func finish(back_text := "Voltar", preferred_index := 0) -> void:
	var back := ACTION.new()
	footer.add_child(back)
	back.configure(back_text, func(): back_requested.emit())
	focus_order.append(back)
	for index in focus_order.size():
		var node := focus_order[index]
		var before := focus_order[posmod(index - 1, focus_order.size())]
		var after := focus_order[(index + 1) % focus_order.size()]
		node.focus_neighbor_top = node.get_path_to(before)
		node.focus_neighbor_bottom = node.get_path_to(after)
		node.focus_previous = node.get_path_to(before)
		node.focus_next = node.get_path_to(after)
		node.focus_neighbor_left = NodePath(".")
		node.focus_neighbor_right = NodePath(".")
	focus_order[clampi(preferred_index, 0, focus_order.size() - 1)].grab_focus.call_deferred()

func dismiss() -> void:
	hide()
	if previous_focus != null:
		var prior = previous_focus.get_ref()
		if is_instance_valid(prior) and prior.is_visible_in_tree(): prior.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		back_requested.emit()

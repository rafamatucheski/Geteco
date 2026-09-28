extends Button
var board: Control
var index := -1
var item_texture: Texture2D

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed: return
	if event.button_index==MOUSE_BUTTON_RIGHT:
		accept_event(); board.adapter.ui.quick_use(board.container_id,index)
	elif event.button_index==MOUSE_BUTTON_LEFT and event.shift_pressed:
		accept_event(); board.adapter.ui.quick_transfer(board.container_id,index)

func _get_drag_data(_at: Vector2) -> Variant:
	if not board.adapter.can_edit(board.container_id): return null
	var data := {"container":board.container_id,"index":index,"owner":board.adapter}
	var preview := TextureRect.new()
	preview.texture=item_texture; preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size=size
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	return data

func _can_drop_data(at: Vector2,data: Variant) -> bool:
	return board._can_drop_data(position+at,data)

func _drop_data(at: Vector2,data: Variant) -> void:
	board._drop_data(position+at,data)

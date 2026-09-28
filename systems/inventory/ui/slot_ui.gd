class_name SlotUI
extends PanelContainer

@onready var icon: TextureRect = $Margin/Icon
@onready var amount_label: Label = $AmountLabel

var slot_data: SlotData
var is_equipment_slot: bool = false
var accepted_item_types: Array[ItemData.ItemType] = []

# Actually, the easiest way to swap styles is to use add_theme_stylebox_override.

func _ready() -> void:
	update_visuals()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func set_slot_data(data: SlotData) -> void:
	slot_data = data
	update_visuals()

func update_visuals() -> void:
	if not is_node_ready(): return
	if slot_data == null or slot_data.item_data == null:
		icon.texture = null
		amount_label.text = ""
		return
		
	icon.texture = slot_data.item_data.icon
	
	if slot_data.amount > 1:
		amount_label.text = str(slot_data.amount)
	else:
		amount_label.text = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Tenta consumir o item
			if slot_data != null and slot_data.item_data != null:
				var ui = get_tree().get_first_node_in_group("inventory_ui")
				if ui and ui.player_manager:
					ui.player_manager.consume_item(slot_data)

# --- Efeitos de Hover (UX) ---
func _on_mouse_entered() -> void:
	# Efeito visual de hover simples mexendo na cor do painel
	modulate = Color(1.2, 1.2, 1.2, 1.0)
	# Opcional: Adicionar som de click/hover aqui

func _on_mouse_exited() -> void:
	modulate = Color(1.0, 1.0, 1.0, 1.0)

# --- Drag and Drop (Arrastar Itens) ---
func _get_drag_data(at_position: Vector2) -> Variant:
	if slot_data == null or slot_data.item_data == null:
		return null
		
	# Criar um visual para o mouse carregar
	var drag_preview = TextureRect.new()
	drag_preview.texture = slot_data.item_data.icon
	drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	drag_preview.custom_minimum_size = Vector2(60, 60)
	
	var control = Control.new()
	drag_preview.position = -0.5 * drag_preview.custom_minimum_size
	control.add_child(drag_preview)
	set_drag_preview(control)
	
	# Retorna o próprio slot como dado de arrasto
	return self

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data is SlotUI and data != self:
		# Se for um slot de equipamento (ex: Coldre), verifica se o tipo bate
		if is_equipment_slot and data.slot_data.item_data != null:
			if not data.slot_data.item_data.item_type in accepted_item_types:
				return false
		return true
	return false

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var from_slot_ui = data as SlotUI
	
	var temp_data = slot_data.item_data
	var temp_amount = slot_data.amount
	
	# Passa do antigo para esse
	slot_data.item_data = from_slot_ui.slot_data.item_data
	slot_data.amount = from_slot_ui.slot_data.amount
	
	# Passa desse para o antigo (Swap)
	from_slot_ui.slot_data.item_data = temp_data
	from_slot_ui.slot_data.amount = temp_amount
	
	# Atualiza a UI de ambos
	update_visuals()
	from_slot_ui.update_visuals()
	
	# (Opcional) Tocar som de equipar/dropar

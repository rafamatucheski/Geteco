class_name InventoryUI
extends Control

const SLOT_UI_SCENE = preload("res://systems/inventory/ui/slot_ui.tscn")

@onready var grid: GridContainer = $MainPanel/Margin/HBox/Right_Container/Grid
@onready var pockets_container: HBoxContainer = $MainPanel/Margin/HBox/Left_Player/Pockets
@onready var weapons_container: VBoxContainer = $MainPanel/Margin/HBox/Left_Player/WeaponSlots
@onready var right_label: Label = $MainPanel/Margin/HBox/Right_Container/Title

var player_manager: InventoryManager
var right_side_inventory: InventoryData

func _ready() -> void:
	add_to_group("inventory_ui") # Permite que baús e porta-malas achem essa UI
	hide()

## Conecta a UI ao jogador (Chame isso quando a cena principal carregar)
func setup_player(manager: InventoryManager) -> void:
	player_manager = manager
	
	# Limpa placeholders
	for c in weapons_container.get_children(): c.queue_free()
	for c in pockets_container.get_children(): c.queue_free()
	
	# Cria Slots de Arma
	var weapon_titles = ["Primária (Costas)", "Secundária (Coldre)", "Branca"]
	var weapon_types = [ItemData.ItemType.WEAPON_PRIMARY, ItemData.ItemType.WEAPON_SECONDARY, ItemData.ItemType.WEAPON_MELEE]
	
	for i in range(3):
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = weapon_titles[i]
		label.custom_minimum_size = Vector2(150, 0)
		
		var slot_ui = SLOT_UI_SCENE.instantiate() as SlotUI
		slot_ui.is_equipment_slot = true
		slot_ui.accepted_item_types = [weapon_types[i]]
		slot_ui.set_slot_data(player_manager.equipment.slots[i])
		
		hbox.add_child(label)
		hbox.add_child(slot_ui)
		weapons_container.add_child(hbox)
		
	# Cria Slots de Bolso
	for i in range(player_manager.pocket_size):
		var slot_ui = SLOT_UI_SCENE.instantiate() as SlotUI
		slot_ui.is_equipment_slot = true
		slot_ui.accepted_item_types = [ItemData.ItemType.CONSUMABLE, ItemData.ItemType.MATERIAL, ItemData.ItemType.QUEST]
		slot_ui.set_slot_data(player_manager.pockets.slots[i])
		pockets_container.add_child(slot_ui)
		
	# Inscreve-se nos eventos da mochila
	player_manager.backpack_equipped.connect(_on_backpack_changed)
	player_manager.backpack_dropped.connect(_on_backpack_changed)
	
	_on_backpack_changed()

func _on_backpack_changed(data: ItemData = null) -> void:
	# Se a tela direita não estiver travada em um Baú (Monaliza), mostra a mochila
	if right_label.text != "MONALIZA" and right_label.text != "PORTA-MALAS":
		if player_manager.backpack_inventory != null:
			set_right_inventory(player_manager.backpack_inventory, "MOCHILA DE COSTAS")
		else:
			set_right_inventory(null, "NENHUMA MOCHILA EQUIPADA")

## Chamado pelos baús do mundo
func open_stash(manager: InventoryManager, stash_inventory: InventoryData, stash_name: String) -> void:
	if player_manager == null:
		setup_player(manager)
	
	set_right_inventory(stash_inventory, stash_name)
	show_ui()

func set_right_inventory(inventory_data: InventoryData, container_name: String) -> void:
	right_side_inventory = inventory_data
	right_label.text = container_name
	
	for child in grid.get_children():
		child.queue_free()
		
	if right_side_inventory == null:
		return
		
	for slot_data in right_side_inventory.slots:
		var slot_ui = SLOT_UI_SCENE.instantiate() as SlotUI
		grid.add_child(slot_ui)
		slot_ui.set_slot_data(slot_data)
		
	if not right_side_inventory.inventory_updated.is_connected(update_right_slots):
		right_side_inventory.inventory_updated.connect(update_right_slots)

func update_right_slots() -> void:
	var slots_ui = grid.get_children()
	for i in range(slots_ui.size()):
		if i < right_side_inventory.slots.size():
			slots_ui[i].update_visuals()

func show_ui() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func hide_ui() -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	
	# Quando fecha o inventário, garante que a tela direita volte para a Mochila
	# (caso ele estivesse olhando o porta-malas)
	_on_backpack_changed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_inventory") or event.is_action_pressed("inventory"):
		if visible:
			hide_ui()
		else:
			show_ui()

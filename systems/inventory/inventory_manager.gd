class_name InventoryManager
extends Node

## Gerenciador Central de Inventário
## Deve ser colocado como filho do Node do Jogador (Player)

signal backpack_equipped(backpack_data: ItemData)
signal backpack_dropped()
signal equipment_changed(slot_index: int, item: ItemData)

@export var pocket_size: int = 2

# Inventários fixos do jogador
var equipment: InventoryData
var pockets: InventoryData

# Mochila atualmente equipada
var current_backpack_item: ItemData
var backpack_inventory: InventoryData

func _ready() -> void:
	_initialize_base_inventories()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("drop_bag"):
		if current_backpack_item != null:
			print("Dropando mochila taticamente!")
			# Pega os dados antes de limpar
			var dropped_item = current_backpack_item
			var dropped_inv = drop_backpack()
			
			# Aqui emitimos um sinal ou instanciamos o RigidBody3D no mundo
			# Como o InventoryManager está no Player, ele pode criar a mochila no mundo:
			var backpack_scene = load("res://systems/inventory/backpack_pickup.tscn")
			if backpack_scene:
				var drop = backpack_scene.instantiate() as BackpackPickup
				drop.backpack_item = dropped_item
				drop.stored_inventory = dropped_inv
				# Joga a mochila na cena (na mesma posição do player)
				get_tree().current_scene.add_child(drop)
				drop.global_position = get_parent().global_position + Vector3(0, 1, -1) # Na frente do player
			
func _initialize_base_inventories() -> void:
	# Cria os bolsos (Acesso Rápido)
	pockets = InventoryData.new()
	for i in range(pocket_size):
		pockets.slots.append(SlotData.new())
		
	# Cria os Equipamentos (3 armas: Primária, Secundária, Branca)
	equipment = InventoryData.new()
	for i in range(3):
		equipment.slots.append(SlotData.new())
		# Conecta sinal para saber quando a arma muda (para atualizar modelo 3D)
		equipment.slots[i].changed.connect(func(): equipment_changed.emit(i, equipment.slots[i].item_data))

## Tenta adicionar um item solto (ex: munição, maçã)
func pickup_item(item: ItemData, amount: int = 1) -> int:
	var left = amount
	
	# 1. Tenta colocar nos bolsos primeiro (acesso rápido)
	left = pockets.add_item(item, left)
	if left == 0: return 0
	
	# 2. Se não couber e tiver mochila, tenta na mochila
	if backpack_inventory != null:
		left = backpack_inventory.add_item(item, left)
		
	return left

## Equipa uma mochila do chão
func equip_backpack(backpack_item: ItemData, loaded_inventory: InventoryData = null) -> bool:
	if current_backpack_item != null:
		return false # Já tem mochila
		
	current_backpack_item = backpack_item
	
	if loaded_inventory != null:
		backpack_inventory = loaded_inventory
	else:
		backpack_inventory = InventoryData.new()
		for i in range(backpack_item.backpack_capacity):
			backpack_inventory.slots.append(SlotData.new())
			
	backpack_equipped.emit(current_backpack_item)
	return true

## Joga a mochila no chão (Drop)
func drop_backpack() -> InventoryData:
	if current_backpack_item == null:
		return null
		
	var dropped_inventory = backpack_inventory
	
	# Limpa as referências
	current_backpack_item = null
	backpack_inventory = null
	
	backpack_dropped.emit()
	return dropped_inventory

## Verifica se o jogador está segurando uma mala de mão (Penalidade de Combate)
func has_combat_penalty() -> bool:
	if current_backpack_item != null:
		return current_backpack_item.is_hand_bag
	return false

## Consome um item (ex: comer maçã, usar bandagem) a partir de um Slot
func consume_item(slot: SlotData) -> bool:
	if slot == null or slot.item_data == null: return false
	
	if slot.item_data.item_type == ItemData.ItemType.CONSUMABLE:
		print("Usou consumível: ", slot.item_data.display_name)
		# AQUI VOCÊ PODE EMITIR UM SINAL PARA CURAR O PLAYER (ex: player.heal(20))
		
		slot.amount -= 1
		return true
		
	return false


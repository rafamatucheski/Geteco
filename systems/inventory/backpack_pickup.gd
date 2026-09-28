class_name BackpackPickup
extends RigidBody3D

@export var backpack_item: ItemData
@export var stored_inventory: InventoryData

func _ready() -> void:
	# Configurações básicas físicas para o drop
	collision_layer = 4 # Layer de itens/interagíveis
	collision_mask = 1 # Chão/Parede
	
	if stored_inventory == null and backpack_item != null:
		stored_inventory = InventoryData.new()
		for i in range(backpack_item.backpack_capacity):
			stored_inventory.slots.append(SlotData.new())

## Função para ser chamada quando o jogador interage
func interact(player_inventory_manager: InventoryManager) -> void:
	var success = player_inventory_manager.equip_backpack(backpack_item, stored_inventory)
	if success:
		queue_free() # Some do chão porque o jogador vestiu
	else:
		print("O jogador já tem uma mochila equipada! Precisa dropar a atual primeiro.")

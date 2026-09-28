class_name PlayerInteractor
extends RayCast3D

## Coloque esse script em um RayCast3D na câmera do Jogador
## Habilite-o para detectar apenas as collision_layers corretas (ex: Layer 4)

@export var inventory_manager: InventoryManager
@export var interact_action: String = "interact" # Mapeie no InputMap (Ex: tecla 'E')

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(interact_action):
		if is_colliding():
			var target = get_collider()
			
			# Se for uma Mochila no chão
			if target is BackpackPickup:
				target.interact(inventory_manager)
				
			# Se for a Monaliza ou um Baú
			elif target is StashContainer:
				target.interact(inventory_manager)
				
			# Se for um item solto (ex: maçã no chão, munição)
			elif target.has_method("pickup_loose_item"):
				var item_data = target.pickup_loose_item()
				inventory_manager.pickup_item(item_data)
				target.queue_free()

class_name StashContainer
extends Node3D

## Componente para Baús, Porta-malas (Monaliza) e Mochilas no chão

@export var stash_name: String = "Armazenamento"
@export var default_capacity: int = 24
@export var inventory_data: InventoryData

func _ready() -> void:
	if inventory_data == null:
		inventory_data = InventoryData.new()
		for i in range(default_capacity):
			inventory_data.slots.append(SlotData.new())

## Chamado pelo Player quando ele interage (aperta E)
func interact(player_inventory_manager: InventoryManager) -> void:
	# Dispara um sinal ou chama um Autoload (ex: GlobalUI) para abrir a interface
	# Como não temos um Autoload ainda, vamos emitir um sinal global ou delegar
	var ui = get_tree().get_first_node_in_group("inventory_ui")
	if ui and ui.has_method("open_stash"):
		ui.open_stash(player_inventory_manager, inventory_data, stash_name)

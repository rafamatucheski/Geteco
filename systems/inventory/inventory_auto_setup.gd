class_name InventoryAutoSetup
extends Node

## Auto-configurador. Você pode jogar esse node em qualquer lugar (ou num Autoload)
## Ele mapeia as teclas automaticamente caso você não tenha feito ainda.

func _ready() -> void:
	_setup_input("ui_inventory", KEY_Q)
	_setup_input("interact", KEY_E)
	_setup_input("drop_bag", KEY_G)

func _setup_input(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var event = InputEventKey.new()
		event.keycode = keycode
		InputMap.action_add_event(action_name, event)
		print("Configurou tecla automática para: ", action_name)

class_name InventoryData
extends Resource

signal inventory_updated

## Define os slots do inventário. Cada elemento é um dicionário ou um outro Resource de Slot.
## Para simplificar agora, faremos um array de recursos `SlotData`.
@export var slots: Array[SlotData] = []

## Tenta adicionar um item ao inventário. Retorna o que sobrar (se não couber tudo).
func add_item(item: ItemData, amount: int = 1) -> int:
	# 1. Tenta colocar em um slot que já tem esse item e não está cheio
	for slot in slots:
		if slot.item_data == item and slot.amount < item.max_stack:
			var available_space = item.max_stack - slot.amount
			if amount <= available_space:
				slot.amount += amount
				inventory_updated.emit()
				return 0
			else:
				slot.amount += available_space
				amount -= available_space
				
	# 2. Tenta encontrar um slot vazio
	for slot in slots:
		if slot.item_data == null:
			slot.item_data = item
			if amount <= item.max_stack:
				slot.amount = amount
				inventory_updated.emit()
				return 0
			else:
				slot.amount = item.max_stack
				amount -= item.max_stack
				
	# Retorna a quantidade que não coube
	inventory_updated.emit()
	return amount

class_name SlotData
extends Resource

@export var item_data: ItemData:
	set(value):
		item_data = value
		changed.emit()

@export var amount: int = 0:
	set(value):
		amount = value
		if amount <= 0:
			item_data = null
			amount = 0
		changed.emit()

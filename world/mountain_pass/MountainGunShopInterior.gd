extends "res://world/harbor/interiors/HarborAmmunationInterior.gd"
## Mountain branch keeps the catalog and owns a separate sales-floor layout.
func _init() -> void:
	super._init()
	mountain_branch = true
	interior_id = &"mountain_gunshop"

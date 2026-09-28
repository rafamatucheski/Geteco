class_name PlayerWeaponModels
extends Node3D

## Coloque esse script no Skeleton3D ou no Mesh do Jogador
## Ele gerencia a visibilidade das armas presas ao corpo

@export var inventory_manager: InventoryManager

@export_category("3D Weapon Nodes")
@export var holster_mesh: Node3D
@export var pistol_in_holster_mesh: Node3D
@export var shotgun_on_back_mesh: Node3D
@export var melee_on_belt_mesh: Node3D

func _ready() -> void:
	# Esconde tudo no início
	if holster_mesh: holster_mesh.hide()
	if pistol_in_holster_mesh: pistol_in_holster_mesh.hide()
	if shotgun_on_back_mesh: shotgun_on_back_mesh.hide()
	if melee_on_belt_mesh: melee_on_belt_mesh.hide()
	
	if inventory_manager:
		inventory_manager.equipment_changed.connect(_on_equipment_changed)

func _on_equipment_changed(slot_index: int, item: ItemData) -> void:
	match slot_index:
		0: # Arma Primária (Costas)
			if shotgun_on_back_mesh:
				shotgun_on_back_mesh.visible = (item != null)
		1: # Arma Secundária (Coldre)
			if holster_mesh:
				holster_mesh.visible = (item != null) # Revela o coldre
			if pistol_in_holster_mesh:
				pistol_in_holster_mesh.visible = (item != null)
		2: # Arma Branca
			if melee_on_belt_mesh:
				melee_on_belt_mesh.visible = (item != null)

class_name ItemData
extends Resource

## Define o tipo do item para o sistema saber onde ele pode ser equipado
enum ItemType {
	CONSUMABLE,       ## Cura, Comida, Bebida
	WEAPON_PRIMARY,   ## Espingardas, Fuzis (Slot Costas)
	WEAPON_SECONDARY, ## Pistolas (Slot Coldre)
	WEAPON_MELEE,     ## Facas, Soqueiras
	BACKPACK,         ## Mochilas (Costas ou Mão)
	MATERIAL,         ## Sucata, dinheiro, etc
	QUEST             ## Itens de missão (ex: os 10 perdidos)
}

@export_category("Basic Info")
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var item_type: ItemType = ItemType.MATERIAL

@export_category("Visuals")
## Ícone 2D para a interface (UI)
@export var icon: Texture2D
## Modelo 3D que vai aparecer quando o item for dropado no chão ou inspecionado
@export var model_3d: PackedScene 

@export_category("Inventory Rules")
## Quantos desse item cabem no mesmo espaço (Slot)? (Ex: Armas = 1, Balas = 30)
@export var max_stack: int = 1
## Se for uma mochila, quantos slots ela adiciona ao jogador? (Ex: 12 ou 24)
@export var backpack_capacity: int = 0
## Se for uma mochila, ela é carregada na mão? (Gera penalidade de combate)
@export var is_hand_bag: bool = false

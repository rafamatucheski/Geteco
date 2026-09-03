class_name ClothingStoreInterior
extends Node2D

@onready var shop_interior: ShopInterior = $ShopInterior
@onready var fitting_area: Area2D = $FittingArea

func _ready() -> void:
	if shop_interior:
		shop_interior.shop_name = "BOUTIQUE DANTE"
		shop_interior.accent_color = Color("9b59b6")
	
	if fitting_area:
		fitting_area.body_entered.connect(_on_fitting_area_entered)

func _on_fitting_area_entered(body: Node2D) -> void:
	if body.is_in_group("player") and body.has_method("open_clothing_store"):
		body.open_clothing_store()

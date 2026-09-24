extends Node
func _ready() -> void:
	_bind_shop.call_deferred(get_parent().get_node("District/NorthFrontage3"),Vector2(0,85),false,0)
func _bind_shop(building: Node2D, door_offset: Vector2, winter: bool, index: int) -> void:
	building.business_name = "UNION"
	building.self_modulate.a = 0.0
	var old_solid := building.get_node_or_null("BuildingSolid") as StaticBody2D
	if is_instance_valid(old_solid): old_solid.queue_free()
	var entrance := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	entrance.set_script(preload("res://world/harbor/HarborEntrance.gd"))
	entrance.name="ClothingEntrance"
	entrance.role="clothing"
	entrance.display_name="UNION"
	entrance.position=door_offset
	entrance.door_width=48
	entrance.door_height=38
	entrance.interior_available=false
	entrance.show_entrance_marker=false
	entrance.show_interaction_prompt=false
	entrance.handle_input_locally=false
	entrance.z_index=7
	building.add_child(entrance)
	var facade := preload("res://world/harbor/UnionClothingFacade.gd").new()
	facade.name="UnionCutawayFacade"
	building.add_child(facade)
	entrance.add_to_group("clothing_shop")
	var manager := get_parent().get_node("Interiors")
	var room := preload("res://world/harbor/interiors/ClothingRoomStandard.gd").new()
	room.name="ClothingRoom%d"%index
	room.winter_stock=winter
	room.inline_mode=true
	room.inline_model_script=preload("res://world/harbor/interiors/UnionInlineArt3D.gd")
	room.inline_bounds=Rect2(-3.95,-1.97,7.9,4.13)
	room.inline_cash_floor=Vector2(1.7,.75)
	room.inline_region=&"harbor"
	room.position=Vector2(30000+index*6000,20000)
	manager.get_node("InteriorSpaces").add_child(room)
	var path := String(get_parent().get_path_to(entrance))
	var id := StringName("harbor/"+path)
	entrance.destination_id=id
	entrance.get_node("Facade").hide()
	room.attach_inline_facade(facade,entrance,manager)
	room.global_position=entrance.global_position-room.project_floor(Vector2(0,2.12))
	facade.bind_inline(entrance,room)
	room.modal_opened.connect(manager._on_dialogue_opened)
	room.modal_closed.connect(manager._on_dialogue_closed)

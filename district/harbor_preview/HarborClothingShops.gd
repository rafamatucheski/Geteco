extends Node
var mountain_bound := false
func _ready() -> void:
	_bind_shop.call_deferred(get_parent().get_node("District/NorthFrontage3"),Vector2(0,85),false,0)
func _process(_delta: float) -> void:
	if mountain_bound: return
	var mountain := get_parent().get_node_or_null("MountainRegion")
	if not mountain: return
	var store := mountain.find_child("SnowOutfitters",true,false)
	if not store: return
	mountain_bound=true
	_bind_shop(store,Vector2(0,35),true,1)
func _bind_shop(building: Node2D, door_offset: Vector2, winter: bool, index: int) -> void:
	var entrance := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	entrance.set_script(preload("res://district/harbor_preview/HarborEntrance.gd"))
	entrance.name="ClothingEntrance"
	entrance.role="clothing"
	entrance.position=door_offset
	entrance.door_width=48
	entrance.interior_available=true
	building.add_child(entrance)
	entrance.add_to_group("clothing_shop")
	var manager := get_parent().get_node("Interiors")
	var room := preload("res://district/harbor_preview/interiors/ClothingRoom3D.gd").new()
	room.name="ClothingRoom%d"%index
	room.winter_stock=winter
	room.position=Vector2(30000+index*6000,20000)
	manager.get_node("InteriorSpaces").add_child(room)
	var path := String(get_parent().get_path_to(entrance))
	var id := StringName("harbor/"+path)
	manager._door_configs[path]={"interior":room,"spawn":room.spawn_point,"id":id}
	entrance.destination_id=id
	entrance.destination_requested.connect(manager._on_exterior_destination_requested.bind(room,room.spawn_point))
	manager._bind_exit_door(room.exit_door,id,room)
	room.modal_opened.connect(manager._on_dialogue_opened)
	room.modal_closed.connect(manager._on_dialogue_closed)

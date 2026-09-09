extends Node
func _ready() -> void: _build.call_deferred()
func _build() -> void:
	_bind_ammunation()
	for index in 2:
		var building: Node2D=get_parent().get_node("District/NorthFrontage%d" % (0 if index==0 else 4))
		var door := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
		door.set_script(preload("res://district/harbor_preview/HarborEntrance.gd"))
		door.name="RobberyEntrance"
		door.role="bank" if index==0 else "fuel"
		door.position=Vector2(0,85)
		door.door_width=48
		door.interior_available=true
		building.add_child(door)
		door.add_to_group("bank_entrance" if index==0 else "fuel_entrance")
		if index==1:
			for x in [-70,70]:
				var pump := Polygon2D.new()
				pump.position=Vector2(x,140)
				pump.polygon=PackedVector2Array([Vector2(-13,-17),Vector2(13,-17),Vector2(13,17),Vector2(-13,17)])
				pump.color=Color("b65c43")
				building.add_child(pump)
				var display := Polygon2D.new()
				display.polygon=PackedVector2Array([Vector2(-9,-12),Vector2(9,-12),Vector2(9,-2),Vector2(-9,-2)])
				display.color=Color("b3c5ba")
				pump.add_child(display)
		var manager := get_parent().get_node("Interiors")
		var room := preload("res://district/harbor_preview/interiors/RobberyRoom3D.gd").new()
		room.name="BankInterior" if index==0 else "FuelInterior"
		room.is_bank=index==0
		room.position=Vector2(42000+index*6000,20000)
		room.entrance=door
		manager.get_node("InteriorSpaces").add_child(room)
		var path := String(get_parent().get_path_to(door))
		var id := StringName("harbor/"+path)
		manager._door_configs[path]={"interior":room,"spawn":room.spawn_point,"id":id}
		door.destination_id=id
		door.destination_requested.connect(manager._on_exterior_destination_requested.bind(room,room.spawn_point))
		manager._bind_exit_door(room.exit_door,id,room)
func _bind_ammunation() -> void:
	var building=get_parent().get_node("District/NorthFrontage2")
	building.business_name="AMMU-NATION / ARMAS"
	building.queue_redraw()
	var door=preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	door.set_script(preload("res://district/harbor_preview/HarborEntrance.gd"))
	door.role="ammunation"
	door.name="AmmunationEntrance"
	door.position=Vector2(0,85)
	door.interior_available=true
	building.add_child(door)
	door.add_to_group("weapon_shop")
	var manager=get_parent().get_node("Interiors")
	var room=manager.ammunation_interior
	var path=String(get_parent().get_path_to(door))
	var id=StringName("harbor/"+path)
	manager._door_configs[path]={"interior":room,"spawn":room.spawn_point,"id":id}
	door.destination_id=id
	door.destination_requested.connect(manager._on_exterior_destination_requested.bind(room,room.spawn_point))
	manager._bind_exit_door(room.exit_door,id,room)


extends Node
func _ready() -> void: _build.call_deferred()
func _build() -> void:
	_bind_ammunation()
	for index in 2:
		var building: Node2D=get_parent().get_node("District/NorthFrontage%d" % (0 if index==0 else 4))
		var door := preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
		door.set_script(preload("res://world/harbor/HarborEntrance.gd"))
		door.name="RobberyEntrance"
		door.role="bank" if index==0 else "fuel"
		door.position=Vector2(0,85)
		door.door_width=48
		door.interior_available=false
		if index <= 1:
			door.show_entrance_marker=false
			door.show_interaction_prompt=false
			door.handle_input_locally=false
		if index == 0:
			door.accent_color = Color("a49666")
		building.add_child(door)
		door.add_to_group("bank_entrance" if index==0 else "fuel_entrance")
		if index==1:
			for x in [-70,70]:
				var pump := Polygon2D.new()
				pump.position=building.to_global(Vector2(x,140))
				pump.polygon=PackedVector2Array([Vector2(-13,-17),Vector2(13,-17),Vector2(13,17),Vector2(-13,17)])
				pump.color=Color("b65c43")
				building.get_parent().add_child(pump)
				var display := Polygon2D.new()
				display.polygon=PackedVector2Array([Vector2(-9,-12),Vector2(9,-12),Vector2(9,-2),Vector2(-9,-2)])
				display.color=Color("b3c5ba")
				pump.add_child(display)
		var manager := get_parent().get_node("Interiors")
		var room := preload("res://world/harbor/interiors/RobberyRoom3D.gd").new()
		room.name="BankInterior" if index==0 else "FuelInterior"
		room.is_bank=index==0
		room.inline_mode=true
		room.position=Vector2(42000+index*6000,20000)
		room.entrance=door
		manager.get_node("InteriorSpaces").add_child(room)
		var path := String(get_parent().get_path_to(door))
		var id := StringName("harbor/"+path)
		door.destination_id=id
		if index == 0:
			var old_bank_solid := building.get_node_or_null("BuildingSolid")
			if old_bank_solid: old_bank_solid.queue_free()
			room.attach_inline_entrance(door)
		else:
			building.self_modulate.a = 0.0
			var old_solid := building.get_node_or_null("BuildingSolid")
			if old_solid: old_solid.queue_free()
			door.get_node("Facade").hide()
			door.self_modulate.a = 0.0
			room.attach_inline_entrance(door)

func _bind_ammunation() -> void:
	var building=get_parent().get_node("District/NorthFrontage2")
	building.business_name="AMMU-NATION"
	building.queue_redraw()
	var door=preload("res://scripts/entrances/BuildingEntrance.tscn").instantiate()
	door.set_script(preload("res://world/harbor/HarborEntrance.gd"))
	door.role="ammunation"
	door.name="AmmunationEntrance"
	door.position=Vector2(0,85)
	door.interior_available=true
	door.show_entrance_marker=false
	building.add_child(door)
	door.add_to_group("weapon_shop")
	# All branches use the same model and projected physical footprint.
	building.self_modulate.a = 0.0
	var old_solid = building.get_node_or_null("BuildingSolid")
	if old_solid: old_solid.queue_free()
	var facade = preload("res://guns/ammunation/AmmunationBranchView.gd").new()
	facade.name = "AmmunationBranchFacade"
	building.add_child(facade)
	facade.build_view(preload("res://guns/ammunation/AmmunationFacade3D.gd"),12.0,25.0,Vector3(0,1.8,0))
	facade.position = door.position-facade.project_floor(Vector2(0,2.9))
	door.get_node("Facade").hide()
	door.self_modulate.a = 0.0
	var manager=get_parent().get_node("Interiors")
	var room=manager.ammunation_interior
	var path=String(get_parent().get_path_to(door))
	var id=StringName("harbor/"+path)
	door.destination_id=id
	facade.bind_entrance(door,room)

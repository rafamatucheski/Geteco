extends "res://tests/test_salvage_geometry.gd"
const MARKER_REVIEW := "D:/geteco/artifacts/neco-marker-0910/"

func shot(label: String) -> void:
	if label!="01_patio" or not captures: return
	var car: Node2D=yard.delivery_car()
	var old_player:=player.global_position
	car.set_physics_process(false)
	player.global_position=car.global_position+Vector2(58,10)
	yard._update_bay_feedback()
	await capture_marker("parked")
	car.is_driven_by_player=true
	player.hide()
	yard._update_bay_feedback()
	await capture_marker("exit_key")
	car.is_driven_by_player=false
	player.show()
	car.set_physics_process(true)
	car.global_position=yard.global_position+Vector2(0,400)
	player.global_position=yard.global_position+Vector2(0,300)
	yard._update_bay_feedback()
	await capture_marker("empty_bay")
	car.global_position=yard.to_global(yard.dock)
	player.global_position=old_player
	yard._update_bay_feedback()

func capture_marker(label: String) -> void:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(MARKER_REVIEW+label+".png")

func audit_access() -> void:
	await super.audit_access()
	var factory:=load("res://emergency/ModernTrafficFactory.gd")
	var car: Node2D=factory.spawn_parked_vehicle(world,"DirectBayDelivery",yard.to_global(yard.dock),PI*.5,"union_sedan",0)
	player.global_position=car.global_position+Vector2(58,10)
	for i in 4: await physics_frame
	check(player.global_position.distance_to(yard.npc.global_position)>90,"Direct delivery works away from NPC interaction radius")
	var balance: int=player.money
	var event:=InputEventKey.new()
	event.physical_keycode=KEY_E
	event.keycode=KEY_E
	event.pressed=true
	Input.parse_input_event(event)
	for i in 5: await process_frame
	check(yard._processing_car==car and not car.is_driven_by_player,"Bay interaction delivers instead of boarding the car")
	check(player.money==balance,"Direct delivery still pays only after crushing")
	event=InputEventKey.new()
	event.physical_keycode=KEY_E
	event.keycode=KEY_E
	event.pressed=false
	Input.parse_input_event(event)
	while yard.art.animating: await process_frame
	check(player.money>balance and not player.is_in_dialogue,"Direct delivery pays and restores controls")

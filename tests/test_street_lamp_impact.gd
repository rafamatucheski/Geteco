extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var lamp=load("res://StreetLamp.gd").new()
	root.add_child(lamp)
	lamp.set_lit(true)
	assert(lamp.model is Node3D and lamp.view is SubViewport)
	var intact_parts: int = lamp.model.get_child_count()
	var neighbour=load("res://StreetLamp.gd").new()
	neighbour.position=Vector2(300,0)
	root.add_child(neighbour)
	lamp.receive_vehicle_impact(25,Vector2.RIGHT)
	assert(not lamp.broken,"Minor impact does not break lamp")
	assert(lamp.model.get_child_count()==intact_parts,"Impact preserves the complete lamp model")
	await create_timer(.8).timeout
	assert(lamp.model.rotation.length()<.01,"Pole settles after minor impact")
	var car:=CharacterBody2D.new()
	car.position=Vector2(-35,0)
	car.collision_layer=2
	car.collision_mask=1
	var col:=CollisionShape2D.new()
	col.shape=CircleShape2D.new()
	col.shape.radius=10
	car.add_child(col)
	root.add_child(car)
	preload("res://VehicleMotionSafety.gd").configure(car)
	for i in 40:
		await physics_frame
		car.velocity=Vector2(40,0)
		preload("res://VehicleMotionSafety.gd").move(car)
	assert(lamp.broken,"Real moving vehicle knocks pole down")
	assert(not lamp.lamp_light.visible and lamp.collision_layer==0)
	lamp.set_lit(true)
	assert(not lamp.lamp_light.visible,"Night cycle cannot relight a broken pole")
	await create_timer(.8).timeout
	assert(lamp.model.quaternion.get_angle()>1.4)
	assert(lamp.z_index<8 and not lamp._occlusion.monitoring and not lamp._occlusion.overlay.visible,"Fallen hardware rests below cars without standing occlusion")
	assert(not neighbour.broken and neighbour.model.quaternion.is_equal_approx(Quaternion.IDENTITY),"Falling cannot rotate another lamp sharing the intact cache")
	lamp.restore_world_prop()
	await physics_frame
	assert(lamp.z_index==8 and lamp._occlusion.monitoring and lamp.collision_layer==1,"Repair restores upright depth and physical base")
	lamp.receive_vehicle_impact(80,Vector2.LEFT)
	await create_timer(.2).timeout
	lamp.restore_world_prop()
	await create_timer(.8).timeout
	assert(not lamp.broken and lamp.z_index==8 and lamp._occlusion.monitoring,"Repair cancels a pending fall completion")
	# Authored overlaps must be corrected and stay corrected after world renewal.
	neighbour.position = lamp.position
	var lighting = load("res://world/shared/roads/RoadLighting.gd").new()
	root.add_child(lighting)
	lighting._clear_authored_poles()
	assert(lamp.global_position.distance_to(neighbour.global_position) >= 40.0, "Authored duplicate poles are separated")
	var renewal = root.get_node("WorldRenewal")
	assert(renewal.entries[lamp.get_instance_id()].home.origin == lamp.global_position, "Renewal keeps the cleared foundation")
	lighting.queue_free()
	lamp.queue_free()
	neighbour.queue_free()
	car.queue_free()
	await process_frame
	print("STREET_LAMP_IMPACT PASS")
	quit()

extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var lamp=load("res://StreetLamp.gd").new()
	root.add_child(lamp)
	lamp.set_lit(true)
	assert(lamp.model is Node3D and lamp.view is SubViewport)
	lamp.receive_vehicle_impact(65,Vector2.RIGHT)
	assert(not lamp.broken,"Minor impact does not break lamp")
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
	for i in 20:
		await physics_frame
		car.velocity=Vector2(250,0)
		preload("res://VehicleMotionSafety.gd").move(car)
	assert(lamp.broken,"Real moving vehicle knocks pole down")
	assert(not lamp.lamp_light.visible and lamp.collision_layer==0)
	lamp.set_lit(true)
	assert(not lamp.lamp_light.visible,"Night cycle cannot relight a broken pole")
	await create_timer(.8).timeout
	assert(lamp.model.quaternion.get_angle()>1.4)
	lamp.queue_free()
	car.queue_free()
	await process_frame
	print("STREET_LAMP_IMPACT PASS")
	quit()

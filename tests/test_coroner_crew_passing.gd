extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps = 0
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var care := root.get_node("CoronerCare")
	var victim := preload("res://AnimatedPedestrian3D.gd").new()
	world.add_child(victim)
	victim._die()
	var key: String = care.identity(victim)
	var unit := preload("res://EmergencyVehicle.tscn").instantiate()
	unit.type = 3
	unit.position = Vector2(0,500)
	world.add_child(unit)
	unit.activate()
	unit.set_physics_process(false)
	unit.deployed_morticians = 2
	var bearer := preload("res://Mortician.tscn").instantiate()
	bearer.hearse = unit
	bearer.target = victim
	bearer.is_stretcher_bearer = true
	bearer.position = Vector2(0,38)
	world.add_child(bearer)
	bearer._access_route.assign([Vector2(0,28)])
	var support := preload("res://Mortician.tscn").instantiate()
	support.hearse = unit
	support.target = victim
	support.position = Vector2(0,22)
	world.add_child(support)
	support.state = support.State.RETURN_HEARSE
	support._return_route.assign([Vector2(0,28),Vector2(0,260)])
	unit._response_crew.assign([bearer,support])
	var passing := false
	for frame in 1800:
		await physics_frame
		if is_instance_valid(bearer) and absf(bearer.position.x)>8: passing = true
		if care.records()[key].phase=="transport": break
	var success: bool = passing and care.records()[key].phase=="transport"
	if not success: print("PASSING diagnostic bearer=",bearer.position if is_instance_valid(bearer) else Vector2.INF," support=",support.position if is_instance_valid(support) else Vector2.INF)
	print("CORONER_PASSING ","PASS" if success else "FAIL"," phase=",care.records()[key].phase)
	world.queue_free()
	for i in 3: await process_frame
	quit(0 if success else 1)

extends SceneTree
var failed := false
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ",message)
	if not value: failed=true
func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene=world
	var view=preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	world.add_child(view)
	view.build_view(preload("res://world/harbor/PortBossGarageArt.gd"),28,22)
	var factory=preload("res://world/shared/emergency/ModernTrafficFactory.gd")
	var adapter_script=preload("res://systems/interiors/InteriorVehiclePresentation.gd")
	var car=factory.spawn_parked_vehicle(world,"RemovedCar",Vector2.ZERO,0,"porto_rosso",2)
	car.ensure_presentation()
	var adapter=adapter_script.new()
	world.add_child(adapter)
	adapter.configure(car,view)
	var borrowed_model: WeakRef=weakref(car.body_model)
	check(car.body_model.get_parent()==view.viewport_3d,"Actual articulated model admitted")
	car.queue_free()
	await process_frame
	await process_frame
	check(borrowed_model.get_ref()==null and adapter.car==null,"Removing car frees borrowed model")
	car=factory.spawn_parked_vehicle(world,"SurvivingCar",Vector2.ZERO,0,"porto_rosso",2)
	car.ensure_presentation()
	adapter=adapter_script.new()
	world.add_child(adapter)
	adapter.configure(car,view)
	view.queue_free()
	await process_frame
	await process_frame
	check(is_instance_valid(car.body_model) and car.body_model.get_parent()==car.body_viewport,"Unloading room restores surviving car")
	check(car.visual.visible and car.collision.shape is RectangleShape2D and not car.has_meta("interior_vehicle_presentation"),"Original exterior collision and visibility restored")
	print("INTERIOR_VEHICLE_LIFECYCLE failed=",failed)
	quit(1 if failed else 0)

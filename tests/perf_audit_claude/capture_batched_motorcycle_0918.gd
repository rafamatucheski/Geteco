extends SceneTree
## Prova visual: a moto passa pelo pipeline real (apply_archetype -> _setup_3d_model
## -> VehicleMeshBatcher.batch_model) depois do conserto da chave de identidade.
## Salva um PNG do body_viewport de verdade, não um render isolado do modelo cru.

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var vehicle = (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate()
	vehicle.defer_presentation = false
	vehicle.crop = VehicleCatalog.VEHICLE_CROPS[0]
	vehicle.target_length = 76.0
	world.add_child(vehicle)
	vehicle.apply_archetype("bike_urban", Color("c7313a"))
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var out_dir := "res://tests/perf_audit_claude/results/police_combat_diag_1".get_base_dir()
	var path := "D:/geteco/game/tests/perf_audit_claude/results/batched_motorcycle_0918.png"
	vehicle.body_viewport.get_texture().get_image().save_png(path)
	print("SAVED ", path, " children=", vehicle.body_model.get_child_count())
	quit(0)

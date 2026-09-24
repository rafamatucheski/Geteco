extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var vehicle := (load("res://cars/traffic/TrafficVehicle.tscn") as PackedScene).instantiate() as CharacterBody2D
	var sequence := preload("res://cars/VehicleTheftSequence.gd").new()
	var rejected: bool = not sequence.prepare(vehicle, null, Vector2.ZERO, -1.0)
	print(("PASS " if rejected else "FAIL ") + "externally rendered vehicle rejects private-viewport theft prelude")

	var viewport := SubViewport.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.make_current()
	vehicle.body_viewport = viewport
	vehicle.body_model = Node3D.new()
	viewport.add_child(vehicle.body_model)
	var supported: bool = sequence.prepare(vehicle, null, Vector2.ZERO, -1.0)
	print(("PASS " if supported else "FAIL ") + "vehicle with private viewport keeps theft prelude")
	sequence.free()
	vehicle.free()
	viewport.free()
	quit(0 if rejected and supported else 1)

extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Deliberately invalid opt-in used to prove that direct regional publication is
## atomic and retryable. This fixture is never part of a production manifest.


func vehicle_prepared_template_resource() -> PackedScene:
	var root := Node3D.new()
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	return scene


func prepare_vehicle_prewarm_materials() -> void:
	paint = mat("paint", "ffffff", 0.0, 0.5)


func validate_vehicle_prepared_template(_template: Node3D) -> bool:
	return false


func bind_vehicle_prepared_template_materials(_template: Node) -> void:
	pass


func build() -> void:
	paint = mat("paint", "ffffff", 0.0, 0.5)
	box(Vector3.ZERO, Vector3.ONE, paint)

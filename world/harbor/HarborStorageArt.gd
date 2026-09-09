extends "res://world/mountain_pass/MountainStaticModelView.gd"
## Static port art projected into the same ground plane as gameplay physics.
func _ready() -> void:
	z_as_relative = false
	z_index = 4
	build_view(preload("res://prototypes/harbor_art_pack/compositions/PortStorageDepot3D.gd"), 10.5, 22.0, Vector3(0, 0.5, 0))
	var index := 0
	for bounds: AABB in model.get_obstacle_bounds():
		# Include stacked cargo as obstacles; never use the whole yard envelope.
		add_solid(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)), "CargoObstacle%d" % index)
		index += 1

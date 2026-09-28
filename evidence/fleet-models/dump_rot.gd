extends SceneTree
func _initialize() -> void:
	var model: Node3D = (load("res://assets/fleet/boxrunner.scn") as PackedScene).instantiate()
	for part in model.get_children():
		if part is MeshInstance3D and part.position.y > 1.7 and part.position.z < -1.4:
			print(part.mesh.get_class()," pos=",part.position.snapped(Vector3.ONE*.01)," rot=",part.rotation_degrees.snapped(Vector3.ONE*.1)," scale=",part.scale.snapped(Vector3.ONE*.01)," size=",part.mesh.get("size"))
	quit()

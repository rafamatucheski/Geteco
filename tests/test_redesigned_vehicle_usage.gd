extends "res://tests/test_vehicle_usage.gd"
## Mantém as checagens existentes de população, encaixe de carga e restauração, e então afirma
## que remover o limite legado não tira a nova carroceria de picape de várias superfícies.
func stored_setup(car: CharacterBody3D, id: String, world: Node3D) -> void:
	super.stored_setup(car, id, world)
	var body := car.visual.get_node_or_null("Body") as MeshInstance3D
	check(body != null and body.mesh != null, id + ": redesigned body survives usage setup")
	if body == null or body.mesh == null: return
	var roles: Array[String] = []
	for surface in body.mesh.get_surface_count():
		roles.append(preload("res://runtime/VehicleSurfaceRoles.gd").key(body, surface))
	check("paint" in roles and "glass" in roles and "detail" in roles, id + ": usage preserves paint, glass and bed detail surfaces")

extends SceneTree
const IDS=["ranch_pickup","ranch_single","nimbus_minivan","courier_van","boxrunner","mare_microvan","toco_minitruck"]
func _initialize()->void:
	for id:String in IDS:
		var model:Node3D=preload("res://runtime/FleetCatalog.gd").create(id)
		print("UTILITY_INSPECT ",id," spec ",preload("res://data/catalogs/VehicleDoorSpecs.gd").row(id)," meta ",model.get_meta("vehicle_interior_spec",{}))
		for part:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			print(part.name," ",part.transform*part.get_aabb()," ",part.get_meta("wheel_center","none"))
			for s in part.mesh.get_surface_count():
				print("FORMAT ",part.mesh.surface_get_format(s)," array sizes ",part.mesh.surface_get_arrays(s).map(func(a):return 0 if a==null else a.size()))
				print("SURFACE ",s," ",preload("res://runtime/VehicleSurfaceRoles.gd").key(part,s)," ",part.mesh.surface_get_array_len(s)," ",part.mesh.surface_get_array_index_len(s))
		model.free()
	quit()


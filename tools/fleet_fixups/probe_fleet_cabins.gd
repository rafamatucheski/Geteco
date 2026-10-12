extends SceneTree
## Read-only resource diagnostic: cabin inference before/after consolidation.
## No scene writes, gameplay approval, rendering or performance measurement.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const REGISTRY = preload("res://runtime/RedesignedFleet.gd")
const INTERIOR = preload("res://gameplay/VehicleInterior.gd")
const DOORS = preload("res://data/catalogs/VehicleDoorSpecs.gd")
const ROLES = preload("res://runtime/VehicleSurfaceRoles.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var ids: Array = REGISTRY.MESH_COUNTS.keys()
	var label := "cabin-probe"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids = Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	var report := {"method":"Read-only VehicleInterior inference on actual Vehicle resources; no performance or visual approval", "vehicles":{}}
	for id: String in ids:
		var entry := {"door":DOORS.row(id)}
		for variant in ["original", "redesigned"]:
			REGISTRY.enabled = variant == "redesigned"
			FLEET._data.clear()
			INTERIOR._specs.clear()
			var car := VEHICLE.new()
			car.archetype = id
			car.process_mode = Node.PROCESS_MODE_DISABLED
			root.add_child(car)
			var details := {"authored":car.visual.get_meta("vehicle_interior_spec",{}), "visual_scale":car.visual.scale, "spec":INTERIOR.spec(car), "glass":[]}
			for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
				if part.mesh == null or part.has_meta("wheel_center"): continue
				for surface in part.mesh.get_surface_count():
					if not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
					var vertices: PackedVector3Array = part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var lo := Vector3(INF,INF,INF)
					var hi := Vector3(-INF,-INF,-INF)
					var top_z0 := INF
					var xf := car.global_transform.affine_inverse() * part.global_transform
					for vertex: Vector3 in vertices:
						var p := xf * vertex
						lo = lo.min(p)
						hi = hi.max(p)
					for vertex: Vector3 in vertices:
						var p := xf * vertex
						if p.y > hi.y - .1: top_z0 = minf(top_z0,p.z)
					details.glass.append({"part":str(part.name),"surface":surface,"role":ROLES.key(part,surface),"min":lo,"max":hi,"top_z0":top_z0})
			entry[variant] = details
			car.free()
		report.vehicles[id] = entry
		print("CABIN_PROBE ",id," ",entry.original.spec.get("sz")," -> ",entry.redesigned.spec.get("sz"))
	var output := "res://evidence/fleet-redesign-20261011/validation/" + label + ".json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()

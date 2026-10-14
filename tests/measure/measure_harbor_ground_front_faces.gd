extends "res://tests/measure/measure_harbor_ground_layers.gd"
## Diagnostic counterpart: clockwise Godot top faces have a negative Y cross.
## The original census intentionally sees both sides; never compare their totals
## as before/after performance or claim every retained face is outdoor pavement.
var reported := {}

func _scan(chunk: Node3D) -> void:
	super._scan(chunk)
	# Report the complete two requested pairs, even when they disappear below
	# the inherited report's top-40 cutoff. Their footprints fit one chunk each.
	for target in ["AmmunationFacade3D", "CemeteryHouseExterior3D"]:
		var present := false
		for node in chunk.find_children("*", "MeshInstance3D", true, false):
			if _label(node,chunk).begins_with(target+"/"): present = true; break
		if not present: continue
		var area_m2 := 0.0
		var overlapping_m2 := 0.0
		for cell in layers:
			var owns := false
			var underlying := false
			for label in layers[cell]:
				if str(label).begins_with(target+"/"): owns = true
				if label == "HarborSurface_concrete" or label == "OriginalCemetery3D/CemeteryLawn" or label == "OriginalCemetery3D/CemeteryPath": underlying = true
			if owns:
				area_m2 += CELL*CELL
				if underlying: overlapping_m2 += CELL*CELL
		print("FACADE_COMPLETE_PAIR ",target," sampled_floor_m2=",area_m2," underlying_overlap_m2=",overlapping_m2)

func _mesh_faces(mesh: Mesh, xform: Transform3D, label: String) -> void:
	var faces := mesh.get_faces()
	var kept := 0
	for i in range(0, faces.size(), 3):
		var p0: Vector3 = xform * faces[i]
		var p1: Vector3 = xform * faces[i+1]
		var p2: Vector3 = xform * faces[i+2]
		var normal := (p1-p0).cross(p2-p0)
		if normal.length_squared() < 1e-8 or normal.normalized().y > -MIN_UP: continue
		var top := maxf(p0.y, maxf(p1.y, p2.y))
		var bottom := minf(p0.y, minf(p1.y, p2.y))
		if top > GROUND_MAX_Y or bottom < GROUND_MIN_Y: continue
		kept += _rasterize([Vector2(p0.x,p0.z), Vector2(p1.x,p1.z), Vector2(p2.x,p2.z)], label)
	if kept > 0 and ("Hospital" in label or "EarthRoadVerge" in label or "SerenoForestFloor" in label):
		var bounds: AABB = xform * mesh.get_aabb()
		var key := label + str(bounds)
		if not reported.has(key):
			reported[key] = true
			print("UPPER_GROUND_SOURCE ", label, " bounds=", bounds, " cells=", kept)

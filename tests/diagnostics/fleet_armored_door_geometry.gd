extends SceneTree
const BUILDER = preload("res://gameplay/VehicleDoorBuilder.gd")
const SPECS = preload("res://data/catalogs/VehicleDoorSpecs.gd")
func _initialize() -> void:
	var report := {}
	for label in ["before", "after"]:
		var path: String = "res://evidence/fleet-redesign-20261011/service/before/armored_truck.scn" if label == "before" else "res://assets/fleet/redesigned/armored_truck.scn"
		var model: Node3D = (load(path) as PackedScene).instantiate()
		var result := BUILDER.cut(model, SPECS.row("armored_truck"), 1.16)
		var rows := []
		for side in [-1, 1]:
			for kind in ["leaf", "inner"]:
				var groups: Dictionary = result.leaf[side] if kind == "leaf" else result.inner[side]
				for material in groups:
					var group: Dictionary = groups[material]
					var area := 0.0
					var tris := []
					for i in range(0, group.pos.size(), 3):
						var polygon := []
						for k in 3: polygon.append([group.pos[i+k], group.nrm[i+k], group.uv[i+k], group.col[i+k]])
						var clipped: Array = BUILDER._clip_box(polygon, {"zf":-2.035,"zr":-1.04,"sill":.87,"top":1.99})[0]
						if clipped.is_empty(): continue
						for j in range(1, clipped.size()-1):
							var a: Vector3 = clipped[0][0]
							var b: Vector3 = clipped[j][0]
							var c: Vector3 = clipped[j+1][0]
							var cross := (b-a).cross(c-a)
							if absf(cross.x) < .00001: continue
							area += absf(cross.x)*.5
							tris.append({"a":str(a),"b":str(b),"c":str(c),"cross":str(cross.normalized()),"stored_normal":str(clipped[0][1])})
					if area > 0: rows.append({"side":side,"kind":kind,"key":group.key,"material":str(material),"area_yz":area,"triangles":tris})
		report[label] = rows
		model.free()
	var checks := []
	var ok := true
	for side in [-1, 1]:
		for kind in ["leaf", "inner"]:
			var before := 0.0
			var after := 0.0
			for row in report.before:
				if row.side==side and row.kind==kind and row.key in ["paint","card"]: before+=float(row.area_yz)
			for row in report.after:
				if row.side==side and row.kind==kind and row.key in ["paint","card"]: after+=float(row.area_yz)
			var passes := after >= before*.99
			ok = ok and passes
			checks.append({"side":side,"kind":kind,"original_projected_area":before,"after_projected_area":after,"ok":passes})
	report["checks"] = checks
	report["ok"] = ok
	var path := "res://evidence/fleet-redesign-20261011/temporal/armored-door-geometry.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ARMORED_DOOR_GEOMETRY ", path)
	print("ARMORED_DOOR_CHECKS ", JSON.stringify(checks))
	quit(0 if ok else 1)

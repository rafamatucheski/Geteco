extends SceneTree

func _initialize() -> void:
	var geometry := HarborRoadGeometry3D.new()
	var roads: Array[Dictionary] = [{"id":"south_port_probe","points":PackedVector3Array([Vector3(-5,0,0),Vector3(5,0,0)]),"width":7.5}]
	geometry.configure(roads)
	var left := Node3D.new()
	var right := Node3D.new()
	# Place a dash midpoint exactly on the chunk boundary.
	geometry._build_markings(left,Rect2(-10,-5,5.875,10))
	geometry._build_markings(right,Rect2(-4.125,-5,14.125,10))
	var seen := {}
	var failures: Array[String] = []
	for parent in [left,right]:
		for mark in parent.find_children("Dash_*","MeshInstance3D",true,false):
			var key := str(mark.position)
			if seen.has(key): failures.append("Duplicate coplanar lane paint at "+key)
			seen[key] = true
			if mark.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: failures.append("Paint casts a raised shadow")
			if mark.position.y <= .026: failures.append("Paint intersects asphalt")
	if seen.size() != 3: failures.append("Missing/extra dashes across chunk boundary")
	left.free()
	right.free()
	print("PORT_MARKING_OWNERSHIP dashes=",seen.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)

extends SceneTree

func _initialize() -> void:
	var geometry := HarborRoadGeometry3D.new()
	var roads: Array[Dictionary] = [{"id":"south_port_probe","points":PackedVector3Array([Vector3(-5,0,0),Vector3(5,0,0)]),"width":7.5}]
	geometry.configure(roads)
	var left := Node3D.new()
	var right := Node3D.new()
	# Põe o ponto médio de um traço exatamente no limite do chunk.
	geometry._build_markings(left,Rect2(-10,-5,5.875,10))
	geometry._build_markings(right,Rect2(-4.125,-5,14.125,10))
	var seen := {}
	var failures: Array[String] = []
	for parent in [left,right]:
		# Tracinhos soltos (GETECO_DASH_BATCH=0) ou em lote por cor: a leitura cobre os dois.
		for mark in HarborRoadGeometry3D.dash_marks(parent):
			var origin: Vector3 = (mark.transform as Transform3D).origin
			var key := str(origin)
			if seen.has(key): failures.append("Duplicate coplanar lane paint at "+key)
			seen[key] = true
			if int(mark.cast_shadow) != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: failures.append("Paint casts a raised shadow")
			if origin.y <= .026: failures.append("Paint intersects asphalt")
	if seen.size() != 3: failures.append("Missing/extra dashes across chunk boundary")
	var paving := Node3D.new()
	geometry.build_chunk(paving,Rect2(-10,-5,20,10))
	var surfaces := 0
	for mesh in paving.find_children("HarborRoad_*","MeshInstance3D",true,false):
		surfaces += 1
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("Flat paving casts unstable shadows onto adjacent layers")
	if surfaces != 4: failures.append("Missing road paving layers")
	if paving.find_children("*Solid","StaticBody3D",true,false).is_empty():
		failures.append("Asphalt lost physical support")
	paving.free()
	var lots := HarborUrbanSurface3D.new()
	lots.configure()
	var exit_lot := Node3D.new()
	lots.build_chunk(exit_lot,Rect2(180,125,30,35))
	if exit_lot.get_child_count() == 0: failures.append("Missing port exit lot finish")
	for mesh in exit_lot.get_children():
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("Port exit lot casts unstable ground shadows")
	exit_lot.free()
	left.free()
	right.free()
	print("PORT_MARKING_OWNERSHIP dashes=",seen.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)

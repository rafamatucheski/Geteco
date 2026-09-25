extends RefCounted
## Small, shared model finishing pass. Gameplay anchors and moving parts stay intact.
const GEO = preload("res://assets/regions/source/scripts/player/WeaponPresentation3D.gd")
# Immutable local geometry, bounded independently of weapon instances.
static var _bevel_meshes: Dictionary = {}
const BEVEL_CACHE_LIMIT := 256

static func apply(root: Node3D, id: String, muzzle: Vector3) -> void:
	if id == "fists": return
	var steel := GEO._mat(Color("56616b"), 0.78, 0.34)
	var dark := GEO._mat(Color("20272b"), 0.55, 0.48)
	var rubber := GEO._mat(Color("181b1c"), 0.0, 0.84)
	var brass := GEO._mat(Color("a78a50"), 0.7, 0.4)
	if id in ["ak47", "m4a1", "smg", "micro_smg", "shotgun", "sawed_off", "magnum"]:
		# Dark recessed muzzle surrounded by a steel lip, not a solid capped cylinder.
		var tip := muzzle + Vector3(0, 0, 0.021)
		GEO._cylinder(root, "MuzzleLip", tip, 0.016, 0.014, steel, Vector3(90,0,0))
		GEO._cylinder(root, "MuzzleOpening", tip + Vector3(0,0,-0.0075), 0.010, 0.001, rubber, Vector3(90,0,0))
	if id in ["ak47", "m4a1", "smg", "micro_smg"]:
		GEO._trigger_guard(root, Vector3(0,-0.039,-0.015), dark)
		GEO._box(root,"EjectionRecess",Vector3(0.024,0.02,-0.012),Vector3(0.002,0.022,0.06),rubber)
		GEO._box(root,"ChargingHandle",Vector3(0.037,0.021,0.005),Vector3(0.03,0.012,0.017),steel)
		for z in [-0.068,0.035]:
			GEO._cylinder(root,"ReceiverPin",Vector3(0,0.005,z),0.004,0.049,steel,Vector3(0,0,90))
		GEO._box(root,"Selector",Vector3(-0.025,-0.005,0.021),Vector3(0.004,0.009,0.027),steel)
		for y in [-0.045,-0.063,-0.081]:
			GEO._box(root,"GripCheckering",Vector3(0,y,0.043),Vector3(0.036,0.004,0.044),rubber)
		if id == "ak47":
			GEO._cylinder(root,"GasTube",Vector3(0,0.045,-0.20),0.011,0.21,dark,Vector3(90,0,0))
			GEO._box(root,"FrontSightPost",Vector3(0,0.052,-0.365),Vector3(0.018,0.044,0.025),dark)
			GEO._box(root,"RearSightLeaf",Vector3(0,0.054,-0.065),Vector3(0.028,0.010,0.048),steel)
			GEO._box(root,"ButtPad",Vector3(0,-0.02,0.29),Vector3(0.043,0.082,0.007),rubber)
		else:
			for z in [-0.20,-0.176,-0.152,-0.128,-0.104]:
				GEO._box(root,"ForeEndVent",Vector3(0,0.014,z),Vector3(0.048,0.018,0.008),rubber)
				# The SMG receiver ends at -.18; the rifle's forward tooth floats over its exposed barrel.
				if id not in ["smg", "micro_smg"] or z >= -.18:
					GEO._box(root,"RailTooth",Vector3(0,0.048,z),Vector3(0.034,0.009,0.009),steel)
			GEO._box(root,"ButtPad",Vector3(0,0,0.247 if id == "m4a1" else 0.187),Vector3(0.044,0.095,0.008),rubber)
			if id == "m4a1":
				var lens := GEO._mat(Color("346269"),0.45,0.22)
				GEO._box(root,"SightLens",Vector3(0,0.067,-0.0555),Vector3(0.024,0.023,0.001),lens)
	elif id in ["shotgun", "sawed_off"]:
		GEO._trigger_guard(root,Vector3(0,-0.035,0.0),dark)
		GEO._box(root,"EjectionRecess",Vector3(0.025,0.018,0),Vector3(0.002,0.025,0.065),rubber)
		var pump := root.get_node_or_null("Pump") as Node3D
		if pump:
			for z in [-0.055,-0.033,-0.011,0.011,0.033,0.055]:
				GEO._box(pump,"PumpGroove",Vector3(0,0,z),Vector3(0.054,0.054,0.004),dark)
	elif id == "magnum":
		GEO._trigger_guard(root,Vector3(0,-0.017,-0.025),dark)
		GEO._box(root,"HammerSpur",Vector3(0,0.050,0.065),Vector3(0.014,0.024,0.022),steel)
		var drum := root.get_node("ReloadCylinder")
		for i in 6:
			var angle := i*TAU/6
			GEO._cylinder(drum,"ChamberRecess",Vector3(cos(angle)*0.018,-0.041,sin(angle)*0.018),0.006,0.002,rubber,Vector3.ZERO)
		for side in [-1.0,1.0]:
			GEO._cylinder(root,"GripScrew",Vector3(side*0.020,-0.053,0.036),0.006,0.003,brass,Vector3(0,0,90))
	elif id == "rpg":
		for z in [-0.08,0.0,0.08]:
			GEO._cylinder(root,"HeatShieldBand",Vector3(0,0.08,z),0.044,0.012,dark,Vector3(90,0,0))
		GEO._box(root,"SightBracket",Vector3(-0.047,0.10,-0.08),Vector3(0.025,0.045,0.028),dark)
		GEO._cylinder(root,"SightTube",Vector3(-0.06,0.13,-0.09),0.014,0.11,steel,Vector3(90,0,0))
		GEO._cylinder(root,"ExhaustOpening",Vector3(0,0.08,0.501),0.030,0.002,rubber,Vector3(90,0,0))
	elif id == "flamethrower":
		for z in [-0.12,0.0]:
			GEO._cylinder(root,"TankBand",Vector3(0.075,-0.045,z),0.047,0.014,dark,Vector3(90,0,0))
		GEO._cylinder(root,"PressureDial",Vector3(0.075,0.006,-0.12),0.016,0.012,brass,Vector3.ZERO)
		for z in [-0.37,-0.35,-0.33]:
			GEO._cylinder(root,"ShroudBand",Vector3(0,0.02,z),0.035,0.006,steel,Vector3(90,0,0))
	elif id == "grenade":
		GEO._box(root,"SafetyLever",Vector3(0.033,0.024,-0.10),Vector3(0.013,0.070,0.017),steel)
		GEO._box(root,"LeverBridge",Vector3(0.017,0.062,-0.10),Vector3(0.046,0.011,0.019),steel)
		for y in [-0.024,0.0,0.024]:
			GEO._cylinder(root,"BodyBand",Vector3(0,y,-0.10),0.044 if y == 0 else 0.038,0.007,dark,Vector3.ZERO)
		var ring := MeshInstance3D.new()
		ring.name = "SafetyRing"
		var torus := TorusMesh.new()
		torus.inner_radius = 0.010
		torus.outer_radius = 0.014
		torus.rings = 12
		torus.ring_segments = 6
		ring.mesh = torus
		ring.position = Vector3(-0.019,0.05,-0.1)
		ring.rotation.x = PI/2
		ring.material_override = steel
		root.add_child(ring)
	elif id in ["bat", "axe", "knife"]:
		for z in [0.025,0.045,0.065,0.085]:
			GEO._cylinder(root,"GripBinding",Vector3(0,0,z),0.020 if id != "knife" else 0.017,0.004,rubber,Vector3(90,0,0))
	_finish_meshes(root)
	for moving_name in ["Pump","ReloadCylinder"]:
		var moving := root.get_node_or_null(NodePath(moving_name)) as Node3D
		if moving: _batch_static(moving)
	_batch_static(root)

static func _finish_meshes(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			if child.mesh is BoxMesh:
				child.mesh = _beveled_box(child.mesh.size)
			elif child.mesh is CylinderMesh:
				child.mesh.radial_segments = 16
				child.mesh.rings = 1
			elif child.mesh is SphereMesh:
				child.mesh.radial_segments = 16
				child.mesh.rings = 8
		_finish_meshes(child)

static func _beveled_box(size: Vector3) -> ArrayMesh:
	if _bevel_meshes.has(size): return _bevel_meshes[size]
	var half := size * 0.5
	var inset := minf(0.003, minf(size.x, minf(size.y,size.z)) * 0.18)
	var core := half - Vector3.ONE * inset
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Six inset faces, twelve bevel strips, eight clipped corners.
	for axis in 3:
		var u := (axis+1)%3
		var v := (axis+2)%3
		for sign_axis in [-1.0,1.0]:
			var points: Array[Vector3] = []
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var p := Vector3.ZERO
				p[axis] = half[axis]*sign_axis
				p[u] = core[u]*corner.x
				p[v] = core[v]*corner.y
				points.append(p)
			_face(st,points)
		for su in [-1.0,1.0]:
			for sv in [-1.0,1.0]:
				var points: Array[Vector3] = []
				for k in 4:
					var p := Vector3.ZERO
					p[axis] = core[axis] * (-1 if k < 2 else 1)
					p[u] = (half[u] if k in [0,3] else core[u])*su
					p[v] = (core[v] if k in [0,3] else half[v])*sv
					points.append(p)
				_face(st,points)
	for x in [-1.0,1.0]:
		for y in [-1.0,1.0]:
			for z in [-1.0,1.0]:
				var points: Array[Vector3] = []
				for axis in 3:
					var p := core
					p[axis] = half[axis]
					points.append(p*Vector3(x,y,z))
				_face(st,points)
	var mesh := st.commit()
	if _bevel_meshes.size() < BEVEL_CACHE_LIMIT: _bevel_meshes[size] = mesh
	return mesh

static func _face(st: SurfaceTool, points: Array[Vector3]) -> void:
	var normal := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	var center := Vector3.ZERO
	for p in points: center += p
	if normal.dot(center) < 0:
		points.reverse()
		normal = -normal
	# Godot uses clockwise front faces; supply the outward normal explicitly.
	for i in range(1,points.size()-1):
		for k in [0,i+1,i]:
			st.set_normal(normal)
			st.add_vertex(points[k])

static func _batch_static(root: Node3D) -> void:
	var batches := {}
	for child in root.find_children("*","MeshInstance3D",true,false):
		var ancestor: Node = child
		var moving := false
		while ancestor != root:
			if ancestor.name in ["Pump","LoadedRocket","ReloadCylinder"]: moving = true
			ancestor = ancestor.get_parent()
		if moving: continue
		if child.mesh == null or child.mesh.get_surface_count() == 0: continue
		var transform: Transform3D = root.global_transform.affine_inverse() * child.global_transform if root.is_inside_tree() else _local_transform(child,root)
		for surface in child.mesh.get_surface_count():
			var material: Material = child.material_override if child.material_override else child.mesh.surface_get_material(surface)
			if material == null: continue
			var key := material.get_instance_id()
			if not batches.has(key):
				var merged: Array = []
				merged.resize(Mesh.ARRAY_MAX)
				merged[Mesh.ARRAY_INDEX] = PackedInt32Array()
				batches[key] = {"arrays": merged, "material": material}
			var merged: Array = batches[key].arrays
			var arrays: Array = child.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var previous_count: int = merged[Mesh.ARRAY_VERTEX].size() if merged[Mesh.ARRAY_VERTEX] != null else 0
			# Transform shared vertices once, not once for each triangle corner.
			arrays[Mesh.ARRAY_VERTEX] = transform * vertices
			var normal_basis := transform.basis.inverse().transposed()
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in normals.size(): normals[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
			if arrays[Mesh.ARRAY_TANGENT] != null:
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				var handedness := -1.0 if transform.basis.determinant() < 0 else 1.0
				for i in range(0, tangents.size(), 4):
					var tangent := (transform.basis * Vector3(tangents[i], tangents[i+1], tangents[i+2])).normalized()
					tangents[i] = tangent.x
					tangents[i+1] = tangent.y
					tangents[i+2] = tangent.z
					tangents[i+3] *= handedness
				arrays[Mesh.ARRAY_TANGENT] = tangents
			# Keep optional UV/color data when a material combines primitive types.
			for channel in Mesh.ARRAY_INDEX:
				if arrays[channel] == null and merged[channel] == null: continue
				var stride := 4 if channel in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS] else 1
				var destination = merged[channel]
				if destination == null:
					destination = arrays[channel].slice(0, 0)
					destination.resize(previous_count * stride)
					if channel == Mesh.ARRAY_COLOR: destination.fill(Color.WHITE)
				var incoming = arrays[channel]
				if incoming == null:
					incoming = destination.slice(0, 0)
					incoming.resize(vertices.size() * stride)
					if channel == Mesh.ARRAY_COLOR: incoming.fill(Color.WHITE)
				destination.append_array(incoming)
				merged[channel] = destination
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var merged_indices: PackedInt32Array = merged[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for i in vertices.size(): merged_indices.append(previous_count + i)
			else:
				for index in indices: merged_indices.append(previous_count + index)
			merged[Mesh.ARRAY_INDEX] = merged_indices
		child.get_parent().remove_child(child)
		child.free()
	for key in batches:
		var part := MeshInstance3D.new()
		part.name = "FinishedMaterial_" + str(key)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, batches[key].arrays)
		mesh.surface_set_material(0, batches[key].material)
		part.mesh = mesh
		root.add_child(part)

static func _local_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != root:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

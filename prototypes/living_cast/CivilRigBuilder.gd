extends RefCounted

## Derived from the approved isolated civil study. Materials shared across rigs.
static var mats: Dictionary = {}

func make_rig(parent: Node3D, variant: int) -> Dictionary:
	build_person(parent, variant)
	var accessory := material("accessory_%d" % variant, ["4b4238", "e6c35a", "6f4942", "564433", "34333b", "29352e"][variant % 6])
	match variant % 6:
		1: # Dock worker: hard hat and high visibility waist band.
			ell(parent, Vector3(0, 1.73, 0), Vector3(0.29, 0.17, 0.29), accessory)
			ell(parent, Vector3(0, 1.68, -0.015), Vector3(0.34, 0.035, 0.34), accessory)
			box(parent, Vector3(0, 1.01, -0.17), Vector3(0.34, 0.035, 0.016), material("reflector", "d8cfad"))
		2: # Backpack, longer hair and asymmetric fringe.
			ell(parent, Vector3(0, 1.19, 0.17), Vector3(0.29, 0.35, 0.15), accessory)
			for side in [-1.0, 1.0]:
				box(parent, Vector3(side * 0.15, 1.25, -0.17), Vector3(0.027, 0.25, 0.015), accessory)
				ell(parent, Vector3(side * 0.11, 1.57, 0.035), Vector3(0.09, 0.26, 0.19), material("long_hair", "362725"))
		3: # Older resident: spectacles, scarf, muted clothing.
			for side in [-1.0, 1.0]:
				box(parent, Vector3(side * 0.055, 1.592, -0.126), Vector3(0.068, 0.031, 0.008), accessory)
			box(parent, Vector3(0, 1.4, -0.067), Vector3(0.18, 0.09, 0.13), accessory)
			box(parent, Vector3(0.056, 1.27, -0.172), Vector3(0.06, 0.23, 0.02), accessory)
		4: # Unarmed fighter; knit cap, no automatic firearm.
			ell(parent, Vector3(0, 1.73, 0), Vector3(0.28, 0.18, 0.27), accessory)
		5:
			box(parent, Vector3(0, 1.06, -0.166), Vector3(0.28, 0.05, 0.022), accessory)
	var pieces := parent.get_children()
	var joints := {}
	for entry in [["torso", Vector3(0, 0.85, 0)], ["head", Vector3(0, 1.25, 0)],
		["left_upper_arm", Vector3(-0.21, 1.32, 0)], ["right_upper_arm", Vector3(0.21, 1.32, 0)],
		["left_upper_leg", Vector3(-0.105, 0.87, 0)], ["right_upper_leg", Vector3(0.105, 0.87, 0)]]:
		var joint := Node3D.new()
		joint.name = entry[0]
		joint.position = entry[1]
		parent.add_child(joint)
		joints[entry[0]] = joint
	for side in ["left", "right"]:
		var sign_side := -1.0 if side == "left" else 1.0
		for limb_name in ["arm", "leg"]:
			var joint := Node3D.new()
			joint.name = side + "_lower_" + limb_name
			joints[side + "_upper_" + limb_name].add_child(joint)
			joint.position = Vector3(sign_side * 0.075, -0.235, 0) if limb_name == "arm" else Vector3(sign_side * 0.01, -0.36, 0)
			joints[joint.name] = joint
	for piece in pieces:
		var pos: Vector3 = piece.position
		var key := "torso"
		var side := "left" if pos.x < 0 else "right"
		if pos.y > 1.40:
			key = "head"
		elif absf(pos.x) > 0.205 and pos.y > 0.74:
			key = side + ("_upper_arm" if pos.y > 1.085 else "_lower_arm")
		elif pos.y < 0.87 and absf(pos.x) > 0.05:
			key = side + ("_upper_leg" if pos.y > 0.51 else "_lower_leg")
		piece.reparent(joints[key], true)
	# Merge static pieces by material WITHIN each joint, preserving articulation.
	# No extra draw call for every lace, collar or hair tuft.
	for joint in joints.values():
		var batches := {}
		for child in joint.get_children():
			if child is MeshInstance3D:
				var mat: Material = child.material_override
				if not batches.has(mat):
					var surface := SurfaceTool.new()
					surface.begin(Mesh.PRIMITIVE_TRIANGLES)
					batches[mat] = surface
				batches[mat].append_from(child.mesh, 0, child.transform)
				joint.remove_child(child)
				child.free()
		for mat in batches:
			var merged := MeshInstance3D.new()
			merged.mesh = batches[mat].commit()
			merged.material_override = mat
			joint.add_child(merged)
	parent.scale = Vector3([0.83, 0.91, 0.77, 0.81, 0.98, 0.87][variant % 6], [0.84, 0.88, 0.81, 0.82, 0.86, 0.9][variant % 6], 0.84)
	return joints

func material(key: String, color: String) -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.roughness = 0.9
	mats[key] = m
	return m

func ell(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 20
	mesh.rings = 12
	mesh.radius = 0.5
	mesh.height = 1.0
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.scale = size
	node.material_override = mat
	parent.add_child(node)
	return node

func box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = mat
	parent.add_child(node)
	return node

func limb(parent: Node3D, start: Vector3, end: Vector3, radius: float, mat: Material) -> void:
	var shape := CapsuleMesh.new()
	shape.radius = radius
	shape.height = start.distance_to(end) + radius * 1.5
	shape.radial_segments = 16
	shape.rings = 8
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = mat
	node.position = (start + end) * 0.5
	parent.add_child(node)
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())

func build_person(parent: Node3D, variant: int = 0) -> void:
	var skin := material("skin_%d" % variant, ["ad7655", "714b36", "d6a181", "875638", "c18e69", "9e6b4d"][variant % 6])
	var skin_light := material("skin_light_%d" % variant, ["bc8965", "835c43", "e0b094", "976846", "ce9b7a", "ae7b5d"][variant % 6])
	var hair := material("hair_%d" % variant, ["292623", "252020", "362725", "8b8780", "211d1c", "43312a"][variant % 6])
	var jacket := material("jacket_%d" % variant, ["586353", "c08236", "785f75", "354a60", "713d38", "354c42"][variant % 6])
	var seam := material("seam", "384539")
	var shirt := material("shirt", "ddd1b8")
	var denim := material("denim_%d" % variant, ["344553", "41423d", "33313c", "56575c", "262a32", "5a5145"][variant % 6])
	var denim_light := material("denim_light", "435865")
	var shoe := material("shoe", "65493b")
	var sole := material("sole", "c5b99e")
	var eyes := material("eyes", "242322")
	var metal := material("metal", "b4a784")
	# Separate pelvis, legs and shoes; stance is slightly asymmetric.
	ell(parent, Vector3(0, 0.88, 0), Vector3(0.35, 0.26, 0.24), denim)
	for side in [-1.0, 1.0]:
		var hip := Vector3(side * 0.105, 0.87, 0)
		var knee := Vector3(side * 0.115, 0.51, -0.015 if side < 0 else 0.025)
		var ankle := Vector3(side * 0.135, 0.16, 0.015 if side < 0 else 0.06)
		limb(parent, hip, knee, 0.09, denim)
		limb(parent, knee, ankle, 0.072, denim)
		box(parent, ankle + Vector3(0, 0.015, -0.062), Vector3(0.12, 0.022, 0.024), denim_light)
		ell(parent, ankle + Vector3(0, -0.095, -0.063), Vector3(0.16, 0.095, 0.30), sole)
		ell(parent, ankle + Vector3(0, -0.065, -0.063), Vector3(0.153, 0.125, 0.27), shoe)
		for lace in 3:
			box(parent, ankle + Vector3(0, -0.005, -0.10 + lace * 0.028), Vector3(0.083, 0.009, 0.008), shirt)
	# Torso, open field jacket, hem and patch pockets.
	ell(parent, Vector3(0, 1.14, 0), Vector3(0.44, 0.51, 0.28), jacket)
	if variant in [0, 3]:
		ell(parent, Vector3(0, 1.18, -0.128), Vector3(0.19, 0.37, 0.055), shirt)
	elif variant == 1:
		for side in [-1.0, 1.0]:
			box(parent, Vector3(side * 0.12, 1.18, -0.136), Vector3(0.035, 0.28, 0.026), shirt)
	elif variant == 2:
		ell(parent, Vector3(0, 1.015, -0.13), Vector3(0.26, 0.14, 0.075), jacket)
		for side in [-1.0, 1.0]:
			box(parent, Vector3(side * 0.038, 1.30, -0.125), Vector3(0.008, 0.12, 0.012), shirt)
	elif variant == 5:
		box(parent, Vector3(0, 1.17, -0.115), Vector3(0.30, 0.30, 0.075), seam)
		for side in [-1.0, 1.0]:
			box(parent, Vector3(side * 0.082, 1.16, -0.17), Vector3(0.063, 0.105, 0.033), jacket)
	box(parent, Vector3(0, 0.925, -0.13), Vector3(0.32, 0.035, 0.024), seam)
	for side in [-1.0, 1.0]:
		if variant in [0, 3]:
			var panel := ell(parent, Vector3(side * 0.123, 1.13, -0.104), Vector3(0.17, 0.43, 0.125), jacket)
			panel.rotation.z = side * 0.035
			box(parent, Vector3(side * 0.062, 1.12, -0.161), Vector3(0.012, 0.31, 0.012), seam)
			box(parent, Vector3(side * 0.143, 1.17, -0.158), Vector3(0.084, 0.083, 0.018), seam)
			box(parent, Vector3(side * 0.143, 1.18, -0.17), Vector3(0.077, 0.063, 0.011), jacket)
			box(parent, Vector3(side * 0.143, 1.211, -0.178), Vector3(0.084, 0.016, 0.013), seam)
			ell(parent, Vector3(side * 0.143, 1.205, -0.187), Vector3.ONE * 0.009, metal)
			var collar := box(parent, Vector3(side * 0.072, 1.345, -0.09), Vector3(0.086, 0.13, 0.028), seam)
			collar.rotation.z = side * -0.40
		var shoulder := Vector3(side * 0.21, 1.32, 0)
		var elbow := Vector3(side * 0.285, 1.085, 0.0)
		var wrist := Vector3(side * 0.285, 0.865, -0.07)
		limb(parent, shoulder, elbow, 0.084, skin if variant == 4 else jacket)
		limb(parent, elbow, wrist, 0.069, skin if variant in [1,4] else jacket)
		if variant == 4:
			limb(parent, shoulder, shoulder.lerp(elbow, 0.35), 0.09, jacket)
		else:
			limb(parent, wrist + Vector3(0, 0.04, 0.006), wrist, 0.07, seam)
		ell(parent, wrist + Vector3(0, -0.064, -0.006), Vector3(0.075, 0.13, 0.055), skin)
		ell(parent, wrist + Vector3(-side * 0.031, -0.038, -0.033), Vector3(0.033, 0.075, 0.032), skin_light)
	# Neck, jaw and face are distinct volumes, not a single featureless sphere.
	ell(parent, Vector3(0, 1.405, 0), Vector3(0.135, 0.16, 0.135), skin)
	ell(parent, Vector3(0, 1.575, -0.005), Vector3(0.255, 0.315, 0.25), skin)
	ell(parent, Vector3(0, 1.48, -0.065), Vector3(0.187, 0.14, 0.17), skin_light)
	for side in [-1.0, 1.0]:
		ell(parent, Vector3(side * 0.126, 1.57, 0), Vector3(0.047, 0.088, 0.052), skin)
		ell(parent, Vector3(side * 0.050, 1.59, -0.115), Vector3(0.036, 0.014, 0.012), eyes)
		var brow := box(parent, Vector3(side * 0.05, 1.614, -0.113), Vector3(0.045, 0.012, 0.012), hair)
		brow.rotation.z = side * 0.07
	ell(parent, Vector3(0, 1.558, -0.128), Vector3(0.041, 0.063, 0.051), skin_light)
	if variant != 2:
		ell(parent, Vector3(0, 1.479, -0.122), Vector3(0.105, 0.035, 0.014), material("stubble", "674e3e"))
	box(parent, Vector3(0, 1.499, -0.146), Vector3(0.058, 0.007, 0.009), material("lip", "835640"))
	ell(parent, Vector3(0, 1.694, 0.008), Vector3(0.259, 0.115, 0.251), hair)
	ell(parent, Vector3(0, 1.612, 0.09), Vector3(0.23, 0.15, 0.095), hair)
	for i in 5:
		var tuft := ell(parent, Vector3(-0.084 + i * 0.038, 1.733 + sin(i) * 0.006, -0.026), Vector3(0.064, 0.055, 0.19), hair)
		tuft.rotation.z = -0.18
	# Wristwatch gives one intentionally asymmetric detail.
	ell(parent, Vector3(-0.285, 0.88, -0.127), Vector3(0.045, 0.055, 0.018), metal)
	ell(parent, Vector3(-0.285, 0.88, -0.138), Vector3(0.034, 0.042, 0.009), eyes)

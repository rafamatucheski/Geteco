extends RefCounted
## Extract actual visible production meshes, retaining their materials and pose.
## Each source branch belongs to exactly one physical fragment.
const PARTS := ["head_node", "torso_node", "left_upper_arm", "right_upper_arm", "left_upper_leg", "right_upper_leg"]
static var cut_material: StandardMaterial3D
static var bone_material: StandardMaterial3D

static func rig_for(actor: Node) -> Node3D:
	for key in ["model_root", "driver_model", "model"]:
		if actor.get(key) is Node3D: return actor.get(key)
	return null

static func sources(actor: Node) -> Dictionary:
	var result := {}
	for key in PARTS:
		if actor.get(key) is Node3D: result[key] = [actor.get(key)]
	if not result.is_empty(): return result
	var rig := rig_for(actor)
	if rig == null or not rig.get("limbs") is Array or rig.limbs.size() < 4: return result
	for i in 4: result[["left_upper_leg", "left_upper_arm", "right_upper_leg", "right_upper_arm"][i]] = [rig.limbs[i]]
	result["head_node"] = []
	result["torso_node"] = []
	var body_root: Node3D = rig.get("pose_root") if rig.get("pose_root") is Node3D else rig
	for mesh in body_root.get_children():
		if mesh == rig.get("breath"): continue
		if mesh is Node3D and not rig.limbs.has(mesh) and mesh.visible:
			result["head_node" if mesh.position.y >= 1.48 else "torso_node"].append(mesh)
	return result

static func plans(actor: Node, rng: RandomNumberGenerator) -> Array:
	var variants := [
		[[0], [1, 2, 3], [4], [5]],
		[[0, 1, 2], [3], [4], [5]],
		[[0], [1, 3], [2], [4], [5]],
		[[0], [1], [2], [3], [4], [5]]
	]
	var result: Array = []
	var available := sources(actor)
	for group in variants[rng.randi_range(0, variants.size()-1)]:
		var keys: Array[String] = []
		for index in group:
			if available.has(PARTS[index]) and not available[PARTS[index]].is_empty(): keys.append(PARTS[index])
		if not keys.is_empty(): result.append(keys)
	return result

static func build(actor: Node2D, keys: Array) -> Node3D:
	var root := Node3D.new()
	var rig := rig_for(actor)
	var available := sources(actor)
	var inverse := rig.global_transform.affine_inverse()
	var scale_basis := Basis.from_scale(rig.scale)
	var included: Array[Node3D] = []
	for key in keys:
		for branch in available[key]: included.append(branch)
	var used := {}
	for branch in included:
		_copy_meshes(branch, root, inverse, scale_basis, included, actor, used)
	# Small closed cut surfaces at severed joints, with a recessed bone centre.
	for key in keys:
		if key == "torso_node": continue
		if key == "head_node" and keys.has("torso_node"): continue
		if key in ["left_upper_arm", "right_upper_arm"] and keys.has("torso_node"): continue
		var joint: Node3D = available[key][0]
		var at := scale_basis * (inverse * joint.global_position)
		var radius := 0.056 if "arm" in key else 0.067
		if key == "head_node":
			at.y -= 0.045
			_cap(root, at, radius, PI, 0)
		else: _cap(root, at, radius, 0, 0)
	if keys.has("torso_node"):
		for key in ["head_node", "left_upper_arm", "right_upper_arm"]:
			if keys.has(key) or not available.has(key) or available[key].is_empty(): continue
			var joint: Node3D = available[key][0]
			var at := scale_basis * (inverse * joint.global_position)
			_cap(root, at, .064 if key == "head_node" else .052, 0, 0 if key == "head_node" else (PI/2 if key == "left_upper_arm" else -PI/2))
	var bounds := bounds_for(root)
	var center := bounds.get_center()
	for mesh in root.get_children(): mesh.position -= center
	root.set_meta("fragment_bounds", AABB(bounds.position-center, bounds.size))
	root.set_meta("source_parts", keys.duplicate())
	return root

static func _copy_meshes(node: Node, root: Node3D, inverse: Transform3D, scale_basis: Basis, included: Array[Node3D], actor: Node, used: Dictionary) -> void:
	if node.name in [&"WeaponMount", &"MuzzleFlash", &"PersonBurning"]: return
	if node is Node3D and not node.visible: return
	# Some rigs nest limbs under the torso. Never duplicate another fragment.
	for key in PARTS:
		if actor.get(key) == node and not included.has(node): return
	if node is MeshInstance3D and node.visible and node.mesh != null and not used.has(node):
		used[node] = true
		var copy := MeshInstance3D.new()
		copy.mesh = node.mesh
		copy.material_override = node.material_override
		for surface in node.mesh.get_surface_count():
			copy.set_surface_override_material(surface, node.get_surface_override_material(surface))
		copy.transform = Transform3D(scale_basis, Vector3.ZERO) * inverse * node.global_transform
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(copy)
	for child in node.get_children(): _copy_meshes(child, root, inverse, scale_basis, included, actor, used)

static func _cap(root: Node3D, at: Vector3, radius: float, x_angle: float, z_angle: float) -> void:
	if cut_material == null:
		cut_material = StandardMaterial3D.new()
		cut_material.albedo_color = Color("752d30")
		cut_material.roughness = .78
		bone_material = StandardMaterial3D.new()
		bone_material.albedo_color = Color("bba789")
		bone_material.roughness = .9
	for layer in 2:
		var mesh := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius * (1.0 if layer == 0 else .25)
		disc.bottom_radius = disc.top_radius * .86
		disc.height = .014 if layer == 0 else .006
		disc.radial_segments = 12
		mesh.mesh = disc
		mesh.material_override = cut_material if layer == 0 else bone_material
		mesh.rotation = Vector3(x_angle, 0, z_angle)
		mesh.position = at + mesh.basis.y * (0 if layer == 0 else .009)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)

static func bounds_for(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh in root.get_children():
		if not mesh is MeshInstance3D: continue
		var bounds: AABB = mesh.transform * mesh.get_aabb()
		result = bounds if first else result.merge(bounds)
		first = false
	return result

static func floor_offset(model: Node3D) -> float:
	var bounds: AABB = model.get_meta("fragment_bounds", AABB())
	return -(Transform3D(model.basis, Vector3.ZERO) * bounds).position.y

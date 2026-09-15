extends RefCounted
## Ten persistent silhouettes, independent of rank, weapons and collision.
const PROFILES := [
	{"height": 1.04, "width": 0.86, "depth": 0.88, "limb": 0.90, "skin": "c99573", "hair": "30251f"},
	{"height": 1.00, "width": 1.00, "depth": 1.00, "limb": 1.00, "skin": "87583f", "hair": "201c1b", "woman": true, "hairstyle": "bun"},
	{"height": 0.97, "width": 1.28, "depth": 1.38, "limb": 1.16, "skin": "d7a383", "hair": "584b43"},
	{"height": 1.07, "width": 1.12, "depth": 1.05, "limb": 1.15, "skin": "684733", "hair": "211d1c"},
	{"height": 0.93, "width": 0.90, "depth": 0.92, "limb": 0.94, "skin": "b77b54", "hair": "332620", "woman": true, "hairstyle": "short"},
	{"height": 1.03, "width": 1.34, "depth": 1.42, "limb": 1.22, "skin": "936448", "hair": "25201e"},
	{"height": 0.96, "width": 1.05, "depth": 1.08, "limb": 1.02, "skin": "dbb398", "hair": "8a8279"},
	{"height": 1.08, "width": 0.95, "depth": 0.94, "limb": 0.96, "skin": "a16d4c", "hair": "302922", "woman": true, "hairstyle": "ponytail"},
	{"height": 0.94, "width": 1.20, "depth": 1.24, "limb": 1.12, "skin": "79523e", "hair": "6d6864", "woman": true, "hairstyle": "bun"},
	{"height": 1.01, "width": 1.10, "depth": 1.13, "limb": 1.08, "skin": "c18a65", "hair": "473027"},
]
static var next_model := 0

static func uniform_body(material: Material, woman := false) -> MeshInstance3D:
	# Same ring construction as Dante's overshirt: shoulder width is retained
	# up to the sleeve joint instead of tapering into a capsule's rounded tip.
	var rings := [Vector4(-.20, .16, .145, 0), Vector4(-.08, .17, .16, 0), Vector4(.12, .175, .15, 0), Vector4(.20, .18, .12, 0), Vector4(.25, .065, .06, 0)]
	if woman:
		# Tailoring stays under the same duty belt, pockets and ballistic vest.
		rings[0].y *= 1.04
		rings[1].y *= .90
		rings[3].y *= .96
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size() - 1):
		for column in 16:
			for corner in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var ring: Vector4 = rings[row + corner.y]
				var angle := float(column + corner.x) / 16.0 * TAU
				surface.add_vertex(Vector3(sin(angle) * ring.y, ring.x, cos(angle) * ring.z))
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	return mesh

static func prepare(actor: Node) -> void:
	if actor.has_meta("police_appearance"): return
	var index: int = actor.appearance_model
	if index < 0:
		index = next_model
		next_model = (next_model + 1) % PROFILES.size()
	index = posmod(index, PROFILES.size())
	actor.appearance_model = index
	actor.set_meta("appearance_variant", index)
	actor.set_meta("police_appearance", PROFILES[index])
	actor.set_meta("appearance_female", PROFILES[index].get("woman", false))

static func apply(actor: Node) -> void:
	var profile: Dictionary = actor.get_meta("police_appearance")
	actor.model_root.scale = Vector3(1.0, profile.height, 1.0)
	actor.torso_node.scale = Vector3(profile.width, 1.0, profile.depth)
	for upper: Node3D in [actor.left_upper_arm, actor.right_upper_arm]:
		upper.position.x *= profile.width
		# NPCCombatRig transfers thickness onto meshes before its grip solver.
		upper.scale = Vector3(profile.limb, 1.0, profile.limb)
	for upper: Node3D in [actor.left_upper_leg, actor.right_upper_leg]:
		upper.position.x *= lerpf(1.0, profile.width, 0.45)
		var thickness := Vector3(profile.limb, 1.0, profile.limb)
		for child in upper.get_children():
			if child is MeshInstance3D: child.scale *= thickness
		var lower: Node3D = actor.left_lower_leg if upper == actor.left_upper_leg else actor.right_lower_leg
		for child in lower.get_children():
			if child is MeshInstance3D: child.scale *= thickness
	var index: int = actor.appearance_model
	actor.head_node.scale.x *= 0.95 + (index % 4) * 0.035
	var detail := preload("res://characters/pedestrians/CitizenDetails.gd")
	var head: Node3D = actor.head_node
	var hair := Color(profile.hair)
	if profile.get("woman", false):
		# Refine the face within the fitted cap/helmet, without scaling headwear.
		var face := head.get_node_or_null("CitizenFace") as Node3D
		if face: face.scale *= Vector3(.92, .96, 1.0)
		_woman_hair(head, hair, profile.hairstyle)
		return
	# Short sideburns remain below the issued cap/helmet.
	for side in [-1, 1]:
		detail.piece(head, Vector3(.027, .092, .10), Vector3(side * .155, .035, .014), hair, true)
	if index in [2, 6, 8]:
		detail.piece(head, Vector3(.102, .026, .025), Vector3(0, -.055, -.177), hair, true)
	elif index in [3, 5, 9]:
		detail.piece(head, Vector3(.145, .066, .095), Vector3(0, -.111, -.091), hair, true)

static func _woman_hair(head: Node3D, color: Color, style: String) -> void:
	# One material/mesh batch, no new viewport or animation process. The hair
	# follows the existing head joint and fits beneath every issued headpiece.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces := [
		[Vector3(.31, .22, .23), Vector3(0, .025, .075)],
		[Vector3(.05, .15, .13), Vector3(-.147, .005, .015)],
		[Vector3(.05, .15, .13), Vector3(.147, .005, .015)],
	]
	match style:
		"bun": pieces.append([Vector3(.15, .14, .15), Vector3(0, -.045, .195)])
		"ponytail": pieces.append([Vector3(.085, .22, .095), Vector3(0, -.12, .19)])
		_: pieces.append([Vector3(.29, .12, .17), Vector3(0, -.085, .095)])
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	for piece: Array in pieces:
		surface.append_from(sphere, 0, Transform3D(Basis.from_scale(piece[0]), piece[1]))
	var mesh := MeshInstance3D.new()
	mesh.name = "ServiceHair"
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .9
	mesh.material_override = material
	head.add_child(mesh)

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


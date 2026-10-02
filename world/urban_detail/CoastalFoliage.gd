@tool
extends RefCounted
## Shared opaque foliage: rounded lobes and subtle facet colours, no frame work.
static var meshes: Dictionary = {}

static func mesh(variant: int) -> ArrayMesh:
	variant = posmod(variant, 3)
	if meshes.has(variant): return meshes[variant]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SIDES := 12
	const RINGS := 8
	for ring in RINGS:
		for side in SIDES:
			var a := _point(ring, side, variant)
			var b := _point(ring + 1, side, variant)
			var c := _point(ring + 1, side + 1, variant)
			var d := _point(ring, side + 1, variant)
			var tint := Color.WHITE.darkened(float(posmod(side * 7 + ring * 3 + variant, 5)) * .025)
			for vertex in [a, b, c, a, c, d]:
				surface.set_color(tint)
				surface.add_vertex(vertex)
	surface.generate_normals()
	var result := surface.commit()
	meshes[variant] = result
	return result

static func _point(ring: int, side: int, variant: int) -> Vector3:
	var latitude := PI * float(ring) / 8.0
	var angle := TAU * float(side) / 12.0
	var phase := float(variant) * 1.7
	var lobes := 1.0 + .13 * sin(angle * 3.0 + phase + latitude * 2.0) + .07 * cos(angle * 5.0 - latitude * 3.0)
	return Vector3(sin(latitude) * cos(angle) * lobes, cos(latitude), sin(latitude) * sin(angle) * lobes)

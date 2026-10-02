extends RefCounted
## Shared opaque crowns: irregular outline and small leaf-colour facets.
static var cache: Dictionary = {}

static func mesh(variant: int) -> ArrayMesh:
	variant=posmod(variant,5)
	if cache.has(variant): return cache[variant]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in 10:
		for side in 14:
			var a := _point(ring,side,variant)
			var b := _point(ring+1,side,variant)
			var c := _point(ring+1,side+1,variant)
			var d := _point(ring,side+1,variant)
			var shade := float(posmod(ring*19+side*7+variant*11,13))/12.0
			for vertex in [a,b,c,a,c,d]:
				t.set_color(Color("d1d8b1").lerp(Color.WHITE,shade).darkened((1-shade)*.10))
				t.add_vertex(vertex)
	t.generate_normals()
	var result := t.commit()
	cache[variant]=result
	return result

static func _point(ring: int, side: int, variant: int) -> Vector3:
	var v := PI*float(ring)/10.0
	var a := TAU*float(posmod(side,14))/14.0
	var phase := float(variant)*1.3
	var edge := 1.0+.16*sin(a*5+v*3+phase)+.08*cos(a*7-v*4+phase)
	var y := cos(v)+.075*sin(a*4+phase)*sin(v)
	return Vector3(sin(v)*cos(a)*edge,y,sin(v)*sin(a)*edge)

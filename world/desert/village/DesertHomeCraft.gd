extends RefCounted
## Shared static joinery: rounded edges with real normals, without per-frame work.
static var _meshes: Dictionary = {}
static var _plaster: Texture2D

static func plaster_texture() -> Texture2D:
	if _plaster!=null: return _plaster
	var pixels := Image.create_empty(64,64,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new()
	random.seed=19473
	for y in 64:
		for x in 64:
			var value := .94+random.randf_range(-.045,.045)+sin(x*.38+sin(y*.21))*.018
			pixels.set_pixel(x,y,Color(value,value,value))
	pixels.generate_mipmaps()
	_plaster=ImageTexture.create_from_image(pixels)
	return _plaster

static func rounded_box(size: Vector3, radius: float) -> ArrayMesh:
	var key := str(size)+":"+str(radius)
	if _meshes.has(key): return _meshes[key]
	var half := size*.5
	var bevel := minf(radius,minf(half.x,minf(half.y,half.z))*.85)
	var inner := half-Vector3.ONE*bevel
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Grid lines include the exact bevel boundaries; broad faces stay flat.
	for normal in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		var u: Vector3=Vector3.UP if absf(normal.y)<.5 else Vector3.BACK
		var v: Vector3=normal.cross(u)
		var hu := absf(u.dot(half))
		var hv := absf(v.dot(half))
		var us := [-hu,-hu+bevel,hu-bevel,hu]
		var vs := [-hv,-hv+bevel,hv-bevel,hv]
		for row in 3:
			for column in 3:
				for corner in [Vector2i(0,0),Vector2i(1,1),Vector2i(1,0),Vector2i(0,0),Vector2i(0,1),Vector2i(1,1)]:
					var raw: Vector3=normal*absf(normal.dot(half))+u*us[column+corner.x]+v*vs[row+corner.y]
					var core := raw.clamp(-inner,inner)
					var n := (raw-core).normalized()
					surface.set_normal(n)
					surface.set_uv(Vector2(raw.dot(u),raw.dot(v)))
					surface.add_vertex(core+n*bevel)
	var result := surface.commit()
	_meshes[key]=result
	return result

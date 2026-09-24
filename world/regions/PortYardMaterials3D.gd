extends RefCounted

## Shared world-tiled concrete for the working port apron.
static var _concrete: StandardMaterial3D

static func concrete() -> StandardMaterial3D:
	if _concrete != null: return _concrete
	var image := Image.create(256,256,false,Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 90612
	noise.frequency = .035
	for y in 256:
		for x in 256:
			var stain := noise.get_noise_2d(float(x),float(y))
			var grit := noise.get_noise_2d(float(x)*3.4+31.0,float(y)*3.4)
			var joint := .72 if x % 128 < 2 or y % 128 < 2 else 1.0
			var track_x := (x >= 39 and x < 45) or (x >= 60 and x < 66)
			var tracks := .88 if track_x and y % 128 > 22 and y % 128 < 112 else 1.0
			var value := clampf((.90+stain*.12+grit*.045)*joint*tracks,.62,1.05)
			image.set_pixel(x,y,Color(.34*value,.36*value,.35*value))
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_texture = ImageTexture.create_from_image(image)
	_concrete.uv1_triplanar = true
	_concrete.uv1_world_triplanar = true
	_concrete.uv1_scale = Vector3.ONE / 8.0
	_concrete.roughness = .94
	_concrete.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _concrete

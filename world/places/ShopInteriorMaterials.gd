extends RefCounted
## Small shared mipmapped tiles; generated once, no per-frame material work.
static var _textures: Dictionary = {}
static var _materials: Dictionary = {}

static func material(kind: String, color: Color) -> StandardMaterial3D:
	var key := kind + color.to_html()
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.albedo_texture = texture(kind)
	result.roughness = .94 if kind == "cloth" else .82
	result.uv1_triplanar = true
	result.uv1_scale = Vector3(1.4, 1.4, 1.4) if kind == "wood" else Vector3.ONE * 2.0
	_materials[key] = result
	return result

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61722
	for y in 64:
		for x in 64:
			var value := .92 + rng.randf_range(-.035, .035)
			if kind == "wood":
				value += sin(x * .82 + sin(y * TAU / 64.0) * .65) * .045
				value += sin(x * .29) * .035
			elif kind == "cloth":
				value += .025 if (x + y) % 2 == 0 else -.025
			elif kind == "stone":
				var row := floori(y / 16.0)
				if y % 16 < 1 or (x + (16 if row % 2 else 0)) % 32 < 1: value -= .20
				value += sin(floorf((x + row * 16) / 32.0) * 6.4 + row * 3.5) * .045
			image.set_pixel(x, y, Color(value, value, value))
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_textures[kind] = result
	return result

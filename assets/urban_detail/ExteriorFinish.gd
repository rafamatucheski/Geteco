extends RefCounted
## Shared metric finishes. Local projection on vehicles keeps paint attached
## to the body; world projection on buildings preserves scale across instances.
static var _textures: Dictionary = {}
static var _materials: Dictionary = {}

static func material(kind: String, tint: Color, world_space := true) -> StandardMaterial3D:
	var key := kind + tint.to_html() + str(world_space)
	if _materials.has(key): return _materials[key]
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.albedo_texture = texture(kind)
	result.roughness = .68 if kind == "paint" else .9
	result.uv1_triplanar = true
	result.uv1_world_triplanar = world_space
	result.uv1_scale = Vector3.ONE / 4.0
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_materials[key] = result
	return result

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41011
	for y in 256:
		for x in 256:
			var tone := .96 + rng.randf_range(-.018, .018)
			if kind == "tile":
				# 0.25 x 0.5 m courses, staggered and periodic over four metres.
				var row := floori(y / 16.0)
				var across := (x + (16 if row % 2 else 0)) % 32
				var course := y % 16
				tone -= .07 * sin(float(across) / 32.0 * PI)
				if across < 2 or course < 2: tone -= .25
				elif course < 4: tone += .025
			elif kind == "roof":
				# Painted metal sheets: broad panels and narrow sealed seams.
				tone -= .035 * (sin(x * TAU / 256.0) * sin(y * TAU / 128.0) + 1.0)
				if y % 64 < 2: tone -= .16
				elif y % 64 < 4: tone += .025
			else:
				# Fine painted finish; no artificial masonry grid on metal fascia.
				tone -= .025 * (sin(x * TAU / 256.0) * cos(y * TAU / 256.0) + 1.0)
			image.set_pixel(x, y, Color(tone, tone, tone))
	image.generate_mipmaps()
	var result := ImageTexture.create_from_image(image)
	_textures[kind] = result
	return result

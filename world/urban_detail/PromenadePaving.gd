@tool
extends RefCounted
static var tile: Texture2D
static var materials: Dictionary = {}

static func material(tint: Color, world_projection := false) -> StandardMaterial3D:
	var key := tint.to_html() + str(world_projection)
	if materials.has(key): return materials[key]
	if tile == null:
		var image := Image.create_empty(256,256,false,Image.FORMAT_RGB8)
		var noise := FastNoiseLite.new()
		noise.seed = 73129
		noise.frequency = 1.0
		# Periodic coordinates give continuous concrete without a visible tile grid.
		for y in 256:
			for x in 256:
				var a := TAU * float(x) / 256.0
				var b := TAU * float(y) / 256.0
				var periodic := Vector3((3.0 + cos(b)) * cos(a), (3.0 + cos(b)) * sin(a), sin(b))
				var wear := noise.get_noise_3dv(periodic * 2.1)
				var grain := noise.get_noise_3dv(periodic * 34.0)
				var aggregate := maxf(0.0, -grain - .18)
				var tone := .88 + wear * .085 + grain * .055 - aggregate * .06
				# Four-metre tile: one-metre slabs with 3 cm recessed joints.
				# Keep the grid aligned to the existing road/world UVs at chunk seams.
				var cell_x := floori(x / 64.0)
				var cell_y := floori(y / 64.0)
				tone += sin(cell_x * 13.7 + cell_y * 9.1) * .035
				if x % 64 < 2 or y % 64 < 2: tone -= .18
				elif x % 64 < 4 or y % 64 < 4: tone += .025
				image.set_pixel(x,y,Color(tone * 1.008,tone,tone * .986))
		image.generate_mipmaps()
		tile = ImageTexture.create_from_image(image)
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.albedo_texture = tile
	result.roughness = .92
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if world_projection:
		result.uv1_triplanar = true
		result.uv1_world_triplanar = true
		result.uv1_scale = Vector3.ONE * .25
	materials[key] = result
	return result

@tool
extends RefCounted
## One mineral paving finish for Harbor sidewalks, courts and building lots.
## World projection keeps the one-metre joints aligned across roads/chunks.
const COLOR := Color("aaa9a1")
const EDGE_COLOR := Color("878d88")
static var _tile: Texture2D
static var _lawn_tile: Texture2D
static var _materials: Dictionary = {}

static func material(tint := COLOR) -> StandardMaterial3D:
	var key := tint.to_html()
	if _materials.has(key): return _materials[key]
	if _tile == null:
		var image := Image.create(256,256,false,Image.FORMAT_RGB8)
		var noise := FastNoiseLite.new()
		noise.seed = 13102026
		noise.frequency = 1.0
		for y in 256:
			for x in 256:
				var a := TAU * float(x) / 256.0
				var b := TAU * float(y) / 256.0
				var periodic := Vector3((3.0+cos(b))*cos(a),(3.0+cos(b))*sin(a),sin(b))
				var grain := noise.get_noise_3dv(periodic*28.0)
				var mineral := noise.get_noise_3dv(periodic*3.0)
				# Three-centimetre recessed joints survive the gameplay mip level;
				# adjacent slabs keep the same tone instead of a checkerboard.
				var tone := .89 + grain*.055 + mineral*.025
				if x%64 < 2 or y%64 < 2: tone -= .30
				elif x%64 == 2 or y%64 == 2: tone -= .065
				image.set_pixel(x,y,Color(tone,tone,tone))
		image.generate_mipmaps()
		_tile = ImageTexture.create_from_image(image)
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.albedo_texture = _tile
	result.roughness = .94
	result.metallic_specular = .12
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	result.uv1_scale = Vector3.ONE*.25
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = result
	return result


static func lawn_material(tint: Color) -> StandardMaterial3D:
	var key := "lawn/"+tint.to_html()
	if _materials.has(key): return _materials[key]
	if _lawn_tile == null:
		var image := Image.create(256,256,false,Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 14102026
		# Two-metre tile. Fine blades occupy centimetres, never large wavy
		# noise contours; random directions avoid the old woven-fabric pattern.
		for y in 256:
			for x in 256:
				var shade := .78+rng.randf_range(-.025,.025)
				image.set_pixel(x,y,Color(shade*.97,shade,shade*.94))
		for blade in 9000:
			var start := Vector2(rng.randi_range(0,255),rng.randi_range(0,255))
			var direction := Vector2.from_angle(rng.randf()*TAU)
			var length := rng.randi_range(2,5)
			var shade := rng.randf_range(.72,.88)
			for step in length:
				var point := start+direction*float(step)
				image.set_pixel(posmod(roundi(point.x),256),posmod(roundi(point.y),256),Color(shade*.95,shade,shade*.90))
		image.generate_mipmaps()
		_lawn_tile = ImageTexture.create_from_image(image)
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.albedo_texture = _lawn_tile
	result.roughness = 1.0
	result.metallic_specular = .08
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	result.uv1_scale = Vector3.ONE*.5
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = result
	return result

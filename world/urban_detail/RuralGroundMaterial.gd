extends RefCounted
## Shared mipmapped earth and grass, continuous across roads and nearby yards.
static var _material: ShaderMaterial
static func material() -> ShaderMaterial:
	if _material != null: return _material
	var noise := FastNoiseLite.new()
	noise.seed = 92826
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = .018
	noise.fractal_octaves = 4
	var colors := Gradient.new()
	colors.set_color(0,Color("594932"))
	colors.set_color(1,Color("92734d"))
	colors.add_point(.55,Color("796143"))
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.seamless = true
	texture.generate_mipmaps = true
	texture.noise = noise
	texture.color_ramp = colors
	_material = ShaderMaterial.new()
	_material.shader = preload("res://world/urban_detail/rural_ground.gdshader")
	_material.set_shader_parameter("earth_texture",texture)
	_material.set_shader_parameter("grass_texture",preload("res://world/urban_detail/HarborGrassTufts.gd").ground_material("grass").albedo_texture)
	return _material

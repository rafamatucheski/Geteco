extends RefCounted
## Offline albedos shared by native woodland, access roads and their shoulders.
## One owner per surface; no procedural texture workers or extra finish planes.
static var _material: ShaderMaterial
static func material() -> ShaderMaterial:
	if _material != null: return _material
	_material = ShaderMaterial.new()
	_material.shader = preload("res://world/urban_detail/rural_ground.gdshader")
	_material.set_shader_parameter("earth_texture",preload("res://assets/materials/woodland/earth.png"))
	_material.set_shader_parameter("grass_texture",preload("res://assets/materials/woodland/woodland.png"))
	return _material

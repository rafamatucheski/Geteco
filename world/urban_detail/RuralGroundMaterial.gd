extends RefCounted
## Albedos offline compartilhados pelo bosque nativo, estradas de acesso e acostamentos.
## Um dono por superfície; sem workers de textura procedural nem planos de acabamento extras.
static var _material: ShaderMaterial
static func material() -> ShaderMaterial:
	if _material != null: return _material
	_material = ShaderMaterial.new()
	_material.shader = preload("res://world/urban_detail/rural_ground.gdshader")
	_material.set_shader_parameter("earth_texture",preload("res://assets/materials/woodland/earth.png"))
	_material.set_shader_parameter("grass_texture",preload("res://assets/materials/woodland/woodland.png"))
	return _material

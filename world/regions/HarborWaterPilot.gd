extends RefCounted
## Piloto de autoria em volta do cais sul. Mantém o resto do Harbor igual.
## Os shaders fazem fade para a água original através do limite interno de 24 m.
const BOUNDS := Rect2(128.0, 128.0, 192.0, 192.0)
const SURFACE := preload("res://world/regions/harbor_water_pilot.gdshader")
const SHORE := preload("res://world/regions/harbor_shore_pilot.gdshader")
static var enabled := false

static func includes_chunk(rect: Rect2) -> bool:
	return enabled and BOUNDS.intersects(rect)

static func make_material(shader: Shader) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = shader
	return result

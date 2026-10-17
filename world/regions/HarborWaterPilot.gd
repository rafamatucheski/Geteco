extends RefCounted
## Authoring pilot around the southern quay. Keep the rest of Harbor unchanged.
## The shaders fade to the original water across the inner 24 m boundary.
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

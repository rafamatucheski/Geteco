@tool
extends RefCounted
## Shared mineral finishes, projected in world space across chunk boundaries.
const COLOR := Color("a0abb1")
const EDGE_COLOR := Color("76786b")
# Offline textures are explicit export dependencies and shared across chunks.
const TILES := {
	"concrete": preload("res://assets/materials/harbor_paving/concrete.png"),
	"service": preload("res://assets/materials/harbor_paving/service.png"),
	"limestone": preload("res://assets/materials/harbor_paving/limestone.png"),
	"brick": preload("res://assets/materials/harbor_paving/brick.png"),
	"quay": preload("res://assets/materials/harbor_paving/quay.png"),
}
static var _lawn_tile: Texture2D
static var _materials: Dictionary = {}

const FINISH_COLORS := {"concrete": COLOR, "service": Color("777d7a"), "limestone": Color("85877f"), "brick": Color("696258"), "quay": Color("787f7d")}

static func material(tint := COLOR, finish: String = "concrete") -> StandardMaterial3D:
	var key := finish + "/" + tint.to_html()
	if _materials.has(key): return _materials[key]

	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.albedo_texture = TILES.get(finish,TILES.concrete)
	result.roughness = .94
	result.metallic_specular = .12
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	result.uv1_scale = Vector3.ONE / (8.0 if finish == "concrete" else 4.0 if finish == "brick" else 16.0)
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

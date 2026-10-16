@tool
extends RefCounted
## A mesma instância recebe chuva e reflexo costeiro em cidade, ponte e estrada.
## A projeção em coordenadas globais atravessa os limites sem reiniciar textura.
const SHADER := preload("res://world/urban_detail/coastal_wet_asphalt.gdshader")
static var _material: ShaderMaterial
static var _aggregate: Texture2D
static var _roughness: Texture2D

static func material() -> ShaderMaterial:
	if _material != null: return _material
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("base_texture", aggregate())
	_material.set_shader_parameter("roughness_texture", roughness())
	return _material

static func aggregate() -> Texture2D:
	if _aggregate != null: return _aggregate
	var image := Image.create(128,128,false,Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 2147
	noise.frequency = 1.0
	for y in 128:
		for x in 128:
			var a := TAU*float(x)/128.0
			var b := TAU*float(y)/128.0
			var periodic := Vector3((2.0+cos(b))*cos(a),(2.0+cos(b))*sin(a),sin(b))
			var grain := noise.get_noise_3dv(periodic*9.0)
			var aggregate_value := noise.get_noise_3dv(periodic*23.0+Vector3(29,0,11))
			var wear := clampf(.80+grain*.085+aggregate_value*.045,.65,.94)
			image.set_pixel(x,y,Color(.19*wear,.205*wear,.22*wear))
	image.generate_mipmaps()
	_aggregate = ImageTexture.create_from_image(image)
	return _aggregate

static func roughness() -> Texture2D:
	if _roughness != null: return _roughness
	var image := Image.create(128,128,false,Image.FORMAT_L8)
	var noise := FastNoiseLite.new()
	noise.seed = 13102026
	noise.frequency = 1.0
	for y in 128:
		for x in 128:
			var a := TAU*float(x)/128.0
			var b := TAU*float(y)/128.0
			var periodic := Vector3((2.0+cos(b))*cos(a),(2.0+cos(b))*sin(a),sin(b))
			var basin := noise.get_noise_3dv(periodic*.72)
			var edge := noise.get_noise_3dv(periodic*2.1+Vector3(17,3,11))
			var value := lerpf(.95,1.0,smoothstep(-.40,.40,basin+edge*.08))
			image.set_pixel(x,y,Color(value,value,value))
	image.generate_mipmaps()
	_roughness = ImageTexture.create_from_image(image)
	return _roughness

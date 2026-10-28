extends RefCounted
## Pinturas do interior dos bares (tools/build_bar_textures.py): piso, paredes, frente do balcão,
## estante, quadros, neon, alvo e feltro, em quadros planos colados nas superfícies das caixas.
##
## Por que quadros e não textura nas caixas: o BoxMesh espalha as seis faces num atlas 3 x 2, e a
## pintura precisa cair inteira numa face só. O material repete o da folha de porta do kit pintado
## (só albedo, rugosidade e filtro anisotrópico; a repetição em `uv1_scale` é uniforme), que o
## PaintedFacadePrewarm já compila: nenhuma variante de shader nova ao entrar.
## Interruptor: o mesmo GETECO_PAINTED_FACADES=0 do kit volta às caixas lisas (A/B).
const ROOT := "res://assets/places/bars/"
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
## Afastamento das superfícies: parede pintada e, na frente dela, quadros.
const LIFT := .005
static var _materials := {}


static func available(prefix: String) -> bool:
	return KIT.enabled() and ResourceLoader.exists(ROOT + prefix + "_wall.jpg")


static func material(texture: String, tiles := Vector2.ONE) -> StandardMaterial3D:
	var key := texture + str(tiles)
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ROOT + texture + ".jpg")
	mat.roughness = .88
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.uv1_scale = Vector3(tiles.x, tiles.y, 1)
	_materials[key] = mat
	return mat


## Quadro vertical de `size` (largura x altura) com centro em `at`, olhando para `yaw`
## (0 = +Z, PI*.5 = +X, -PI*.5 = -X, PI = -Z).
static func panel(parent: Node3D, texture: String, at: Vector3, size: Vector2, yaw := 0.0, tiles := Vector2.ONE) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Painted_" + texture
	var quad := QuadMesh.new()
	quad.size = size
	node.mesh = quad
	node.position = at
	node.rotation.y = yaw
	node.material_override = material(texture, tiles)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## Quadro deitado (piso, feltro) de `size` em X e Z, olhando para cima.
static func flat(parent: Node3D, texture: String, at: Vector3, size: Vector2, tiles := Vector2.ONE) -> MeshInstance3D:
	var node := panel(parent, texture, at, size, 0.0, tiles)
	node.rotation = Vector3(-PI*.5, 0, 0)
	return node


## Piso e as quatro paredes de uma sala de 16 x 12 m (paredes de 0,24 m e 3,3 m de altura) com
## a porta de `door_half` de meia largura no meio da frente. Repetição a cada 2 m.
static func shell(parent: Node3D, prefix: String, door_half: float) -> void:
	var inner := Vector2(7.76, 5.76)
	flat(parent, prefix + "_floor", Vector3(0, .003, 0), inner*2, inner)
	var height := 3.3
	panel(parent, prefix + "_wall", Vector3(0, height*.5, -inner.y+LIFT), Vector2(inner.x*2, height), 0.0, Vector2(inner.x, height*.5))
	panel(parent, prefix + "_wall", Vector3(-inner.x+LIFT, height*.5, 0), Vector2(inner.y*2, height), PI*.5, Vector2(inner.y, height*.5))
	panel(parent, prefix + "_wall", Vector3(inner.x-LIFT, height*.5, 0), Vector2(inner.y*2, height), -PI*.5, Vector2(inner.y, height*.5))
	var front_w := inner.x-door_half
	for side in [-1, 1]:
		panel(parent, prefix + "_wall", Vector3(side*(door_half+front_w*.5), height*.5, inner.y-LIFT), Vector2(front_w, height), PI, Vector2(front_w*.5, height*.5))

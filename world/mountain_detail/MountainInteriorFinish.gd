extends RefCounted
## Acabamento dos interiores da serra com textura de verdade (concreto de fôrma, bloco, piso
## epóxi, chapa pintada descascando, tecido, tábua). Antes os interiores eram caixas de cor lisa
## e liam como maquete: o pedido de 27/10 foi "textura interna antiga, mal detalhada".
##
## As imagens são neutras (cinza) e a cor do material as tinge: um conjunto de mapas serve todas
## as cores. O ganho divide pela luminância média de cada imagem (medida uma vez com PIL), para a
## paleta autorada não escurecer. UV triplanar em metros de mundo, como o UrbanSurfaces: o mesmo
## conjunto de recursos de shader (albedo + normal + rugosidade, triplanar de mundo, filtro linear
## com mipmaps) que a serra inteira já desenha, então nenhum shader novo compila ao entrar.

const BLOCK_ALBEDO := preload("res://assets/materials/digo_workshop/block_albedo.png")
const BLOCK_NORMAL := preload("res://assets/materials/digo_workshop/block_normal.png")
const BLOCK_ROUGH := preload("res://assets/materials/digo_workshop/block_roughness.png")
const EPOXY_ALBEDO := preload("res://assets/materials/digo_workshop/epoxy_albedo.png")
const EPOXY_NORMAL := preload("res://assets/materials/digo_workshop/epoxy_normal.png")
const EPOXY_ROUGH := preload("res://assets/materials/digo_workshop/epoxy_roughness.png")
const CAST_ALBEDO := preload("res://assets/prologue/concrete_albedo.png")
const CAST_NORMAL := preload("res://assets/prologue/concrete_normal.png")
const PAINTED_ALBEDO := preload("res://assets/prologue/painted_albedo.png")
const PAINTED_NORMAL := preload("res://assets/prologue/painted_normal.png")
const FABRIC_ALBEDO := preload("res://assets/prologue/fabric_albedo.png")
const FABRIC_NORMAL := preload("res://assets/prologue/fabric_normal.png")
const WOOD_ALBEDO := preload("res://assets/prologue/wood_albedo.png")
const WOOD_NORMAL := preload("res://assets/prologue/wood_normal.png")
const PLASTER_ALBEDO := preload("res://assets/prologue/plaster_albedo.png")
const PLASTER_NORMAL := preload("res://assets/prologue/plaster_normal.png")
const SLAB_ALBEDO := preload("res://assets/materials/bridge/concrete_albedo.png")
const SLAB_NORMAL := preload("res://assets/materials/bridge/concrete_normal.png")
## Rugosidade genérica para as imagens que não trazem a sua.
const CONCRETE_ROUGH := preload("res://assets/materials/bridge/concrete_roughness.png")

## [albedo, normal, rugosidade, luminância média (sRGB), metros por repetição, força do relevo]
const KINDS := {
	"block": [BLOCK_ALBEDO, BLOCK_NORMAL, BLOCK_ROUGH, .707, 1.6, .45],
	"epoxy": [EPOXY_ALBEDO, EPOXY_NORMAL, EPOXY_ROUGH, .485, 4.0, .26],
	"slab": [SLAB_ALBEDO, SLAB_NORMAL, CONCRETE_ROUGH, .489, 3.0, .5],
	"cast": [CAST_ALBEDO, CAST_NORMAL, CONCRETE_ROUGH, .663, 3.2, .55],
	"painted": [PAINTED_ALBEDO, PAINTED_NORMAL, CONCRETE_ROUGH, .662, 1.8, .5],
	"fabric": [FABRIC_ALBEDO, FABRIC_NORMAL, CONCRETE_ROUGH, .665, .9, .6],
	"wood": [WOOD_ALBEDO, WOOD_NORMAL, CONCRETE_ROUGH, .664, 1.2, .7],
	"plaster": [PLASTER_ALBEDO, PLASTER_NORMAL, CONCRETE_ROUGH, .665, 2.6, .45],
}

static var _cache: Dictionary = {}

## Textura pelo nome do material autorado nos interiores (chalés, alojamento). Vazio = fica liso:
## o que brilha, vidro, latão, pelagem, papel e miudezas de cor pura.
static func kind_for(key: String) -> String:
	if _has(key, ["glass", "brass", "edison", "cavity", "copper", "flame", "bone", "fur", "snout", "paper", "mug",
			"bread", "bottle", "jar", "banker", "logbook", "rubber", "glow", "ivory", "ebony", "marker", "white"]):
		return ""
	if _has(key, ["cloth", "quilt", "pillow", "wool", "velvet", "parka", "plaid", "leather", "shade", "blanket", "linen", "rug"]):
		return "fabric"
	if _has(key, ["iron", "steel", "antenna", "radio", "ammo", "metal", "stove"]):
		return "painted"
	if _has(key, ["stone", "slate", "mortar", "hearth"]):
		return "cast"
	if _has(key, ["chink", "plaster"]):
		return "plaster"
	if _has(key, ["wood", "log", "beam", "mantel", "birch", "floor", "table", "counter", "chest", "desk", "rod", "plank", "oak", "pine", "bench", "shelf"]):
		return "wood"
	return ""


static func _has(key: String, words: Array) -> bool:
	for word in words:
		if key.contains(word): return true
	return false


## Material texturizado e cacheado por (tipo, cor, rugosidade, metal). `color` é o tom visto de
## longe; `roughness` multiplica o mapa de rugosidade.
static func material(kind: String, color: Color, roughness := .9, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s:%s:%.2f:%.2f" % [kind, color.to_html(false), roughness, metallic]
	if _cache.has(key): return _cache[key]
	var maps: Array = KINDS[kind]
	var gain := 1.0 / float(maps[3])
	var result := StandardMaterial3D.new()
	result.resource_name = "mountain_interior_" + kind
	result.albedo_texture = maps[0]
	result.albedo_color = Color(minf(color.r * gain, 1.0), minf(color.g * gain, 1.0), minf(color.b * gain, 1.0))
	result.normal_enabled = true
	result.normal_texture = maps[1]
	result.normal_scale = float(maps[5])
	result.roughness_texture = maps[2]
	result.roughness = roughness
	result.metallic = metallic
	result.uv1_triplanar = true
	result.uv1_world_triplanar = true
	result.uv1_scale = Vector3.ONE / float(maps[4])
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_cache[key] = result
	return result

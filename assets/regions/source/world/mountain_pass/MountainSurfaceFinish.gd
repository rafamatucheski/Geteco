extends RefCounted
## Acabamento de superfície dos prédios e props da montanha de gelo. O reboco genérico
## (um só mapa para madeira, telhado, pedra e neve) ainda lia como plano chapado: aqui
## cada material recebe o mapa do seu papel (tábua, telha, pedra, metal, neve, tecido)
## do UrbanSurfaces, em espaço de mundo, mantendo o tom que o material já tinha.

const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")

## Tipo de superfície pelo nome do material. Vazio = não mexe (pelagem, couro, papel...).
static func kind_for(id: String, metallic := 0.0) -> String:
	var key := id.to_lower()
	if _has(key, ["fur", "leather", "bone", "paper", "bread", "jar", "bottle", "mug", "pillow", "quilt", "blanket", "velvet", "rubber", "snout", "antler", "flame", "glow", "lamp", "glass", "screen", "cavity", "soot"]):
		return ""
	if metallic > 0.1 or _has(key, ["metal", "iron", "steel", "brass", "copper", "gold", "strap", "blade", "antenna", "grindstone"]):
		return "metal"
	if _has(key, ["snow"]):
		return "snow"
	if _has(key, ["roof", "shingle", "slate"]):
		return "shingle"
	if _has(key, ["paving", "cobble"]):
		return "paving"
	if _has(key, ["stone", "rock", "found", "chimney", "plinth", "brick"]):
		return "granite"
	if _has(key, ["concrete"]):
		return "concrete"
	if _has(key, ["dirt", "earth"]):
		return "gravel"
	if _has(key, ["sawdust", "plaster"]):
		return "plaster"
	if _has(key, ["cloth", "fabric", "tarp", "awning", "wool", "plaid", "parka", "canvas"]):
		return "fabric"
	if _has(key, ["wood", "timber", "log", "plank", "board", "beam", "bark", "door", "shutter", "pole", "bench", "fence", "trim", "post", "cut_end", "sign", "deck", "wall", "floor", "chalet", "cabin", "table", "desk", "chest", "crate", "mantel", "birch", "pine", "ski", "mud"]):
		return "wood"
	return ""


static func _has(key: String, words: Array) -> bool:
	for word in words:
		if key.contains(word):
			return true
	return false


## Aplica o mapa do tipo ao material (idempotente). `kind` vazio infere pelo `id`.
## Devolve o mesmo material. O ganho que compensa a luminância da textura fica em
## "tone_gain": quem recolorir depois (set_main_color) deve multiplicar a cor por ele.
static func apply(mat: StandardMaterial3D, id: String, kind := "") -> StandardMaterial3D:
	if mat.has_meta("tone_gain"):
		return mat
	if mat.emission_enabled or mat.albedo_color.a < 1.0 or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return mat
	var surface := kind if not kind.is_empty() else kind_for(id, mat.metallic)
	if surface.is_empty():
		return mat
	var color := mat.albedo_color
	var roughness := mat.roughness
	# Telha, tábua e pedra pedem escala menor que o reboco para o desenho aparecer da câmera alta.
	var tile := 1.6 if surface in ["wood", "shingle", "fabric"] else (3.0 if surface == "snow" else 2.0)
	var bump := 0.55 if surface == "snow" else (0.8 if surface in ["shingle", "granite", "paving"] else 1.0)
	SURFACES.detail(mat, surface, tile, bump)
	var gain: float = mat.albedo_color.r
	mat.albedo_color = Color(minf(color.r * gain, 1.0), minf(color.g * gain, 1.0), minf(color.b * gain, 1.0))
	mat.roughness = roughness if surface == "metal" else maxf(roughness, 0.9)
	mat.set_meta("tone_gain", gain)
	return mat

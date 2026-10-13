extends RefCounted
## Acabamento de árvores, cactos e arbustos: copa de folhagem, tronco de casca e cacto de
## costelas, no mesmo mapa do UrbanSurfaces da montanha. As malhas de flora levam a cor no
## vértice (variação por planta), então o mapa neutro só multiplica essa cor: o tom que a
## planta já tinha é mantido e o desenho aparece de perto.

const SURFACES := preload("res://assets/urban_detail/UrbanSurfaces.gd")
static var _cache: Dictionary = {}


## Material de flora com cor no vértice. `tint` é a cor do material (branco quando a cor
## vem toda do vértice); o ganho da textura é compensado para não escurecer.
static func material(kind: String, tint := Color.WHITE, tile := 1.6, bump := 1.0, roughness := 0.95, srgb_vertex := false) -> StandardMaterial3D:
	var key := "%s:%s:%s" % [kind, tint.to_html(true), srgb_vertex]
	if _cache.has(key):
		return _cache[key]
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = srgb_vertex
	SURFACES.detail(mat, kind, tile, bump)
	var gain := mat.albedo_color.r
	mat.albedo_color = Color(minf(tint.r * gain, 1.0), minf(tint.g * gain, 1.0), minf(tint.b * gain, 1.0))
	mat.roughness = roughness
	mat.metallic_specular = 0.0
	_cache[key] = mat
	return mat


## Copa: folhas em tufos, tom da árvore no `tint`, variação por faceta no vértice.
static func foliage(tint: Color) -> StandardMaterial3D:
	return material("foliage", tint, 1.2, 0.9)


## Tronco e galhos: casca sulcada; cor no vértice.
static func bark() -> StandardMaterial3D:
	return material("bark", Color.WHITE, 1.4, 1.1, 0.97, true)


## Cacto e plantas secas do deserto: costelas verticais e pintas de espinho.
static func cactus() -> StandardMaterial3D:
	return material("cactus", Color.WHITE, 1.0, 1.0, 0.9, true)

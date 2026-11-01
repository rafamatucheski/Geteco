extends RefCounted
## Decalques antigos de rua e calçada (óleo, remendo, rachadura, sujeira, bueiro, grelha) e as
## texturas procedurais deles, separados do CityChunkDressing em 01/11 (Onda 1). O sorteio
## (_roll por chave de posição) é o mesmo, na mesma ordem.
## Tudo estático, como o dono. `g` é o script do CityChunkDressing (preload cíclico, o mesmo que
## SidewalkFill/StreetJunk já fazem): o que continua no dono (_roll, _pick, _add, _push, _in_chunk,
## _context, constantes de calçada e de poste, _lamp_meshes) é lido por `g.`; o dono mantém cada
## função antiga como delegação de uma linha com a mesma assinatura, então testes e
## SidewalkFill/StreetJunk/HarborUtilityLines que chamam pelo dono não mudam.

const g := preload("res://world/city_look/CityChunkDressing.gd")
const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const BRIDGE_SURFACE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const ROAD_WEAR := preload("res://world/shared/roads/HarborRoadWear.gd")
const TABLES := preload("res://data/catalogs/CityDressingTables.gd")
const ROOF_TINTS := TABLES.ROOF_TINTS

static func _road_wear(context: Dictionary, batches: Dictionary) -> void:
	# O esgoto da polícia tem uma escotilha interativa dedicada exatamente neste ponto.
	# Mantém as tampas genéricas da rua afastadas para não sobreporem o acesso autorado.
	for road in context.roads:
		var points: PackedVector2Array = road.points
		var width: float = road.width
		var travelled := 0.0
		for index in points.size() - 1:
			var a := points[index]
			var b := points[index + 1]
			var length := a.distance_to(b)
			if length < 0.01: continue
			# Todo decalque daqui fica a menos de meia rua + calçada da amostra: trecho e amostra longe do
			# chunk não colocam nada. Pular só soma o comprimento (a fase das amostras segue igual); antes
			# cada chunk formatava e sorteava a rua inteira, mesmo os quilômetros fora dele.
			var reach := width * 0.5 + g.SIDEWALK + 1.0
			var near := (context.rect as Rect2).grow(reach)
			if not Rect2(a, Vector2.ZERO).expand(b).intersects(near, true):
				travelled += length
				continue
			var tangent := (b - a) / length
			var normal := Vector2(tangent.y, -tangent.x)
			var yaw := atan2(tangent.x, tangent.y)
			var s := fposmod(-travelled, 3.0)
			while s < length:
				var along := a + tangent * s
				if not near.has_point(along):
					s += 3.0
					continue
				var key := "%s|w|%d|%d" % [road.id, index, int(s * 10.0)]
				var roll := g._roll(key)
				# A ponte reconstruída não recebe os antigos remendos procedurais.
				if BRIDGE_SURFACE.owns_surface_point(along):
					s += 3.0
					continue
				var lane := (1.0 if g._roll(key + "l") < 0.5 else -1.0) * width * 0.25
				# Óleo, remendo, rachadura, bueiro e grelha da pista passaram para HarborRoadWear (um lote
				# com atlas). A sujeira da calçada abaixo continua igual, no mesmo sorteio.
				if roll < 0.38 and ROAD_WEAR.enabled():
					pass
				elif roll < 0.22:
					# Óleo pinga no meio da faixa, onde o carro para.
					var p := along + normal * (lane + (g._roll(key + "o") - 0.5) * 0.6)
					if g._in_chunk(context, p) and not g._near_junction(context, p, 1.0):
						var size := 0.7 + g._roll(key + "s") * 1.1
						g._push(batches, "decal:oil", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(size, 1, size * 1.5)), Vector3(p.x, g.DECAL_Y, p.y)))
				elif roll < 0.29:
					var p := along + normal * (g._roll(key + "p") - 0.5) * width * 0.6
					if g._in_chunk(context, p) and not g._near_junction(context, p, 0.0):
						var w := 1.6 + g._roll(key + "pw") * 2.4
						var h := 1.2 + g._roll(key + "ph") * 3.0
						g._push(batches, "decal:patch", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(w, 1, h)), Vector3(p.x, g.DECAL_Y - 0.002, p.y)))
				elif roll < 0.34:
					var p := along + normal * (g._roll(key + "c") - 0.5) * width * 0.7
					if g._in_chunk(context, p):
						var size := 2.5 + g._roll(key + "cs") * 3.5
						g._push(batches, "decal:crack", Transform3D(Basis(Vector3.UP, yaw + g._roll(key + "cr") * TAU).scaled(Vector3(size, 1, size)), Vector3(p.x, g.DECAL_Y + 0.001, p.y)))
				elif roll < 0.355:
					var p := along + normal * lane * 0.2
					if g._in_chunk(context, p) and not g._near_junction(context, p, 0.0) and p.distance_to(g.SEWER_ACCESS) > 1.35:
						g._add(batches, "manhole", Vector3(p.x, 0.028, p.y), tangent)
				elif roll < 0.38:
					var side := 1.0 if g._roll(key + "d") < 0.5 else -1.0
					var p := along + normal * side * (width * 0.5 - 0.25)
					if g._in_chunk(context, p) and not g._near_junction(context, p, 0.0):
						g._add(batches, "drain", Vector3(p.x, 0.028, p.y), tangent)
				elif roll < 0.46:
					# Sujeira/chiclete na calçada.
					var side := 1.0 if g._roll(key + "g") < 0.5 else -1.0
					var p := along + normal * side * (width * 0.5 + 0.4 + g._roll(key + "gd") * (g.SIDEWALK - 0.8))
					if g._in_chunk(context, p) and not g._inside_building(context, p, 0.0):
						var size := 0.5 + g._roll(key + "gs") * 1.2
						g._push(batches, "decal:grime", Transform3D(Basis.IDENTITY.scaled(Vector3(size, 1, size)), Vector3(p.x, g.DECAL_Y, p.y)))
				s += 3.0
			travelled += length


static func _decal_spec(kind: String) -> Dictionary:
	match kind:
		"contact":
			return {"material": MATERIALS.ground_decal("contact", _soft_rect_texture(), Color(0.02, 0.03, 0.04, 0.62))}
		"contact_tight":
			return {"material": MATERIALS.ground_decal("contact_tight", _soft_rect_texture(0.55), Color(0.01, 0.015, 0.02, 0.55))}
		"oil":
			return {"material": MATERIALS.ground_decal("oil", MATERIALS.alpha_blob("oil", 0.15), Color(0.02, 0.02, 0.025, 0.42))}
		"patch":
			return {"material": MATERIALS.ground_decal("patch", _soft_rect_texture(0.18), Color(0.05, 0.06, 0.07, 0.38))}
		"crack":
			return {"material": MATERIALS.ground_decal("crack", _crack_texture(), Color(0.03, 0.03, 0.035, 0.75))}
		"grime":
			return {"material": MATERIALS.ground_decal("grime", MATERIALS.alpha_blob("grime", 0.0), Color(0.12, 0.10, 0.07, 0.3))}
		"tree_pit":
			# Terra escura da gola da árvore de rua (SidewalkFill): mesmo shader dos outros decalques.
			return {"material": MATERIALS.ground_decal("tree_pit", _soft_rect_texture(0.1), Color(0.13, 0.09, 0.06, 0.88))}
		"roof_tar":
			return {"material": MATERIALS.ground_decal("roof_tar", _soft_rect_texture(0.08), Color(0.06, 0.06, 0.07, 0.45))}
	if kind.begins_with("roof_"):
		var index := kind.trim_prefix("roof_").to_int()
		return {"material": MATERIALS.ground_decal(kind, _soft_rect_texture(0.03), ROOF_TINTS[index])}
	return {"material": MATERIALS.flat(Color.MAGENTA)}


static var _textures := {}


## Retângulo de borda suave: sombra de contato (prédio) e remendo de asfalto.
## edge = fração da meia largura usada para o degradê.
static func _soft_rect_texture(edge := 0.42) -> ImageTexture:
	var key := "rect_%.2f" % edge
	if _textures.has(key): return _textures[key]
	var size := 64
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := absf((x + 0.5) / size * 2.0 - 1.0)
			var v := absf((y + 0.5) / size * 2.0 - 1.0)
			var d := maxf(u, v)
			var alpha := 1.0 - smoothstep(1.0 - edge, 1.0, d)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


## Rachaduras: três passeios aleatórios a partir do centro (determinístico).
static func _crack_texture() -> ImageTexture:
	if _textures.has("crack"): return _textures["crack"]
	var size := 128
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 90221
	for branch in 5:
		var p := Vector2(size * 0.5, size * 0.5)
		var heading := rng.randf() * TAU
		for step in 70:
			heading += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(heading), sin(heading)) * 0.9
			if p.x < 1 or p.y < 1 or p.x > size - 2 or p.y > size - 2: break
			var fade := 1.0 - step / 70.0
			image.set_pixelv(Vector2i(p), Color(1, 1, 1, fade))
			if step < 30: image.set_pixelv(Vector2i(p) + Vector2i(1, 0), Color(1, 1, 1, fade * 0.6))
	var texture := ImageTexture.create_from_image(image)
	_textures["crack"] = texture
	return texture

extends RefCounted
## Objetos de vida encostados nas paredes, o teste de pegada deles e a decoração da parede do
## fundo, separados do HarborBuildingDressing em 01/11 (Onda 1).
## O estado do andar (_spec, _palette, _rng, _frame, _layout, lotes, sólidos, camas, decoração) continua
## no HarborBuildingDressing e é lido e escrito por `g.`; o dono mantém cada função antiga como
## delegação de uma linha com a mesma assinatura. Os sorteios de `g._rng` saem na mesma ordem de
## antes (test_harbor_interior_variety compara dois populate do mesmo andar).
## `g` fica como RefCounted, e não como o script do dono, para não criar preload cíclico. O dono
## solta os auxiliares no fim de populate: dono e auxiliar se referenciam e, sendo RefCounted, o
## ciclo não se desfaria sozinho.
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")

var g: RefCounted

func _init(host: RefCounted) -> void:
	g = host

## Peça canônica: costas em -Z (parede), frente em +Z, base no chão em `at`.
func _life_object(kind: String, at: Vector3, id: String) -> void:
	match kind:
		"plant":
			g._cylinder(at + Vector3(0, .20, 0), .21, .40, ["8a7655", "b06a4a", "6e7f8a"][g._layout % 3], id, "ceramic")
			for leaf in 7: g._box(at + Vector3(sin(leaf * 2.3) * .14, .52 + leaf * .05, cos(leaf * 2.3) * .14), Vector3(.18, .26, .14), ["5a7655", "6f8a55", "4a6a50"][leaf % 3], id, "cloth")
		"tall_plant":
			g._cylinder(at + Vector3(0, .22, 0), .24, .44, ["d8d2c0", "3f4346", "8a7655"][g._layout % 3], id, "ceramic")
			g._box(at + Vector3(0, .80, 0), Vector3(.05, .80, .05), "6b5a40", id)
			for leaf in 9: g._box(at + Vector3(sin(leaf * 1.9) * .18, .95 + leaf * .07, cos(leaf * 1.9) * .16), Vector3(.24, .16, .20), ["4f7a4f", "6f8a55", "3e6a48"][leaf % 3], id, "cloth")
		"floor_lamp":
			g._cylinder(at + Vector3(0, .02, 0), .17, .04, g._palette.metal, id, "metal")
			g._box(at + Vector3(0, .75, 0), Vector3(.03, 1.46, .03), g._palette.metal, id, "metal")
			g._cylinder(at + Vector3(0, 1.48, 0), .19, .26, g._palette.linen, id, "cloth")
		"boxes":
			g._box(at + Vector3(-.10, .21, 0), Vector3(.56, .42, .56), "a88c61", id, "paper")
			g._box(at + Vector3(-.10, .421, 0), Vector3(.08, .006, .57), "c5b283", id, "paper")
			g._box(at + Vector3(.12, .56, .02), Vector3(.40, .28, .40), "b39a6e", id, "paper")
			if g._rng.randf() < .5: g._box(at + Vector3(.27, .13, .08), Vector3(.22, .26, .36), "9c7e55", id, "paper")
		"basket":
			g._box(at + Vector3(0, .17, 0), Vector3(.52, .34, .40), "b39468", id, "cloth")
			for fold in 2: g._box(at + Vector3(.04 * fold, .36 + fold * .04, 0), Vector3(.40, .05, .30), [g._palette.cloth, g._palette.linen][fold], id, "cloth")
		"guitar":
			g._box(at + Vector3(0, .26, .05), Vector3(.40, .48, .10), g._palette.accent, id)
			g._box(at + Vector3(0, .58, .05), Vector3(.32, .28, .09), g._palette.accent, id)
			g._box(at + Vector3(0, .88, .02), Vector3(.06, .40, .04), "3d3a33", id)
			g._cylinder(at + Vector3(0, .40, .105), .06, .01, "2d2a26", id, "metal")
			g._box(at + Vector3(0, .15, -.05), Vector3(.30, .30, .10), "2d3133", id, "metal")
		"radio_table":
			g._table_base(at, id, Vector2(.54, .42), .66)
			g._box(at + Vector3(0, .80, 0), Vector3(.34, .18, .18), "6b5a40", id)
			g._cylinder(at + Vector3(-.08, .80, .092), .05, .01, "c9c7bc", id, "metal")
		"bin":
			g._cylinder(at + Vector3(0, .25, 0), .16, .50, ["3f4346", "5e7774", "8c3b32"][g._layout % 3], id, "metal")
			g._box(at + Vector3(.02, .51, 0), Vector3(.16, .04, .12), "d9d1b8", id, "paper")
		"coat_rack":
			g._cylinder(at + Vector3(0, .03, 0), .22, .06, g._palette.wood, id, "wood")
			g._box(at + Vector3(0, .88, 0), Vector3(.05, 1.72, .05), g._palette.wood, id)
			g._box(at + Vector3(.12, 1.25, .05), Vector3(.22, .70, .18), g._palette.cloth, id, "cloth")
			g._box(at + Vector3(-.10, 1.40, -.04), Vector3(.18, .40, .14), "3f4a5a", id, "cloth")
		"bicycle":
			for wheel in [-.52, .52]:
				g._record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.62, .04, .62)), at + Vector3(wheel, .32, 0)), "2a2c2b", "rubber")
				g._record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.50, .045, .50)), at + Vector3(wheel, .32, 0)), "8e9690", "metal")
			g._box(at + Vector3(0, .52, 0), Vector3(1.0, .04, .04), g._palette.accent, id, "metal")
			g._box(at + Vector3(-.18, .48, 0), Vector3(.04, .36, .04), g._palette.accent, id, "metal")
			g._box(at + Vector3(-.18, .70, 0), Vector3(.22, .05, .10), "2a2c2b", id, "rubber")
			g._box(at + Vector3(.46, .80, 0), Vector3(.05, .04, .44), "2a2c2b", id, "metal")
			g._reserve(id, AABB(at + Vector3(-.84, 0, -.23), Vector3(1.68, .98, .46)))
		"fan":
			g._cylinder(at + Vector3(0, .03, 0), .2, .05, g._palette.metal, id, "metal")
			g._box(at + Vector3(0, .58, 0), Vector3(.04, 1.10, .04), g._palette.metal, id, "metal")
			g._record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.40, .10, .40)), at + Vector3(0, 1.08, .04)), "c9c7bc", "metal")
			g._reserve(id, AABB(at + Vector3(-.23, 0, -.23), Vector3(.46, 1.22, .46)))
		"shelf":
			g._box(at + Vector3(0, .78, -.17), Vector3(1.0, 1.55, .04), g._palette.wood, id)
			for side in [-1.0, 1.0]: g._box(at + Vector3(side * .48, .78, 0), Vector3(.04, 1.55, .38), g._palette.wood, id)
			for level in 4:
				g._box(at + Vector3(0, .05 + level * .48, 0), Vector3(.96, .03, .38), g._palette.wood, id)
				if level == 3: continue
				for item in 3:
					var x := -.30 + item * .30
					if (item + level + g._layout) % 3 == 0: g._cylinder(at + Vector3(x, .16 + level * .48, 0), .07, .20, [g._palette.accent, "b8bca7", "8a7655"][item], id, "ceramic")
					else: g._box(at + Vector3(x, .17 + level * .48, 0), Vector3(.22, .22 + (item % 2) * .06, .26), [g._palette.cloth, "b5a37c", "6b7769", "a28b6c"][(item + level) % 4], id, "paper")
		"suitcase":
			g._box(at + Vector3(0, .32, 0), Vector3(.52, .62, .24), ["3f4a5a", "8c4a32", "5e7774"][g._layout % 3], id, "cloth")
			g._box(at + Vector3(0, .66, 0), Vector3(.18, .05, .04), "2a2c2b", id, "metal")
		"shoe_rack":
			g._box(at + Vector3(0, .24, 0), Vector3(.80, .48, .30), g._palette.wood, id)
			for pair in 3:
				for shoe in 2: g._box(at + Vector3(-.26 + pair * .26 + shoe * .08, .52, .02), Vector3(.07, .07, .24), ["2a2c2b", "8c4a32", "d8d2c0"][pair], id, "rubber")
		"dresser":
			g._box(at + Vector3(0, .45, 0), Vector3(1.04, .90, .48), g._palette.cabinet, id)
			for drawer in 3: g._box(at + Vector3(0, .17 + drawer * .27, .245), Vector3(.96, .22, .012), g._palette.wood, id)
			g._surface_items(at + Vector3(0, .90, -.04), id, 2, .40)
		"cooler":
			g._box(at + Vector3(0, .50, 0), Vector3(.38, 1.0, .38), "d6d6cc", id, "ceramic")
			g._cylinder(at + Vector3(0, 1.16, 0), .15, .30, "8fb3c2", id, "glass")
			g._box(at + Vector3(0, .80, .20), Vector3(.10, .06, .04), "3f5d7a", id, "metal")
		"extinguisher":
			g._cylinder(at + Vector3(0, .27, 0), .09, .54, "a3352c", id, "metal")
			g._box(at + Vector3(0, .57, 0), Vector3(.10, .06, .14), "2a2c2b", id, "metal")
		"crates":
			g._box(at + Vector3(0, .36, 0), Vector3(.84, .72, .84), "8b7653", id)
			for slat in 3: g._box(at + Vector3(0, .12 + slat * .24, .425), Vector3(.84, .08, .012), "a68a5f", id)
		"barrel":
			g._cylinder(at + Vector3(0, .46, 0), .30, .92, ["3f5d7a", "8c4a32", "4f6a50"][g._layout % 3], id, "metal")
			for ring in [.18, .74]: g._cylinder(at + Vector3(0, ring, 0), .305, .03, "2d3133", id, "metal")
		"tire":
			for tire in 3: g._cylinder(at + Vector3(0, .10 + tire * .20, 0), .34, .19, "2a2c2b", id, "rubber")
		"bench":
			g._box(at + Vector3(0, .42, 0), Vector3(1.28, .06, .42), g._palette.wood, id)
			for leg in [-.55, .55]: g._box(at + Vector3(leg, .20, 0), Vector3(.06, .40, .38), g._palette.metal, id, "metal")
		"toys":
			g._box(at + Vector3(0, .20, 0), Vector3(.70, .40, .44), g._palette.accent, id)
			for toy in 4: g._box(at + Vector3(-.24 + toy * .16, .45, (toy % 2) * .08), Vector3(.12, .12, .12), ["c0904a", "5b7fa0", "a5502f", "8fa04a"][toy], id, "ceramic")

## Objetos de vida encostados nas paredes, sorteados por prédio/andar. A
## pegada é testada contra corredores, escada, entrada, sólidos, estações e
## recompensas; a parede da frente (lado da câmera) fica livre.
func _life_objects() -> void:
	var size: Vector2 = g._spec.size
	var pool: Array = g.LIFE_POOLS.get(str(g._spec.family), g.LIFE_POOLS.residential).duplicate()
	if g._spec.program == "kids": pool.append_array(["toys", "toys"])
	if g._spec.abandoned: pool = ["boxes", "crates", "bin", "tire", "barrel"]
	var target: int = clampi(int(size.x * size.y / 18.0), 3, 7) + (2 if g._spec.abandoned else 0)
	var used := {}
	var spots: Array[Dictionary] = []
	var half := size * .5
	# Parede do fundo (yaw 0), frente (PI), leste (-PI/2) e oeste (PI/2).
	var t := -half.x + .7
	while t < half.x - .6:
		# A parede da frente fica livre: atrás dela fica o controle de oclusão
		# do contrato e é por ela que a câmera olha para dentro.
		spots.append({"wall":"back", "t":t})
		t += .55
	t = -half.y + .8
	while t < half.y - .7:
		spots.append({"wall":"east", "t":t})
		spots.append({"wall":"west", "t":t})
		t += .55
	var tries := 0
	for spot in CONTENT._shuffled(g._rng, spots):
		if g._decor_count >= target or tries > 90: break
		tries += 1
		if pool.is_empty(): break
		var kind: String = pool[g._rng.randi() % pool.size()]
		var dims: Vector3 = g.LIFE_SIZES[kind]
		if spot.wall == "front" and dims.z > .74: continue
		var face := .26
		var yaw := 0.0
		var at := Vector3.ZERO
		match str(spot.wall):
			"back": at = Vector3(spot.t, 0, -half.y + face + dims.y * .5 + .02)
			"front":
				at = Vector3(spot.t, 0, half.y - face - dims.y * .5 - .02)
				yaw = PI
			"east":
				at = Vector3(half.x - face - dims.y * .5 - .02, 0, spot.t)
				yaw = -PI * .5
			_:
				at = Vector3(-half.x + face + dims.y * .5 + .02, 0, spot.t)
				yaw = PI * .5
		var rotated := absf(sin(yaw)) > .5
		var extent := Vector2(dims.y, dims.x) if rotated else Vector2(dims.x, dims.y)
		var rect := Rect2(Vector2(at.x, at.z) - extent * .5, extent)
		if not _decor_fits(rect): continue
		var id: String = "Decor%02d_%s" % [g._decor_count, kind]
		g._frame = Transform3D(Basis(Vector3.UP, yaw), at) * Transform3D(Basis.IDENTITY, -at)
		_life_object(kind, at, id)
		g._frame = Transform3D.IDENTITY
		# Todo objeto de vida é sólido por inteiro (vaso, folhas e base).
		g._reserve(id, Transform3D(Basis(Vector3.UP, yaw), at) * AABB(Vector3(-dims.x * .5, 0, -dims.y * .5), Vector3(dims.x, dims.z, dims.y)))
		g._decor.append(kind)
		g._decor_count += 1
		# Um de cada (dois para vasos e caixas): a sala não vira depósito de fãs.
		used[kind] = int(used.get(kind, 0)) + 1
		if used[kind] >= (2 if kind in ["plant", "boxes", "crates", "toys"] else 1): pool.erase(kind)

func _decor_fits(rect: Rect2) -> bool:
	var size: Vector2 = g._spec.size
	if rect.position.x < -size.x * .5 + .25 or rect.end.x > size.x * .5 - .25: return false
	if rect.position.y < -size.y * .5 + .25 or rect.end.y > size.y * .5 - .25: return false
	# Corredor central, faixa transversal da escada, a própria escada e a porta.
	if rect.grow(.22).intersects(Rect2(-1.23, -size.y * .5, 2.46, size.y)): return false
	if rect.grow(.22).intersects(Rect2(-size.x * .5, .78, size.x, 1.37)): return false
	if rect.grow(.35).intersects(Rect2(-size.x * .5 + .43, -1.82, 2.24, 4.06)): return false
	if g._spec.floor == 0 and rect.grow(.45).intersects(Rect2(g._spec.entrance.x - .65, 1.2, 1.30, size.y * .5)): return false
	for id in g._solids:
		var bounds: AABB = g._solids[id]
		# Ao redor da cama fica um vão livre: é por ali que se deita e levanta.
		var gap := .85 if str(id) == "Bed" or str(id).ends_with("_bed") else .24
		if rect.grow(gap).intersects(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)): return false
	for station in g._spec.occupants:
		var point: Vector3 = station.position
		if rect.grow(.80).has_point(Vector2(point.x, point.z)): return false
	for reward in g._spec.rewards:
		var point: Vector3 = reward.local_position
		if rect.grow(.65).has_point(Vector2(point.x, point.z)): return false
	# Sala trancada: paredes, porta e a aproximação do esconderijo ficam livres.
	for reward in g._spec.rewards:
		if not reward.get("locked", false): continue
		var door_z := -size.y * .5 + 2.30
		if rect.grow(.45).intersects(Rect2(-1.12, -size.y * .5 + .24, .14, size.y * .5 - 2.09)): return false
		if rect.grow(.45).intersects(Rect2(-size.x * .5 + .24, -1.93, size.x * .5 - 1.29, .16)): return false
		if rect.get_center().x < -1.0 and rect.intersects(Rect2(-size.x * .5, door_z - .57, size.x * .5, 1.14)): return false
		if rect.get_center().x < -1.0 and rect.intersects(Rect2(-size.x * .5, -3.02, size.x * .5, 1.05)): return false
	return true

## Quadros, relógio, prateleiras e espelho na parede do fundo (não sólidos),
## fora das janelas e acima de móveis altos encostados nela.
func _wall_decor(rear: float, _x: float) -> void:
	var size: Vector2 = g._spec.size
	var window_half := minf(1.8, size.x * .24) * .5 + .18
	var count: int = 2 + g._rng.randi() % 4
	var placed: Array[Rect2] = []
	var clock_used := false
	for attempt in 24:
		if placed.size() >= count: break
		var width: float = g._rng.randf_range(.35, .95)
		var height: float = g._rng.randf_range(.30, .70)
		var kind: int = g._rng.randi() % 6
		# Um relógio só por parede.
		if kind == 1 and clock_used: kind = 0
		if kind == 1:
			clock_used = true
			width = .34
			height = .34
		var x: float = g._rng.randf_range(-size.x * .5 + .5 + width * .5, size.x * .5 - .5 - width * .5)
		var y: float = g._rng.randf_range(1.45, 2.15)
		var rect := Rect2(x - width * .5, y - height * .5, width, height)
		var blocked := false
		for side in [-1.0, 1.0]:
			if absf(x - side * size.x * .27) < window_half + width * .5: blocked = true
		for other in placed:
			if other.grow(.12).intersects(rect): blocked = true
		for bounds: AABB in g._solids.values():
			if bounds.position.z > -size.y * .5 + 1.0: continue
			if bounds.end.y > rect.position.y - .05 and bounds.position.x < rect.end.x and bounds.end.x > rect.position.x: blocked = true
		if blocked: continue
		placed.append(rect)
		var at := Vector3(x, y, rear + .03)
		match kind:
			0, 4:
				# Quadro abstrato emoldurado: duas a três manchas de cor.
				g._box(at, Vector3(width, height, .04), g._palette.wood if kind == 0 else g._palette.metal, "", "wood" if kind == 0 else "metal")
				g._box(at + Vector3(0, 0, .022), Vector3(width - .08, height - .08, .006), ["d8d2c0", "c9b8a0", "aeb9b4"][g._layout % 3], "", "paper")
				for blot in 2 + g._rng.randi() % 2:
					g._box(at + Vector3(g._rng.randf_range(-.25, .25) * width, g._rng.randf_range(-.2, .2) * height, .027),
						Vector3(width * g._rng.randf_range(.18, .4), height * g._rng.randf_range(.2, .45), .004),
						[g._palette.accent, g._palette.cloth, "526c76", "a5502f", "8a987f"][g._rng.randi() % 5], "", "paper")
			1:
				# Relógio redondo.
				g._record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.34, .05, .34)), at), g._palette.metal, "metal")
				g._record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.29, .01, .29)), at + Vector3(0, 0, .03)), "e4ddcc", "ceramic")
				g._box(at + Vector3(0, .05, .04), Vector3(.015, .10, .004), "2a2c2b", "", "metal")
				g._box(at + Vector3(.04, 0, .04), Vector3(.08, .012, .004), "2a2c2b", "", "metal")
			2:
				# Prateleira de parede com objetos.
				g._box(at + Vector3(0, -height * .5, .08), Vector3(width, .03, .18), g._palette.wood)
				for item in maxi(1, int(width / .2)):
					var ix := -width * .5 + .12 + item * .2
					if item % 2 == 0: g._cylinder(at + Vector3(ix, -height * .5 + .10, .08), .05, .16, [g._palette.accent, "b8bca7", "8a7655"][item % 3], "", "ceramic")
					else: g._box(at + Vector3(ix, -height * .5 + .11, .08), Vector3(.12, .18, .12), [g._palette.cloth, "b5a37c"][item % 2], "", "paper")
			3:
				# Espelho.
				g._box(at, Vector3(width * .7, height + .2, .03), g._palette.wood)
				g._box(at + Vector3(0, 0, .018), Vector3(width * .7 - .06, height + .14, .006), "9fb3b8", "", "glass")
			_:
				# Painel de fotos pequenas.
				for photo in 3:
					g._box(at + Vector3((photo - 1) * width * .34, (photo % 2) * .08, 0), Vector3(width * .26, height * .55, .03), g._palette.wood)
					g._box(at + Vector3((photo - 1) * width * .34, (photo % 2) * .08, .017), Vector3(width * .22, height * .45, .005), [g._palette.cloth, "8a987f", "b39468"][photo], "", "paper")

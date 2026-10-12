extends "res://world/places/sewers/SewerVariantBase.gd"
## Cisterna Velha: o maior de todos, um salão abandonado com um lago preto no meio, colunas, desabamentos e uma
## capela improvisada onde mora Padre Nicanor. Quase sem luz: velas no altar, um brilho verde na água e a fogueira da
## Tita. Dois segredos grandes: uma ilha no lago, alcançada por uma passarela de tábuas que termina nela, e um cofre
## no canto sudeste escondido atrás de uma lona e de canos (abertura em x = 14,5, z = 10,2..11,2).
const REWARDS := [
	{"id": "sewer_cistern_island", "kind": "cash", "amount": 2200, "local_position": Vector3(3.0, 0, -0.9)},
	{"id": "sewer_cistern_vault_cash", "kind": "cash", "amount": 7500, "local_position": Vector3(19.0, 0, 10.6)},
	{"id": "sewer_cistern_vault_shotgun", "kind": "weapon", "item": "sawed_off", "amount": 1, "ammo": 24, "local_position": Vector3(19.4, 0, 7.6)},
	{"id": "sewer_cistern_chapel", "kind": "cash", "amount": 600, "local_position": Vector3(-19.8, 0, 6.6)},
]
const RESIDENTS := [
	{"id": "sewer_cistern_nicanor", "name": "Padre Nicanor", "local_position": Vector3(-16.5, 0, 5.4),
		"appearance": {"coat_color": Color("1f1f24"), "pants_color": Color("1b1b1f"), "appearance_variant": 512}},
	{"id": "sewer_cistern_tita", "name": "Tita", "local_position": Vector3(11.8, 0, -8.6),
		"appearance": {"coat_color": Color("4a3a3a"), "pants_color": Color("2a2c30"), "appearance_variant": 640, "is_female": true}},
]

func _build() -> void:
	half = Vector2(22, 13)
	mood = {"tint": Color(0.0, 0.006, 0.01), "base": 0.72, "edge": 0.94, "halo": 4.8, "halo_strength": 0.62}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#090d0e", ["#1c2523", "#1f2721", "#18221f", "#252619"])
	walls(3.4, 1.1, 0.35, "#1d2421")
	ladder(Vector3(-19.5, 0, -12.0))
	# Desabamentos no canto nordeste e uma bolsa a oeste.
	rubble(Rect2(16.0, -13.0, 6.0, 3.2), 2.0)
	rubble(Rect2(-22.0, -3.0, 1.8, 3.0), 1.6)
	# Lago preto no meio: bloqueado, com a passarela (x = 2,4..3,6) que vai até a ilha e acaba nela.
	water(Rect2(-8, -3.5, 22, 7), -0.16, "#04100f")
	solid_rects["LakeW"] = Rect2(-8, -3.4, 10.4, 6.8)
	solid_rects["LakeE"] = Rect2(3.6, -3.4, 10.4, 6.8)
	solid_rects["LakeGapN"] = Rect2(2.4, -3.4, 1.2, 1.4)
	for edge in [Vector2(-8, -3.5), Vector2(-8, 3.5)]: box(Vector3(3.0, 0.02, edge.y), Vector3(22.0, 0.12, 0.16), "#2b332d")
	for plank in 14:
		var board := box(Vector3(3.0, 0.03 - (plank % 4) * 0.01, 3.4 - plank * 0.3), Vector3(1.1, 0.05, 0.26), "#3f301f")
		board.rotation.y = _rng.randf_range(-0.04, 0.04)
	box(Vector3(3.0, 0.04, -1.0), Vector3(2.6, 0.06, 2.6), "#33281a")
	box(Vector3(3.0, 0.2, -1.6), Vector3(1.0, 0.4, 0.6), "#241a10", false, "IslandChest")
	for point in [Vector2(-5.0, 0.6), Vector2(8.0, -1.4), Vector2(11.0, 1.8), Vector2(-1.0, -2.0), Vector2(6.0, 2.4)]:
		var glow := box(Vector3(point.x, -0.05, point.y), Vector3(1.4, 0.02, 0.8), "#2f8a52", false, "", 1.0)
		glow.rotation.y = _rng.randf() * TAU
	lamp(Vector3(3.0, 0.6, 0.0), "#3aff8a", 1.2, 6.0, true)
	# Colunas em duas fileiras (norte e sul), tanque enferrujado e canos no fundo.
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		box(Vector3(x, 1.7, 8.5), Vector3(0.9, 3.4, 0.9), "#2c332e", false, "Column")
		if x > -10.0: box(Vector3(x, 1.7, -8.0), Vector3(0.9, 3.4, 0.9), "#2c332e", false, "Column")
	cyl(Vector3(-13.0, 1.0, -6.0), 2.6, 2.0, "#26322d", true, "Tank")
	cyl(Vector3(-13.0, 2.05, -6.0), 2.65, 0.1, "#3f4d46", true)
	for ring in 3: cyl(Vector3(-13.0, 0.4 + ring * 0.7, -6.0), 2.63, 0.06, "#161e1b", true)
	pipe(Vector3(-20.0, 3.0, -12.9), Vector3(14.0, 3.0, -12.9), 0.4, "#2f3d36")
	pipe(Vector3(-20.0, 2.2, -12.9), Vector3(4.0, 2.2, -12.9), 0.22, "#3a4a41")
	for x in [-17.0, -9.0, -2.0, 6.0, 12.0]: drips(Vector3(x, 3.0, -12.6))
	for x in [-16.0, -11.0, -5.0, 1.0, 7.0, 13.0]: rust_streak(x, -12.92, _rng.randf_range(1.5, 2.8), 3.2)
	# Capela: altar de caixotes com velas, bancos quebrados, cruz torta e o Padre Nicanor.
	box(Vector3(-19.5, 0.45, 4.2), Vector3(3.0, 0.9, 0.8), "#241f1a", false, "Altar")
	box(Vector3(-19.5, 1.35, 4.6), Vector3(0.1, 1.0, 0.1), "#3a2a1a").rotation.z = 0.12
	box(Vector3(-19.5, 1.6, 4.6), Vector3(0.6, 0.1, 0.1), "#3a2a1a").rotation.z = 0.12
	for x in [-20.6, -19.5, -18.4]: box(Vector3(x, 0.98, 3.9), Vector3(0.06, 0.16, 0.06), "#e6dcb0", false, "", 1.8)
	lamp(Vector3(-19.5, 1.3, 3.5), "#ffcf7a", 1.3, 4.5, true)
	for row in 3:
		var bench := box(Vector3(-15.8, 0.22, 8.0 + row * 1.5), Vector3(2.6, 0.44, 0.5), "#2f2418", false, "Bench")
		bench.rotation.y = _rng.randf_range(-0.12, 0.12)
	# Acampamento da Tita (nordeste do lago) com fogueira num barril.
	fire_barrel(Vector3(10.4, 0, -9.4))
	box(Vector3(12.8, 0.12, -9.8), Vector3(2.0, 0.24, 1.0), "#403d30", false, "Mattress")
	box(Vector3(12.8, 0.26, -9.8), Vector3(1.5, 0.06, 0.9), "#4d2626")
	# Cofre secreto sudeste: paredes de tijolo, abertura escondida, tesouro e a serrada.
	for wall in [Rect2(14.5, 6.0, 0.4, 4.2), Rect2(14.5, 11.2, 0.4, 1.8), Rect2(14.5, 5.8, 7.5, 0.3)]:
		box(Vector3(wall.get_center().x, 0.8, wall.get_center().y), Vector3(wall.size.x, 1.6, wall.size.y), "#262b25", false, "VaultWall")
	box(Vector3(14.2, 1.0, 10.7), Vector3(0.05, 1.9, 1.5), "#101a22")
	for index in 6: pipe(Vector3(14.0, 0.1, 10.0 + index * 0.25), Vector3(14.0, 2.1, 10.0 + index * 0.25), 0.05, "#3a4a41")
	box(Vector3(19.0, 0.2, 9.6), Vector3(1.6, 0.4, 0.8), "#1d150e", false, "StashChest")
	for index in 3: box(Vector3(21.2, 0.25 + index * 0.45, 12.0), Vector3(1.2, 0.4, 0.8), "#33302a", false, "VaultCrate")
	lamp(Vector3(19.0, 1.5, 8.6), "#ffb95a", 0.8, 4.0)
	# Sujeira pesada, ossos e tonéis tóxicos brilhando em verde.
	heap(Vector3(-4.0, 0, 6.0), 1.0, 12, true)
	heap(Vector3(7.0, 0, 6.6), 0.9, 11, true)
	heap(Vector3(-18.0, 0, -6.4), 0.7, 9)
	heap(Vector3(18.5, 0, 0.8), 0.7, 9)
	for point in [Vector2(-3.0, -6.0), Vector2(12.4, 4.6)]:
		cyl(Vector3(point.x, 0.32, point.y), 0.24, 0.64, "#1d3a1d", true, "Barrel")
		cyl(Vector3(point.x, 0.65, point.y), 0.2, 0.03, "#58ff6a", false, "", 3.0)
		lamp(Vector3(point.x, 0.9, point.y), "#4aff5a", 0.8, 3.6, true)
	scatter_grime(Rect2(-21.0, -12.0, 42.0, 24.0), 50, 24, 0)
	skeleton(Vector3(-6.0, 0, 5.0), 0.7)
	skeleton(Vector3(14.5, 0, -2.5), -2.0)
	skeleton(Vector3(-10.0, 0, 11.0), 1.4)
	graffiti(Vector3(-5.0, 2.0, -12.95), Vector2(4.0, 1.4), "#4a1a14")
	graffiti(Vector3(9.0, 1.8, -12.95), Vector2(2.4, 1.0), "#1c3a55")

extends "res://world/places/sewers/SewerVariantBase.gd"
## Poço de Santa Lua: uma cisterna redonda de pedra seca, com a bacia vazia no meio, uma coluna de sol que cai do poço e
## luas entalhadas nas paredes. O Ermitão Jacó mantém o santuário de ex-votos (velas, bonecos de barro e fitas). Nada de
## lixo: ossos de cabra, areia e silêncio. Segredo: a pedra da lua, no leste, gira e esconde a câmara dos fundadores.
const REWARDS := [
	{"id": "desert_under_well_offerings", "kind": "cash", "amount": 450, "local_position": Vector3(6.0, 0, -6.4)},
	{"id": "desert_under_well_founders", "kind": "cash", "amount": 1500, "local_position": Vector3(9.2, 0, 0.1)},
]
const RESIDENTS := [
	{"id": "desert_under_well_jaco", "name": "Ermitão Jacó", "local_position": Vector3(3.6, 0, -6.0),
		"appearance": {"coat_color": Color("a69a7a"), "pants_color": Color("5a4e3a"), "appearance_variant": 811}},
]

func _build() -> void:
	half = Vector2(10, 10)
	mood = {"tint": Color(0.03, 0.02, 0.012), "base": 0.55, "edge": 0.88, "halo": 3.2, "halo_strength": 0.45}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#9a8a70", ["#a8967a", "#a08c6e", "#9a8a70", "#b09c7a"])
	walls(3.0, 1.0, 0.35, "#8a7a62")
	ladder(Vector3(-6.2, 0, -7.0), "#7a5a38", "#8a6a44", "#2a2218")
	# Cantos desabados fazem a sala redonda; a bacia fica no centro.
	rubble(Rect2(-10, -10, 3.4, 3.4), 2.6, "#6a5c46")
	rubble(Rect2(6.6, -10, 3.4, 3.4), 2.6, "#6a5c46")
	rubble(Rect2(-10, 6.6, 3.4, 3.4), 2.6, "#6a5c46")
	rubble(Rect2(6.6, 6.6, 3.4, 3.4), 2.6, "#6a5c46")
	# Bacia seca com degraus concêntricos e uma poça de água limpa no fundo.
	cyl(Vector3(0, 0.0, 0.5), 4.2, 0.1, "#8a785a")
	cyl(Vector3(0, -0.02, 0.5), 3.4, 0.1, "#6e5e44")
	cyl(Vector3(0, -0.04, 0.5), 2.5, 0.1, "#4a3e2c")
	var spring := cyl(Vector3(0.3, 0.0, 0.7), 1.0, 0.03, "#5aa8b8", false, "", 0.8)
	spring.scale.z = 0.6
	# Coluna de sol: disco brilhante no chão e luz forte vinda de cima.
	cyl(Vector3(0, 0.07, 0.5), 2.0, 0.02, "#ffe2a0", false, "", 0.9)
	lamp(Vector3(0, 3.0, 0.5), "#ffd890", 1.7, 6.0)
	# Luas entalhadas nas paredes (brilho pálido) e a pedra da lua, que esconde a câmara dos fundadores.
	for point in [Vector2(-6.0, -half.y + 0.06), Vector2(0.0, -half.y + 0.06), Vector2(6.0, -half.y + 0.06)]:
		cyl(Vector3(point.x, 1.6, point.y), 0.5, 0.04, "#e8e1cf", false, "", 1.0).rotation.x = PI * 0.5
		cyl(Vector3(point.x + 0.2, 1.65, point.y + 0.03), 0.42, 0.04, "#8a7a62").rotation.x = PI * 0.5
	for index in 5: stain(Vector3(_rng.randf_range(-3.0, 3.0), 0, _rng.randf_range(-2.0, 3.0)), _rng.randf_range(0.2, 0.5), "#5a4a34")
	# Santuário do Jacó (nordeste): mesa de pedra com velas, bonecos de barro, fitas e a esteira dele.
	box(Vector3(6.0, 0.45, -8.2), Vector3(3.2, 0.9, 0.9), "#7a6a52", false, "Shrine")
	for index in 7: box(Vector3(4.8 + index * 0.4, 1.0, -8.2 + (index % 2) * 0.15), Vector3(0.06, 0.16, 0.06), "#f0e6bc", false, "", 1.8)
	for index in 4: cyl(Vector3(5.0 + index * 0.7, 1.05, -7.9), 0.1, 0.22, "#b9774a")
	for index in 6:
		var ribbon := box(Vector3(3.2 + index * 1.0, 2.3, -half.y + 0.1), Vector3(0.1, 0.9, 0.01), ["#a8362a", "#e0b43a", "#3a6aa8", "#e8e1cf", "#7a3a8a", "#2f8a52"][index])
		ribbon.rotation.z = (index - 3) * 0.05
	lamp(Vector3(6.0, 1.5, -7.2), "#ffcf7a", 1.3, 4.5, true)
	box(Vector3(3.6, 0.04, -5.6), Vector3(1.8, 0.04, 1.0), "#6a4a38")
	# Ossos de cabra, areia soprada pela boca do poço e cântaros quebrados.
	skeleton(Vector3(-3.0, 0, 4.4), 0.5)
	skeleton(Vector3(2.0, 0, 6.2), -2.2)
	for dune in [Vector3(-8.0, 0.2, 2.0), Vector3(-6.0, 0.15, 5.0), Vector3(4.6, 0.2, 5.2)]:
		box(dune, Vector3(2.6, 0.4, 1.8), "#c9b080").rotation.y = dune.x
	for index in 6: cyl(Vector3(-7.0 + index * 0.5, 0.14, 7.0 - (index % 2) * 0.5), 0.13, 0.28, "#b9774a")
	# Câmara dos fundadores (leste): abertura em x = 8,0, z = -0,7..0,5, escondida pela pedra da lua inclinada.
	for wall in [Rect2(8.0, -4.0, 0.4, 3.3), Rect2(8.0, 0.5, 0.4, 3.5)]:
		box(Vector3(wall.get_center().x, 1.2, wall.get_center().y), Vector3(wall.size.x, 2.4, wall.size.y), "#6a5c46", false, "ChamberWall")
	var moon_stone := box(Vector3(7.7, 0.9, -0.1), Vector3(0.3, 1.7, 1.5), "#8a7a62")
	moon_stone.rotation.z = 0.12
	cyl(Vector3(7.5, 1.1, -0.1), 0.4, 0.04, "#e8e1cf", false, "", 1.2).rotation.z = PI * 0.5
	box(Vector3(9.2, 0.2, 0.1), Vector3(0.9, 0.4, 0.6), "#5a4a28")
	for index in 3: cyl(Vector3(9.5, 0.18 + index * 0.3, 2.4), 0.2, 0.28, "#b9774a")
	lamp(Vector3(9.2, 1.2, 0.1), "#ffe0a0", 0.9, 3.0)
	graffiti(Vector3(-3.0, 1.4, -half.y + 0.05), Vector2(1.2, 0.5), "#6d3a2a")

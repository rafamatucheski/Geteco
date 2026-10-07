extends "res://world/places/sewers/SewerVariantBase.gd"
## Adega do Horizonte: o porão do motel, assoalho de tábua, vigas de madeira e lamparinas de óleo. Seu Tião destila
## cachaça de cacto em dois alambiques de cobre, o pôquer rola na mesa do meio e, atrás da estante giratória do
## sudeste, fica o quarto onde o motel esconde fugitivos (Hóspede Sete) e o cofre do dono.
const REWARDS := [
	{"id": "desert_under_cellar_jars", "kind": "cash", "amount": 800, "local_position": Vector3(1.9, 0, -4.4)},
	{"id": "desert_under_cellar_magnum", "kind": "weapon", "item": "magnum", "amount": 1, "ammo": 18, "local_position": Vector3(7.2, 0, 3.0)},
	{"id": "desert_under_cellar_safe", "kind": "cash", "amount": 2600, "local_position": Vector3(10.0, 0, 4.8)},
]
const RESIDENTS := [
	{"id": "desert_under_cellar_tiao", "name": "Seu Tião", "local_position": Vector3(-1.6, 0, -1.8),
		"appearance": {"coat_color": Color("a8a08a"), "pants_color": Color("4a3a2c"), "appearance_variant": 905}},
	{"id": "desert_under_cellar_sete", "name": "Hóspede Sete", "local_position": Vector3(8.6, 0, 3.6),
		"appearance": {"coat_color": Color("3a4a5a"), "pants_color": Color("2a2e34"), "appearance_variant": 944}},
]

func _build() -> void:
	half = Vector2(11, 6.5)
	mood = {"tint": Color(0.035, 0.016, 0.004), "base": 0.58, "edge": 0.9, "halo": 3.0, "halo_strength": 0.45}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#4e3a24", ["#5a4128", "#634830", "#4e3a24", "#6a4e32"])
	walls(2.8, 1.0, 0.35, "#6e5a44")
	# Escada de madeira no oeste (visual): degraus subindo para a luz do alçapão.
	for step in 7: box(Vector3(-10.4, 0.12 + step * 0.3, -3.0 - step * 0.3), Vector3(1.0, 0.1, 0.34), "#7a5a38")
	box(Vector3(-10.9, 1.0, -4.2), Vector3(0.1, 2.0, 2.6), "#5a4128")
	lamp(Vector3(-9.8, 2.0, -3.6), "#ffe3a8", 1.5, 5.0)
	# Vigas de madeira (decoração) e a lamparina de óleo no centro.
	for x in range(-8, 9, 4):
		box(Vector3(float(x), 1.2, -half.y + 0.2), Vector3(0.3, 2.4, 0.3), "#4a3320")
		box(Vector3(float(x), 2.45, 0.0), Vector3(0.24, 0.24, half.y * 2.0 - 0.4), "#3f2c1a")
	for point in [Vector2(-5.0, -5.4), Vector2(2.0, 5.5), Vector2(9.0, -1.0)]:
		box(Vector3(point.x, 1.0, point.y), Vector3(0.18, 0.28, 0.18), "#2a2622", true)
		box(Vector3(point.x, 1.0, point.y), Vector3(0.1, 0.18, 0.1), "#ffb25a", false, "", 2.0)
		lamp(Vector3(point.x, 1.2, point.y + 0.4), "#ff9a3a", 1.5, 5.0, true)
	# Destilaria: dois alambiques de cobre com serpentina, fogo embaixo, e fileira de barris.
	for x in [-2.4, 0.4]:
		cyl(Vector3(x, 0.55, -3.8), 0.7, 1.1, "#b9743a", true, "Still")
		cyl(Vector3(x, 1.3, -3.8), 0.4, 0.5, "#c98446", true)
		pipe(Vector3(x + 0.2, 1.5, -3.8), Vector3(x + 1.2, 0.9, -4.6), 0.07, "#b9743a")
		box(Vector3(x, 0.14, -3.2), Vector3(0.5, 0.2, 0.4), "#ff8a2a", false, "", 2.4)
	lamp(Vector3(-1.0, 0.6, -3.1), "#ff8a3a", 1.8, 5.0, true)
	for index in 6: barrel(Vector3(-9.0 + index * 1.15, 0, -5.4), ["#6a4a2a", "#5a3f26"][index % 2])
	for index in 4: barrel(Vector3(3.4 + index * 0.55, 0, -5.4 - (index % 2) * 0.2), "#6a4a2a")
	# Garrafas em estantes na parede leste e engradados de cacto.
	box(Vector3(9.6, 0.9, -5.5), Vector3(3.0, 1.8, 0.4), "#4a3320", false, "Shelf")
	for index in 12: cyl(Vector3(8.4 + (index % 6) * 0.45, 0.5 + (index / 6) * 0.7, -5.3), 0.07, 0.34, ["#3a5a3e", "#8a6a2c", "#41596a"][index % 3])
	crate(Vector3(3.6, 0, -4.8), Vector3(0.8, 0.6, 0.8), "#5a4128", 0.3)
	# Mesa de pôquer com cartas, fichas e três cadeiras.
	box(Vector3(-5.0, 0.4, 2.6), Vector3(2.2, 0.8, 1.4), "#1f4a2f", false, "Table")
	for index in 5: box(Vector3(-5.6 + index * 0.3, 0.84, 2.6), Vector3(0.14, 0.02, 0.2), "#e8e1cf")
	for chair in [Vector2(-6.6, 2.6), Vector2(-3.4, 2.6), Vector2(-5.0, 4.0)]: box(Vector3(chair.x, 0.25, chair.y), Vector3(0.5, 0.5, 0.5), "#5a4128", false, "Chair")
	puddle(Vector3(0.0, 0, 1.6), 0.6)
	# Quarto escondido (sudeste): estante giratória em x = 5,0 cobrindo a abertura z = 3,8..5,0.
	for wall in [Rect2(5.0, 0.4, 0.4, 3.4), Rect2(5.0, 5.0, 0.4, 1.5), Rect2(5.4, 0.4, 5.6, 0.4)]:
		box(Vector3(wall.get_center().x, 1.2, wall.get_center().y), Vector3(wall.size.x, 2.4, wall.size.y), "#5a4a38", false, "BunkWall")
	box(Vector3(4.7, 1.0, 4.4), Vector3(0.3, 2.0, 1.3), "#4a3320")
	for index in 6: cyl(Vector3(4.6, 0.4 + (index % 3) * 0.55, 3.95 + (index / 3) * 0.9), 0.07, 0.3, ["#3a5a3e", "#8a6a2c"][index % 2])
	for cot in [Vector2(7.0, 1.6), Vector2(9.4, 1.6)]:
		box(Vector3(cot.x, 0.25, cot.y), Vector3(1.8, 0.3, 0.8), "#4a4a3a", false, "Cot")
		box(Vector3(cot.x, 0.43, cot.y), Vector3(1.7, 0.06, 0.7), "#5a4040")
	box(Vector3(10.0, 0.5, 6.2), Vector3(1.0, 1.0, 0.6), "#2a2e30", true, "Safe")
	lamp(Vector3(8.6, 1.4, 3.4), "#ffcf7a", 1.0, 4.0)
	heap(Vector3(-7.8, 0, 5.4), 0.7, 9)
	scatter_grime(Rect2(-10.0, -5.8, 20.0, 11.5), 10, 0, 0)
	graffiti(Vector3(0.0, 1.7, -half.y + 0.05), Vector2(1.4, 0.7), "#5a1e18")

extends "res://world/places/sewers/SewerVariantBase.gd"
## Poço 3 da Serra Bruta: o cruzamento de duas galerias da mina antiga, escoradas de madeira, com trilhos, vagonetes e
## caixas de dinamite. Quase sem luz: só o brilho azul de cristais nas paredes e a lanterna do Velho Ozias, que se perdeu
## aqui há trinta anos. Segredo: a galeria leste está tapada por um desabamento com uma fresta onde passa um corpo; além
## dela fica a pepita da veia de ouro.
const REWARDS := [
	{"id": "desert_under_mine_pick", "kind": "weapon", "item": "axe", "amount": 1, "local_position": Vector3(-8.0, 0, -1.6)},
	{"id": "desert_under_mine_pay", "kind": "cash", "amount": 1100, "local_position": Vector3(-1.2, 0, -6.8)},
	{"id": "desert_under_mine_dynamite", "kind": "weapon", "item": "grenade", "amount": 1, "ammo": 6, "local_position": Vector3(6.0, 0, 1.5)},
	{"id": "desert_under_mine_gold", "kind": "cash", "amount": 4800, "local_position": Vector3(14.8, 0, 0.0)},
]
const RESIDENTS := [
	{"id": "desert_under_mine_ozias", "name": "Velho Ozias", "local_position": Vector3(0.8, 0, 5.6),
		"appearance": {"coat_color": Color("5a5a52"), "pants_color": Color("33322e"), "appearance_variant": 1003}},
]

func _build() -> void:
	half = Vector2(16, 9)
	mood = {"tint": Color(0.0, 0.01, 0.022), "base": 0.74, "edge": 0.96, "halo": 3.6, "halo_strength": 0.6}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#0c0a08", ["#3a3226", "#3f3528", "#332d22", "#463a2a"])
	walls(3.0, 1.0, 0.35, "#3a3326")
	ladder(Vector3(-13.6, 0, -7.7), "#6a5a3a", "#7a6a44", "#14100c")
	# Galerias em cruz: tudo que não é galeria é rocha desabada.
	rubble(Rect2(-10.0, -9.0, 6.5, 5.5), 2.4, "#2a241c")
	rubble(Rect2(3.5, -9.0, 12.5, 5.5), 2.4, "#2a241c")
	rubble(Rect2(3.5, 3.5, 12.5, 5.5), 2.4, "#2a241c")
	rubble(Rect2(-16.0, 3.5, 12.5, 5.5), 2.4, "#2a241c")
	# Trilhos ao longo da galeria horizontal e vagonetes de minério.
	for side in [-0.38, 0.38]: box(Vector3(0, 0.05, side), Vector3(half.x * 2.0 - 4.0, 0.06, 0.06), "#6a5a44", true)
	for tie in range(-14, 12): box(Vector3(float(tie), 0.03, 0.0), Vector3(0.14, 0.04, 1.1), "#3a2c1a")
	for cart in [Vector2(9.2, 0.0), Vector2(-5.6, 0.0)]:
		box(Vector3(cart.x, 0.55, cart.y), Vector3(1.7, 0.8, 1.05), "#6a4a2a", true, "Cart")
		box(Vector3(cart.x, 1.0, cart.y), Vector3(1.5, 0.12, 0.9), "#3a3a36", true)
		for wheel in [-0.6, 0.6]: cyl(Vector3(cart.x + wheel, 0.2, cart.y + 0.42), 0.2, 0.08, "#2a2622", true).rotation.x = PI * 0.5
	# Escoras de madeira: postes a cada 3 m nas duas galerias, com travessas.
	for x in range(-9, 11, 3):
		for side in [-3.2, 3.2]: box(Vector3(float(x), 1.4, side), Vector3(0.22, 2.8, 0.22), "#4a3320")
		box(Vector3(float(x), 2.75, 0.0), Vector3(0.2, 0.2, 6.8), "#3f2c1a")
	for z in range(-7, 8, 3):
		for side in [-3.2, 3.2]: box(Vector3(side, 1.4, float(z)), Vector3(0.22, 2.8, 0.22), "#4a3320")
	# Cristais azuis nas paredes e rocha (a única luz), com brilho que pulsa.
	for point in [Vector2(-8.0, -3.4), Vector2(-1.0, -8.6), Vector2(2.0, 8.6), Vector2(-3.0, 3.4), Vector2(8.0, -3.4), Vector2(11.0, 3.4), Vector2(0.0, -5.0)]:
		for index in 3:
			var crystal := box(Vector3(point.x + index * 0.22, 0.4 + index * 0.18, point.y), Vector3(0.14, 0.7 + index * 0.25, 0.14), "#5ad8ff", false, "", 3.0)
			crystal.rotation = Vector3(0.2 * index, index, -0.2 * index)
		lamp(Vector3(point.x, 0.8, point.y), "#4ac8ff", 1.0, 4.0, true)
	# Elevador de gaiola no cruzamento: plataforma, correntes e a viga do cabo.
	box(Vector3(0.0, 0.08, -1.8), Vector3(2.2, 0.16, 1.4), "#4a443a", true)
	for side in [-1.0, 1.0]: cyl(Vector3(side * 1.0, 1.4, -1.8), 0.05, 2.8, "#5a564a", true)
	box(Vector3(0.0, 2.8, -1.8), Vector3(2.2, 0.12, 0.14), "#5a564a", true)
	lamp(Vector3(0.0, 2.4, -1.8), "#9fd6ff", 0.9, 3.5, true)
	# Dinamite, ferramentas e o canto do Ozias com a lanterna.
	for index in 4: crate(Vector3(5.0 + index * 0.55, 0, 2.7 + (index % 2) * 0.1), Vector3(0.5, 0.4, 0.5), "#8a2a1f", index * 0.3)
	box(Vector3(-8.0, 0.4, -1.6), Vector3(0.12, 0.8, 0.12), "#3a2a1a")
	box(Vector3(-8.0, 0.8, -1.6), Vector3(0.6, 0.1, 0.1), "#6a6a62", true)
	box(Vector3(0.8, 0.14, 6.2), Vector3(1.8, 0.28, 0.9), "#3a342a")
	lamp(Vector3(0.9, 0.7, 5.8), "#ffb25a", 1.2, 4.0, true)
	skeleton(Vector3(-7.0, 0, 0.4), 0.9)
	skeleton(Vector3(7.4, 0, -2.2), -0.5)
	box(Vector3(-1.2, 0.2, -6.8), Vector3(0.5, 0.3, 0.4), "#7a6a38")
	# Veia de ouro (leste): desabamento com fresta em x = 11,5..13,5, z = -0,5..0,5, escondida por tábuas e pedras.
	for plug in [Rect2(11.5, -3.5, 2.0, 3.0), Rect2(11.5, 0.5, 2.0, 3.0)]:
		rubble(plug, 2.0, "#2a241c")
	box(Vector3(12.4, 0.9, 0.0), Vector3(0.2, 1.8, 1.0), "#3a2a18").rotation.y = 0.4
	box(Vector3(12.6, 0.3, -0.2), Vector3(0.9, 0.6, 0.5), "#3a342a").rotation.y = 0.7
	box(Vector3(14.8, 0.2, 0.0), Vector3(0.9, 0.4, 0.6), "#7a6a28", false, "", 0.8)
	for index in 5: box(Vector3(15.6, 0.3 + index * 0.4, -1.0 + (index % 2) * 2.0), Vector3(0.18, 0.5, 0.24), "#e0b43a", false, "", 1.2)
	lamp(Vector3(14.6, 1.0, 0.0), "#ffd25a", 1.2, 4.0, true)
	scatter_grime(Rect2(-14.0, -8.0, 28.0, 16.0), 14, 6, 0)
	graffiti(Vector3(-12.0, 1.8, -half.y + 0.05), Vector2(2.0, 0.8), "#6d2a1e")

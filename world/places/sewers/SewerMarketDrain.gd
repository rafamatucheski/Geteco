extends "res://world/places/sewers/SewerVariantBase.gd"
## Beco do Mercado: um tubo apertado e imundo, entupido de entulho nos dois cantos, onde Seu Abel montou o canto
## dele junto a um barril de fogo. Quase sem luz: só o fogo e uma lâmpada morrendo. Pequeno e quase sem segredo:
## as economias dele debaixo do colchão e uma faca esquecida entre os barris.
const REWARDS := [
	{"id": "sewer_market_savings", "kind": "cash", "amount": 180, "local_position": Vector3(6.4, 0, -3.2)},
	{"id": "sewer_market_knife", "kind": "weapon", "item": "knife", "amount": 1, "local_position": Vector3(-3.0, 0, 2.2)},
]
const RESIDENTS := [
	{"id": "sewer_market_abel", "name": "Seu Abel", "local_position": Vector3(3.6, 0, -0.4),
		"appearance": {"coat_color": Color("4a4033"), "pants_color": Color("2f302c"), "appearance_variant": 41}},
]

func _build() -> void:
	half = Vector2(8, 5)
	mood = {"tint": Color(0.03, 0.02, 0.01), "base": 0.7, "edge": 0.94, "halo": 2.6, "halo_strength": 0.5}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#14110d", ["#2f2b22", "#332e22", "#2a2a22", "#38301f"])
	walls(2.8, 1.0, 0.35, "#2b2f28")
	ladder(Vector3(-6.2, 0, -3.4))
	# Entulho fecha o canto sudeste e uma bolsa no fundo: o beco vira um L estreito.
	rubble(Rect2(3.0, 1.9, 5.0, 3.1), 1.4)
	rubble(Rect2(-1.2, -5.0, 3.0, 1.6), 1.6)
	# Esgoto escorrendo pela frente, mais lama que água.
	water(Rect2(-half.x, 3.0, 11.0, 1.3), -0.07, "#1c2a1a")
	pipe(Vector3(-7.5, 2.3, -4.9), Vector3(-1.4, 2.3, -4.9), 0.2, "#3a453d")
	pipe(Vector3(-1.4, 2.3, -4.9), Vector3(-1.4, 0.2, -4.9), 0.14, "#3a453d")
	for x in [-5.0, -3.0, 2.4]: drips(Vector3(x, 2.1, -4.7))
	for x in [-6.8, -3.5, 0.0, 2.8]: rust_streak(x, -4.95, _rng.randf_range(1.0, 2.0))
	# Só duas luzes: a lâmpada morrendo (vermelha, falha muito) e o fogo do Abel.
	service_lamp(Vector3(-4.2, 2.6, -4.8), "#ff6a3a", 1.1, 4.5, true)
	# Canto do Abel: colchão podre, cobertor, papelão, carrinho de mercado e roupa de varal.
	box(Vector3(6.4, 0.14, -3.2), Vector3(2.0, 0.28, 1.0), "#403d30")
	box(Vector3(6.6, 0.3, -3.2), Vector3(1.4, 0.06, 0.95), "#4d2626")
	box(Vector3(5.5, 0.3, -3.2), Vector3(0.38, 0.1, 0.55), "#6d6858")
	fire_barrel(Vector3(4.8, 0, -1.4))
	_shopping_cart(Vector3(7.0, 0, -0.6))
	for index in 3: box(Vector3(5.2 + index * 0.55, 0.9 + (index % 2) * 0.1, -4.55), Vector3(0.38, 0.7, 0.03), ["#4a5a66", "#6a5a2a", "#4a3445"][index])
	pipe(Vector3(4.8, 1.35, -4.55), Vector3(7.0, 1.3, -4.55), 0.012, "#8a8a8a")
	for index in 3: box(Vector3(2.6 + index * 0.9, 0.18, -2.4 + (index % 2) * 0.6), Vector3(0.8, 0.36, 0.6), ["#5a4e38", "#4d4330", "#675a42"][index], false, "Cardboard")
	box(Vector3(-3.0, 0.3, 2.2), Vector3(0.9, 0.6, 0.9), "#3a3023", false, "")
	barrel(Vector3(-5.2, 0, 1.4), "#33403a")
	barrel(Vector3(-4.6, 0, 1.9), "#4a3b28")
	for index in 7: cyl(Vector3(0.0 + index * 0.37, 0.09, -1.0 + (index % 3) * 0.3), 0.04, 0.18, ["#3a5a3e", "#6a5020", "#41596a"][index % 3])
	# Sujeira por toda parte: manchas, musgo e montes de lixo.
	heap(Vector3(-0.8, 0, 0.8), 0.8, 11, true)
	heap(Vector3(-6.8, 0, 2.2), 0.6, 8)
	heap(Vector3(1.9, 0, -1.8), 0.5, 7)
	scatter_grime(Rect2(-7.5, -4.5, 10.0, 8.2), 16, 8, 0)
	skeleton(Vector3(-2.4, 0, -0.3), 0.4)
	graffiti(Vector3(-3.4, 1.5, -4.92), Vector2(1.5, 0.8), "#6d2a1e")
	graffiti(Vector3(0.9, 1.7, -4.92), Vector2(0.9, 0.4), "#223a55")

func _shopping_cart(at: Vector3) -> void:
	box(at + Vector3(0, 0.55, 0), Vector3(0.9, 0.04, 0.55), "#6d7373", true, "Cart")
	for corner in [Vector2(-0.43, -0.25), Vector2(0.43, -0.25), Vector2(-0.43, 0.25), Vector2(0.43, 0.25)]:
		cyl(at + Vector3(corner.x, 0.28, corner.y), 0.04, 0.56, "#6d7373", true)
	box(at + Vector3(0, 0.9, -0.27), Vector3(0.9, 0.5, 0.03), "#838a8a", true)
	box(at + Vector3(0, 0.75, 0.0), Vector3(0.6, 0.34, 0.4), "#493f2e")

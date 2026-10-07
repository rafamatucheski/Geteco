extends "res://world/places/sewers/SewerVariantBase.gd"
## Beco do Mercado: um dreno de ponta cega onde Seu Abel montou o canto dele. Pequeno e quase sem segredo:
## as economias dele debaixo do colchão e uma faca esquecida no caixote.
const REWARDS := [
	{"id": "sewer_market_savings", "kind": "cash", "amount": 180, "local_position": Vector3(5.6, 0, -3.5)},
	{"id": "sewer_market_knife", "kind": "weapon", "item": "knife", "amount": 1, "local_position": Vector3(-3.3, 0, 2.3)},
]
const RESIDENTS := [
	{"id": "sewer_market_abel", "name": "Seu Abel", "local_position": Vector3(3.0, 0, -0.5),
		"appearance": {"coat_color": Color("5b4f3d"), "pants_color": Color("3a3a35"), "appearance_variant": 41}},
]

func _build() -> void:
	half = Vector2(8, 5)
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0))
	walls()
	ladder(Vector3(-6.2, 0, -3.4))
	# Canal raso na frente: a água escorre para fora da sala.
	water(Rect2(-half.x, 3.0, half.x * 2.0, 1.3))
	for x in [-6.0, -2.0, 2.0, 6.0]: box(Vector3(x, 0.02, 3.0), Vector3(0.12, 0.05, 1.3), "#5d6c68", true)
	pipe(Vector3(-7.5, 2.3, -4.9), Vector3(7.5, 2.3, -4.9), 0.2, "#61746b")
	pipe(Vector3(7.5, 2.3, -4.9), Vector3(7.5, 0.2, -4.9), 0.14, "#61746b")
	drips(Vector3(-1.0, 2.1, -4.7))
	drips(Vector3(4.6, 2.1, -4.7))
	puddle(Vector3(-1.0, 0, -4.2), 0.5)
	puddle(Vector3(1.5, 0, 1.0), 0.6)
	service_lamp(Vector3(-4.0, 2.6, -4.8), "#ffbd66", 1.8, 5.5, true)
	# Canto do Abel: colchão, cobertor, barril de fogo, carrinho de mercado e roupa no varal.
	box(Vector3(5.6, 0.14, -3.5), Vector3(2.0, 0.28, 1.0), "#6e6a57")
	box(Vector3(5.8, 0.3, -3.5), Vector3(1.4, 0.06, 0.95), "#7a3b3b")
	box(Vector3(4.7, 0.3, -3.5), Vector3(0.38, 0.1, 0.55), "#a59f8a")
	fire_barrel(Vector3(4.4, 0, -1.1))
	_shopping_cart(Vector3(6.6, 0, 0.6))
	for index in 3:
		box(Vector3(5.0 + index * 0.5, 0.9 + (index % 2) * 0.1, -4.6), Vector3(0.38, 0.7, 0.03), ["#7a8b9c", "#a8883e", "#6b4e63"][index])
	pipe(Vector3(4.6, 1.35, -4.6), Vector3(6.6, 1.3, -4.6), 0.012, "#cfcfcf")
	for index in 3: box(Vector3(2.6 + index * 0.9, 0.18, -2.7 + (index % 2) * 0.5), Vector3(0.8, 0.36, 0.6), ["#8a7a5c", "#7c6c52", "#9a8863"][index], false, "Cardboard")
	crate(Vector3(-2.2, 0, 2.5), Vector3(0.9, 0.62, 0.9), "#756347", 0.3)
	barrel(Vector3(-5.2, 0, 1.4))
	barrel(Vector3(-4.6, 0, 1.9), "#6b5a3d")
	# Garrafas e latas no chão, o chão fala do morador.
	for index in 6: cyl(Vector3(0.6 + index * 0.37, 0.09, -1.0 + (index % 3) * 0.3), 0.04, 0.18, ["#4d7a52", "#8a6a2c", "#5a7587"][index % 3])
	graffiti(Vector3(-3.0, 1.5, -4.92), Vector2(1.7, 0.9), "#d65a3a")
	graffiti(Vector3(1.2, 1.7, -4.92), Vector2(1.1, 0.5), "#5a9ad6")

func _shopping_cart(at: Vector3) -> void:
	box(at + Vector3(0, 0.55, 0), Vector3(0.9, 0.04, 0.55), "#9aa0a0", true, "Cart")
	for corner in [Vector2(-0.43, -0.25), Vector2(0.43, -0.25), Vector2(-0.43, 0.25), Vector2(0.43, 0.25)]:
		cyl(at + Vector3(corner.x, 0.28, corner.y), 0.04, 0.56, "#9aa0a0", true)
	box(at + Vector3(0, 0.9, -0.27), Vector3(0.9, 0.5, 0.03), "#b5bbbb", true)
	box(at + Vector3(0, 0.75, 0.0), Vector3(0.6, 0.34, 0.4), "#6c5e46")

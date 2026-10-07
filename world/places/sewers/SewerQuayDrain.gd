extends "res://world/places/sewers/SewerVariantBase.gd"
## Dreno do Cais: o canal de maré corta a sala em duas margens, com uma passarela de tábuas. Dona Marlene
## pesca na margem norte; na sul, atrás dos barris, ficou uma mochila seca e um taco de beisebol.
const REWARDS := [
	{"id": "sewer_quay_dry_bag", "kind": "cash", "amount": 420, "local_position": Vector3(7.3, 0, 3.9)},
	{"id": "sewer_quay_bat", "kind": "weapon", "item": "bat", "amount": 1, "local_position": Vector3(-6.2, 0, 3.4)},
]
const RESIDENTS := [
	{"id": "sewer_quay_marlene", "name": "Dona Marlene", "local_position": Vector3(-2.9, 0, -1.95),
		"appearance": {"coat_color": Color("6a5a64"), "pants_color": Color("3b3f45"), "appearance_variant": 77, "is_female": true}},
]

func _build() -> void:
	half = Vector2(9, 5.5)
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0))
	walls()
	ladder(Vector3(-7.2, 0, -4.6))
	# Canal de maré: bloqueado nas margens, com a passarela (sem colisão) entre x = 3,2 e 4,6.
	water(Rect2(-half.x, -1.4, half.x * 2.0, 2.8), -0.14, "#0f4a52")
	box(Vector3(-2.9, 0.02, -1.4), Vector3(12.2, 0.12, 0.14), "#747d68", false, "BankLeft")
	box(Vector3(-2.9, 0.02, 1.4), Vector3(12.2, 0.12, 0.14), "#747d68")
	box(Vector3(6.8, 0.02, -1.4), Vector3(4.4, 0.12, 0.14), "#747d68")
	box(Vector3(6.8, 0.02, 1.4), Vector3(4.4, 0.12, 0.14), "#747d68")
	solid_rects["CanalWest"] = Rect2(-half.x, -1.3, 12.2, 2.6)
	solid_rects["CanalEast"] = Rect2(4.6, -1.3, 4.4, 2.6)
	for plank in 6:
		box(Vector3(3.2 + 0.23 + plank * 0.25, 0.04, 0.0), Vector3(0.22, 0.05, 2.9), "#7a5c3a")
	box(Vector3(3.2, -0.04, 0.0), Vector3(0.06, 0.2, 2.9), "#5a4128")
	box(Vector3(4.6, -0.04, 0.0), Vector3(0.06, 0.2, 2.9), "#5a4128")
	# Comporta de maré na parede leste e canos no fundo.
	box(Vector3(half.x - 0.2, 1.1, 0.0), Vector3(0.3, 2.0, 3.0), "#2f3d3a", true)
	cyl(Vector3(half.x - 0.38, 1.1, 0.0), 0.5, 0.08, "#a15c35", true).rotation.z = PI * 0.5
	pipe(Vector3(-8.5, 2.2, -5.35), Vector3(8.5, 2.2, -5.35), 0.22, "#61746b")
	pipe(Vector3(0.0, 2.2, -5.35), Vector3(0.0, 0.1, -5.35), 0.16, "#61746b")
	for x in [-6.0, 1.5, 6.0]: drips(Vector3(x, 2.0, -5.1))
	service_lamp(Vector3(-5.0, 2.6, -5.2), "#ffbd66", 2.0, 6.0, true)
	service_lamp(Vector3(5.5, 2.6, 5.0), "#9fd6ff", 1.4, 5.5)
	# Margem norte: acampamento da Marlene com lona, fogareiro, rádio e vara de pesca sobre a água.
	box(Vector3(-2.0, 2.0, -3.4), Vector3(3.2, 0.06, 2.0), "#4a6b78").rotation.z = 0.06
	for post in [Vector2(-3.5, -4.3), Vector2(-0.5, -4.3), Vector2(-3.5, -2.5), Vector2(-0.5, -2.5)]:
		cyl(Vector3(post.x, 1.0, post.y), 0.04, 2.0, "#6b5a3d")
	box(Vector3(-1.6, 0.18, -3.0), Vector3(0.6, 0.36, 0.5), "#7a5c3a", false, "Stool")
	box(Vector3(-2.4, 0.18, -3.8), Vector3(0.34, 0.2, 0.2), "#2c3338", true)
	cyl(Vector3(-0.6, 0.12, -3.6), 0.2, 0.24, "#3c3f44", true, "Stove")
	cyl(Vector3(-0.6, 0.3, -3.6), 0.17, 0.12, "#8a9788", true)
	lamp(Vector3(-0.6, 0.7, -3.3), "#ff9d4a", 1.4, 4.0, true)
	pipe(Vector3(-4.4, 0.5, -1.7), Vector3(-5.6, 1.4, 0.2), 0.014, "#c6b37f")
	box(Vector3(-6.6, 0.35, -2.4), Vector3(0.9, 0.7, 1.0), "#756347", false, "CrateNorth")
	# Margem sul: barris escondendo a mochila, caixotes e um corrimão enferrujado.
	barrel(Vector3(6.4, 0, 3.0))
	barrel(Vector3(6.9, 0, 2.7), "#6b5a3d")
	barrel(Vector3(7.7, 0, 2.5))
	crate(Vector3(5.2, 0, 4.4), Vector3(0.9, 0.7, 0.9), "#756347", 0.4)
	crate(Vector3(-5.0, 0, 2.6), Vector3(0.9, 0.62, 0.9), "#6a5a3f", 0.2)
	crate(Vector3(-7.4, 0, 2.5), Vector3(0.9, 0.5, 0.9), "#6a5a3f", -0.3)
	for x in range(-8, 3, 2): cyl(Vector3(float(x), 0.45, 1.75), 0.03, 0.9, "#8a6a4a", true)
	pipe(Vector3(-8.0, 0.88, 1.75), Vector3(2.0, 0.88, 1.75), 0.02, "#8a6a4a")
	puddle(Vector3(1.0, 0, 3.2), 0.7)
	puddle(Vector3(-2.5, 0, -4.4), 0.5)
	graffiti(Vector3(3.0, 1.6, -5.42), Vector2(2.0, 0.9), "#d6b13a")
	graffiti(Vector3(-6.0, 1.7, -5.42), Vector2(1.2, 0.7), "#d65a8a")

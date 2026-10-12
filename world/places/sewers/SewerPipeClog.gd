extends "res://world/places/sewers/SewerVariantBase.gd"
## Cano Entupido: o menor de todos, um trecho de tubulação desabado e quase totalmente escuro, com lama até o tornozelo,
## ossos e um único morador que já não bate bem. Sem luz além de uma lâmpada vermelha quase morta.
const REWARDS := [
	{"id": "sewer_pipe_cash", "kind": "cash", "amount": 250, "local_position": Vector3(0.4, 0, 1.3)},
	{"id": "sewer_pipe_axe", "kind": "weapon", "item": "axe", "amount": 1, "local_position": Vector3(3.4, 0, -0.6)},
]
const RESIDENTS := [
	{"id": "sewer_pipe_maluco", "name": "O Maluco", "local_position": Vector3(0.8, 0, -0.6),
		"appearance": {"coat_color": Color("33382f"), "pants_color": Color("231f1b"), "appearance_variant": 9}},
]

func _build() -> void:
	half = Vector2(5, 3.5)
	mood = {"tint": Color(0.02, 0.012, 0.0), "base": 0.8, "edge": 0.97, "halo": 2.2, "halo_strength": 0.55}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#0d0a07", ["#241d14", "#281f15", "#1f1b14", "#2d2316"])
	walls(2.6, 0.9, 0.35, "#222520")
	ladder(Vector3(-3.2, 0, -2.6))
	# Três cantos desabados fecham a sala num oval torto.
	rubble(Rect2(3.0, -3.5, 2.0, 1.5), 1.6)
	rubble(Rect2(-5.0, 2.0, 2.2, 1.5), 1.5)
	rubble(Rect2(3.2, 2.1, 1.8, 1.4), 1.5)
	# O cano-mestre atravessa o fundo e vaza; lama preta no chão.
	pipe(Vector3(-4.8, 1.5, -3.2), Vector3(2.8, 1.5, -3.2), 0.55, "#2f3a33")
	for ring in 4: cyl(Vector3(-3.6 + ring * 2.0, 1.5, -3.2), 0.6, 0.06, "#1d241f", true).rotation.z = PI * 0.5
	drips(Vector3(-0.5, 1.3, -2.9))
	drips(Vector3(1.4, 1.3, -2.9))
	stain(Vector3(-0.5, 0, -2.4), 1.0, "#080604")
	stain(Vector3(2.0, 0, 0.4), 1.2, "#0a0806")
	water(Rect2(-1.8, 1.4, 3.6, 1.3), -0.06, "#120d08")
	for x in [-4.0, -1.0, 1.5]: rust_streak(x, -3.45, _rng.randf_range(1.0, 2.0), 2.3)
	# Uma lâmpada vermelha quase morta; é a única luz.
	service_lamp(Vector3(-2.0, 2.4, -3.3), "#ff3a22", 0.9, 4.0, true)
	# Restos: ossos, lixo, colchão encharcado, caixote com o dinheiro e o machado cravado no entulho.
	skeleton(Vector3(2.4, 0, 0.9), 0.3)
	box(Vector3(1.4, 0.1, -1.6), Vector3(1.6, 0.2, 0.8), "#2c2a22", false, "Mattress")
	heap(Vector3(-1.6, 0, 0.4), 0.7, 11, true)
	heap(Vector3(3.8, 0, 0.2), 0.45, 7)
	heap(Vector3(-4.3, 0, 0.8), 0.45, 6)
	box(Vector3(0.4, 0.2, 2.2), Vector3(0.6, 0.4, 0.5), "#33281a", false, "StashCrate")
	box(Vector3(3.4, 0.35, -0.6), Vector3(0.12, 0.7, 0.12), "#3a2a1a")
	scatter_grime(Rect2(-4.6, -2.8, 8.4, 5.2), 12, 8, 0)
	graffiti(Vector3(-1.4, 1.2, -3.45), Vector2(1.1, 0.5), "#5a1e18")

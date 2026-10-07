extends "res://world/places/sewers/SewerVariantBase.gd"
## Dreno do Cais: o canal de maré corta a sala em duas margens, com uma passarela de tábuas podres. Água turva e
## verde, algas, ferrugem e quase nenhuma luz (uma grade de rua deixa cair um fio de luz fria). Dona Marlene pesca na
## margem norte; na sul, atrás dos barris, ficaram uma mochila seca e um taco de beisebol.
const REWARDS := [
	{"id": "sewer_quay_dry_bag", "kind": "cash", "amount": 420, "local_position": Vector3(7.3, 0, 3.9)},
	{"id": "sewer_quay_bat", "kind": "weapon", "item": "bat", "amount": 1, "local_position": Vector3(-4.3, 0, 3.5)},
]
const RESIDENTS := [
	{"id": "sewer_quay_marlene", "name": "Dona Marlene", "local_position": Vector3(-2.9, 0, -1.95),
		"appearance": {"coat_color": Color("4d4048"), "pants_color": Color("2c2f34"), "appearance_variant": 77, "is_female": true}},
]

func _build() -> void:
	half = Vector2(9, 5.5)
	mood = {"tint": Color(0.0, 0.025, 0.03), "base": 0.72, "edge": 0.95, "halo": 3.0, "halo_strength": 0.5}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#0f1514", ["#27322d", "#2a342b", "#222e2c", "#303322"])
	walls(2.8, 1.0, 0.35, "#262c27")
	ladder(Vector3(-7.2, 0, -4.6))
	# Canto sudoeste desabado e um pedaço do fundo leste: contorno torto.
	rubble(Rect2(-9.0, 3.7, 2.6, 1.8), 1.3)
	rubble(Rect2(6.2, -5.5, 2.8, 1.8), 1.7)
	# Canal de maré: bloqueado nas margens, com a passarela (sem colisão) entre x = 3,2 e 4,6.
	water(Rect2(-half.x, -1.4, half.x * 2.0, 2.8), -0.14, "#0b2e2c")
	box(Vector3(-2.9, 0.02, -1.4), Vector3(12.2, 0.12, 0.14), "#3d4538")
	box(Vector3(-2.9, 0.02, 1.4), Vector3(12.2, 0.12, 0.14), "#3d4538")
	box(Vector3(6.8, 0.02, -1.4), Vector3(4.4, 0.12, 0.14), "#3d4538")
	box(Vector3(6.8, 0.02, 1.4), Vector3(4.4, 0.12, 0.14), "#3d4538")
	solid_rects["CanalWest"] = Rect2(-half.x, -1.3, 12.2, 2.6)
	solid_rects["CanalEast"] = Rect2(4.6, -1.3, 4.4, 2.6)
	for plank in 6:
		var rotten := box(Vector3(3.2 + 0.23 + plank * 0.25, 0.04 - (plank % 3) * 0.015, 0.0), Vector3(0.22, 0.05, 2.9 - (plank % 2) * 0.5), "#4a3a24")
		rotten.rotation.y = _rng.randf_range(-0.05, 0.05)
	box(Vector3(3.2, -0.04, 0.0), Vector3(0.06, 0.2, 2.9), "#33281a")
	box(Vector3(4.6, -0.04, 0.0), Vector3(0.06, 0.2, 2.9), "#33281a")
	# Algas luminosas na água (verde doente), comporta de maré enferrujada e canos no fundo.
	for point in [Vector2(-6.0, 0.4), Vector2(-1.0, -0.6), Vector2(1.8, 0.7), Vector2(7.0, -0.3)]:
		var alga := box(Vector3(point.x, -0.04, point.y), Vector3(0.9, 0.02, 0.5), "#3a8a52", false, "", 0.9)
		alga.rotation.y = _rng.randf() * TAU
	box(Vector3(half.x - 0.2, 1.1, 0.0), Vector3(0.3, 2.0, 3.0), "#22302b", true)
	cyl(Vector3(half.x - 0.38, 1.1, 0.0), 0.5, 0.08, "#6b3d24", true).rotation.z = PI * 0.5
	pipe(Vector3(-8.5, 2.2, -5.35), Vector3(5.8, 2.2, -5.35), 0.22, "#34453d")
	pipe(Vector3(0.0, 2.2, -5.35), Vector3(0.0, 0.1, -5.35), 0.16, "#34453d")
	for x in [-6.0, 1.5, 4.8]: drips(Vector3(x, 2.0, -5.1))
	for x in [-5.0, -2.0, 1.0, 3.5]: rust_streak(x, -5.45, _rng.randf_range(1.0, 2.2))
	# Fio de luz frio vindo da grade da rua + o fogareiro da Marlene: é só isso.
	lamp(Vector3(5.0, 2.8, 3.4), "#7fb8ff", 1.0, 5.0, true)
	box(Vector3(5.0, 3.0, 3.4), Vector3(1.0, 0.04, 1.0), "#6fa0d6", false, "", 1.4)
	# Margem norte: acampamento da Marlene com lona rasgada, fogareiro, rádio e vara de pesca.
	box(Vector3(-2.0, 2.0, -3.4), Vector3(3.2, 0.06, 2.0), "#2f4852").rotation.z = 0.06
	for post in [Vector2(-3.5, -4.3), Vector2(-0.5, -4.3), Vector2(-3.5, -2.5), Vector2(-0.5, -2.5)]:
		cyl(Vector3(post.x, 1.0, post.y), 0.04, 2.0, "#42361f")
	box(Vector3(-1.6, 0.18, -3.0), Vector3(0.6, 0.36, 0.5), "#4a3a24", false, "Stool")
	box(Vector3(-2.4, 0.18, -3.8), Vector3(0.34, 0.2, 0.2), "#1c2125", true)
	cyl(Vector3(-0.6, 0.12, -3.6), 0.2, 0.24, "#262a2e", true, "Stove")
	cyl(Vector3(-0.6, 0.3, -3.6), 0.17, 0.12, "#5e6a5e", true)
	lamp(Vector3(-0.6, 0.7, -3.3), "#ff8f3a", 1.5, 3.8, true)
	pipe(Vector3(-4.4, 0.5, -1.7), Vector3(-5.6, 1.4, 0.2), 0.014, "#8a7a52")
	box(Vector3(-6.6, 0.35, -2.4), Vector3(0.9, 0.7, 1.0), "#4a3c26", false, "CrateNorth")
	# Margem sul: barris escondendo a mochila, caixotes podres e um corrimão enferrujado.
	barrel(Vector3(6.4, 0, 3.0), "#33403a")
	barrel(Vector3(6.9, 0, 2.7), "#4a3b28")
	barrel(Vector3(7.7, 0, 2.5), "#33403a")
	crate(Vector3(5.2, 0, 4.4), Vector3(0.9, 0.7, 0.9), "#4a3c26", 0.4)
	crate(Vector3(-5.0, 0, 2.6), Vector3(0.9, 0.62, 0.9), "#433620", 0.2)
	for x in range(-8, 3, 2): cyl(Vector3(float(x), 0.45, 1.75), 0.03, 0.9, "#5a4430", true)
	pipe(Vector3(-8.0, 0.88, 1.75), Vector3(2.0, 0.88, 1.75), 0.02, "#5a4430")
	heap(Vector3(-2.0, 0, 3.4), 0.9, 12, true)
	heap(Vector3(2.4, 0, 4.4), 0.6, 8)
	heap(Vector3(-7.8, 0, -1.6), 0.5, 7)
	scatter_grime(Rect2(-8.5, -5.0, 14.0, 10.0), 18, 12, 0)
	skeleton(Vector3(0.6, 0, 3.2), -0.6)
	graffiti(Vector3(3.0, 1.6, -5.42), Vector2(2.0, 0.9), "#5a4a14")
	graffiti(Vector3(-6.0, 1.7, -5.42), Vector2(1.2, 0.7), "#5a2038")

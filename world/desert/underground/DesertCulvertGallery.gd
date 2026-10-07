extends "res://world/places/sewers/SewerVariantBase.gd"
## Galeria da Rodovia: um bueiro de estrada de verdade, um túnel de concreto de 40 m sob a rodovia do sal, com lama seca
## rachada, dunas de areia entrando pela boca e feixes de sol quente caindo pelas grades da pista. Nada de esgoto: aqui
## só passa água quando enche o leito. Dona Zefa vive no nicho norte (tecelã, com a caixa de latão), Beto Cascavel caça
## cobras no lado leste. Segredo: um tubo lateral escondido atrás de uma duna, na ponta leste, com o dinheiro dos
## contrabandistas de sal e o rifle do Beto.
const REWARDS := [
	{"id": "desert_under_culvert_tin", "kind": "cash", "amount": 900, "local_position": Vector3(-3.4, 0, -4.0)},
	{"id": "desert_under_culvert_stash", "kind": "cash", "amount": 1200, "local_position": Vector3(18.6, 0, 2.4)},
	{"id": "desert_under_culvert_rifle", "kind": "weapon", "item": "hunting_rifle", "amount": 1, "ammo": 12, "local_position": Vector3(18.8, 0, -3.0)},
]
const RESIDENTS := [
	{"id": "desert_under_culvert_zefa", "name": "Dona Zefa", "local_position": Vector3(-4.8, 0, -3.2),
		"appearance": {"coat_color": Color("8a4a32"), "pants_color": Color("4a3a2c"), "appearance_variant": 701, "is_female": true}},
	{"id": "desert_under_culvert_beto", "name": "Beto Cascavel", "local_position": Vector3(11.0, 0, 3.0),
		"appearance": {"coat_color": Color("6a5a3a"), "pants_color": Color("3a362a"), "appearance_variant": 733}},
]

func _build() -> void:
	half = Vector2(20, 5)
	mood = {"tint": Color(0.035, 0.022, 0.008), "base": 0.5, "edge": 0.86, "halo": 3.0, "halo_strength": 0.4}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#7a6d57", ["#8a7c62", "#8f7e60", "#7a6d57", "#968462"])
	walls(2.8, 0.9, 0.35, "#8a8270")
	# Costelas de concreto a cada 4 m (decoração) e a marca d'água das enchentes: uma faixa clara a 1,2 m.
	for x in range(-18, 19, 4):
		box(Vector3(float(x), 1.4, -half.y + 0.12), Vector3(0.5, 2.8, 0.24), "#7a7260")
		box(Vector3(float(x), 0.3, half.y - 0.1), Vector3(0.5, 0.6, 0.2), "#7a7260")
	box(Vector3(0, 1.2, -half.y + 0.03), Vector3(half.x * 2.0, 0.14, 0.03), "#5a4a30")
	# Boca oeste: luz forte, a gente entra por ali (spawn em x = -17). Grade enferrujada e dunas entrando.
	box(Vector3(-half.x + 0.1, 1.2, 0.0), Vector3(0.12, 2.4, 3.2), "#fff0c8", false, "", 2.2)
	lamp(Vector3(-17.6, 1.6, 0.0), "#ffe0a0", 2.2, 6.5)
	for index in 6: box(Vector3(-half.x + 0.3, 1.1, -1.5 + index * 0.6), Vector3(0.06, 2.2, 0.06), "#6a3d22", true)
	for dune in [Vector3(-18.0, 0.3, 2.6), Vector3(-16.4, 0.2, -2.2), Vector3(-14.0, 0.15, 3.2), Vector3(-19.0, 0.4, -1.0)]:
		box(dune, Vector3(2.8, 0.5, 2.0), "#c9b080").rotation.y = dune.x * 0.3
	# Grades da pista: quatro feixes de sol quente com manchas de luz no chão.
	for x in [-8.0, 0.0, 8.0, 15.0]:
		box(Vector3(x, 0.04, 0.4), Vector3(1.6, 0.02, 1.2), "#fff0c0", false, "", 1.6)
		lamp(Vector3(x, 2.4, 0.4), "#ffdca0", 1.7, 6.0, true)
	# Lama seca e rachada, com rastros de pneu.
	for index in 22:
		var crack := box(Vector3(_rng.randf_range(-18.0, 18.0), 0.035, _rng.randf_range(-4.0, 4.0)), Vector3(_rng.randf_range(0.6, 1.6), 0.01, 0.05), "#4a3c28")
		crack.rotation.y = _rng.randf() * PI
	for side in [-1.0, 1.0]:
		for dash in 12: box(Vector3(-17.0 + dash * 1.6, 0.04, side * 0.9), Vector3(0.8, 0.01, 0.16), "#5a4a30")
	# Nicho da Zefa (norte): tapetes, panela no fogo, esteira, caixa de latão e cabras de pano.
	box(Vector3(-4.0, 0.03, -3.4), Vector3(4.2, 0.03, 2.4), "#a8362a")
	box(Vector3(-4.0, 0.04, -3.4), Vector3(3.6, 0.03, 1.8), "#e0b43a")
	box(Vector3(-4.0, 0.05, -3.4), Vector3(2.4, 0.03, 1.2), "#3a6aa8")
	campfire(Vector3(-2.2, 0, -3.4), 1.8)
	cyl(Vector3(-2.2, 0.55, -3.4), 0.18, 0.3, "#3a362f", false, "")
	box(Vector3(-3.4, 0.2, -4.0), Vector3(0.5, 0.3, 0.4), "#9a8438")
	for index in 3: cyl(Vector3(-6.6 + index * 0.4, 0.3, -4.4), 0.16, 0.6, "#b9774a", false, "WaterJar")
	box(Vector3(-5.2, 1.4, -half.y + 0.06), Vector3(1.6, 1.0, 0.03), "#a8362a")
	# Beto Cascavel (leste): gaiolas de cobra, caixotes, pele esticada e o cavalete de trabalho.
	for index in 4: box(Vector3(9.0 + index * 0.9, 0.3, 3.9), Vector3(0.7, 0.6, 0.5), "#6a5a3a", false, "Cage")
	for index in 4: box(Vector3(9.0 + index * 0.9, 0.31, 3.65), Vector3(0.66, 0.5, 0.02), "#2a2418")
	box(Vector3(12.6, 0.4, 2.0), Vector3(2.0, 0.8, 0.8), "#5a4a30", false, "Bench")
	box(Vector3(12.6, 0.84, 2.0), Vector3(0.6, 0.06, 0.2), "#cfc7a8")
	heap(Vector3(6.2, 0, -3.2), 0.7, 9)
	# Carcaça de um carro entalado no meio do túnel (um fusca de ferro-velho) e pneus empilhados.
	box(Vector3(4.4, 0.55, -3.4), Vector3(3.4, 0.9, 1.5), "#5e4a3a", false, "Wreck").rotation.y = 0.12
	box(Vector3(4.2, 1.2, -3.4), Vector3(1.6, 0.5, 1.3), "#3a3a36").rotation.y = 0.12
	for tire in 3: cyl(Vector3(-9.6 + tire * 0.1, 0.18 + tire * 0.3, 3.6), 0.4, 0.28, "#161513", false, "Tires")
	# Segredo (ponta leste): tubo lateral atrás de uma duna; abertura em x = 17,0, z = -2,2..-1,0.
	for wall in [Rect2(16.6, -5.0, 0.4, 2.8), Rect2(16.6, -1.0, 0.4, 6.0)]:
		box(Vector3(wall.get_center().x, 1.0, wall.get_center().y), Vector3(wall.size.x, 2.0, wall.size.y), "#6e6652", false, "SecretWall")
	box(Vector3(16.0, 0.45, -1.6), Vector3(1.4, 0.9, 1.5), "#c9b080").rotation.y = 0.4
	box(Vector3(17.6, 0.25, 2.4), Vector3(1.0, 0.5, 0.6), "#8a7438")
	for index in 5: box(Vector3(19.4, 0.25 + (index % 2) * 0.2, -3.6 + index * 0.2), Vector3(0.6, 0.3, 0.3), "#e8e1cf")
	lamp(Vector3(18.4, 1.2, 0.0), "#ffcf7a", 1.1, 4.0, true)
	scatter_grime(Rect2(-18.0, -4.4, 35.0, 8.8), 0, 0, 0)
	skeleton(Vector3(13.8, 0, -3.8), 0.6)
	graffiti(Vector3(0.0, 1.8, -half.y + 0.05), Vector2(3.0, 0.9), "#6d2a1e")

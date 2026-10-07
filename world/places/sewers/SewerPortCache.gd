extends "res://world/places/sewers/SewerVariantBase.gd"
## Dreno do Porto: uma cisterna apodrecida sob o cais, escura como breu, com três lâmpadas de sódio fracas e tonéis
## tóxicos que brilham em verde. Contrabandistas guardam armas e dinheiro no lado sul; a parte de baixo é usada por
## moradores de rua. Segredo: um cofre no canto nordeste, atrás de uma lona e de canos pendurados (abertura em
## x = 12,2, z = -4,6..-3,2), com o grosso do dinheiro.
const REWARDS := [
	{"id": "sewer_port_rack_ak47", "kind": "weapon", "item": "ak47", "amount": 1, "ammo": 60, "local_position": Vector3(-9.5, 0, 6.2)},
	{"id": "sewer_port_ledger", "kind": "cash", "amount": 900, "local_position": Vector3(-7.7, 0, 6.2)},
	{"id": "sewer_port_safe", "kind": "cash", "amount": 3500, "local_position": Vector3(11.2, 0, 4.5)},
	{"id": "sewer_port_tonho_stash", "kind": "cash", "amount": 300, "local_position": Vector3(-14.4, 0, 3.4)},
	{"id": "sewer_port_vault_cash", "kind": "cash", "amount": 5200, "local_position": Vector3(14.3, 0, -7.2)},
	{"id": "sewer_port_vault_grenades", "kind": "weapon", "item": "grenade", "amount": 1, "ammo": 5, "local_position": Vector3(14.4, 0, -5.4)},
]
const RESIDENTS := [
	{"id": "sewer_port_tonho", "name": "Tonho", "local_position": Vector3(-12.6, 0, 2.5),
		"appearance": {"coat_color": Color("3c4437"), "pants_color": Color("26292c"), "appearance_variant": 206}},
	{"id": "sewer_port_nena", "name": "Dona Nena", "local_position": Vector3(-2.2, 0, 3.6),
		"appearance": {"coat_color": Color("5a4452"), "pants_color": Color("2f2d33"), "appearance_variant": 318, "is_female": true}},
]

func _build() -> void:
	half = Vector2(16, 10)
	mood = {"tint": Color(0.0, 0.008, 0.02), "base": 0.74, "edge": 0.96, "halo": 3.6, "halo_strength": 0.55}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#0b1112", ["#212b29", "#242d27", "#1d2827", "#2c2d20"])
	walls(3.2, 1.0, 0.35, "#222a27")
	ladder(Vector3(-12.6, 0, -8.3))
	# Desabamento no canto sudeste e uma bolsa entulhada a oeste do cofre secreto.
	rubble(Rect2(13.2, 8.0, 2.8, 2.0), 1.6)
	rubble(Rect2(-16.0, 5.6, 2.2, 2.4), 1.5)
	# Canal de drenagem no meio com três passarelas (x = -9,5..-8, 0..1,6 e 10..11,5).
	water(Rect2(-half.x, -0.8, half.x * 2.0, 2.6), -0.14, "#06191c")
	for z in [-0.8, 1.8]: box(Vector3(0, 0.02, z), Vector3(half.x * 2.0, 0.12, 0.14), "#3a4337")
	solid_rects["CanalA"] = Rect2(-half.x, -0.7, 6.5, 2.4)
	solid_rects["CanalB"] = Rect2(-8.0, -0.7, 8.0, 2.4)
	solid_rects["CanalC"] = Rect2(1.6, -0.7, 8.4, 2.4)
	solid_rects["CanalD"] = Rect2(11.5, -0.7, 4.5, 2.4)
	for bridge_x in [-8.75, 0.8, 10.75]:
		box(Vector3(bridge_x, 0.03, 0.5), Vector3(1.5, 0.06, 2.7), "#2e3a36", true)
		for rung in 6: box(Vector3(bridge_x - 0.62 + rung * 0.25, 0.07, 0.5), Vector3(0.05, 0.03, 2.7), "#52605a", true)
	# Cisternas enferrujadas e passarela alta ao longo do fundo.
	for x in [-4.5, 4.5]:
		cyl(Vector3(x, 1.0, -5.6), 2.1, 2.0, "#2d3a35", true, "Cistern")
		cyl(Vector3(x, 2.05, -5.6), 2.15, 0.1, "#4a5a52", true)
		for ring in 3: cyl(Vector3(x, 0.4 + ring * 0.7, -5.6), 2.13, 0.06, "#1d2926", true)
		stain(Vector3(x, 0, -3.1), 1.4, "#0d1210")
	box(Vector3(0, 1.6, -9.0), Vector3(half.x * 2.0 - 4.0, 0.08, 1.2), "#2f3a35", true)
	for x in range(-12, 13, 4):
		cyl(Vector3(float(x), 0.8, -9.4), 0.06, 1.6, "#1d2926", true)
		cyl(Vector3(float(x), 0.8, -8.6), 0.06, 1.6, "#1d2926", true)
	pipe(Vector3(-15.0, 2.7, -9.85), Vector3(15.0, 2.7, -9.85), 0.3, "#34453d")
	pipe(Vector3(-15.0, 2.0, -9.85), Vector3(2.0, 2.0, -9.85), 0.18, "#3d4d44")
	for x in [-11.0, -6.0, 0.0, 6.0, 12.0]: drips(Vector3(x, 2.8, -9.6))
	for x in [-13.0, -9.0, -3.0, 2.0, 8.0, 13.0]: rust_streak(x, -9.92, _rng.randf_range(1.4, 2.6), 3.0)
	# Três lâmpadas de sódio fracas e falhando; tonéis tóxicos brilhando em verde.
	service_lamp(Vector3(-9.0, 3.0, -9.6), "#ff9a3a", 1.2, 6.0, true)
	service_lamp(Vector3(9.0, 3.0, -9.6), "#ff9a3a", 1.0, 6.0, true)
	service_lamp(Vector3(0.0, 3.0, 9.4), "#3a5aff", 0.7, 7.0, true)
	for point in [Vector2(3.0, 3.4), Vector2(-4.6, -1.2)]:
		cyl(Vector3(point.x, 0.32, 0.0 + point.y), 0.24, 0.64, "#1d3a1d", true, "Barrel", 0.0)
		cyl(Vector3(point.x, 0.65, 0.0 + point.y), 0.2, 0.03, "#58ff6a", false, "", 3.0)
		lamp(Vector3(point.x, 0.9, point.y), "#4aff5a", 0.9, 3.6, true)
	# Cache dos contrabandistas (sul): fileira de caixotes, estante de armas e cofre.
	for index in 5:
		crate(Vector3(-4.0 + index * 1.15, 0, 8.3), Vector3(1.05, 0.9, 1.0), ["#4a3c26", "#433620", "#52432c"][index % 3], index * 0.15)
	crate(Vector3(-2.9, 0.9, 8.3), Vector3(0.95, 0.7, 0.9), "#433620", 0.2)
	box(Vector3(-8.6, 0.55, 7.7), Vector3(3.0, 1.1, 0.25), "#2b2823", false, "Rack")
	for plank in 3: box(Vector3(-8.6, 0.3 + plank * 0.35, 7.55), Vector3(3.0, 0.05, 0.12), "#3f3022")
	box(Vector3(12.2, 0.6, 7.6), Vector3(1.4, 1.2, 1.0), "#1f2427", true, "Safe")
	cyl(Vector3(12.2, 0.7, 7.08), 0.22, 0.05, "#8a7a3a", true).rotation.x = PI * 0.5
	box(Vector3(9.4, 0.4, 8.2), Vector3(2.4, 0.8, 1.0), "#3a3128", false, "Pallet")
	for index in 4: barrel(Vector3(5.0 + index * 0.55, 0, 7.4 + (index % 2) * 0.5), ["#33403a", "#4a3b28"][index % 2])
	# Acampamento do Tonho (oeste) e da Dona Nena (centro-sul).
	box(Vector3(-13.6, 0.12, 4.0), Vector3(2.0, 0.24, 1.0), "#403d30")
	box(Vector3(-13.6, 0.26, 4.0), Vector3(1.5, 0.06, 0.9), "#26384a")
	fire_barrel(Vector3(-11.4, 0, 3.2))
	box(Vector3(-13.9, 1.2, 1.3), Vector3(0.04, 1.0, 2.4), "#6a5a2a")
	box(Vector3(-2.0, 0.18, 5.4), Vector3(0.9, 0.36, 0.6), "#4a3a24", false, "Stool")
	cyl(Vector3(-1.2, 0.15, 5.2), 0.2, 0.3, "#262a2e", true, "Stove")
	lamp(Vector3(-1.2, 0.7, 5.0), "#ff8f3a", 1.2, 3.6, true)
	# Cofre secreto (nordeste): paredes com abertura escondida por lona e canos.
	for wall in [Rect2(12.2, -9.6, 0.3, 5.0), Rect2(12.2, -3.2, 0.3, 1.2)]:
		box(Vector3(wall.get_center().x, 0.8, wall.get_center().y), Vector3(wall.size.x, 1.6, wall.size.y), "#2f3530", false, "VaultWall")
	box(Vector3(12.0, 1.0, -3.9), Vector3(0.05, 1.9, 1.7), "#16222b")
	for index in 5: pipe(Vector3(11.8, 0.1, -4.5 + index * 0.35), Vector3(11.8, 2.1, -4.5 + index * 0.35), 0.05, "#3d4d44")
	box(Vector3(14.3, 0.2, -7.2), Vector3(1.6, 0.4, 0.8), "#241c14")
	for index in 3: box(Vector3(15.1, 0.25 + index * 0.45, -8.9), Vector3(0.9, 0.4, 0.7), "#3a362a", false, "VaultCrate")
	lamp(Vector3(14.0, 1.6, -5.8), "#ffb95a", 0.8, 3.4)
	# Sujeira pesada por toda a cisterna.
	heap(Vector3(-6.0, 0, -2.6), 0.9, 12, true)
	heap(Vector3(8.0, 0, 3.4), 0.8, 11, true)
	heap(Vector3(-14.2, 0, -3.0), 0.7, 9)
	heap(Vector3(14.0, 0, 3.6), 0.6, 8)
	scatter_grime(Rect2(-15.0, -8.5, 30.0, 17.5), 34, 16, 0)
	skeleton(Vector3(3.6, 0, 3.2), 0.9)
	skeleton(Vector3(-10.0, 0, 3.8), -1.4)
	graffiti(Vector3(-13.0, 1.9, -9.92), Vector2(2.8, 1.2), "#6d2a1e")
	graffiti(Vector3(7.0, 1.7, -9.92), Vector2(1.8, 0.8), "#223a55")

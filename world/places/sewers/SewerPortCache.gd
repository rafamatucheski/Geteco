extends "res://world/places/sewers/SewerVariantBase.gd"
## Dreno do Porto: a maior cisterna sob o cais. Contrabandistas guardam armas e dinheiro no lado sul; a parte
## de baixo é usada por moradores de rua. Segredo: um cofre no canto nordeste, atrás de uma lona e de canos
## pendurados (abertura em x = 12,2, z = -4,6..-3,2), com o grosso do dinheiro.
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
		"appearance": {"coat_color": Color("4d5646"), "pants_color": Color("33363a"), "appearance_variant": 206}},
	{"id": "sewer_port_nena", "name": "Dona Nena", "local_position": Vector3(-2.2, 0, 3.6),
		"appearance": {"coat_color": Color("73596a"), "pants_color": Color("403d44"), "appearance_variant": 318, "is_female": true}},
]

func _build() -> void:
	half = Vector2(16, 10)
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0))
	walls(3.2)
	ladder(Vector3(-12.6, 0, -8.3))
	# Canal de drenagem no meio com três passarelas (x = -9,5..-8, 0..1,6 e 10..11,5).
	water(Rect2(-half.x, -0.8, half.x * 2.0, 2.6), -0.14, "#0e4650")
	for z in [-0.8, 1.8]: box(Vector3(0, 0.02, z), Vector3(half.x * 2.0, 0.12, 0.14), "#747d68")
	solid_rects["CanalA"] = Rect2(-half.x, -0.7, 6.5, 2.4)
	solid_rects["CanalB"] = Rect2(-8.0, -0.7, 8.0, 2.4)
	solid_rects["CanalC"] = Rect2(1.6, -0.7, 8.4, 2.4)
	solid_rects["CanalD"] = Rect2(11.5, -0.7, 4.5, 2.4)
	for bridge_x in [-8.75, 0.8, 10.75]:
		box(Vector3(bridge_x, 0.03, 0.5), Vector3(1.5, 0.06, 2.7), "#5d6c68", true)
		for rung in 6: box(Vector3(bridge_x - 0.62 + rung * 0.25, 0.07, 0.5), Vector3(0.05, 0.03, 2.7), "#8a9788", true)
	# Cisternas e passarela alta ao longo do fundo.
	for x in [-4.5, 4.5]:
		cyl(Vector3(x, 1.0, -5.6), 2.1, 2.0, "#4f5f58", true, "Cistern")
		cyl(Vector3(x, 2.05, -5.6), 2.15, 0.1, "#7a8a82", true)
		for ring in 3: cyl(Vector3(x, 0.4 + ring * 0.7, -5.6), 2.13, 0.06, "#2f3d3a", true)
	box(Vector3(0, 1.6, -9.0), Vector3(half.x * 2.0 - 4.0, 0.08, 1.2), "#4d5953", true)
	for x in range(-12, 13, 4):
		cyl(Vector3(float(x), 0.8, -9.4), 0.06, 1.6, "#2f3d3a", true)
		cyl(Vector3(float(x), 0.8, -8.6), 0.06, 1.6, "#2f3d3a", true)
	pipe(Vector3(-15.0, 2.7, -9.85), Vector3(15.0, 2.7, -9.85), 0.3, "#61746b")
	pipe(Vector3(-15.0, 2.0, -9.85), Vector3(2.0, 2.0, -9.85), 0.18, "#6e7c74")
	for x in [-11.0, -6.0, 0.0, 6.0, 12.0]: drips(Vector3(x, 2.8, -9.6))
	service_lamp(Vector3(-9.0, 3.0, -9.6), "#ffbd66", 2.4, 8.0, true)
	service_lamp(Vector3(0.0, 3.0, -9.6), "#ffbd66", 2.2, 8.0)
	service_lamp(Vector3(9.0, 3.0, -9.6), "#ffbd66", 2.2, 8.0, true)
	service_lamp(Vector3(0.0, 3.0, 9.4), "#9fd6ff", 1.6, 9.0)
	# Cache dos contrabandistas (sul): fileira de caixotes, estante de armas e cofre.
	for index in 5:
		crate(Vector3(-4.0 + index * 1.15, 0, 8.3), Vector3(1.05, 0.9, 1.0), ["#756347", "#6a5a3f", "#7c6a4a"][index % 3], index * 0.15)
	crate(Vector3(-2.9, 0.9, 8.3), Vector3(0.95, 0.7, 0.9), "#6a5a3f", 0.2)
	box(Vector3(-8.6, 0.55, 7.7), Vector3(3.0, 1.1, 0.25), "#3d3a33", false, "Rack")
	for plank in 3: box(Vector3(-8.6, 0.3 + plank * 0.35, 7.55), Vector3(3.0, 0.05, 0.12), "#5d4a36")
	box(Vector3(12.2, 0.6, 7.6), Vector3(1.4, 1.2, 1.0), "#2f3437", true, "Safe")
	cyl(Vector3(12.2, 0.7, 7.08), 0.22, 0.05, "#c9aa66", true).rotation.x = PI * 0.5
	box(Vector3(9.4, 0.4, 8.2), Vector3(2.4, 0.8, 1.0), "#54483a", false, "Pallet")
	for index in 4: barrel(Vector3(5.0 + index * 0.55, 0, 7.4 + (index % 2) * 0.5), ["#4b655f", "#6b5a3d"][index % 2])
	# Acampamento do Tonho (oeste) e da Dona Nena (centro-sul).
	box(Vector3(-13.6, 0.12, 4.0), Vector3(2.0, 0.24, 1.0), "#6e6a57")
	box(Vector3(-13.6, 0.26, 4.0), Vector3(1.5, 0.06, 0.9), "#3f5a6e")
	fire_barrel(Vector3(-11.4, 0, 3.2))
	box(Vector3(-13.9, 1.2, 1.3), Vector3(0.04, 1.0, 2.4), "#a8883e")
	box(Vector3(-2.0, 0.18, 5.4), Vector3(0.9, 0.36, 0.6), "#7a5c3a", false, "Stool")
	cyl(Vector3(-1.2, 0.15, 5.2), 0.2, 0.3, "#3c3f44", true, "Stove")
	lamp(Vector3(-1.2, 0.7, 5.0), "#ff9d4a", 1.3, 4.0, true)
	# Cofre secreto (nordeste): paredes com abertura escondida por lona e canos.
	for wall in [Rect2(12.2, -9.6, 0.3, 5.0), Rect2(12.2, -3.2, 0.3, 1.2)]:
		box(Vector3(wall.get_center().x, 0.8, wall.get_center().y), Vector3(wall.size.x, 1.6, wall.size.y), "#4d544a", false, "VaultWall")
	box(Vector3(12.0, 1.0, -3.9), Vector3(0.05, 1.9, 1.7), "#2b3a45")
	for index in 5: pipe(Vector3(11.8, 0.1, -4.5 + index * 0.35), Vector3(11.8, 2.1, -4.5 + index * 0.35), 0.05, "#6e7c74")
	box(Vector3(14.3, 0.2, -7.2), Vector3(1.6, 0.4, 0.8), "#3a2f24")
	for index in 3: box(Vector3(15.1, 0.25 + index * 0.45, -8.9), Vector3(0.9, 0.4, 0.7), "#56503f", false, "VaultCrate")
	lamp(Vector3(14.0, 1.6, -5.8), "#ffcf7a", 1.4, 4.0)
	puddle(Vector3(6.0, 0, -2.0), 0.9)
	puddle(Vector3(-6.0, 0, 3.5), 0.8)
	graffiti(Vector3(-13.0, 1.9, -9.92), Vector2(2.8, 1.2), "#d65a3a")
	graffiti(Vector3(7.0, 1.7, -9.92), Vector2(1.8, 0.8), "#5a9ad6")
	graffiti(Vector3(15.0, 1.8, 0.0), Vector2(0.03, 1.4), "#d6b13a")

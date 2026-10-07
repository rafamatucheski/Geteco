extends "res://world/places/sewers/SewerVariantBase.gd"
## Galeria do Armazém: cruzamento de dutos enferrujados sob os galpões, iluminado só por lâmpadas de emergência
## vermelhas que falham. Canal central com duas passarelas, desabamento no fundo, o escritório de manutenção no canto
## nordeste (armário com munição) e, no sudeste, um vão escondido atrás de uma cortina de canos onde a equipe do
## armazém guardava o que não podia constar na nota.
const REWARDS := [
	{"id": "sewer_warehouse_locker", "kind": "weapon", "item": "magnum", "amount": 1, "ammo": 18, "local_position": Vector3(10.2, 0, -4.7)},
	{"id": "sewer_warehouse_cash", "kind": "cash", "amount": 650, "local_position": Vector3(-8.6, 0, 4.9)},
	{"id": "sewer_warehouse_stash", "kind": "cash", "amount": 1800, "local_position": Vector3(10.5, 0, 5.7)},
	{"id": "sewer_warehouse_knuckles", "kind": "weapon", "item": "knuckles", "amount": 1, "local_position": Vector3(10.7, 0, 4.1)},
]
const RESIDENTS := [
	{"id": "sewer_warehouse_zeca", "name": "Zeca", "local_position": Vector3(-6.2, 0, 3.6),
		"appearance": {"coat_color": Color("39424a"), "pants_color": Color("26292d"), "appearance_variant": 133}},
]

func _build() -> void:
	half = Vector2(12, 7)
	mood = {"tint": Color(0.03, 0.006, 0.004), "base": 0.64, "edge": 0.92, "halo": 3.4, "halo_strength": 0.5}
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0), "#150f0d", ["#352c27", "#392f27", "#2e2a26", "#40332a"])
	walls(2.8, 1.0, 0.35, "#352b27")
	ladder(Vector3(-9.6, 0, -5.9))
	# Desabamentos: o teto cedeu no fundo (entre os dutos) e no canto sudoeste.
	rubble(Rect2(-6.6, -7.0, 2.8, 2.5), 2.0, "#2b2522")
	rubble(Rect2(-12.0, 5.2, 2.2, 1.8), 1.4, "#2b2522")
	# Canal central: lama preta, com duas passarelas de grade (x = -4,8..-3,2 e 5,2..6,8).
	water(Rect2(-half.x, -1.6, half.x * 2.0, 3.2), -0.14, "#14110d")
	for z in [-1.6, 1.6]: box(Vector3(0, 0.02, z), Vector3(half.x * 2.0, 0.12, 0.14), "#4a3f35")
	solid_rects["CanalA"] = Rect2(-half.x, -1.5, 7.2, 3.0)
	solid_rects["CanalB"] = Rect2(-3.2, -1.5, 8.4, 3.0)
	solid_rects["CanalC"] = Rect2(6.8, -1.5, 5.2, 3.0)
	for bridge_x in [-4.0, 6.0]:
		box(Vector3(bridge_x, 0.03, 0.0), Vector3(1.6, 0.06, 3.3), "#3f3a34", true)
		for rung in 7: box(Vector3(bridge_x - 0.7 + rung * 0.233, 0.07, 0.0), Vector3(0.05, 0.03, 3.3), "#5a4638", true)
	# Dutos enferrujados no fundo, colunas de pedra rachadas e vazamentos de vapor.
	pipe(Vector3(-3.4, 2.3, -6.8), Vector3(11.5, 2.3, -6.8), 0.26, "#4d3b30")
	pipe(Vector3(-3.4, 1.7, -6.8), Vector3(4.0, 1.7, -6.8), 0.16, "#5a463a")
	pipe(Vector3(11.5, 2.3, -6.8), Vector3(11.5, 0.1, -6.8), 0.18, "#4d3b30")
	for x in [-1.0, 3.0]:
		box(Vector3(x, 1.2, -4.2), Vector3(0.7, 2.4, 0.7), "#3f3a34", false, "Column")
		box(Vector3(x, 1.2, 4.2), Vector3(0.7, 2.4, 0.7), "#3f3a34", false, "Column")
	var valve := TorusMesh.new()
	valve.inner_radius = 0.26
	valve.outer_radius = 0.32
	var wheel := MeshInstance3D.new()
	wheel.mesh = valve
	wheel.material_override = _mat("#6b3d24", true)
	wheel.position = Vector3(-2.2, 1.0, -6.7)
	wheel.rotation.x = PI * 0.5
	add_child(wheel)
	for x in [-9.0, -2.5, 0.5, 7.0]: drips(Vector3(x, 2.1, -6.6))
	for x in [-11.0, -9.0, -3.0, 1.5, 4.5, 8.5]: rust_streak(x, -6.92, _rng.randf_range(1.2, 2.3))
	# Luz de emergência vermelha e fraca, falhando; uma lâmpada azul doente perto do cruzamento sul.
	service_lamp(Vector3(-7.4, 2.7, -6.7), "#ff2a1e", 1.5, 6.0, true)
	service_lamp(Vector3(2.0, 2.7, -6.7), "#ff2a1e", 1.1, 5.0, true)
	service_lamp(Vector3(0.0, 2.7, 6.6), "#4a78ff", 0.7, 5.0, true)
	# Escritório de manutenção (nordeste): porta em x = 6, z = -5,2..-3,6.
	for wall in [Rect2(6.0, -6.9, 0.25, 1.7), Rect2(6.0, -3.6, 0.25, 0.9), Rect2(6.0, -2.95, 5.6, 0.25)]:
		box(Vector3(wall.get_center().x, 0.6, wall.get_center().y), Vector3(wall.size.x, 1.2, wall.size.y), "#3a3732", false, "Office")
	box(Vector3(8.4, 0.38, -5.6), Vector3(1.6, 0.76, 0.8), "#3f3022", false, "Desk")
	box(Vector3(8.2, 0.8, -5.7), Vector3(0.5, 0.04, 0.38), "#9a9684")
	box(Vector3(10.2, 0.9, -6.5), Vector3(1.0, 1.8, 0.5), "#2d3d37", true, "Locker")
	box(Vector3(10.2, 0.9, -6.24), Vector3(0.9, 1.7, 0.02), "#3f564c", true)
	lamp(Vector3(8.4, 1.6, -4.6), "#ffcf7a", 0.9, 4.0, true)
	# Cruzamento sul: caixotes empilhados, barris vazando e o acampamento do Zeca com barril de fogo.
	for stack in [Vector2(-1.5, 4.8), Vector2(-0.4, 5.5), Vector2(0.8, 4.9)]:
		crate(Vector3(stack.x, 0, stack.y), Vector3(1.0, 0.8, 1.0), "#4a3c26", stack.x * 0.2)
	crate(Vector3(-0.9, 0.8, 5.1), Vector3(0.9, 0.6, 0.9), "#433620", 0.3)
	for index in 4:
		barrel(Vector3(3.5 + index * 0.5, 0, 5.6 - (index % 2) * 0.4), ["#33403a", "#4a3b28", "#33403a", "#3a2f20"][index])
		stain(Vector3(3.5 + index * 0.5, 0, 6.0 - (index % 2) * 0.4), 0.45, "#0c0a08")
	box(Vector3(-7.4, 0.12, 4.6), Vector3(1.8, 0.24, 0.9), "#403d30")
	box(Vector3(-7.4, 0.26, 4.6), Vector3(1.4, 0.06, 0.8), "#26384a")
	fire_barrel(Vector3(-5.6, 0, 5.4))
	crate(Vector3(-8.6, 0, 2.6), Vector3(0.8, 0.6, 0.8), "#433620", 0.4)
	for index in 5: cyl(Vector3(-4.6 + index * 0.34, 0.09, 3.1 - (index % 2) * 0.25), 0.04, 0.18, ["#3a5a3e", "#6a5020"][index % 2])
	# Vão secreto (sudeste): parede de tijolo com abertura em z = 5,0..6,2 escondida por uma cortina de canos.
	for wall in [Rect2(8.2, 2.4, 0.3, 2.6), Rect2(8.2, 6.2, 0.3, 0.75)]:
		box(Vector3(wall.get_center().x, 0.65, wall.get_center().y), Vector3(wall.size.x, 1.3, wall.size.y), "#38342f", false, "SecretWall")
	for index in 6:
		pipe(Vector3(8.0, 0.1, 4.95 + index * 0.2), Vector3(8.0, 2.0 + (index % 2) * 0.2, 4.95 + index * 0.2), 0.05 + (index % 3) * 0.015, "#4d3b30")
	box(Vector3(8.0, 1.0, 5.6), Vector3(0.04, 1.8, 1.5), "#1d241f")
	crate(Vector3(10.7, 0, 3.0), Vector3(0.9, 0.7, 0.9), "#3a2f20", 0.2)
	box(Vector3(10.5, 0.2, 5.7), Vector3(1.2, 0.4, 0.7), "#2d2419")
	lamp(Vector3(10.0, 1.4, 5.0), "#ffb95a", 0.8, 3.2)
	# Sujeira: lixo empilhado, manchas escuras, musgo e ossos.
	heap(Vector3(-10.5, 0, 0.8), 0.9, 12, true)
	heap(Vector3(2.0, 0, -3.6), 0.6, 9)
	heap(Vector3(-2.0, 0, 3.0), 0.6, 9)
	scatter_grime(Rect2(-11.5, -6.5, 23.0, 13.0), 22, 12, 0)
	skeleton(Vector3(4.0, 0, 3.0), 2.2)
	graffiti(Vector3(-7.0, 1.6, -6.92), Vector2(2.2, 1.0), "#1f5a3a")
	graffiti(Vector3(2.0, 1.4, -6.92), Vector2(1.4, 0.7), "#6d2a1e")

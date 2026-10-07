extends "res://world/places/sewers/SewerVariantBase.gd"
## Galeria do Armazém: cruzamento de dutos sob os galpões. Um canal central com duas passarelas, o escritório
## de manutenção no canto nordeste (armário com munição) e, no sudeste, um vão escondido atrás de uma cortina
## de canos onde a equipe do armazém guardava o que não podia constar na nota.
const REWARDS := [
	{"id": "sewer_warehouse_locker", "kind": "weapon", "item": "magnum", "amount": 1, "ammo": 18, "local_position": Vector3(10.2, 0, -4.7)},
	{"id": "sewer_warehouse_cash", "kind": "cash", "amount": 650, "local_position": Vector3(-8.6, 0, 4.9)},
	{"id": "sewer_warehouse_stash", "kind": "cash", "amount": 1800, "local_position": Vector3(10.5, 0, 5.7)},
	{"id": "sewer_warehouse_knuckles", "kind": "weapon", "item": "knuckles", "amount": 1, "local_position": Vector3(10.7, 0, 4.1)},
]
const RESIDENTS := [
	{"id": "sewer_warehouse_zeca", "name": "Zeca", "local_position": Vector3(-6.2, 0, 3.6),
		"appearance": {"coat_color": Color("49535c"), "pants_color": Color("2f3338"), "appearance_variant": 133}},
]

func _build() -> void:
	half = Vector2(12, 7)
	floor_slab(Rect2(-half.x, -half.y, half.x * 2.0, half.y * 2.0))
	walls()
	ladder(Vector3(-9.6, 0, -5.9))
	# Canal central com duas passarelas de grade (x = -4,8..-3,2 e 5,2..6,8).
	water(Rect2(-half.x, -1.6, half.x * 2.0, 3.2), -0.14, "#10464a")
	for z in [-1.6, 1.6]: box(Vector3(0, 0.02, z), Vector3(half.x * 2.0, 0.12, 0.14), "#747d68")
	solid_rects["CanalA"] = Rect2(-half.x, -1.5, 7.2, 3.0)
	solid_rects["CanalB"] = Rect2(-3.2, -1.5, 8.4, 3.0)
	solid_rects["CanalC"] = Rect2(6.8, -1.5, 5.2, 3.0)
	for bridge_x in [-4.0, 6.0]:
		box(Vector3(bridge_x, 0.03, 0.0), Vector3(1.6, 0.06, 3.3), "#5d6c68", true)
		for rung in 7: box(Vector3(bridge_x - 0.7 + rung * 0.233, 0.07, 0.0), Vector3(0.05, 0.03, 3.3), "#8a9788", true)
	# Dutos no fundo e colunas de pedra que dividem a nave.
	pipe(Vector3(-11.5, 2.3, -6.8), Vector3(11.5, 2.3, -6.8), 0.26, "#61746b")
	pipe(Vector3(-11.5, 1.7, -6.8), Vector3(4.0, 1.7, -6.8), 0.16, "#6e7c74")
	pipe(Vector3(11.5, 2.3, -6.8), Vector3(11.5, 0.1, -6.8), 0.18, "#61746b")
	for x in [-1.0, 3.0]:
		box(Vector3(x, 1.2, -4.2), Vector3(0.7, 2.4, 0.7), "#6b7462", false, "Column")
		box(Vector3(x, 1.2, 4.2), Vector3(0.7, 2.4, 0.7), "#6b7462", false, "Column")
	var valve := TorusMesh.new()
	valve.inner_radius = 0.26
	valve.outer_radius = 0.32
	var wheel := MeshInstance3D.new()
	wheel.mesh = valve
	wheel.material_override = _mat("#a15c35", true)
	wheel.position = Vector3(-2.2, 1.0, -6.7)
	wheel.rotation.x = PI * 0.5
	add_child(wheel)
	for x in [-9.0, -5.0, 0.5, 7.0]: drips(Vector3(x, 2.1, -6.6))
	service_lamp(Vector3(-6.0, 2.7, -6.7), "#ffbd66", 2.0, 7.0, true)
	service_lamp(Vector3(1.0, 2.7, -6.7), "#ffbd66", 1.8, 6.5)
	service_lamp(Vector3(-2.0, 2.7, 6.6), "#9fd6ff", 1.5, 7.0, true)
	# Escritório de manutenção (nordeste): porta em x = 6, z = -5,2..-3,6.
	for wall in [Rect2(6.0, -6.9, 0.25, 1.7), Rect2(6.0, -3.6, 0.25, 0.9), Rect2(6.0, -2.95, 5.6, 0.25)]:
		box(Vector3(wall.get_center().x, 0.6, wall.get_center().y), Vector3(wall.size.x, 1.2, wall.size.y), "#58625b", false, "Office")
	box(Vector3(8.4, 0.38, -5.6), Vector3(1.6, 0.76, 0.8), "#5d4a36", false, "Desk")
	box(Vector3(8.2, 0.8, -5.7), Vector3(0.5, 0.04, 0.38), "#d8d4c4")
	box(Vector3(10.2, 0.9, -6.5), Vector3(1.0, 1.8, 0.5), "#455e55", true, "Locker")
	box(Vector3(10.2, 0.9, -6.24), Vector3(0.9, 1.7, 0.02), "#5f7a6e", true)
	lamp(Vector3(8.4, 1.6, -4.6), "#ffe3a0", 1.6, 4.5)
	# Cruzamento sul: caixotes empilhados, barris e o acampamento do Zeca com barril de fogo.
	for stack in [Vector2(-1.5, 4.8), Vector2(-0.4, 5.5), Vector2(0.8, 4.9)]:
		crate(Vector3(stack.x, 0, stack.y), Vector3(1.0, 0.8, 1.0), "#756347", stack.x * 0.2)
	crate(Vector3(-0.9, 0.8, 5.1), Vector3(0.9, 0.6, 0.9), "#6a5a3f", 0.3)
	for index in 4: barrel(Vector3(3.5 + index * 0.5, 0, 5.6 - (index % 2) * 0.4), ["#4b655f", "#6b5a3d", "#4b655f", "#5a4b3a"][index])
	box(Vector3(-7.4, 0.12, 4.6), Vector3(1.8, 0.24, 0.9), "#6e6a57")
	box(Vector3(-7.4, 0.26, 4.6), Vector3(1.4, 0.06, 0.8), "#3f5a6e")
	fire_barrel(Vector3(-5.6, 0, 5.4))
	crate(Vector3(-8.6, 0, 2.6), Vector3(0.8, 0.6, 0.8), "#6a5a3f", 0.4)
	for index in 5: cyl(Vector3(-4.6 + index * 0.34, 0.09, 3.1 - (index % 2) * 0.25), 0.04, 0.18, ["#4d7a52", "#8a6a2c"][index % 2])
	# Vão secreto (sudeste): parede de tijolo com uma abertura em z = 5,0..6,2 escondida por uma cortina de canos.
	for wall in [Rect2(8.2, 2.4, 0.3, 2.6), Rect2(8.2, 6.2, 0.3, 0.75)]:
		box(Vector3(wall.get_center().x, 0.65, wall.get_center().y), Vector3(wall.size.x, 1.3, wall.size.y), "#585f52", false, "SecretWall")
	for index in 6:
		pipe(Vector3(8.0 + index * 0.0, 0.1, 4.95 + index * 0.2), Vector3(8.0, 2.0 + (index % 2) * 0.2, 4.95 + index * 0.2), 0.05 + (index % 3) * 0.015, "#6e7c74")
	box(Vector3(8.0, 1.0, 5.6), Vector3(0.04, 1.8, 1.5), "#35403a")
	crate(Vector3(10.7, 0, 3.0), Vector3(0.9, 0.7, 0.9), "#5a4a38", 0.2)
	box(Vector3(10.5, 0.2, 5.7), Vector3(1.2, 0.4, 0.7), "#4a3b2c")
	lamp(Vector3(10.0, 1.4, 5.0), "#ffcf7a", 1.0, 3.5)
	puddle(Vector3(-0.5, 0, -3.5), 0.7)
	puddle(Vector3(4.0, 0, 3.0), 0.8)
	graffiti(Vector3(-7.0, 1.6, -6.92), Vector2(2.2, 1.0), "#3ab07a")
	graffiti(Vector3(2.0, 1.4, -6.92), Vector2(1.4, 0.7), "#d65a3a")

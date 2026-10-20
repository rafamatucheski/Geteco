extends "res://assets/CivilianModel.gd"
## Esquiador de fundo do Cume Branco (20/10/2026): o mesmo rig humano dos pedestres, com duas poses
## próprias. "ski": joelhos dobrados, tronco à frente, braços adiante segurando os bastões e o corpo
## inclinando para dentro da curva (`carve`, -1..1, vindo do MountainSkiers). "lift": sentado na
## cadeira do teleférico. Nos dois a passada de caminhada não roda (o deslocamento é do trilho).
var mode := "ski"
var carve := 0.0
## Batida do bastão: 0..1, sobe quando o MountainSkiers pede uma fincada.
var pole_plant := 0.0

func _measure(delta: float) -> void:
	if mode == "walk":
		super._measure(delta)
		return
	_last_position = global_position
	_speed = 0.0
	_travel = 0.0

func _pose(dt: float) -> void:
	if mode == "lift":
		sit_amount = 1.0
		super._pose(dt)
		return
	if mode != "ski":
		super._pose(dt)
		return
	sit_amount = 0.0
	var lean := clampf(carve, -1.0, 1.0)
	var crouch := 0.2 + 0.05 * absf(lean)
	var pelvis_basis := Basis.from_euler(Vector3(0.22, 0.0, lean * 0.22))
	var pelvis_position := Vector3(lean * 0.05, pelvis_y - crouch, -0.05)
	pelvis.transform = Transform3D(pelvis_basis, pelvis_position)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Esquis paralelos: o pé de dentro da curva recua um pouco e sobe a ponta.
		var inside := side * lean
		_place_leg(i, pelvis_basis, pelvis_position, Vector3(side * 0.12 + lean * 0.06, ankle_height, 0.04 * inside), 0.0)
	var breathe := sin(clock * 2.3 + _seed) * 0.01
	spine.transform = Transform3D(Basis.from_euler(Vector3(0.3 + breathe, -lean * 0.12, -lean * 0.18)), SPINE_OFFSET)
	head_node.transform = Transform3D(Basis.from_euler(Vector3(-0.36, lean * 0.1, lean * 0.12)) * Basis.from_scale(_head_scale), NECK)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		# Mão de dentro da curva vai à frente para fincar o bastão.
		var plant := pole_plant if side * lean < 0.0 else 0.0
		var flex := 0.55 + 0.25 * plant
		var elbow := 1.0 - 0.3 * plant
		upper_arms[i].transform = Transform3D(Basis.from_euler(Vector3(-flex, 0.0, side * 0.32)), _shoulders[i])
		forearms[i].transform = Transform3D(Basis(Vector3.RIGHT, -elbow), Vector3(0, -_arm_measure(i).x, 0))

## Ponta da mão (onde o bastão fica preso), em coordenadas globais.
func hand_point(i: int) -> Vector3:
	return forearms[i].to_global(Vector3(0, -forearm_len, 0))

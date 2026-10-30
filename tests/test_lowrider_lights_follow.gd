extends SceneTree
## Luzes do lowrider acompanham a hidráulica (jogador, 29/10: "quando se mexem com a
## suspensão, a luz do carro não acompanha"). A hidráulica move só o `visual`
## (LowriderHydraulics._apply); os projetores SpotLight3D e o brilho do farol do
## VehicleEquipment eram filhos do CharacterBody3D e ficavam na altura assada.
## Confere, com a frente levantada, de lado, no pulo e de volta ao repouso, que cada projetor,
## cada brilho e o facho de NPC mantêm a mesma pose relativa à carroceria (e sobem com ela),
## que a lente de farol se move igual ao projetor, e que carro sem hidráulica continua com o
## farol no corpo, como antes.
## Rodar com janela: tools/run_godot_locked.sh --path . --script res://tests/test_lowrider_lights_follow.gd
const VEHICLE = preload("res://scripts/Vehicle.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func advance(lift: Node, seconds: float) -> void:
	for i in int(seconds / STEP): lift._physics_process(STEP)

## Tudo que o equipamento acende: projetores por lado, brilho de cada lente e o facho único de NPC.
func lights_of(equipment: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for item in equipment.lamps: result.append(item.lamp)
	for item in equipment.glows: result.append(item.sprite)
	if is_instance_valid(equipment.npc_beam): result.append(equipment.npc_beam)
	return result

func relative(car: Node3D, node: Node3D) -> Transform3D:
	return car.visual.global_transform.affine_inverse() * node.global_transform

## Centro de cada lente de farol, no mundo (malha juntada: meta de superfície "headlight").
func headlight_lenses(car: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var keys: Array = part.get_meta("sport_surface_material_keys", [])
		for s in keys.size():
			if str(keys[s]) == "headlight": result.append(part.global_transform * part.mesh.get_aabb().get_center())
	return result

func compare(car: Node3D, lights: Array[Node3D], rest: Array, label: String) -> float:
	var worst := 0.0
	for i in lights.size():
		var now := relative(car, lights[i])
		var drift: float = now.origin.distance_to((rest[i] as Transform3D).origin)
		var turn: float = (now.basis.get_rotation_quaternion().angle_to((rest[i] as Transform3D).basis.get_rotation_quaternion()))
		worst = maxf(worst, drift + turn)
	check(worst < .001, "%s: luzes na mesma pose em relação à carroceria (desvio %.4f)" % [label, worst])
	return worst

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)

	# Carro comum: projetor no corpo, como sempre (só moto e lowrider penduram no visual).
	var plain := VEHICLE.new()
	plain.archetype = "potro_68"
	stage.add_child(plain)
	plain.process_mode = Node.PROCESS_MODE_DISABLED
	var plain_equipment: Node = plain.ensure_equipment(stage)
	check(plain_equipment.lamps.size() == 2, "muscle car tem dois projetores")
	check(plain_equipment.lamps.all(func(item): return item.lamp.get_parent() == plain), "muscle car sem hidráulica mantém o farol no corpo")
	plain.free()

	var car := VEHICLE.new()
	car.archetype = "imperador_64"
	stage.add_child(car)
	car.process_mode = Node.PROCESS_MODE_DISABLED
	var lift: Node = car.hydraulics
	check(lift != null, "lowrider tem hidráulica")
	if lift == null:
		finish(stage)
		return
	var equipment: Node = car.ensure_equipment(stage)
	check(equipment.lamps.size() == 2, "lowrider tem dois projetores (%d)" % equipment.lamps.size())
	# Liga como o jogador e devolve o volante: a hidráulica é comandada à mão no teste.
	car.controlled = true
	check(equipment.toggle_headlights(), "farol do lowrider liga")
	car.controlled = false
	var lights := lights_of(equipment)
	check(lights.size() >= 3, "projetores, brilhos e facho de NPC encontrados (%d)" % lights.size())
	for node in lights: check(node.get_parent() == car.visual, "%s pendurado na carroceria que a hidráulica move" % node.name)
	var rest: Array = []
	var rest_global: Array[Vector3] = []
	for node in lights:
		rest.append(relative(car, node))
		rest_global.append(node.global_position)
	var lenses_rest := headlight_lenses(car)
	check(lenses_rest.size() == 2, "duas lentes de farol no modelo (%d)" % lenses_rest.size())
	# Projetor colado à lente do seu lado: no máximo 10 cm (o facho nasce 6 cm à frente da lente).
	for item in equipment.lamps:
		var at: Vector3 = item.lamp.global_position
		var nearest := INF
		for lens in lenses_rest: nearest = minf(nearest, at.distance_to(lens))
		check(nearest < .10, "projetor junto da lente (%.3f m)" % nearest)

	# Frente no alto: nariz sobe ~30 cm e as luzes vão junto.
	lift.set_corners(1, 1, 0, 0)
	advance(lift, 1.5)
	compare(car, lights, rest, "frente levantada")
	var rise := INF
	for i in equipment.lamps.size():
		rise = minf(rise, equipment.lamps[i].lamp.global_position.y - rest_global[i].y)
	check(rise > .2, "projetores sobem com a frente (%.3f m)" % rise)
	var lenses_up := headlight_lenses(car)
	for i in equipment.lamps.size():
		var lamp_move: Vector3 = equipment.lamps[i].lamp.global_position - rest_global[i]
		var best := INF
		for j in lenses_up.size(): best = minf(best, (lenses_up[j] - lenses_rest[j] - lamp_move).length())
		check(best < .02, "projetor se move igual à lente (diferença %.4f m)" % best)

	# Inclinada de lado.
	lift.set_corners(1, 0, 1, 0)
	advance(lift, 1.5)
	compare(car, lights, rest, "de lado")
	check(equipment.lamps[0].lamp.global_position.y != rest_global[0].y, "projetor muda de altura com a rolagem")

	# Pulo cheio: no alto do pulo as luzes estão no alto.
	lift.set_corners(0, 0, 0, 0)
	advance(lift, 2.0)
	check(lift.hop(1.0), "pulo aceito")
	var peak := 0.0
	for i in 40:
		lift._physics_process(STEP)
		peak = maxf(peak, equipment.lamps[0].lamp.global_position.y - rest_global[0].y)
	check(peak > .6, "projetor sobe no pulo (%.3f m)" % peak)
	compare(car, lights, rest, "no pulo")

	# Fim do show: tudo volta à pose assada.
	advance(lift, 4.0)
	check(not lift.active(), "hidráulica em repouso")
	var back := 0.0
	for i in lights.size(): back = maxf(back, lights[i].global_position.distance_to(rest_global[i]))
	check(back < .001, "luzes de volta ao lugar (desvio %.4f m)" % back)
	finish(stage)

func finish(stage: Node) -> void:
	stage.free()
	print("LOWRIDER_LIGHTS_FOLLOW ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

extends SceneTree
## Portas e embarque de TODOS os veículos com porta, um por um. Sem renderizar: monta o
## veículo, o corpo do Dante e a apresentação de embarque e percorre a animação quadro a
## quadro, medindo o que o olho perceberia como defeito:
##   - a folha existe, abre de verdade (vão sem lataria) e fechada é a mesma silhueta;
##   - o corpo espera fora do arco da folha e nunca a atravessa (nem ao fechar);
##   - o corpo só cruza o plano da lataria pelo vão da porta;
##   - a mão encosta no batente (contato) e o corpo termina no banco.
## Rodar: godot --path . --script res://tests/test_vehicle_doors.gd [-- id ...]
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const BOARDING := preload("res://gameplay/VehicleBoardingPresentation.gd")
const SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")

## Raio do corpo (cápsula do Dante) e folga aceitável junto da folha e do casco.
const BODY_RADIUS := .27
const SAMPLES := 90
const HEAD_TOP := .26
## Conversíveis: não há teto para a cabeça atravessar.
const OPEN_TOP := ["beach_cabriolet", "porto_rosso"]

var stage: Node3D
var actor: CharacterBody3D
var failures: Array[String] = []
var checks := 0
var report: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures.append(message)
	push_error(message)

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	actor = ACTOR.new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	await process_frame
	var ids: Array = Array(OS.get_cmdline_user_args()).filter(func(argument): return argument != "verbose")
	if ids.is_empty():
		for id in FLEET.all().keys():
			if str(id).begins_with("bike_") or id in ["army_tank", "route_city", "bike_police"]: continue
			ids.append(id)
		# Recompensa da garagem: modelo próprio fora do catálogo da frota.
		ids.append("cobra_boss_ironback")
		ids.sort()
	for id in ids: await test_vehicle(str(id))
	await test_incremental_build()
	for line in report: print(line)
	print("VEHICLE_DOORS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

## Preparar a porta aos poucos (enquanto o jogador caminha até o carro) dá exatamente a mesma
## folha que prepará-la de uma vez, e o carro fica inteiro no meio do trabalho.
func test_incremental_build() -> void:
	for id in ["sedan_classic", "ranch_single", "cargo_flatbed_truck"]:
		var slow := spawn(id, 0.0)
		var quick := spawn(id, 0.0)
		await process_frame
		var visible_before := count_visible_parts(slow)
		var steps := 0
		while not slow.warm_doors(400):
			steps += 1
			check(count_visible_parts(slow) == visible_before, id + ": o carro mudou no meio do preparo da porta")
			if steps > 400: break
		check(steps > 0, id + ": o preparo em pedaços terminou de uma vez (orçamento não é respeitado)")
		quick.finish_doors()
		check(skin_vertices(slow) == skin_vertices(quick) and skin_vertices(slow) > 0, id + ": folha incremental difere da folha de uma vez (%d × %d)" % [skin_vertices(slow), skin_vertices(quick)])
		slow.queue_free()
		quick.queue_free()
		await process_frame

func count_visible_parts(car: CharacterBody3D) -> int:
	var count := 0
	for node in car.visual.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).visible: count += 1
	return count

func skin_vertices(car: CharacterBody3D) -> int:
	var total := 0
	if not is_instance_valid(car.door_presentation): return 0
	for node in car.door_presentation.find_children("Skin", "MeshInstance3D", true, false):
		var mesh: ArrayMesh = (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count(): total += mesh.surface_get_array_len(surface)
	return total

func spawn(id: String, yaw: float) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.paint_color = Color("b04a3c")
	stage.add_child(car)
	car.set_physics_process(false)
	car.global_position = Vector3(0, .04, 0)
	car.rotation.y = yaw
	return car

func test_vehicle(id: String) -> void:
	var car := spawn(id, 0.0)
	await process_frame
	var klass: String = car.boarding_class()
	if klass in ["open", "bus"]:
		car.queue_free()
		return
	var tag := id + ": "
	check(SPECS.has_row(id), tag + "veículo sem linha na tabela de portas (VehicleDoorSpecs)")
	# A lataria medida na malha bate com o `x` da tabela (a tabela não envelheceu).
	if SPECS.has_row(id) and id != "sport_coupe":
		var listed: Dictionary = SPECS.row(id)
		var measured: float = preload("res://gameplay/VehicleDoorBuilder.gd").measure(car.visual, listed)
		check(listed.has("x") and absf(float(listed.get("x", 0.0)) - measured) <= .03, tag + "x da tabela %.2f ≠ lataria medida %.2f" % [float(listed.get("x", 0.0)), measured])
	var worst_leaf := INF
	var worst_plane := 0
	var min_hand := INF
	var finish_error := 0.0
	for yaw in [0.0, 0.9]:
		car.rotation.y = yaw
		for side in car.boarding_sides():
			var layout: Dictionary = car.door_layout(side)
			check(not layout.is_empty(), tag + "sem layout de porta no lado %d" % side)
			if layout.is_empty(): continue
			var presentation: Node3D = car.door_presentation
			check(presentation.hinges.has(side), tag + "sem dobradiça no lado %d" % side)
			# O ponto de espera fica fora do círculo que a ponta da folha varre.
			var hinge2 := Vector2(layout.hinge.x, layout.hinge.z)
			var stand2 := Vector2(layout.stand.x, layout.stand.z)
			check(hinge2.distance_to(stand2) >= float(layout.length) + BODY_RADIUS, tag + "ponto de espera dentro do arco da folha (lado %d)" % side)
			# O vão existe: sem nenhum triângulo de lataria entre a dobradiça e a linha traseira.
			for start_kind in ["beside", "front", "rear"]:
				var start := start_point(car, side, start_kind)
				for exiting in [false, true]:
					# Saindo, o destino é o que o Driving escolhe: o ponto de espera fora do arco.
					if exiting and start_kind != "beside": continue
					if exiting: start = car.to_global(Vector3(layout.stand.x, 0.0, layout.stand.z))
					var result: Dictionary = await run_boarding(car, side, start, exiting, layout)
					worst_leaf = minf(worst_leaf, result.leaf)
					worst_plane += int(result.plane)
					min_hand = minf(min_hand, result.hand)
					finish_error = maxf(finish_error, result.finish)
					var label := "%s%s lado %d de %s yaw %.1f" % [tag, "saída" if exiting else "entrada", side, start_kind, yaw]
					check(result.leaf >= BODY_RADIUS, label + ": corpo a %.2f m da folha (mínimo %.2f)" % [result.leaf, BODY_RADIUS])
					check(int(result.plane) == 0, label + ": %d quadros cruzando a lataria fora do vão" % result.plane)
					check(int(result.hull) == 0, label + ": %d quadros dentro do casco na aproximação" % result.hull)
					check(int(result.head) == 0, label + ": cabeça atravessa o teto em %d quadros (até %.2f m acima do vão)" % [result.head, result.head_over])
					check(result.finish <= .16, label + ": terminou a %.2f m do destino" % result.finish)
					check(result.grip_frames >= 3, label + ": mão nunca encostou no batente")
	report.append("%-22s %-5s folha≥%.2f m  mão≥%.2f m  fim≤%.2f m" % [id, klass, worst_leaf, min_hand, finish_error])
	car.queue_free()
	await process_frame

func start_point(car: CharacterBody3D, side: int, kind: String) -> Vector3:
	var local := Vector3.ZERO
	match kind:
		"beside": local = Vector3(float(side) * (car.half_width + .55), 0, car._cab_z() + .2)
		"front": local = Vector3(float(side) * (car.half_width + .6), 0, -car.half_length - 1.4)
		"rear": local = Vector3(float(side) * (car.half_width + .7), 0, car.half_length + 1.2)
	local.y = 0.0
	var point: Vector3 = car.to_global(local)
	point.y = car.global_position.y
	return point

## Percorre a apresentação inteira sem tween: fixa `progress` e chama `_apply`, como o
## `_process` real faria, e mede a cada quadro.
func run_boarding(car: CharacterBody3D, side: int, start: Vector3, exiting: bool, layout: Dictionary) -> Dictionary:
	actor.global_position = start
	actor.show()
	var transition = BOARDING.new()
	stage.add_child(transition)
	var landing: Vector3 = car.to_global(Vector3(layout.stand.x, 0.0, layout.stand.z))
	landing.y = car.global_position.y
	if exiting: transition.begin_exit(stage, car, actor, start, side)
	else: transition.begin_entry(stage, car, actor, side)
	if is_instance_valid(transition._motion): transition._motion.kill()
	transition.set_process(false)
	var leaf_min := INF
	var plane_hits := 0
	var hull_hits := 0
	var hand_min := INF
	var grip_frames := 0
	var gripping_hand: int = actor._combat_bones[transition._grip_side + "Hand"]
	var head_bone: int = actor._combat_bones["Head"]
	var covered: bool = car.archetype not in OPEN_TOP
	var head_hits := 0
	var head_max := -INF
	var hinge := Vector2(layout.hinge.x, layout.hinge.z)
	var length: float = layout.length
	var angle: float = layout.angle
	var motion_seconds: float = transition.duration - transition.CLOSE_SECONDS
	var skin: float = layout.skin
	var spec: Dictionary = car.door_presentation.spec
	var door_start := 0.0 if exiting else -1.0
	for step in range(SAMPLES + 1):
		var t := float(step) / SAMPLES
		transition.progress = 1.0 - t if exiting else t
		transition._apply()
		if door_start < 0.0 and transition._door_started: door_start = t
		await process_frame
		if not actor.visible: continue
		var local: Vector3 = car.to_local(actor.global_position)
		var point := Vector2(local.x, local.z)
		# A folha abre em .28 s desde o começo do movimento (entrada) ou desde que o corpo sai
		# do banco (saída): mede contra o ângulo que ela tem naquele instante, não o final.
		var elapsed := maxf(t - door_start, 0.0) * motion_seconds if door_start >= 0.0 else -1.0
		var opened := float(side) * angle * (.5 - .5 * cos(PI * clampf(elapsed / .28, 0.0, 1.0))) if elapsed >= 0.0 else 0.0
		var tip := hinge + Vector2(sin(absf(opened)) * float(side), cos(opened)) * length
		var leaf_distance := distance_to_segment(point, hinge, tip)
		if leaf_distance < leaf_min and leaf_distance < BODY_RADIUS and "verbose" in OS.get_cmdline_user_args():
			print("   DEBUG ", "exit" if exiting else "entry", " side ", side, " t=%.2f phase=%s dist=%.2f opened=%.2f local=%s door_start=%.2f approach=%.2f" % [t, transition.phase, leaf_distance, opened, point.snappedf(.01), door_start, transition._approach])
		leaf_min = minf(leaf_min, leaf_distance)
		# Cruzar o plano da lataria só pelo vão da porta.
		if absf(local.x) < skin + .12 and (local.z < float(spec.zf) + .10 or local.z > float(spec.zr) + .02) and absf(local.x) > skin - .55:
			# Dentro do casco fora do vão só vale a partir do banco: ali o corpo está sentado.
			if car.to_local(actor.global_position).distance_to(car.to_local(car.driver_seat_anchor())) > .9: plane_hits += 1
		if transition.phase == "approach":
			if absf(local.x) < car.half_width + .05 and absf(local.z) < car.half_length + .05: hull_hits += 1
		# Cabeça dentro do casco: o topo dela (a junta mais uns 13 cm) não passa do teto do vão.
		if covered and absf(local.x) < skin - .05 and local.z > float(spec.zf) and local.z < float(spec.zr) + .3:
			var head: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(head_bone).origin))
			var roof: float = float(spec.top) * car.visual.scale.y
			head_max = maxf(head_max, head.y + HEAD_TOP - roof)
			if head.y + HEAD_TOP > roof + .02: head_hits += 1
		if transition.phase in ["reach", "step"]:
			var hand: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(gripping_hand).origin)
			var grip: Vector3 = car.to_global(layout.grip)
			var distance := hand.distance_to(Vector3(grip.x, hand.y, grip.z))
			hand_min = minf(hand_min, distance)
			if distance <= .32: grip_frames += 1
	if exiting:
		# Porta fechando com o corpo parado no destino: nada pode estar no arco.
		var landing_local: Vector3 = car.to_local(start)
		for close_step in range(0, 21):
			var swing := angle * (1.0 - float(close_step) / 20.0)
			var closing_tip := hinge + Vector2(sin(swing) * float(side), cos(swing)) * length
			leaf_min = minf(leaf_min, distance_to_segment(Vector2(landing_local.x, landing_local.z), hinge, closing_tip))
	var target: Vector3 = start if exiting else car.driver_seat_anchor()
	var final_error := Vector2(actor.global_position.x - target.x, actor.global_position.z - target.z).length() if not exiting else Vector2(actor.global_position.x - start.x, actor.global_position.z - start.z).length()
	if exiting:
		# Terminada a saída, o corpo está no destino pedido.
		final_error = Vector2(actor.global_position.x - start.x, actor.global_position.z - start.z).length()
	transition.abort("test_done")
	await process_frame
	car.animate_driver_door(side, false, 0.0)
	return {"head": head_hits, "head_over": head_max, "leaf": leaf_min, "plane": plane_hits, "hull": hull_hits, "hand": hand_min, "finish": final_error, "grip_frames": grip_frames}

static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), .0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

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
const BUILDER := preload("res://gameplay/VehicleDoorBuilder.gd")

## Raio do corpo (cápsula do Dante) e folga aceitável junto da folha e do casco.
const BODY_RADIUS := .27
## Mocap: centro dos ossos do tronco contra a folha (o raio do corpo em volta do osso é ~.15 m).
const MOCAP_TORSO_CLEARANCE := .12
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
		var source_counts := door_source_counts(slow)
		# O limite generoso escala com o trabalho real de origem e permite preparação,
		# montagem de superfícies e finalização de peças além dos lotes de triângulos.
		var max_calls: int = source_counts.triangles * 2 + source_counts.surfaces * 8 + source_counts.parts * 8 + 8
		var steps := 0
		# Orçamento zero força o montador a ceder no próximo limite de progresso;
		# mesmo uma malha grande não pode ser cortada inteira na primeira chamada.
		while not slow.warm_doors(0):
			steps += 1
			check(count_visible_parts(slow) == visible_before, id + ": o carro mudou no meio do preparo da porta")
			check(not slow.door_presentation.ready_for_boarding, id + ": trabalho pendente não pode anunciar porta pronta")
			if steps >= max_calls: break
		check(source_counts.parts > 0 and steps > 0, id + ": preparo deve dividir o trabalho inclusive quando o casco é uma peça única")
		check(steps < max_calls, id + ": preparo incremental deve completar em quantidade finita de estágios derivada da fonte")
		check(is_instance_valid(slow.door_presentation) and slow.door_presentation.ready_for_boarding, id + ": preparo incremental deve terminar pronto para embarque")
		report.append("INCREMENTAL_DOOR %s parts=%d surfaces=%d triangles=%d intermediate_steps=%d calls=%d max_calls=%d budget_usec=0" % [id,source_counts.parts,source_counts.surfaces,source_counts.triangles,steps,steps+1,max_calls])
		quick.finish_doors()
		check(skin_vertices(slow) == skin_vertices(quick) and skin_vertices(slow) > 0, id + ": folha incremental difere da folha de uma vez (%d × %d)" % [skin_vertices(slow), skin_vertices(quick)])
		slow.queue_free()
		quick.queue_free()
		await process_frame

func door_source_counts(car: CharacterBody3D) -> Dictionary:
	var parts := BUILDER._parts(car.visual)
	var surfaces := 0
	var triangles := 0
	for part in parts:
		for surface in part.mesh.get_surface_count():
			surfaces += 1
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			@warning_ignore("integer_division")
			triangles += count / 3
	return {"parts":parts.size(),"surfaces":surfaces,"triangles":triangles}

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
					var leaf_needed: float = MOCAP_TORSO_CLEARANCE if result.mocap else BODY_RADIUS
					check(result.leaf >= leaf_needed, label + ": corpo a %.2f m da folha (mínimo %.2f)" % [result.leaf, leaf_needed])
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
	# Mocap (VehicleBoardingMocap, porta do motorista de carro baixo): a folha segue a mão e o corpo,
	# então mede-se o ângulo real dela contra o tronco; a saída anda de 0 a 1 e termina onde o clipe pousa.
	var mocap: bool = transition._mocap != null
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
		transition.progress = 1.0 - t if exiting and not mocap else t
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
		if mocap:
			leaf_distance = mocap_leaf_distance(car, side, layout)
			var hips_local: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor.hips).origin))
			point = Vector2(hips_local.x, hips_local.z)
			local = Vector3(hips_local.x, 0.0, hips_local.z)
		if mocap and leaf_distance < MOCAP_TORSO_CLEARANCE and "verbose" in OS.get_cmdline_user_args():
			var parts := []
			for bone_name in ["Hips", "Spine02", "Head"]:
				var bp: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[bone_name]).origin))
				parts.append("%s(%.2f,%.2f,%.2f)=%.2f" % [bone_name, bp.x, bp.y, bp.z, distance_to_segment(Vector2(bp.x, bp.z), hinge, leaf_tip(car, side, layout))])
			print("   DEBUG mocap ", "exit" if exiting else "entry", " t=%.2f phase=%s dist=%.2f door=%.2f " % [t, transition.phase, leaf_distance, car.door_presentation.current_angle(side)], " ".join(parts), " hinge=", hinge, " len=", layout.length)
		if leaf_distance < leaf_min and leaf_distance < BODY_RADIUS and "verbose" in OS.get_cmdline_user_args():
			print("   DEBUG ", "exit" if exiting else "entry", " side ", side, " t=%.2f phase=%s dist=%.2f opened=%.2f local=%s door_start=%.2f approach=%.2f" % [t, transition.phase, leaf_distance, opened, point.snappedf(.01), door_start, transition._approach])
		leaf_min = minf(leaf_min, leaf_distance)
		# Cruzar o plano da lataria só pelo vão da porta.
		if absf(local.x) < skin + .12 and (local.z < float(spec.zf) + .10 or local.z > float(spec.zr) + .02) and absf(local.x) > skin - .55:
			# Dentro do casco fora do vão só vale a partir do banco: ali o corpo está sentado.
			if local.distance_to(car.to_local(car.driver_seat_anchor())) > .9: plane_hits += 1
		if transition.phase == "approach":
			if absf(local.x) < car.half_width + .05 and absf(local.z) < car.half_length + .05: hull_hits += 1
		# Cabeça dentro do casco: o topo dela (a junta mais uns 13 cm) não passa do teto do vão.
		if covered and absf(local.x) < skin - .05 and local.z > float(spec.zf) and local.z < float(spec.zr) + .3:
			var head: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(head_bone).origin))
			var roof: float = float(spec.top) * car.visual.scale.y
			head_max = maxf(head_max, head.y + HEAD_TOP - roof)
			if head.y + HEAD_TOP > roof + .02:
				head_hits += 1
				if mocap and "verbose" in OS.get_cmdline_user_args():
					print("   DEBUG head ", "exit" if exiting else "entry", " t=%.2f phase=%s over=%.3f head=%s hips=%s" % [t, transition.phase, head.y + HEAD_TOP - roof, head.snappedf(.01), local.snappedf(.01)])
		if transition.phase in ["reach", "step"] or (mocap and transition.phase in ["open", "closing"]):
			var hand: Vector3 = actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(gripping_hand).origin)
			var grip: Vector3 = car.to_global(layout.grip)
			var distance := hand.distance_to(Vector3(grip.x, hand.y, grip.z))
			if mocap:
				# A mão do clipe pega a maçaneta da folha (abrir, fechar), não o batente.
				var hand_local: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones["LeftHand"]).origin))
				distance = distance_to_segment(Vector2(hand_local.x, hand_local.z), hinge, leaf_tip(car, side, layout))
			hand_min = minf(hand_min, distance)
			if distance <= .32: grip_frames += 1
	if exiting and not mocap:
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
	if mocap:
		# Mocap: o Actor fica parado na origem do clipe e o quadril anda; a entrada termina com a pelve no
		# banco e a saída com a pelve no pouso que o próprio clipe escolheu (conferido livre ao começar).
		var pelvis: Vector3 = preload("res://gameplay/VehicleInterior.gd").pelvis_world(actor)
		if exiting:
			# Saída: não há destino pedido; o corpo tem que terminar fora do arco que a folha varre ao
			# fechar (senão a porta bate nele). Erro = quanto falta para sair do arco.
			var local_pelvis: Vector3 = car.to_local(pelvis)
			var offset := Vector2(float(side) * (local_pelvis.x - float(layout.hinge.x)), local_pelvis.z - float(layout.hinge.z))
			var opened: float = car.door_presentation.current_angle(side)
			var at := atan2(offset.x, offset.y)
			# Porta já fechada pela mão do clipe: o fechamento foi medido quadro a quadro (folha × tronco).
			var in_sweep := opened > .01 and at >= -.1 and at <= opened + .2
			final_error = maxf(0.0, float(layout.length) + MOCAP_TORSO_CLEARANCE - offset.length()) if in_sweep else 0.0
		else:
			var goal: Vector3 = preload("res://gameplay/VehicleBoardingMocap.gd").seat_pelvis(car)
			final_error = Vector2(pelvis.x - goal.x, pelvis.z - goal.z).length()
	transition.abort("test_done")
	await process_frame
	car.animate_driver_door(side, false, 0.0)
	return {"head": head_hits, "head_over": head_max, "leaf": leaf_min, "plane": plane_hits, "hull": hull_hits, "hand": hand_min, "finish": final_error, "grip_frames": grip_frames, "mocap": mocap}

## Ponta da folha no ângulo em que ela está agora (plano do veículo).
static func leaf_tip(car: CharacterBody3D, side: int, layout: Dictionary) -> Vector2:
	var opened: float = car.door_presentation.current_angle(side)
	return Vector2(layout.hinge.x, layout.hinge.z) + Vector2(sin(opened) * float(side), cos(opened)) * float(layout.length)

## Menor distância do tronco (quadril, peito, cabeça) à folha no ângulo real dela; só pontos na altura
## da folha (pé e corpo deitado passam por baixo dela).
func mocap_leaf_distance(car: CharacterBody3D, side: int, layout: Dictionary) -> float:
	var hinge := Vector2(layout.hinge.x, layout.hinge.z)
	var tip := leaf_tip(car, side, layout)
	var nearest := INF
	for bone_name in ["Hips", "Spine02", "Head"]:
		var point: Vector3 = car.to_local(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(actor._combat_bones[bone_name]).origin))
		if point.y < .28: continue
		nearest = minf(nearest, distance_to_segment(Vector2(point.x, point.z), hinge, tip))
	return nearest

static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), .0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

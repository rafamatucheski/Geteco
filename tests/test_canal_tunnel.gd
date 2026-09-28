extends SceneTree
## Túnel do canal: piso contínuo e com rampa ≤ 12,5 %, vão livre sob o teto, cais por
## cima intacto, mar recortado, trânsito NPC fora do túnel e um carro físico de verdade
## (mundo de produção) que desce pela boca oeste, passa sob a quay_boulevard e o canal e
## sobe na ilha sem cair nem bater no teto; depois o mesmo carro percorre o cais por cima.
## Uso: "$GODOT" --path . --script res://tests/test_canal_tunnel.gd -- --no-save
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))

func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 300:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var production = world.production
	var region: Node3D = production.region
	check(region != null and region.region_id == "harbor", "Mundo começa em Harbor")
	var car: CharacterBody3D = world.driving.car
	# Entra no carro como o jogador (o foco do streaming segue o carro dirigido).
	# Começa no acesso em nível, fora da pista da warehouse_way (trânsito ali parava o teste).
	var start := Vector3(141.6, 0.12, TUNNEL.inner_south() - 2.0)
	car.place(start, -PI * 0.5)
	for i in 3: await physics_frame
	var entered := false
	for side in [-1, 1]:
		world.player.teleport(car.to_global(Vector3(side * (car.half_width + .65), .04, .15)))
		await physics_frame
		if world.driving.interact(): entered = true; break
	check(entered, "Jogador entra no carro")
	# --- Estrutura estática, célula a célula (o streaming só mantém o entorno do carro) ---
	var worst_grade := 0.0
	var holes: Array[float] = []
	var low_ceiling: Array[float] = []
	var signs := {}
	for cell_x in [2, 3, 4, 5]:
		var stop: float = cell_x * 64.0 + 32.0
		car.place(Vector3(stop, TUNNEL.floor_y(stop) + 0.12, TUNNEL.CENTER_Z + 1.6), -PI * 0.5)
		for i in 900:
			await physics_frame
			if i > 5 and region.is_streaming_idle(): break
		for sign in region.find_children("CanalTunnelSign", "Label3D", true, false): signs[sign.global_position.snapped(Vector3.ONE)] = true
		var x: float = maxf(cell_x * 64.0, TUNNEL.W_TOP)
		var previous := TUNNEL.floor_y(x)
		while x <= minf(cell_x * 64.0 + 64.0, TUNNEL.E_TOP):
			var y := TUNNEL.floor_y(x)
			worst_grade = maxf(worst_grade, absf(y - previous) / 0.5)
			previous = y
			for z in [TUNNEL.CENTER_Z - 1.6, TUNNEL.CENTER_Z + 1.6]:
				var hit := ray(Vector3(x, y + 1.0, z), Vector3(x, y - 1.0, z))
				if hit.is_empty() or absf(hit.position.y - y) > 0.06:
					holes.append(x)
					if holes.size() == 1: print("CANAL_TUNNEL buraco x=%.1f hit=%s" % [x, hit.get("position", "nada")])
				# 3,5 m livres na faixa (limite anunciado na placa).
				var roof := ray(Vector3(x, y + 0.2, z), Vector3(x, y + 3.5, z))
				if not roof.is_empty():
					low_ceiling.append(x)
					if low_ceiling.size() == 1: print("CANAL_TUNNEL teto em ", roof.position, " ", roof.collider.get_path())
			x += 0.5
		if cell_x == 2:
			# Cais por cima: laje do túnel sustenta a quay_boulevard na altura da rua.
			for z in [TUNNEL.outer_north() + 0.2, TUNNEL.CENTER_Z, TUNNEL.outer_south() - 0.2]:
				for qx in [183.0, 188.0, 191.5]:
					var lid := ray(Vector3(qx, 4.0, z), Vector3(qx, -3.0, z))
					check(not lid.is_empty() and absf(lid.position.y) < 0.05, "Quay_boulevard firme sobre o túnel em x=%.1f z=%.1f (%s)" % [qx, z, str(lid.get("position", "nada")) + " " + (str(lid.collider.get_path()) if not lid.is_empty() else "")])
	print("CANAL_TUNNEL rampa_max=%.3f buracos=%s teto_baixo=%s" % [worst_grade, holes.slice(0, 6), low_ceiling.slice(0, 6)])
	check(worst_grade <= 0.126, "Rampa ≤ 12,5 %% (%.3f)" % worst_grade)
	check(holes.is_empty(), "Piso contínuo em todo o túnel")
	check(low_ceiling.is_empty(), "3,5 m livres sob o teto em todo o túnel")
	check(signs.size() == 2, "Placas nos dois pórticos (%d)" % signs.size())
	check(TUNNEL.floor_y((TUNNEL.SHORE_W + TUNNEL.SHORE_E) * 0.5) <= -5.9, "Tubo a -6 m sob o canal")
	# Mar opaco recortado sobre a vala/tubo; lâmina translúcida própria no canal.
	var water_over := 0
	for mesh in region.find_children("Water", "MeshInstance3D", true, false):
		var data: ArrayMesh = mesh.mesh
		var arrays := data.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in range(0, idx.size(), 3):
			var c: Vector3 = (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
			if TUNNEL.open_cuts()[0].has_point(Vector2(c.x, c.z)) or TUNNEL.open_cuts()[1].has_point(Vector2(c.x, c.z)) or Rect2(TUNNEL.SHORE_W, TUNNEL.outer_north(), TUNNEL.SHORE_E - TUNNEL.SHORE_W, TUNNEL.outer_south() - TUNNEL.outer_north()).has_point(Vector2(c.x, c.z)):
				water_over += 1
	check(water_over == 0, "Mar não desenha sobre a vala/tubo (%d triângulos)" % water_over)
	check(region.find_children("*", "Light3D", true, false).filter(func(n): return n.get_parent() != null and str(n.get_path()).contains("CanalTunnel")).is_empty(), "Túnel sem luzes dinâmicas")
	# Trânsito NPC usa o túnel (rua virtual "canal_tunnel", ver CanalTunnel3D.traffic_roads),
	# mas nenhuma rua de superfície pode se ligar a um nó abaixo do nível da rua: isso
	# seria cruzamento falso com a quay_boulevard ou a esplanada por cima.
	var graph = production.traffic_routes
	var false_crossings := 0
	var tunnel_edges := 0
	for from in graph.edges:
		for edge in graph.edges[from]:
			if edge.id == TUNNEL.TRAFFIC_ID:
				tunnel_edges += 1
				continue
			if graph.vertices[edge.from].y < -0.5 or graph.vertices[edge.to].y < -0.5: false_crossings += 1
	check(tunnel_edges >= 4, "Túnel no grafo de trânsito nos dois sentidos (%d)" % tunnel_edges)
	check(false_crossings == 0, "Nenhuma rua de superfície ligada ao fundo do túnel (%d)" % false_crossings)

	# --- Carro físico atravessa ---
	# As paradas de inspeção acima teleportam o carro entre células (trânsito, trancas);
	# a travessia começa com o carro inteiro e destravado.
	# Um teleporte pode cair na área de um serviço/loja e abrir menu modal (trava o carro).
	if world.session.get("modal") == true: world.session.close_menu()
	paused = false
	car.health = car.max_health
	car.input_locked = false
	car.set_external_driver(true)
	car.place(start, -PI * 0.5)
	for i in 3: await physics_frame
	var lane_z := TUNNEL.CENTER_Z + 1.6
	var lowest := 10.0
	var ceiling_hits := 0
	var wall_hits := 0
	var blockers := 0
	var stuck_prints := 0
	var worst_gap := 0.0
	var reached := false
	for frame in 3600:
		var forward := -car.global_basis.z
		var error: float = lane_z - car.global_position.z
		car.steer_input = clampf(-0.35 * error + 2.5 * forward.z, -1.0, 1.0)
		car.throttle_input = 1.0 if car.speed < 13.0 else 0.0
		car.brake_input = false
		car.input_locked = false
		# Algo do jogo (entrada do jogador ao volante) às vezes devolve o controle ao teclado.
		if not car.external_input: car.set_external_driver(true)
		await physics_frame
		var p := car.global_position
		lowest = minf(lowest, p.y)
		# Teto = estrutura estática acima do carro (alguém caindo em cima não conta).
		for c in car.get_slide_collision_count():
			var hit_top := car.get_slide_collision(c)
			if hit_top.get_collider() is StaticBody3D and hit_top.get_normal().y < -0.7:
				ceiling_hits += 1
				print("CANAL_TUNNEL teto tocado em ", p, " piso=%.2f " % TUNNEL.floor_y(p.x), (hit_top.get_collider() as Node).get_path())
		# Parede = só estrutura estática; carro estacionado/trânsito na east_union não conta.
		for c in car.get_slide_collision_count():
			var col := car.get_slide_collision(c)
			if not col.get_collider() is StaticBody3D and blockers < 3:
				blockers += 1
				var who = col.get_collider()
				print("CANAL_TUNNEL obstáculo móvel em ", p, " ", who.get_path() if who is Node else who, " ", who.get_script().resource_path if who is Node and who.get_script() else "")
			if col.get_collider() is StaticBody3D and absf(col.get_normal().y) < 0.7:
				wall_hits += 1
				print("CANAL_TUNNEL parede em ", p, " n=", col.get_normal(), " ", (col.get_collider() as Node).get_path())
		if p.x > TUNNEL.W_TOP and p.x < TUNNEL.E_TOP: worst_gap = maxf(worst_gap, absf(p.y - TUNNEL.floor_y(p.x)))
		if p.y < -8.0: break
		if frame > 120 and absf(car.speed) < 0.3 and stuck_prints < 4:
			stuck_prints += 1
			print("CANAL_TUNNEL travou f=%d pos=%s parede=%s n_parede=%s chao=%s n_chao=%s" % [frame, p, car.is_on_wall(), car.get_wall_normal(), car.is_on_floor(), car.get_floor_normal()])
			for c in car.get_slide_collision_count():
				var col := car.get_slide_collision(c)
				print("    col n=%s em %s shape=%d %s" % [col.get_normal(), col.get_position(), col.get_collider_shape_index(), col.get_collider()])
		# Saiu da vala e já rodou 4 m em nível no acesso da exchange_lane.
		if p.x > TUNNEL.E_TOP + 4.0: reached = true; break
	var end := car.global_position
	if not reached:
		var probe := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(8, 3, 4)
		probe.shape = box
		probe.transform = Transform3D(Basis.IDENTITY, end + Vector3(3, 1.2, 0))
		probe.collision_mask = 0xFFFF
		probe.exclude = [car.get_rid()]
		for hit in root.world_3d.direct_space_state.intersect_shape(probe, 16):
			var node = hit.collider
			print("CANAL_TUNNEL perto do carro parado: ", node.get_path() if node is Node else node, " ", node.global_position if node is Node3D else "", " camada=", node.get("collision_layer"))
		print("CANAL_TUNNEL parado vel=%.2f thr=%.1f ext=%s ctrl=%s colisoes=%d" % [car.speed, car.throttle_input, car.external_input, car.controlled, car.get_slide_collision_count()])
		for ci in car.get_slide_collision_count():
			var hit: KinematicCollision3D = car.get_slide_collision(ci)
			print("CANAL_TUNNEL colide com %s n=%s em %s" % [str(hit.get_collider().name), str(hit.get_normal().snapped(Vector3.ONE*.01)), str(hit.get_position().snapped(Vector3.ONE*.1))])
		for c in car.get_slide_collision_count(): print("   ", car.get_slide_collision(c).get_normal(), " ", car.get_slide_collision(c).get_collider())
	print("CANAL_TUNNEL carro fim=%s mais_baixo=%.2f desvio_piso=%.2f teto=%d parede=%d" % [end, lowest, worst_gap, ceiling_hits, wall_hits])
	check(reached, "Carro sai pela boca leste (x=%.1f)" % end.x)
	check(lowest < -5.5 and lowest > -6.3, "Carro passou pelo fundo do tubo (%.2f)" % lowest)
	check(worst_gap < 0.6, "Carro acompanha o piso, sem voar nem afundar (%.2f)" % worst_gap)
	check(ceiling_hits == 0, "Não bate no teto")
	check(wall_hits == 0, "Não raspa nas paredes na faixa")
	check(absf(end.y) < 0.3, "Termina no nível da rua na ilha")

	# --- Quay_boulevard continua transitável por cima ---
	if world.session.get("modal") == true: world.session.close_menu()
	car.input_locked = false
	car.place(Vector3(186.0, 0.12, 44.0), PI)
	for i in 3: await physics_frame
	var quay_low := 10.0
	var quay_done := false
	for frame in 600:
		var forward := -car.global_basis.z
		var error: float = 186.0 - car.global_position.x
		car.steer_input = clampf(0.35 * error - 2.5 * forward.x, -1.0, 1.0)
		car.throttle_input = 1.0 if car.speed < 12.0 else 0.0
		car.input_locked = false
		# Algo do jogo (entrada do jogador ao volante) às vezes devolve o controle ao teclado.
		if not car.external_input: car.set_external_driver(true)
		await physics_frame
		quay_low = minf(quay_low, car.global_position.y)
		# Basta cruzar a faixa do túnel: mais adiante o trânsito do cais pode parar o carro.
		if car.global_position.z > TUNNEL.outer_south() + 3.0: quay_done = true; break
	print("CANAL_TUNNEL cais fim=%s mais_baixo=%.2f" % [car.global_position, quay_low])
	check(quay_done, "Carro atravessa o cais sobre o túnel")
	check(quay_low > -0.1, "Cais sem degrau nem buraco (%.2f)" % quay_low)
	print("CANAL_TUNNEL failures=%s" % [failures])
	print("CANAL_TUNNEL ", "PASS" if failures.is_empty() else "FAIL")
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

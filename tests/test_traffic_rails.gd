extends SceneTree
## Contratos funcionais; a opção --count-west conta modos sem medir FPS.
const RAILS := preload("res://gameplay/traffic/TrafficRails.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const PROJECTILE := preload("res://gameplay/Projectile.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")

class TestGameplay extends Node3D:
	var _police_rounds: Array = []
	var aim_point := Vector3.ZERO
	var aiming := false
	func aim_feedback_active() -> bool: return aiming

class TestWorld extends Node3D:
	var player: Node3D
	var gameplay: TestGameplay
	var production: Node
	var session: Node

class TestCannon extends Node3D:
	var shells: Array = []

class RailCar extends "res://scripts/Vehicle.gd":
	var rotation_queries := 0
	func _ready() -> void:
		set_physics_process(false)
		collision_layer = 4
		collision_mask = 7
		floor_snap_length = .4
		shape = CollisionShape3D.new()
		var hull := BoxShape3D.new()
		hull.size = Vector3(2.08,1.4,4.6)
		shape.shape = hull
		shape.position.y = .7
		add_child(shape)
		rotation_shape.size = hull.size-Vector3(0,.15,0)
		sensor_shape.size = Vector3(2.15,1.2,1)
		add_to_group("drivable")
	func can_rotate(yaw: float) -> bool:
		rotation_queries += 1
		return super.can_rotate(yaw)

var failures: Array[String] = []
var checks := 0
var world: TestWorld
var car: RailCar
var test_camera: Camera3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func solid(position_value: Vector3, size: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.position = position_value
	return body

func reset_car() -> void:
	if is_instance_valid(car): car.free()
	car = RailCar.new()
	world.add_child(car)
	car.position = Vector3(100,.02,0)
	car.route = Curve3D.new()
	car.route.bake_interval = .2
	car.route.add_point(Vector3(100,0,2))
	car.route.add_point(Vector3(100,0,-300))
	car.route.set_meta("traffic_open",true)
	car.set_meta("ambient_traffic",true)
	car.traffic = true
	world.player.position = Vector3.ZERO
	world.gameplay.aiming = false
	world.gameplay._police_rounds.clear()
	# Pousar com o solver real: um único passo pode terminar ainda acima do piso.
	for step in 30:
		await physics_frame
		car.velocity.y -= 20.0/Engine.physics_ticks_per_second
		car.move_and_slide()
		if car.is_on_floor(): break
	check(car.is_on_floor(),"Admissão usa apoio físico real")
	car.velocity = Vector3.ZERO
	car.speed = 3.0
	car.horizontal_velocity = Vector3(0,0,-3)
	await physics_frame

func tick() -> void:
	await physics_frame
	car._stall_physics_tick(1.0/Engine.physics_ticks_per_second)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if "--count-west" in OS.get_cmdline_user_args():
		await count_west()
		return
	if "--inspect-edited" in OS.get_cmdline_user_args():
		await inspect_edited()
		return
	world = TestWorld.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	world.gameplay = TestGameplay.new()
	world.add_child(world.gameplay)
	test_camera = Camera3D.new()
	world.add_child(test_camera)
	test_camera.make_current()
	solid(Vector3(100,-.5,-149),Vector3(8,1,310))
	await reset_car()
	var original := car.global_position
	var velocity_before := car.horizontal_velocity
	car.traffic_rails = RAILS.new()
	var ready: bool = car.traffic_rails.prepare(car,1.0/60.0)
	check(ready == RAILS.enabled,"Interruptor controla admissão ao trilho")
	check(car.global_position == original and car.horizontal_velocity == velocity_before,"Preparar trilho não altera posição nem velocidade")
	var rail_ticks := 0
	var max_error := 0.0
	var max_jump := 0.0
	for step in Engine.physics_ticks_per_second*30:
		var before := car.global_position
		await tick()
		if car.traffic_rails.active: rail_ticks += 1
		max_error = maxf(max_error,absf(car.position.x-100))
		max_jump = maxf(max_jump,car.global_position.distance_to(before))
	check(car.position.z < -140,"Motorista real avança por 30 segundos")
	check(max_error < .1 and absf(car.position.y-.02)<.05,"Carro continua na rua e apoiado")
	check(max_jump < .5,"Entrada e percurso não causam salto")
	check(rail_ticks > Engine.physics_ticks_per_second*29 if RAILS.enabled else rail_ticks == 0,"Trilho permanece ativo longe; desligado conserva física")
	print("TRAFFIC_RAILS percurso passos_trilho=%d erro_lateral=%.4f maior_deslocamento=%.4f" % [rail_ticks,max_error,max_jump])
	world.player.position = car.position+Vector3(20,0,0)
	if RAILS.enabled: car._lod_pending = 3.0/60.0
	var near_before := car.position
	await tick()
	check(not car.traffic_rails.active,"Aproximar jogador devolve física")
	check(car.position.distance_to(near_before)<(.3 if RAILS.enabled else .5),"Retorno respeita o passo físico do modo selecionado")
	if RAILS.enabled:
		check(car._lod_pending == 0,"Retorno do trilho limpa tempo acumulado")
	else:
		check(car._lod_stride() == 4 and car._lod_skipped >= 0,"Desligado conserva o LOD original distante da câmera")
	if RAILS.enabled:
		await enabled_cases()
	world.free()
	await process_frame
	print("TRAFFIC_RAILS checks=%d falhas=%s interruptor=%s" % [checks,failures,RAILS.enabled])
	quit(0 if failures.is_empty() else 1)

func inspect_edited() -> void:
	# Diagnóstico dirigido da falha de integração; mantém geometria, prazo e motorista.
	var scene = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival",true)
	root.add_child(scene)
	for frame in 1800:
		await process_frame
		if scene.session != null and scene.session.ready_for_play: break
	check(scene.production != null,"Diagnóstico: mundo admitido")
	if not failures.is_empty(): scene.free(); quit(1); return
	Engine.physics_ticks_per_second = 180
	var samples: Array = []
	# Isolar a segunda conversão evita a disputa de admissão após a primeira.
	for spec in [["medical_garden_lane","warehouse_way"]]:
		var graph = scene.production.traffic_routes
		var path: Array[int] = []
		for at in graph.edges:
			var incoming := -1
			var outgoing := -1
			for edge in graph.edges[at]:
				if edge.id == spec[0] and graph.vertices[edge.to].x<graph.vertices[at].x: incoming = edge.to
				if edge.id == spec[1] and graph.vertices[edge.to].z>graph.vertices[at].z: outgoing = edge.to
			if incoming>=0 and outgoing>=0: path = [incoming,at,outgoing]; break
		if path.is_empty(): check(false,"Diagnóstico: conversão disponível"); continue
		var center: Vector3 = graph.vertices[path[1]]
		scene.player.teleport(center+Vector3(-10,.1,-10))
		scene.player.controlled_automatically = true
		scene.player.automatic_direction = Vector3.ZERO
		scene.production._update_physical_residency(scene.player.position)
		for frame in 180: await physics_frame
		var route: Curve3D = graph._curve(path,false)
		route.set_meta("traffic_open",true)
		var crossing := route.get_closest_offset(center)
		var start := maxf(0,crossing-12)
		var point := route.sample_baked(start,true)
		var ahead := route.sample_baked(start+.5,true)-point
		var vehicle = scene.production.spawn_vehicle("union_sedan",point+Vector3.UP*.12,atan2(-ahead.x,-ahead.z))
		if vehicle == null: check(false,"Diagnóstico: carro admitido"); continue
		vehicle.route = route
		vehicle.route_distance = start
		vehicle.traffic = true
		var began := Time.get_ticks_msec()
		var last_sample := began-1000
		var target := minf(route.get_baked_length()-2,crossing+8)
		while Time.get_ticks_msec()-began<45000 and vehicle.route_distance<target:
			await physics_frame
			if Time.get_ticks_msec()-last_sample<1000: continue
			last_sample = Time.get_ticks_msec()
			var owners: Array = []
			for junction in vehicle._junction_list:
				for id in JUNCTIONS.owners.get(junction.key,{}):
					var body := instance_from_id(id) as Node3D
					owners.append({"key":str(junction.key),"id":id,"position":str(body.global_position) if is_instance_valid(body) else "liberado","rails":body.get("traffic_rails") != null and body.traffic_rails.active if is_instance_valid(body) else false,"occupies":JUNCTIONS.occupies(junction.key,id)})
			var exit_bodies: Array = []
			if vehicle._exit_blocked:
				for junction in vehicle._junction_list:
					var at: float = junction.offset+JUNCTIONS.EXIT+vehicle.half_length+1.0
					var right: Vector3 = vehicle._route_right(at,route.get_baked_length(),true)
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = vehicle.rotation_shape
					query.collision_mask = 4
					query.exclude = [vehicle.get_rid()]
					query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),vehicle._route_point(at,route.get_baked_length(),true)+Vector3.UP*vehicle.shape.position.y)
					for hit in vehicle.get_world_3d().direct_space_state.intersect_shape(query,4):
						var body: Node3D = hit.collider
						exit_bodies.append({"key":str(junction.key),"id":body.get_instance_id(),"position":str(body.global_position),"speed":body.get("speed"),"ambient":body.get_meta("ambient_traffic",false),"rails":body.get("traffic_rails") != null and body.traffic_rails.active})
			var sample := {"road":spec[0],"position":str(vehicle.position),"progress":vehicle.route_distance,"target":target,"speed":vehicle.speed,"blocked":vehicle.blocked,"junction_wait":vehicle.junction_wait,"gap":vehicle.junction_gap,"held":str(vehicle._held_junction),"exit_blocked":vehicle._exit_blocked,"own_rails":vehicle.traffic_rails != null and vehicle.traffic_rails.active,"floor":vehicle.is_on_floor(),"wall":vehicle.is_on_wall(),"phase":JUNCTIONS._phase_time,"blocker":str(vehicle.blocker) if is_instance_valid(vehicle.blocker) else "","owners":owners,"exit_bodies":exit_bodies}
			samples.append(sample)
			print("TRAFFIC_RAILS_INSPECT ",JSON.stringify(sample))
		check(vehicle.route_distance>=target,"Diagnóstico: passagem "+spec[0])
		vehicle.free()
	var output := FileAccess.open("res://evidence/traffic-rails-20261013/inspect-enabled.json" if RAILS.enabled else "res://evidence/traffic-rails-20261013/inspect-disabled.json",FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"enabled":RAILS.enabled,"samples":samples,"failures":failures},"\t"))
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func enabled_cases() -> void:
	await reset_car()
	world.player.position = Vector3(100,0,50)
	test_camera.position = Vector3(100,3,50)
	await tick()
	check(not car.traffic_rails.active,"Carro visível a 50 m continua físico")
	await reset_car()
	world.player.position = Vector3(50,0,0)
	test_camera.position = Vector3(50,3,0)
	await tick()
	check(car.traffic_rails.active,"Carro fora da tela a 50 m entra em trilho")
	await reset_car()
	world.player.position = Vector3(100,0,80)
	test_camera.position = Vector3(100,3,80)
	await tick()
	check(car.traffic_rails.active,"Carro visível além de 70 m entra em trilho")
	test_camera.position = Vector3.ZERO
	await reset_car()
	await tick()
	check(car.traffic_rails.active,"Carro distante entra em trilho")
	var neighbor := solid(car.position+Vector3(1.4,.7,0),Vector3(1,1,1),4)
	var contact_position := car.position
	await tick()
	check(not car.traffic_rails.active and car.traffic_rails.force_physics,"Vizinho que pode esbarrar força física no mesmo passo")
	check(car.position.x < contact_position.x-.02,"Solver físico resolve o esbarrão lateral real")
	neighbor.free()
	await reset_car()
	await tick()
	var incoming := RailCar.new()
	world.add_child(incoming)
	incoming.position = car.position+Vector3(12,0,0)
	incoming.velocity = Vector3.LEFT*120
	await tick()
	check(not car.traffic_rails.active,"Veículo rápido vindo de fora da esfera também acorda o trânsito")
	incoming.free()
	await reset_car()
	await tick()
	var swapped_position := car.position
	var replacement := car.route.duplicate() as Curve3D
	car.route = replacement
	car.traffic_rails.prepare(car,1.0/60.0)
	check(not car.traffic_rails.active and car.position == swapped_position,"Troca de rota acorda sem reposicionar")
	await reset_car()
	await tick()
	car.position.z -= 5.0
	var relocated := car.position
	car.traffic_rails.prepare(car,1.0/60.0)
	check(not car.traffic_rails.active and car.position == relocated,"Reposicionamento externo não retorna ao ponto antigo do trilho")
	await reset_car()
	await tick()
	car.controlled = true
	car.external_input = true
	car.traffic_rails.prepare(car,1.0/60.0)
	check(not car.traffic_rails.active,"Condutor externo devolve física imediatamente")
	await reset_car()
	await tick()
	var damage_position := car.position
	var damage_velocity := car.horizontal_velocity
	car.receive_damage(1)
	check(not car.traffic_rails.active and car.position == damage_position and car.horizontal_velocity == damage_velocity,"Dano acorda imediatamente sem reposicionar ou perder velocidade")
	await tick()
	check(not car.traffic_rails.active,"Reação ao dano impede reentrada imediata")
	car.engine_disabled = true
	car.traffic_rails.wake(car)
	car.traffic_rails.prepare(car,1.0/60.0)
	check(car.traffic_rails.force_physics,"Despertar externo não é perdido quando outro estado impede trilho")
	for key in ["mission_vehicle","dispatch_unit","race_owned","awaiting_ground","gang_hostile"]:
		await reset_car()
		car.set_meta(key,true)
		await tick()
		check(not car.traffic_rails.active,"Exclusão de "+key)
	await reset_car()
	car.remove_meta("ambient_traffic")
	await tick()
	check(car.traffic_rails == null,"Trânsito de atividade sem marca ambiente conserva física")
	await reset_car()
	car.position.z = -292
	await tick()
	check(not car.traffic_rails.active,"Fim de rota permanece físico para retorno")
	await reset_car()
	await tick()
	world.gameplay._police_rounds.append({"point":car.position+Vector3(-10,.7,0),"direction":Vector3.RIGHT,"speed":100.0,"range":100.0,"distance":0.0})
	await tick()
	check(not car.traffic_rails.active,"Segmento de bala rápida acorda antes do contato")
	await reset_car()
	await tick()
	var grenade := PROJECTILE.new()
	grenade.set_physics_process(false)
	world.gameplay.add_child(grenade)
	grenade.position = car.position+Vector3(5,.1,0)
	await tick()
	check(not car.traffic_rails.active,"Granada sem corpo físico também força física")
	grenade.free()
	await reset_car()
	await tick()
	var tank := RailCar.new()
	world.add_child(tank)
	tank.position = Vector3(300,0,0)
	var cannon := TestCannon.new()
	tank.add_child(cannon)
	tank.tank_cannon = cannon
	cannon.shells.append({"point":car.position+Vector3(-10,.7,0),"direction":Vector3.RIGHT,"remaining":100.0})
	await tick()
	check(not car.traffic_rails.active,"Projétil de tanque também acorda antes da explosão")
	tank.free()
	await reset_car()
	await tick()
	world.gameplay.aiming = true
	world.gameplay.aim_point = car.position+Vector3.UP*.7
	await tick()
	check(not car.traffic_rails.active,"Veículo na linha de mira volta à física")
	await reset_car()
	var wall := solid(Vector3(100,1,-8),Vector3(8,2,1))
	for step in 180: await tick()
	check(car.position.z > -5.3,"Casco não atravessa prédio na rota")
	wall.free()
	var curved_ground := solid(Vector3(200,-.5,-70),Vector3(100,1,100))
	await reset_car()
	var loop := Curve3D.new()
	loop.bake_interval = .2
	for index in 361:
		var angle := TAU*float(index)/360.0
		loop.add_point(Vector3(200+40*cos(angle),0,-70-40*sin(angle)))
	car.route = loop
	car.position = loop.get_point_position(0)+Vector3.UP*.001
	var curve_error := 0.0
	var curve_rails := 0
	for step in 600:
		await tick()
		curve_error = maxf(curve_error,absf(Vector2(car.position.x-200,car.position.z+70).length()-40))
		if car.traffic_rails.active: curve_rails += 1
	check(curve_rails >= 590 and curve_error < .1,"Trilho segue curva suave sem cortar a rua")
	check(car.route_distance > 40,"Carro avança normalmente pela curva fechada")
	curved_ground.free()
	await reset_car()
	await tick()
	var support := world.get_children().filter(func(node): return node is StaticBody3D)
	for body in support: body.free()
	await tick()
	check(not car.traffic_rails.active,"Perda do chão devolve a física sem avançar no vazio")

func count_west() -> void:
	var scene = load("res://Main.tscn").instantiate()
	scene.set_meta("skip_arrival",true)
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if scene.session != null and scene.session.ready_for_play: break
	if scene.session == null or not scene.session.ready_for_play:
		push_error("Contagem P2: sessão não concluiu admissão")
		quit(1)
		return
	await create_timer(30.0).timeout
	var rails := 0
	var physical := 0
	var suspended := 0
	var distant := 0
	var distant_rails := 0
	var distant_physical := 0
	var distance_probe := RAILS.new()
	for vehicle in scene.production.vehicles:
		if not is_instance_valid(vehicle) or not vehicle.traffic or vehicle.health<=0 or not vehicle.get_meta("ambient_traffic",false): continue
		if not vehicle.is_physics_processing() or vehicle.has_meta("awaiting_ground"):
			suspended += 1
			continue
		var on_rails: bool = vehicle.traffic_rails != null and vehicle.traffic_rails.active
		if on_rails: rails += 1
		else: physical += 1
		if distance_probe._far(vehicle):
			distant += 1
			if on_rails: distant_rails += 1
			else: distant_physical += 1
	print("TRAFFIC_RAILS_OESTE ligado=%s trilho=%d fisica=%d suspensos=%d distantes=%d distantes_trilho=%d distantes_fisica=%d jogador=%s" % [RAILS.enabled,rails,physical,suspended,distant,distant_rails,distant_physical,scene.player.global_position])
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--count-output="): continue
		var output := FileAccess.open(argument.trim_prefix("--count-output="),FileAccess.WRITE)
		if output != null:
			output.store_string(JSON.stringify({"enabled":RAILS.enabled,"rails":rails,"physical":physical,"suspended":suspended,"distant":distant,"distant_rails":distant_rails,"distant_physical":distant_physical,"player":str(scene.player.global_position)},"\t"))
		else: check(false,"Não foi possível gravar a contagem")
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

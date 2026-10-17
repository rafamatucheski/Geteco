extends "res://tools/capture_promo_20261007.gd"
## Trailer de 30 s (17/10): câmeras de cinema em perspectiva sobre o jogo de verdade, sem HUD.
## Só captura; nada de produção muda e exige --no-save. Gravação:
##   tools/run_godot_locked.sh --path . --resolution 1920x1080 --write-movie <cena>.avi --fixed-fps 30 \
##     --script res://tools/capture_promo_20261017.gd -- --no-save --promo-scene=<cena> --promo-out=<pasta>
## --promo-scene=scout tira fotos de reconhecimento (sem filme) para escolher enquadramentos.
## A montagem fica em tools/build_promo_20261017.py.

const MOUNTAIN_PLACES = preload("res://world/places/PlaceCatalog.gd")
var cine_fov := 50.0
## Câmera suavizada para planos de perseguição: posição e mira seguem o alvo com atraso,
## senão cada solavanco da física vira tremida na tela.
var smooth_from := Vector3.INF
var smooth_at := Vector3.INF

func extra_scene() -> void:
	world.gameplay.god_mode = true
	world.gameplay.health = 100000
	match scene_id:
		"scout": await scout()
		"vistas": await vistas()
		"parque": await parque()
		"corrida": await corrida()
		"policia": await policia()
		"tiroteio": await tiroteio()
		"arrancada": await arrancada()
		"moto": await moto()
		"serra": await serra()
		"deserto": await deserto()
		_: require(false,"Cena desconhecida: "+scene_id)

func cine(fov := 50.0) -> Camera3D:
	if is_instance_valid(camera): camera.queue_free()
	camera = Camera3D.new()
	camera.fov = fov
	camera.near = .08
	camera.far = 2500
	camera.environment = cine_environment()
	world.add_child(camera)
	camera.make_current()
	smooth_from = Vector3.INF
	smooth_at = Vector3.INF
	return camera

func look(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	if not from.is_equal_approx(at): camera.look_at(at,Vector3.UP if absf((at-from).normalized().y) < .98 else Vector3.FORWARD)
	camera.make_current()

func follow(from: Vector3, at: Vector3, weight := .12) -> void:
	if smooth_from == Vector3.INF:
		smooth_from = from
		smooth_at = at
	smooth_from = smooth_from.lerp(from,weight)
	smooth_at = smooth_at.lerp(at,weight*1.4)
	look(spring_arm(smooth_at,smooth_from),smooth_at)

## Braço com mola: se houver parede/teto entre o alvo e a câmera, a câmera para antes dele.
## Sem isso ela entrava em prédios e o jogo mostrava a silhueta de raio X do carro.
func spring_arm(target: Vector3, wanted: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(target,wanted,1)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return wanted
	return hit.position+(target-wanted).normalized()*.6

func smooth01(t: float) -> float:
	return t*t*(3.0-2.0*t)

func settle_streaming(limit_ms := 30000) -> void:
	var deadline := Time.get_ticks_msec()+limit_ms
	await frames(10)
	while not world.production.region.is_streaming_idle() and Time.get_ticks_msec() < deadline: await process_frame
	await frames(20)

func stage_at(point: Vector3) -> void:
	world.production.region.set_focus(point)
	world.production.region.prepare_collision_at(point)
	world.player.teleport(point)
	world.camera.initialized = false
	await settle_streaming()

func still(label: String) -> void:
	clean_overlay()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(output.path_join(label+".jpg"),.88)
	print("PROMO_STILL ",label)

## Viagem sem destino forçado: o ponto de chegada da região sempre tem chão; o plano
## reposiciona o jogador depois com stage_at().
func go_region(region: String) -> bool:
	if world.session.state.region_id == region: return true
	if region == "desert":
		var fixture: Dictionary = preload("res://tests/fixtures/NorthGatewayFixtures.gd").full_snapshot(world.player.global_position,true,true)
		world.session.state.campaign.restore_snapshot(fixture.campaign)
	# Logo depois da carga o ponto de chegada às vezes está ocupado e a viagem desiste
	# em silêncio ("Destino ocupado"): espera e tenta de novo.
	if region == "mountain" and world.session.state.region_id == "harbor":
		# No reconhecimento a viagem só concluiu partindo da cabeceira da ponte.
		await stage_at(ground(Vector3(430,0,-285))+Vector3.UP*.12)
	for attempt in 4:
		await frames(120)
		if not world.production.travel(region):
			print("PROMO_TRAVEL refused ",region," attempt=",attempt)
			continue
		for i in 3000:
			await process_frame
			if not world.production.travel_busy and world.session.ready_for_play: break
		await frames(60)
		if world.session.state.region_id == region: break
		print("PROMO_TRAVEL not arrived ",region," attempt=",attempt)
	print("PROMO_CHECK ",world.session.state.region_id == region," arrived ",region)
	return world.session.state.region_id == region

func ground(point: Vector3) -> Vector3:
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*300,point-Vector3.UP*300))
	return hit.position if not hit.is_empty() else point

## Céu de verdade para planos em perspectiva: o jogo usa cor lisa porque a câmera normal
## olha para baixo. Só neste processo de captura.
var sky_horizon := Color("c9d6dc")
var sky_top := Color("5d87ad")
var fog_begin := 70.0
var fog_end := 300.0
## Ambiente da câmera de cinema: cópia do ambiente do jogo (luz e cor iguais), com céu em
## degradê e névoa de distância da cor do horizonte, que apaga a borda do mundo carregado.
func cine_environment() -> Environment:
	var env: Environment = world.production.environment.environment.duplicate()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = sky_top
	material.sky_horizon_color = sky_horizon
	material.ground_horizon_color = sky_horizon
	material.ground_bottom_color = sky_horizon
	material.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = sky_horizon
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 1.0
	env.fog_depth_begin = fog_begin
	env.fog_depth_end = fog_end
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	return env

func cinematic_sky(horizon := Color("c9d6dc"), top := Color("5d87ad")) -> void:
	sky_horizon = horizon
	sky_top = top
	var env: Environment = world.production.environment.environment
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = top
	material.sky_horizon_color = horizon
	material.ground_horizon_color = horizon
	material.ground_bottom_color = horizon.darkened(.3)
	material.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = material
	env.sky = sky
	env.background_mode = Environment.BG_SKY

## Reconhecimento: vista de cima (mapa) e oblíquas em perspectiva por ponto.
func scout() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	const AD = preload("res://activities/ActivityDefinitions.gd")
	var spots := [
		["harbor","porto",Vector3(240,.12,120),.27],
		["harbor","porto_tarde",Vector3(240,.12,120),.735],
		["harbor","patio",Vector3(200,.12,40),.42],
		["harbor","centro",Vector3(110,.12,82),.42],
		["harbor","parque_noite",Vector3(-156,.12,94),.92],
		["harbor","motocross",Vector3(-224,.15,-37),.42],
		["harbor","ponte",Vector3(430,.12,-285),.42],
		["mountain","serra",Vector3(650,0,-290),.42],
		["mountain","serra_leste",Vector3(745,0,-420),.42],
		["mountain","esqui",AD.at(Vector2(6600,-3050),"mountain"),.42],
		["mountain","esqui_topo",AD.at(Vector2(7100,-4890),"mountain"),.42],
		["mountain","vila",AD.at(Vector2(7560,-1650),"mountain"),.42],
		["desert","arrancada",Vector3(-1040,0,-1320),.70],
		["desert","pedreira",Vector3(-180,0,-1645),.42],
		["desert","comunidade",Vector3(-543,0,-784),.70],
	]
	for spot in spots:
		if not only.is_empty() and spot[0] not in only.split(","): continue
		if not await go_region(spot[0]): continue
		weather(spot[3])
		var focus: Vector3 = spot[2]
		await stage_at(ground(focus)+Vector3.UP*.12)
		focus = ground(focus)
		make_camera(260)
		look(focus+Vector3(0,400,0),focus)
		await still("scout-%s-mapa"%spot[1])
		cine(55)
		look(focus+Vector3(-70,48,80),focus)
		await still("scout-%s-a"%spot[1])
		look(focus+Vector3(80,40,-70),focus)
		await still("scout-%s-b"%spot[1])
		look(focus+Vector3(-14,3.2,18),focus+Vector3(0,2,0))
		await still("scout-%s-chao"%spot[1])
		var env: Environment = world.production.environment.environment
		var mode := env.background_mode
		cinematic_sky()
		look(focus+Vector3(-60,22,70),focus+Vector3(0,8,0))
		await still("scout-%s-ceu"%spot[1])
		env.background_mode = mode


## ---------------------------------------------------------------- planos do trailer

func forward_of(node: Node3D) -> Vector3:
	var f := -node.global_basis.z
	f.y = 0
	return f.normalized() if f.length() > .01 else Vector3.FORWARD

func chase_view(target: Node3D, back := 7.5, height := 2.3, side := 0.0, ahead := 7.0, weight := .14) -> void:
	var f := forward_of(target)
	var r := f.cross(Vector3.UP)
	var p := target.global_position
	follow(p-f*back+Vector3.UP*height+r*side,p+f*ahead+Vector3.UP*1.0,weight)

func dolly(label: String, count: int, from_a: Vector3, from_b: Vector3, at_a: Vector3, at_b: Vector3) -> void:
	await take(label,count,func(i):
		var k := smooth01(float(i)/float(count-1))
		look(from_a.lerp(from_b,k),at_a.lerp(at_b,k))
	)

func board_player(car) -> bool:
	if not require(is_instance_valid(car),"Veículo existe"): return false
	# Logo depois da viagem o jogador ainda pode estar travado pela transição: tenta algumas vezes.
	var entered := false
	for attempt in 6:
		world.player.input_locked = false
		world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.25+Vector3.UP*.08)
		await frames(20)
		if world.driving.interact():
			entered = true
			break
		print("PROMO_BOARD retry ",attempt," locked=",world.player.input_locked," transition=",world.driving.is_body_transition_active())
		await frames(40)
	if not entered:
		print("PROMO_CHECK false interact")
		return false
	for i in 240:
		await process_frame
		if world.driving.occupied and world.driving.car == car: break
	await frames(30)
	return require(world.driving.occupied and world.driving.car == car,"Jogador ao volante")

## Porto de manhã: navio de contêineres, ponte estaiada e a rua do centro.
func vistas() -> void:
	fog_begin = 170.0
	fog_end = 560.0
	weather(.28)
	cinematic_sky(Color("e9d6c0"),Color("6f93b8"))
	# Enquadramentos do reconhecimento (sem vazio à vista): câmera a ~100 m do foco. Mais
	# longe ela enxergava além das células carregadas e o chão sumia.
	var yard := ground(Vector3(200,0,40))
	await stage_at(yard+Vector3.UP*.12)
	await frames(200)
	cine(52)
	await dolly("porto",150,yard+Vector3(-70,48,80),yard+Vector3(-52,40,88),yard,yard+Vector3(8,0,-4))
	var port := ground(Vector3(240,0,120))
	await stage_at(port+Vector3.UP*.12)
	await frames(200)
	await dolly("porto_navio",150,port+Vector3(80,40,-70),port+Vector3(70,34,-82),port,port+Vector3(-6,0,4))
	var city := ground(Vector3(110,0,82))
	await stage_at(city+Vector3.UP*.12)
	world.production.set_population(40)
	await frames(240)
	await dolly("cidade",150,city+Vector3(-36,22,40),city+Vector3(-20,16,44),city,city+Vector3(10,0,-6))
	await dolly("cidade_rua",150,city+Vector3(-10,4.5,20),city+Vector3(-4,4.0,10),city+Vector3(6,1.5,-20),city+Vector3(10,1.5,-28))
	var houses := ground(Vector3(318,0,20))
	await stage_at(houses+Vector3.UP*.12)
	await frames(120)
	await dolly("sobrados",150,houses+Vector3(-40,30,50),houses+Vector3(-30,24,58),houses,houses+Vector3(6,0,-4))

## Parque de diversões à noite: as luzes acesas.
func parque() -> void:
	fog_begin = 140.0
	fog_end = 460.0
	weather(.93)
	cinematic_sky(Color("1d2738"),Color("0a1120"))
	var center := ground(Vector3(-156,0,94))
	await stage_at(center+Vector3.UP*.12)
	await frames(240)
	cine(50)
	await take("parque",180,func(i):
		var a := -0.9+float(i)*.0035
		look(center+Vector3(cos(a)*70,34,sin(a)*70),center+Vector3(0,4,0))
	)
	await dolly("parque_baixo",150,center+Vector3(-30,6,30),center+Vector3(-22,5,34),center+Vector3(0,5,0),center+Vector3(8,5,-4))

## Corrida de rua da Cobra: grade de largada e perseguição de seis carros.
func corrida() -> void:
	fog_begin = 90.0
	fog_end = 380.0
	weather(.70)
	cinematic_sky(Color("ead2b4"),Color("6b8fb4"))
	var session = world.session
	var snapshot: Dictionary = session.state.campaign.snapshot()
	snapshot.completed = ["primeiro_giro","cobra_contact"]
	snapshot.claimed_rewards = snapshot.completed.duplicate()
	snapshot.flags = {"harbor_delivery_complete":true,"cobra_contact_complete":true}
	snapshot.active_id = ""
	if not require(session.state.campaign.restore_snapshot(snapshot) and session.state.campaign.begin("cobra_race"),"Campanha antes da corrida"): return
	var mission = session.mission_world
	var car = world.driving.car
	car.place(mission.targets.ashbend_start+Vector3(-1.4,.12,3),0)
	world.player.teleport(car.driver_door_anchor(1)+car.global_basis.x*.2+Vector3.UP*.1)
	world.production.region.set_focus(car.global_position)
	await settle_streaming()
	if not await board_player(car): return
	car.place(mission.targets.ashbend_start+Vector3(-1.4,.12,3),0)
	car.speed = 0
	car.horizontal_velocity = Vector3.ZERO
	await physics_frame
	require(mission.perform("race_start"),"Telefone da corrida")
	for child in session.column.get_children():
		if child is Button and child.text == "Entrar na corrida":
			child.pressed.emit()
			break
	race = mission.street_race
	if not require(is_instance_valid(race) and race.running,"Grade de largada"): return
	pilot = preload("res://gameplay/urban_v1/CobraRaceDriver.gd").new()
	pilot.setup(car,21.0,true)
	physics_frame.connect(_race_tick)
	for gate in race.gates:
		if is_instance_valid(gate): gate.hide()
	subject = car
	cine(48)
	# Grade: câmera alta no meio da rua, à frente dos seis carros; eles largam na direção dela.
	var f := forward_of(car)
	var grid_center := Vector3.ZERO
	for entry in race.racers: grid_center += entry.car.global_position/float(race.racers.size())
	await dolly("grade",130,grid_center+f*18+Vector3.UP*2.6,grid_center+f*24+Vector3.UP*3.4,grid_center+Vector3.UP*.8,grid_center+f*6+Vector3.UP*.8)
	await take("lider",210,func(_i): chase_view(race_leader(),8.0,2.6,1.5,8.0,.12))
	await take("pelotao",180,func(_i): chase_view(race_leader(1),9.0,3.2,-2.0,10.0,.12))
	await take("lateral",150,func(_i): chase_view(race_leader(),1.0,1.3,-6.0,5.0,.2))
	await take("frente",150,func(_i):
		var leader := race_leader()
		var g := forward_of(leader)
		follow(leader.global_position+g*13+Vector3.UP*2.0+g.cross(Vector3.UP)*2.0,leader.global_position-g*8+Vector3.UP*.9,.14)
	)
	await take("alto",150,func(_i): chase_view(race_leader(),16,10,4,10,.1))

## O carro em `rank` na corrida (0 = líder), entre os que ainda correm.
func race_leader(rank := 0) -> Node3D:
	var alive: Array = race.racers.filter(func(e): return not e.dnf and is_instance_valid(e.car))
	alive.sort_custom(func(a,b):
		if a.run.get("checkpoint",0) != b.run.get("checkpoint",0): return a.run.get("checkpoint",0) > b.run.get("checkpoint",0)
		return a.run.get("progress",0) > b.run.get("progress",0))
	return alive[mini(rank,alive.size()-1)].car if not alive.is_empty() else subject

func _race_tick() -> void:
	if is_instance_valid(race) and race.running: pilot.tick(1.0/60.0,false)
	if is_instance_valid(race):
		for gate in race.gates:
			if is_instance_valid(gate): gate.hide()

## Perseguição policial pelas ruas do porto: viaturas e helicóptero de verdade.
var autopilot_driver
func policia() -> void:
	weather(.62)
	cinematic_sky(Color("e2d6c6"),Color("6a90b6"))
	fog_begin = 90.0
	fog_end = 420.0
	# Avenida reta que desce para a ponte sobre o mar: espaço aberto, sem prédios colados.
	var route := [Vector3(382.5,0,-130),Vector3(382.5,0,-248),Vector3(386,0,-278),Vector3(405,0,-282),Vector3(440,0,-285),Vector3(600,0,-285),Vector3(700,4,-300)]
	var car = world.driving.car
	car.place(ground(route[0])+Vector3.UP*.12,PI)
	world.production.region.set_focus(car.global_position)
	await settle_streaming()
	if not await board_player(car): return
	autopilot_driver = preload("res://runtime/BenchmarkAutopilot.gd").new(world,car,route,13.0)
	autopilot_driver.begin()
	car.input_locked = true
	world.gameplay.register_crime(80,car.global_position)
	require(world.gameplay.stars >= 3,"Procurado com 3 estrelas")
	# Parado até as viaturas chegarem perto; só então foge pela avenida.
	for i in 1500:
		await process_frame
		var near := 0
		for unit in world.dispatch.units:
			if is_instance_valid(unit.vehicle) and unit.vehicle.global_position.distance_to(car.global_position) < 30: near += 1
		if near >= 2: break
	car.input_locked = false
	physics_frame.connect(_autopilot_tick)
	await frames(75)
	print("PROMO_POLICE units=",world.dispatch.units.size()," heli=",is_instance_valid(world.gameplay.police_air.helicopter))
	subject = car
	cine(50)
	await take("fuga_frente",150,func(_i):
		var g := forward_of(car)
		follow(car.global_position+g*13+Vector3.UP*2.4,car.global_position-g*12+Vector3.UP*.8,.12)
	)
	await take("fuga_lateral",120,func(_i): chase_view(car,3,1.6,7,6,.16))
	await take("fuga_alto",150,func(_i): chase_view(car,18,9,-4,6,.1))
	var air = world.gameplay.police_air
	if is_instance_valid(air.helicopter):
		await take("helicoptero",150,func(_i):
			var h: Vector3 = air.helicopter.global_position
			follow(car.global_position-forward_of(car)*7+Vector3.UP*1.4,h.lerp(car.global_position,.4),.1)
		)

func _autopilot_tick() -> void:
	if autopilot_driver != null and is_instance_valid(autopilot_driver.car): autopilot_driver.drive(1.0/60.0)

## Tiroteio na rua contra a Cobra: fuzil, fogo de volta e um RPG no carro.
var enemies: Array[Node3D] = []
var target_car
func aim_target() -> Vector3:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead: return enemy.global_position
	return target_car.global_position

func steer_weapon(target: Vector3, fire: bool) -> void:
	var controls = root.get_node("GameInput")
	var flat: Vector3 = (target-world.player.global_position).normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0
	down.y = 0
	controls.touch_aim = Vector2(flat.dot(right.normalized()),flat.dot(down.normalized()))
	if fire: world.gameplay.fire_at(target+Vector3.UP*.9)

func tiroteio() -> void:
	fog_begin = 60.0
	fog_end = 280.0
	weather(.66)
	cinematic_sky(Color("e2d6c6"),Color("6a90b6"))
	var gameplay = world.gameplay
	var state = world.session.state
	state.economy.activate_arsenal_cheat()
	for vehicle in world.production.vehicles:
		if is_instance_valid(vehicle) and vehicle.traffic: vehicle.set_physics_process(false)
	var street: Vector3 = world.production.nearest_road(world.driving.car.global_position+Vector3(0,0,18))
	world.production.region.set_focus(street)
	world.player.teleport(street+Vector3.UP*.1)
	await settle_streaming()
	for offset in [Vector3(0,0,12),Vector3(12,0,0),Vector3(-12,0,0),Vector3(0,0,-12),Vector3(0,0,24)]:
		var candidate: Vector3 = world.production.nearest_road(street+offset)+Vector3.UP*.12
		for yaw in [0.0,PI*.5]:
			target_car = world.production.spawn_vehicle("sport_coupe",candidate,yaw)
			if is_instance_valid(target_car): break
		if is_instance_valid(target_car): break
		await frames(2)
	if not require(is_instance_valid(target_car),"Carro alvo"): return
	street = target_car.global_position+Vector3(3,0,7)
	world.player.teleport(street)
	await frames(25)
	state.equip_weapon("m4a1")
	await frames(30)
	for offset in [Vector3(-2,0,-8),Vector3(3,0,-12),Vector3(-5,0,-13),Vector3(1,0,-16)]:
		var enemy := preload("res://gameplay/CobraAgent.gd").new()
		enemy.configure(gameplay,2)
		world.add_child(enemy)
		enemy.global_position = ground(street+offset)+Vector3.UP*.1
		enemy.cooldown = .15+enemies.size()*.3
		enemies.append(enemy)
	root.get_node("GameInput").using_gamepad = true
	Input.action_press("aim")
	cine(46)
	await take("ombro",150,func(i):
		var target := aim_target()
		steer_weapon(target,i > 8 and i%8 == 0)
		var d: Vector3 = target-world.player.global_position
		d.y = 0
		d = d.normalized()
		var r := d.cross(Vector3.UP)
		follow(world.player.global_position-d*3.0+r*1.1+Vector3.UP*2.1,target+Vector3.UP*1.0,.2)
	)
	await take("contraplano",120,func(i):
		var target := aim_target()
		steer_weapon(target,i > 4 and i%6 == 0)
		var d: Vector3 = world.player.global_position-target
		d.y = 0
		d = d.normalized()
		follow(target+d*2.5+d.cross(Vector3.UP)*2.2+Vector3.UP*1.4,world.player.global_position+Vector3.UP*1.2,.2)
	)
	await take("geral",120,func(i):
		var target := aim_target()
		steer_weapon(target,i > 4 and i%5 == 0)
		look(world.player.global_position+Vector3(9,7,10),world.player.global_position.lerp(target,.5)+Vector3.UP)
	)
	# Carro intacto para o RPG: o primeiro já pegou fogo no tiroteio e não explode de novo.
	var fresh
	for offset in [Vector3(-14,0,6),Vector3(14,0,6),Vector3(0,0,22),Vector3(-14,0,-6),Vector3(14,0,-6)]:
		var candidate: Vector3 = world.production.nearest_road(world.player.global_position+offset)+Vector3.UP*.12
		if candidate.distance_to(target_car.global_position) < 8: continue
		for yaw in [0.0,PI*.5]:
			fresh = world.production.spawn_vehicle("sport_coupe",candidate,yaw)
			if is_instance_valid(fresh): break
		if is_instance_valid(fresh): break
	if not is_instance_valid(fresh): fresh = target_car
	state.equip_weapon("rpg")
	await frames(24)
	await take("rpg",150,func(i):
		steer_weapon(fresh.global_position,false)
		var flat: Vector3 = fresh.global_position-world.player.global_position
		flat.y = 0
		flat = flat.normalized()
		var r := flat.cross(Vector3.UP)
		var gap: float = world.player.global_position.distance_to(fresh.global_position)
		look(world.player.global_position-flat*3.0+r*2.2+Vector3.UP*1.7,world.player.global_position+flat*gap*.7+Vector3.UP*1.0)
		if i == 20: print("PROMO_ROCKET ",gameplay.fire_at(fresh.global_position+Vector3.UP*.5))
		# O foguete às vezes passa por cima do carro; quando ele chega, a explosão do jogo
		# é disparada no carro (mesma chamada que o RPG usa ao acertar).
		if i == 20+int(gap/1.2) and fresh.health > 0: gameplay.explode(fresh.global_position+Vector3.UP*.4,2.0,500.0,world.player,true)
	)
	Input.action_release("aim")

## Arrancada no deserto ao pôr do sol: semáforo, largada e as duas máquinas passando.
var drag_launch := -1
var drag_mid := Vector3.ZERO
var drag_side := Vector3.ZERO
func arrancada() -> void:
	fog_begin = 220.0
	fog_end = 1000.0
	if not await go_region("desert"): return
	race = world.session.desert.drag
	weather(.72)
	cinematic_sky(Color("f0c99a"),Color("6d8db3"))
	await stage_at(ground(race.staging_point)+Vector3.UP*.12)
	var car = world.production.spawn_vehicle("desert_mirage",ground(race.staging_point+Vector3(0,0,-6))+Vector3.UP*.1,-PI*.5)
	if not await board_player(car): return
	# Como no teste da arrancada: sem fila do encontro aberto e embarque concluído de fato.
	race.open_meet.enabled = false
	for i in 600:
		await physics_frame
		if car.controlled and not car.input_locked and not world.driving.is_body_transition_active() and absf(car.speed) < .5: break
	weather(.72)
	physics_frame.connect(drag_tick)
	cine(44)
	print("PROMO_DRAG_BLOCK '",race.start_block_reason(),"' near=",race.nearest_action())
	if not require(race.perform("start"),"Arrancada começou"): return
	await frames(3)
	var a: Vector3 = race.racers[0].car.global_position
	var b: Vector3 = race.racers[1].car.global_position
	drag_mid = a.lerp(b,.5)
	var dir: Vector3 = race.direction
	var side := dir.cross(Vector3.UP)
	drag_side = side if side.dot(a-drag_mid) > 0 else -side
	print("PROMO_DRAG_STAGE phase=",race.phase," countdown=",race.countdown)
	await take("largada",330,func(i):
		if drag_launch < 0 and race.phase == "racing":
			drag_launch = i
			print("PROMO_DRAG_LAUNCH frame=",i)
		# Câmera baixa na frente, de lado: os carros vêm para cima dela e passam.
		look(drag_mid+dir*24+drag_side*7.5+Vector3.UP*.55,drag_mid+dir*4+Vector3.UP*.9)
	)
	shots[-1]["launch_frame"] = drag_launch
	await take("paralelo",150,func(_i):
		var c: Vector3 = race.racers[0].car.global_position.lerp(race.racers[1].car.global_position,.5)
		follow(c+drag_side*9+Vector3.UP*1.4+dir*1.5,c+dir*2+Vector3.UP*.8,.25)
	)

## Motocross: pilotos no barro, câmera baixa acompanhando.
func moto() -> void:
	fog_begin = 90.0
	fog_end = 380.0
	weather(.40)
	cinematic_sky()
	world.player.teleport(Vector3(-224,.15,-37))
	world.production.region.set_focus(world.player.position)
	await settle_streaming()
	world.session.state.economy.grant_reward("promo_capture",1000)
	race = world.session.motocross
	race.selected_model = 0
	if not require(race.start_race(0),"Motocross começou"): return
	race.autopilot = true
	await frames(110)
	subject = race.player_bike
	cine(50)
	await take("moto_chase",180,func(_i): chase_view(subject,5.5,1.6,1.2,6.0,.16))
	await take("moto_frente",150,func(_i):
		var g := forward_of(subject)
		follow(subject.global_position+g*9+Vector3.UP*.8+g.cross(Vector3.UP)*2,subject.global_position-g*4+Vector3.UP*.8,.18)
	)
	await take("moto_alto",150,func(_i): chase_view(subject,12,7,4,4,.1))

## Serra nevada: descida de sete carros ao entardecer e uma vista aérea.
func serra() -> void:
	fog_begin = 110.0
	fog_end = 380.0
	if not await go_region("mountain"): return
	var coordinator := get_first_node_in_group("mountain_activities")
	race = coordinator.components.get("mountain_downhill")
	var start: Vector3 = race.course.start_position()
	var right: Vector3 = race.course.direction(10).cross(Vector3.UP).normalized()
	# A descida só acontece à noite (20h–5h): 21h, faróis na neve.
	weather(.875)
	cinematic_sky(Color("2b3752"),Color("0c1426"))
	await stage_at(ground(start+right*3.4)+Vector3.UP*.12)
	var pose: Transform3D = race.course.grid(6)
	var car = world.production.spawn_vehicle("sport_coupe",pose.origin,pose.basis.get_euler().y)
	if not await board_player(car): return
	for i in 600:
		await physics_frame
		if car.controlled and not car.input_locked and not world.driving.is_body_transition_active() and absf(car.speed) < .5: break
	weather(.875)
	print("PROMO_DOWNHILL_BLOCK '",race.start_block_reason(),"'")
	if not require(race.perform("start"),"Descida começou"): return
	pilot = preload("res://activities/mountain_downhill/MountainDownhillDriver.gd").new()
	pilot.setup(car,race.course,0)
	pilot.lane = -1.8
	pilot.desired_lane = -1.8
	subject = car
	physics_frame.connect(downhill_tick)
	await frames(120)
	cine(50)
	await take("descida",210,func(_i): chase_view(car,8,2.6,0,8,.13))
	await take("descida_frente",150,func(_i):
		var g := forward_of(car)
		follow(car.global_position+g*12+Vector3.UP*1.5,car.global_position-g*8+Vector3.UP*.8,.14)
	)
	await take("descida_alto",150,func(_i): chase_view(car,18,12,6,6,.1))

## Deserto: vista larga das dunas e da pedreira.
func deserto() -> void:
	fog_begin = 250.0
	fog_end = 1100.0
	if not await go_region("desert"): return
	weather(.70)
	cinematic_sky(Color("f0c99a"),Color("6d8db3"))
	var drag_at := ground(Vector3(-1040,0,-1320))
	await stage_at(drag_at+Vector3.UP*.12)
	cine(50)
	await dolly("dunas",150,drag_at+Vector3(-90,30,80),drag_at+Vector3(-70,26,92),drag_at,drag_at+Vector3(12,0,-6))
	var quarry := ground(Vector3(-180,0,-1700))
	await stage_at(ground(Vector3(-180,0,-1645))+Vector3.UP*.12)
	await dolly("pedreira",150,quarry+Vector3(-90,80,100),quarry+Vector3(-70,70,110),quarry,quarry+Vector3(8,0,-4))

## Marcadores de objetivo (triângulo amarelo, portões azuis) também são HUD: somem do quadro.
func clean_overlay() -> void:
	super.clean_overlay()
	if race != null and is_instance_valid(race) and "_marker" in race and is_instance_valid(race._marker): race._marker.hide()

extends RefCounted
## População de rua do ProductionWorld (revisão e corte de pedestres, densidade dinâmica, fila de
## nascimentos, cidadãos comuns e moradores sociais do deserto), separada em 01/11 só para o
## ProductionWorld.gd caber na leitura: o estado (cursor/crédito da revisão, escalas de densidade, fila
## de trabalhos, vagas sociais) continua no ProductionWorld, porque testes e outros sistemas leem esses
## campos lá. ProductionWorld mantém cada função antiga como delegação de uma linha, então quem chama
## por nome (testes, sondas, call()/has_method) não muda; population_cap/traffic_cap ficam lá inteiras.
## `g` fica como Node, e não como o script do ProductionWorld, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: uma subclasse do ProductionWorld que
## sobrescreva alguma delas (ou _on_screen, _trace_cost...) continua sendo despachada igual.

const ACTOR := preload("res://scripts/Actor.gd")
const CANAL_TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const DESERT_SOCIAL_ACTOR := preload("res://runtime/desert/DesertSocialActor.gd")
const PORT_POLICY := preload("res://gameplay/urban_v1/HarborPortPolicy.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Moram aqui porque density_target é estática e não alcança o dono; o ProductionWorld os reexporta
## com o mesmo nome (a razão dos valores está ao lado da reexportação).
const DENSITY_PER_UNIT := 0.07
const DENSITY_MIN := 0.4
const DENSITY_STARS := 4
const DENSITY_STARS_SCALE := 0.6

var g: Node

func _init(host: Node) -> void:
	g = host

## Mantém quatro revisões por segundo distribuídas, com no máximo um oitavo por quadro.
## O cursor permanece no sucessor quando uma remoção desloca os índices.
func _review_pedestrians(delta: float) -> void:
	g._pedestrian_review_credit = minf(g._pedestrian_review_credit + delta * g.world.people.size() * 4.0,g.world.people.size())
	var budget := mini(int(g._pedestrian_review_credit),maxi(1,ceili(float(g.world.people.size()) / 8.0)))
	g._pedestrian_review_credit -= budget
	for step in budget:
		if g.world.people.is_empty():
			g._pedestrian_review_cursor = 0
			break
		g._pedestrian_review_cursor %= g.world.people.size()
		var actor = g.world.people[g._pedestrian_review_cursor]
		var retire := not is_instance_valid(actor)
		if not retire:
			var distance: float = actor.global_position.distance_to(g.world.player.global_position)
			retire = PORT_POLICY.contains_private_area(actor.global_position)
			# Rotinas autoradas e travessias preservam a permanência e a recuperação antigas.
			if actor.has_meta("desert_routine") or actor.has_meta("desert_social_slot") or actor.get_meta("footbridge_crosser",false):
				retire = retire or (distance > g.POPULATION_DESPAWN and not g._on_screen(actor.global_position,1.0))
			elif not retire and distance > g.VC_PEDESTRIAN_HIDDEN_DISTANCE:
				retire = distance > g.VC_PEDESTRIAN_VISIBLE_DISTANCE or not g._on_screen(actor.global_position,1.0)
		if retire:
			g.world.people.remove_at(g._pedestrian_review_cursor)
			if is_instance_valid(actor): actor.queue_free()
		else:
			g._pedestrian_review_cursor += 1

## Diagnóstico explícito da P1: conta a cena real após 30 s, sem amostrar FPS/tempo de quadro.
## Fica no arquivo dono da tarefa para não criar um runner em arquivos de outra sessão.
func _count_p1_population() -> void:
	if not g.no_save:
		push_error("P1: contagem exige --no-save para preservar o save do usuário.")
		g.get_tree().quit(1)
		return
	# Headless nasce com viewport 64x64; a câmera precisa do enquadramento de gameplay.
	g.get_tree().root.size = Vector2i(1280,720)
	await g.get_tree().create_timer(30.0).timeout
	var people := 0
	var authored_people := 0
	var farthest_visible := 0.0
	var farthest_hidden := 0.0
	var farthest_common_visible := 0.0
	var farthest_common_hidden := 0.0
	var farthest_traffic := 0.0
	var parked := 0
	var persistent := 0
	for actor in g.world.people:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion(): continue
		people += 1
		var distance: float = actor.global_position.distance_to(g.world.player.global_position)
		var authored: bool = actor.has_meta("desert_routine") or actor.has_meta("desert_social_slot") or actor.get_meta("footbridge_crosser",false)
		if authored: authored_people += 1
		if g._on_screen(actor.global_position,1.0):
			farthest_visible = maxf(farthest_visible,distance)
			if not authored: farthest_common_visible = maxf(farthest_common_visible,distance)
		else:
			farthest_hidden = maxf(farthest_hidden,distance)
			if not authored: farthest_common_hidden = maxf(farthest_common_hidden,distance)
	for car in g.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		if g._is_persistent_vehicle(car): persistent += 1
		elif not car.traffic: parked += 1
		elif g._is_ambient_traffic(car) and car.health > 0.0:
			farthest_traffic = maxf(farthest_traffic,car.global_position.distance_to(g.world.player.global_position))
	# population_vc_enabled e sun_shadow_near_enabled são static var do dono: lidas pelo script,
	# não pela instância, para não depender de como o GDScript resolve estático via objeto.
	var report := {"population_vc":g.get_script().population_vc_enabled,"sun_shadow_near":g.get_script().sun_shadow_near_enabled,
		"region":g.state.region_id,"focus":str(g.world.player.global_position),"pedestrians":people,
		"pedestrian_cap":g.population_cap(),"ambient_traffic":g._ambient_traffic_count(),"traffic_cap":g.traffic_cap(),
		"farthest_visible_m":farthest_visible,"farthest_hidden_m":farthest_hidden,"farthest_traffic_m":farthest_traffic,
		"authored_pedestrians":authored_people,"common_farthest_visible_m":farthest_common_visible,
		"common_farthest_hidden_m":farthest_common_hidden,"viewport":str(g.get_viewport().get_visible_rect().size),
		"parked":parked,"persistent":persistent,"sun_shadow_distance_m":g.sun.directional_shadow_max_distance,
		"native_dispatch_router":is_instance_valid(g.world.dispatch) and g.world.dispatch.router._native != null}
	print("P1_CONTAGEM ",JSON.stringify(report))
	g.get_tree().quit(0 if not g.get_script().population_vc_enabled or (people <= g.VC_MAX_POPULATION and g._ambient_traffic_count() <= g.VC_TRAFFIC_TARGET) else 1)

## Alvo da densidade: cada unidade de despacho em cena tira `DENSITY_PER_UNIT`, e de
## `DENSITY_STARS` estrelas para cima o teto não passa de `DENSITY_STARS_SCALE`.
static func density_target(dispatch_units: int, stars: int) -> float:
	var target := clampf(1.0-float(dispatch_units)*DENSITY_PER_UNIT,DENSITY_MIN,1.0)
	if stars >= DENSITY_STARS: target = minf(target,DENSITY_STARS_SCALE)
	return target

## Public market/terminal streets favour foot traffic; industrial and rural areas
## carry fewer pedestrians. Coordinates follow the authored harbor street layout
## (market/terminal x60..165,z0..100; industrial waterfront south of z156).
## Twenty-metre shoulders avoid a hard population boundary between streets.
static func area_density_target(region_id: String, point: Vector3) -> Vector2:
	if region_id == "mountain": return Vector2(.6,.7)
	if region_id == "desert": return Vector2(.7,.8)
	if region_id != "harbor": return Vector2.ONE
	var target := Vector2(1.0,.9)
	var market_edge := maxf(maxf(60.0-point.x,point.x-165.0),maxf(-point.z,point.z-100.0))
	var market_weight := 1.0-smoothstep(0.0,20.0,market_edge)
	target = target.lerp(Vector2(.9,.7),market_weight)
	return target.lerp(Vector2(.7,.8),smoothstep(156.0,176.0,point.z))

func _update_density() -> void:
	var units := 0
	if is_instance_valid(g.world.dispatch): units = g.world.dispatch.units.size()
	var stars := 0
	if is_instance_valid(g.world.gameplay): stars = int(g.world.gameplay.stars)
	var target: float = g.density_target(units,stars)
	var area_target: Vector2 = g.area_density_target(g.state.region_id,g.world.player.global_position)
	# Interruptor para comparar com/sem a densidade dinâmica em medições.
	if "--no-density" in OS.get_cmdline_user_args():
		target = 1.0
		area_target = Vector2.ONE
	# Chamado a cada 0,25 s: 1,0 -> 0,4 em ~1,5 s; volta em ~7,5 s (sem pisca-pisca com
	# viaturas entrando e saindo).
	g.density_scale = move_toward(g.density_scale,target,.1 if target < g.density_scale else .02)
	# Mudanças de área também assentam aos poucos; a remoção ainda exige distância e estar
	# fora da câmera, então o trânsito visível existente nunca some numa fronteira.
	g.area_density_scale.x = move_toward(g.area_density_scale.x,area_target.x,.02)
	g.area_density_scale.y = move_toward(g.area_density_scale.y,area_target.y,.02)

## Tira no máximo um pedestre e um carro civil por chamada, o mais longe do jogador e fora
## do quadro, enquanto houver mais que o teto atual.
func _trim_density() -> void:
	var origin: Vector3 = g.world.player.position
	if g.world.people.size() > g.population_cap():
		var worst := -1
		var farthest: float = g.DENSITY_TRIM_MIN_DISTANCE
		for index in g.world.people.size():
			var actor = g.world.people[index]
			if not is_instance_valid(actor): continue
			var distance: float = actor.position.distance_to(origin)
			if distance > farthest and not g._on_screen(actor.global_position,1.0):
				farthest = distance
				worst = index
		if worst >= 0:
			var removed = g.world.people[worst]
			g.world.people.remove_at(worst)
			removed.queue_free()
	if g._ambient_traffic_count() > g.traffic_cap():
		var worst_car := -1
		var farthest_car: float = g.DENSITY_TRIM_MIN_DISTANCE
		for index in g.vehicles.size():
			var car = g.vehicles[index]
			if not g._is_ambient_traffic(car) or not car.traffic or car.health <= 0.0 or car == g.world.driving.car: continue
			var distance: float = car.global_position.distance_to(origin)
			if distance > farthest_car and not g._on_screen(car.global_position,3.0):
				farthest_car = distance
				worst_car = index
		if worst_car >= 0:
			var removed_car = g.vehicles[worst_car]
			g.vehicles.remove_at(worst_car)
			removed_car.queue_free()

func _service_population_job() -> void:
	if g._population_jobs.is_empty(): return
	var job: String = g._population_jobs.pop_front()
	var began := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	match job:
		"citizen":
			if g.world.people.size() < g.population_cap(): g._spawn_citizen()
		"traffic":
			if g._ambient_traffic_count() < g.traffic_cap() and not "--no-traffic" in OS.get_cmdline_user_args(): g._spawn_vehicle()
		"equipment":
			for car in g.vehicles:
				if not is_instance_valid(car) or car.is_queued_for_deletion() or is_instance_valid(car.equipment): continue
				if car.traffic or (car.controlled and car.external_input):
					car.ensure_equipment(g.world)
					break
	g._trace_cost("population_job:"+job,began)

func _spawn_citizen() -> void:
	var began := Time.get_ticks_usec() if (g.world.get_meta("benchmark_trace",false) or STALL_WORK.session_enabled) else 0
	g._create_citizen()
	g._trace_cost("population_spawn",began)

func _create_citizen() -> void:
	if g.state.region_id == "desert":
		g._create_desert_citizen()
		return
	var segment: Dictionary = g.population_layout.select(g)
	if segment.is_empty(): return
	var along: Vector3 = segment.a.direction_to(segment.b)
	var point: Vector3 = segment.point
	var margin := minf(20.0,segment.a.distance_to(segment.b)*.4)
	var center: Vector3 = Geometry3D.get_closest_point_to_segment(point,segment.a,segment.b)
	var offset: Vector3 = point-center
	var start: Vector3 = center-along*minf(margin,center.distance_to(segment.a)*.8)+offset
	var finish: Vector3 = center+along*minf(margin,center.distance_to(segment.b)*.8)+offset
	# As calçadas ficam acima da linha central da rua; admite no piso real delas,
	# em vez de recusar uma calçada livre como cápsula dentro do calçamento.
	var grounded: Array[Vector3] = []
	for candidate in [point,start,finish]:
		var ground: Dictionary = g.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*1.0,candidate-Vector3.UP*1.0,1))
		if ground.is_empty() or absf(ground.position.y-candidate.y)>.4: return
		grounded.append(Vector3(candidate.x,ground.position.y+.08,candidate.z))
	point = grounded[0]
	start = grounded[1]
	finish = grounded[2]
	var pedestrian_route: PackedVector3Array = g._clip_citizen_route(point,start,finish)
	if pedestrian_route.is_empty(): return
	var actor = ACTOR.new()
	actor.identity = randi_range(0,10000)
	actor.position = point+Vector3.UP*.08
	actor.speed = randf_range(1.15,1.75)
	actor.route = pedestrian_route
	actor.set_meta("ambient_road_id",str(segment.road.id))
	actor.set_meta("region_id",g.state.region_id)
	g.world.add_child(actor)
	g.world.people.append(actor)

## Mantém a caminhada original onde está livre. Num cruzamento ou obstrução,
## usa a parte apoiada em volta do spawn em vez de recusar a calçada
## inteira. As mesmas amostras de admissão de <=2 m e a cápsula inteira da faixa continuam valendo.
func _clip_citizen_route(point: Vector3, start: Vector3, finish: Vector3) -> PackedVector3Array:
	if g._on_carriageway(point) or CANAL_TUNNEL.reserves(Vector2(point.x,point.z),.5) or PORT_POLICY.contains_private_area(point): return PackedVector3Array()
	if not g.session.position_clear(point+Vector3.UP*.06): return PackedVector3Array()
	var route := PackedVector3Array()
	for target in [start,finish]:
		var last := point
		var steps := maxi(1,ceili(point.distance_to(target)/2.0))
		for i in range(1,steps+1):
			var candidate := point.lerp(target,float(i)/steps)
			if g._on_carriageway(candidate) or CANAL_TUNNEL.reserves(Vector2(candidate.x,candidate.z),.5) or PORT_POLICY.contains_private_area(candidate): break
			if not g.session.position_clear(candidate+Vector3.UP*.08): break
			last = candidate
		route.append(last)
	if route[0].distance_to(route[1]) < 4.0: return PackedVector3Array()
	if PORT_POLICY.segment_enters_private_area(route[0],route[1]): return PackedVector3Array()
	return route if g._pedestrian_route_sweep_clear(route) else PackedVector3Array()

func _create_desert_citizen() -> void:
	var occupied := {}
	for actor in g.world.people:
		if is_instance_valid(actor) and actor.has_meta("desert_social_slot"):
			occupied[int(actor.get_meta("desert_social_slot"))] = true
	var start := randi_range(0,g._desert_social_slots.size()-1)
	for index in g._desert_social_slots.size():
		var slot_id: int = (start+index)%g._desert_social_slots.size()
		if occupied.has(slot_id): continue
		var slot: Dictionary = g._desert_social_slots[slot_id]
		var point: Vector3 = slot.point
		var distance := point.distance_to(g.world.player.global_position)
		# Espaços sociais pequenos cabem dentro do anel de exclusão de 45 m da cidade. Admite
		# os moradores deles mais perto, ainda fora da câmera e nunca em cima de nós.
		if distance < 12.0 or distance > g.POPULATION_SPAWN_MAX or g._on_screen(point,1.0): continue
		if not g.desert_social_route_clear(slot.route): continue
		var actor = DESERT_SOCIAL_ACTOR.new()
		actor.identity = 6100+slot_id
		actor.position = point+Vector3.UP*.08
		actor.speed = 1.2
		actor.route = slot.route
		actor.social_activity = slot.activity
		actor.social_facing = slot.facing
		actor.set_meta("region_id","desert")
		actor.set_meta("desert_social_slot",slot_id)
		g.world.add_child(actor)
		g.world.people.append(actor)
		return

func desert_social_route_clear(route: PackedVector3Array) -> bool:
	# A autoria pode mover prédios: recusa a rota inteira, nunca só o spawn.
	var a := route[0]
	var b := route[-1]
	var steps := maxi(1,ceili(a.distance_to(b)/2.0))
	for i in range(steps+1):
		var point := a.lerp(b,float(i)/steps)
		if g._on_carriageway(point) or not g.session.position_clear(point+Vector3.UP*.08): return false
	return g._pedestrian_route_sweep_clear(route)

func _pedestrian_route_sweep_clear(route: PackedVector3Array) -> bool:
	var a := route[0]
	var b := route[-1]
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	# Inclui o pequeno desvio de faixa de caminhada do Actor na folga varrida.
	capsule.radius = .72 if a.distance_squared_to(b) > .01 else .32
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY,a+Vector3.UP*.98)
	query.motion = b-a
	if not g.world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var result: PackedFloat32Array = g.world.get_world_3d().direct_space_state.cast_motion(query)
	return result[0] >= 1.0

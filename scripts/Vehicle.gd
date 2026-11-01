extends CharacterBody3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const DAMAGE_PANELS := preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd")
const SHADOW_PROXY := preload("res://gameplay/vehicle_effects/VehicleShadowProxy.gd")
var _shadow_proxy: RefCounted
## Comparação local ao processo; o jogo normal usa o protótipo nos modelos escritos.
static var damage_prototype_enabled := not ("--vehicle-damage-baseline" in OS.get_cmdline_user_args())

const VISUAL := preload("res://scripts/VehicleVisual.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const DOOR_SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const WHEELIE := preload("res://gameplay/MotorcycleWheelie.gd")
const DESERT_GROUND := preload("res://gameplay/desert_cars/DesertVehicleGround.gd")
const HYDRAULICS := preload("res://gameplay/lowrider/LowriderHydraulics.gd")
const TRAFFIC_RAILS := preload("res://gameplay/traffic/TrafficRails.gd")
## Auxiliares separados em 01/11 (Onda 3); o estado continua aqui e cada função antiga delega.
const MOTORCYCLE_RIDER := preload("res://scripts/VehicleMotorcycleRider.gd")
var _rider: MOTORCYCLE_RIDER = MOTORCYCLE_RIDER.new(self)
const DOOR_LAYOUT := preload("res://scripts/VehicleDoorLayout.gd")
var _doors: DOOR_LAYOUT = DOOR_LAYOUT.new(self)
const LOD_WRECK := preload("res://scripts/VehicleLodWreck.gd")
var _lod_wreck: LOD_WRECK = LOD_WRECK.new(self)
const TRAFFIC_DRIVE := preload("res://scripts/VehicleTrafficDrive.gd")
var _traffic_drive: TRAFFIC_DRIVE = TRAFFIC_DRIVE.new(self)
var traffic_rails: RefCounted
var _traffic_rail_drive := false
const MAX_SPEED := 15.0 * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
const REVERSE_SPEED := preload("res://gameplay/v1_handling/V1Handling.gd").REVERSE_SPEED_MPS
const WHEELBASE := 2.5
const WALL_DAMAGE_PER_SPEED := 0.65
const WALL_DAMAGE_MAX_RATIO := 0.12
const WALL_DAMAGE_COOLDOWN_SECONDS := 0.5
var _last_wall_damage_frame := -1000000
var paint_color := Color("d5a544"):
	set(value):
		if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b): return
		paint_color = Color(clampf(value.r,0,1),clampf(value.g,0,1),clampf(value.b,0,1),1)
		_paint_requested = true
		if _paint != null: _paint.apply(paint_color)
		if is_instance_valid(door_presentation): door_presentation.apply_paint(paint_color)
		_refresh_tuning_appearance()
var _paint_requested := false
var _paint: RefCounted
var archetype := ""
var vehicle_id := "":
	set(value):
		vehicle_id = value
		if is_instance_valid(visual) and _paint != null:
			# Spans só com diagnóstico de sessão: a van de sorvete custou 35 ms neste setter (17/10).
			var traced := Time.get_ticks_usec() if preload("res://runtime/StallWorkTrace.gd").session_enabled else 0
			preload("res://runtime/VehicleUsage.gd").apply(visual, archetype, value, _paint.materials)
			preload("res://runtime/SessionOperations.gd").completed(self, "vehicle", "vehicle_id_usage", traced)
			traced = Time.get_ticks_usec() if traced != 0 else 0
			_refresh_tuning_appearance()
			preload("res://runtime/SessionOperations.gd").completed(self, "vehicle", "vehicle_id_tuning", traced)
			traced = Time.get_ticks_usec() if traced != 0 else 0
			preload("res://gameplay/icecream/IceCreamVan.gd").attach(self)
			preload("res://runtime/SessionOperations.gd").completed(self, "vehicle", "vehicle_id_icecream_attach", traced)
		if is_instance_valid(visual) and visual.has_node("TaxiLivery"):
			visual.get_node("TaxiLivery").registration(value)
		if value.begins_with("cobra_patrol_") and is_instance_valid(visual):
			preload("res://gameplay/urban_v1/CobraAppearance.gd").livery(self)
		elif value.begins_with("cobra_racer_") and is_instance_valid(visual):
			preload("res://gameplay/urban_v1/CobraAppearance.gd").race_livery(self)
var health := 180.0
var horizontal_velocity := Vector3.ZERO
var damage_look: Node
var body_dents: Node
var breakaway_parts: Node
var equipment: Node
var effects: Node
var equipment_state: Dictionary = {}
var max_health := 180.0
var damage_resistance := 1.0
var tank_cannon: Node3D
var max_forward_speed := MAX_SPEED
var drive_acceleration := 5.0
var half_width := 1.04
var half_length := 2.3
var body_height := 1.4
signal damaged(amount: float)
signal destroyed
var controlled := false
var traffic := false:
	set(value):
		traffic = value
		for part in _motorcycle_rider_parts:
			if is_instance_valid(part): part.visible = value
var _motorcycle_rider_parts: Array[Node3D] = []
var _motorcycle_seat := Vector3(0, -.05, .30)
var _motorcycle_grips: Dictionary = {}
var manual_wheelie: RefCounted
var _motorcycle_visual_rest := Transform3D.IDENTITY
## Altura em que a visual assenta os pneus no chão (ver _seat_wheels_on_ground); reparo volta para ela.
var visual_rest_y := 0.0
var _motorcycle_rear_contact := Vector3.ZERO
var speed := 0.0
var steering := 0.0
var _motion_start_yaw := 0.0
var throttle_input := 0.0
var steer_input := 0.0
var brake_input := false
var external_input := false
var player_damage_attribution := true
var input_locked := false
var engine_disabled := false
## Dirigibilidade da V1 (gameplay/v1_handling/V1Handling.gd) com o jogador ao volante.
var handling = preload("res://gameplay/v1_handling/V1Handling.gd").new()
var _handling_frame := false
var distance_travelled := 0.0
var visual: Node3D
var door_presentation: Node3D
var shape: CollisionShape3D
var wheels: Array[Node3D] = []
## Peças presas ao eixo que esterçam sem rolar (garfo e para-lama de moto).
var steer_pivots: Dictionary = {}
var wheel_spin := 0.0
var _burnout_wheel_spin := 0.0
var tail_material: StandardMaterial3D
## Lowrider (MuscleFleet): carroceria sobe/desce por canto e pula. Nulo nos outros carros.
var hydraulics: Node
var route: Curve3D
var route_distance := 0.0
var route_laps := 0
var blocked := false
## Quem ocupa o sensor frontal (último teste). Usado para desfazer impasse em cruzamento.
var blocker: Object = null
var blocked_time := 0.0
var unjam_time := 0.0
var backoff_time := 0.0
var junction_wait := false
var junction_gap := INF
var _junction_route: Curve3D
var _junction_list: Array = []
var _held_junction: Variant = null
# Cruzamentos anteriores cuja pegada física ainda está ocupada por este veículo.
var _clearing_junctions: Array[Vector3i] = []
var _held_offset := 0.0
var sensor_clock := 0.0
## Tempo travado por obstáculo que não é sinal/PARE. A fila herda o do carro da frente,
## então fila de semáforo vermelho fica em zero e ninguém "ultrapassa no vermelho".
var stall_time := 0.0
## Tempo sem sair do lugar (fora de fila de sinal). A limpeza da população lê isso.
var stuck_time := 0.0
## Desvio: -1 contramão (esquerda), +1 acostamento (direita), 0 na própria faixa.
var bypass_side := 0.0
var bypass_blend := 0.0
var bypass_start := 0.0
var bypass_retry := 0.0
var bypass_lane_shift := NAN
var traffic_escape: RefCounted
var _traffic_retirement_meshes: Array[Dictionary] = []
var _merging_back := false
var _exit_blocked := false
var _sense_tick := false
var sensor_shape := BoxShape3D.new()
var rotation_shape := BoxShape3D.new()

## Diagnóstico de custo (só com world.benchmark_trace): etapas de _ready acima de 2 ms.
func _trace_ready(label: String, began: int) -> int:
	var now := Time.get_ticks_usec()
	if began == 0: return 0
	if now-began >= 2000:
		var world := get_parent()
		var costs: Array = world.get_meta("perf_costs",[])
		if costs.size() < 512: costs.append({"label":"vehicle_ready_"+label+":"+archetype,"start_usec":began,"duration_usec":now-began})
		world.set_meta("perf_costs",costs)
	return now

func _ready() -> void:
	var traced := Time.get_ticks_usec() if get_parent() != null and get_parent().get_meta("benchmark_trace",false) else 0
	collision_layer = 4
	collision_mask = 7
	floor_snap_length = 0.4
	shape = CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.08,1.4,4.6)
	var specification: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(archetype)
	var variant_scale := Vector3.ONE

	if not specification.is_empty():
		match archetype:
			"desert_jeep_4x4": variant_scale = Vector3(1.1, 1.05, 1.05)
			"polar_van": variant_scale = Vector3(1.0, 1.1, 1.1)
			"lumber_pickup_4x4": variant_scale = Vector3(1.0, 1.15, 1.0)
			"ranch_pickup": variant_scale = Vector3(1.0, 1.05, 1.0)
			"station_wagon": variant_scale = Vector3(1.05, 1.0, 1.05)
			"winter_suv_heavy": variant_scale = Vector3(1.08, 1.08, 1.08)
			"muscle_classic": variant_scale = Vector3(1.05, 0.95, 1.05)
		
		var dimensions: Array = specification.bounds_size
		hull.size = Vector3(maxf(.65,dimensions[0]*variant_scale.x),clampf(dimensions[1]*variant_scale.y,1.1,3.6),dimensions[2]*variant_scale.z)
		max_health = float(specification.get("durability",180))
		damage_resistance = clampf(float(specification.get("damage_resistance",1.0)), .05, 1.0)
		health = max_health
		max_forward_speed = clampf(float(specification.max_speed)/16.0,5,45) * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
		drive_acceleration = clampf(float(specification.acceleration)/160.0,2.0,10.0)
		if handling != null: handling.configure(specification)
	half_width = hull.size.x*.5
	half_length = hull.size.z*.5
	body_height = hull.size.y
	shape.shape = hull
	shape.position.y = hull.size.y*.5
	add_child(shape)
	rotation_shape.size = hull.size-Vector3(0,.15,0)
	sensor_shape.size = Vector3(hull.size.x+.07,1.2,1)
	traced = _trace_ready("spec",traced)
	# Etapas separadas em 01/11 (Onda 3) só para caber na leitura; a ordem é a mesma de antes.
	traced = _build_visual(specification, variant_scale, traced)
	traced = _build_wheel_pivots(traced)
	_build_effects(specification, traced)

## Carroceria (frota assada, painéis do protótipo de dano ou genérica), libré, piloto da moto e pintura.
func _build_visual(specification: Dictionary, variant_scale: Vector3, traced: int) -> int:
	if damage_prototype_enabled and DAMAGE_PANELS.supports(archetype): visual = DAMAGE_PANELS.create(archetype)
	if visual == null:
		visual = preload("res://runtime/FleetCatalog.gd").create(archetype) if not specification.is_empty() else VISUAL.create(paint_color)
	if visual == null:
		# Revisão estática de loading: FleetCatalog.create devolve null quando a cena assada
		# falta ou não entra no pacote. Sem este recuo a montagem do mundo parava aqui.
		push_error("Veículo %s sem cena da frota; usando a carroceria genérica." % archetype)
		visual = VISUAL.create(paint_color)
	if variant_scale != Vector3.ONE:
		visual.scale = variant_scale
	traced = _trace_ready("visual",traced)
	visual.name = "Coupe"
	add_child(visual)
	if vehicle_id.begins_with("cobra_patrol_"):
		preload("res://gameplay/urban_v1/CobraAppearance.gd").livery(self)
	elif vehicle_id.begins_with("cobra_racer_"):
		preload("res://gameplay/urban_v1/CobraAppearance.gd").race_livery(self)
	_bind_motorcycle_rider()
	_paint = preload("res://runtime/VehiclePaint.gd").new()
	_paint.bind(visual,archetype)
	if not _paint_requested:
		paint_color = preload("res://runtime/FleetCatalog.gd").default_paint(archetype,_paint.original_color)
	else:
		_paint.apply(paint_color)
	traced = _trace_ready("paint",traced)
	preload("res://runtime/VehicleUsage.gd").apply(visual, archetype, vehicle_id, _paint.materials)
	add_to_group("drivable")
	set_meta("gameplay_role","vehicle")
	return traced

## Pivôs de roda (giram) e de direção (garfo/para-lama da moto, só esterçam), assentados no chão.
func _build_wheel_pivots(traced: int) -> int:
	var pivots: Dictionary = {}
	for part in visual.get_children():
		if str(part.get_meta("coupe_damage_material_key","")) == "tail":
			if tail_material == null: tail_material = part.material_override.duplicate()
			part.material_override = tail_material
		if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true) == false:
			# Garfo, para-lama e guidão da moto também carregam wheel_center, mas só
			# esterçam: no pivô da roda eles giravam junto com o pneu na frente da moto.
			var axle: Vector3 = part.get_meta("wheel_center")
			if not steer_pivots.has(axle):
				var steer_pivot := Node3D.new()
				steer_pivot.position = axle
				steer_pivot.set_meta("front",axle.z < 0)
				visual.add_child(steer_pivot)
				steer_pivots[axle] = steer_pivot
			part.reparent(steer_pivots[axle],false)
			part.position -= axle
		elif part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			if not pivots.has(center):
				var pivot := Node3D.new()
				pivot.position = center
				pivot.set_meta("front",center.z < 0)
				visual.add_child(pivot)
				pivots[center] = pivot
				wheels.append(pivot)
			part.reparent(pivots[center],false)
			part.position -= center
	_seat_wheels_on_ground(pivots)
	traced = _trace_ready("pivots",traced)
	if archetype.begins_with("bike_"):
		manual_wheelie = WHEELIE.new()
		_motorcycle_visual_rest = visual.transform
		for pivot in wheels:
			if not pivot.get_meta("front"):
				_motorcycle_rear_contact = Vector3(pivot.position.x,0,pivot.position.z)
	return traced

## Efeitos, dano, amassados, peças que soltam, canhão do tanque e acessórios por modelo.
func _build_effects(specification: Dictionary, traced: int) -> void:
	effects = preload("res://gameplay/vehicle_effects/VehicleEffects.gd").new()
	effects.configure(self)
	add_child(effects)
	traced = _trace_ready("effects",traced)
	damage_look = preload("res://gameplay/vehicle_effects/VehicleDamage.gd").new()
	damage_look.name = "DamageLook"
	damage_look.configure(self)
	add_child(damage_look)
	body_dents = preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").new()
	body_dents.name = "BodyDents"
	body_dents.configure(self)
	add_child(body_dents)
	if visual.get_meta("breakaway_geometry_version",0)==1:
		breakaway_parts = preload("res://gameplay/vehicle_effects/VehicleBreakawayParts.gd").new()
		breakaway_parts.name = "BreakawayParts"
		breakaway_parts.configure(self)
		add_child(breakaway_parts)
	_trace_ready("damage_look",traced)
	if archetype == "army_tank":
		tank_cannon = preload("res://gameplay/police_response/ground/TankCannon.gd").new()
		tank_cannon.name = "TankCannon"
		tank_cannon.configure(self)
		add_child(tank_cannon)
		var cannon_controls := preload("res://gameplay/police_response/ground/TankDriverControls.gd").new()
		cannon_controls.configure(self)
		add_child(cannon_controls)

	preload("res://gameplay/icecream/IceCreamVan.gd").attach(self)
	preload("res://gameplay/mining/MiningFleet.gd").attach(self)
	if archetype in preload("res://gameplay/desert_cars/DesertCarCatalog.gd").IDS or preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd").has(archetype):
		preload("res://gameplay/desert_cars/DesertCarAdapter.gd").attach(self)
	if bool(specification.get("lowrider", false)):
		hydraulics = HYDRAULICS.new()
		hydraulics.configure(self)
		add_child(hydraulics)
	if SHADOW_PROXY.enabled and SHADOW_PROXY.offer(archetype):
		_shadow_proxy = SHADOW_PROXY.new()
		_shadow_proxy.configure(self)

## Restaura a sombra original antes de varreduras ou mudanças na topologia.
func invalidate_shadow_proxy() -> void:
	if _shadow_proxy != null: _shadow_proxy.invalidate()

func set_external_driver(active: bool) -> void:
	external_input = active
	controlled = active and health > 0
	if not active:
		throttle_input = 0
		steer_input = 0
		brake_input = true

func is_player_damage_source() -> bool:
	return player_damage_attribution and controlled and not external_input

## Veículo que não é trânsito, está parado no chão e ninguém o conduz (estacionado, viatura
## parada na cena): não tem o que simular. Medido no passo de física: ~68 µs por carro parado
## (direção, move_and_slide, efeitos), 6 deles somavam 0,4 ms por passo. Acorda por qualquer
## sinal: velocidade, aceleração pedida, batida (`crash_*`), suspensão do streaming, dano,
## condutor. `is_on_floor()` exige que já tenha pousado.
## O hull de colisão apoia em y=0, mas os modelos da frota trazem o fundo do pneu entre
## +3 cm (flutua) e -3 cm (afunda) (medido em tests/measure/measure_wheel_ground_contact.gd).
## Reassenta a visual para o pneu mais baixo tocar o chão; ignora desvios grandes, que
## são modelo sem pneus de verdade (tanque, esteiras).
func _seat_wheels_on_ground(pivots: Dictionary) -> void:
	var lowest := INF
	for center: Vector3 in pivots:
		for part in pivots[center].get_children():
			if part is MeshInstance3D:
				lowest = minf(lowest,center.y+(part as MeshInstance3D).get_aabb().position.y*part.scale.y+part.position.y)
	if lowest == INF or absf(lowest) > .06: return
	visual.position.y -= lowest*visual.scale.y
	visual_rest_y = visual.position.y

func _is_resting() -> bool:
	return not traffic and health > 0 and not controlled and absf(speed) < 0.05 and absf(throttle_input) < 0.01 		and horizontal_velocity.length_squared() < 0.0025 and velocity.length_squared() < 0.0025 and is_on_floor() 		and not has_meta("crash_stun") and not has_meta("awaiting_ground") and not has_meta("mining_released_load") and (manual_wheelie == null or manual_wheelie.pitch == 0)

## Trânsito ambiente longe da câmera roda menos passos: a 60-110 m um a cada 2, além disso um a cada 4,
## escalonados por carro. O passo executado usa o tempo acumulado e o move_and_slide anda a mesma
## distância (a velocidade horizontal é multiplicada só durante a chamada), então o movimento é o
## mesmo, só mais grosso, onde ninguém enxerga. Perto da câmera, controlado, batido, destruído ou
## suspenso pelo streaming: passo normal.
const LOD_NEAR := LOD_WRECK.LOD_NEAR
const LOD_FAR := LOD_WRECK.LOD_FAR
const LOD_OFFSCREEN_NEAR := LOD_WRECK.LOD_OFFSCREEN_NEAR
const LOD_VIEW_MARGIN := LOD_WRECK.LOD_VIEW_MARGIN
var _lod_skipped := -1
var _lod_pending := 0.0

func _lod_stride() -> int: return _lod_wreck._lod_stride()

## 0 = pular este passo; senão, quantos passos do motor o passo executado representa.
func _lod_gate(delta: float) -> float: return _lod_wreck._lod_gate(delta)

## Carcaças desaparecem dez segundos após a destruição.
const WRECK_LIFETIME := LOD_WRECK.WRECK_LIFETIME
const WRECK_FADE := LOD_WRECK.WRECK_FADE
var _wreck_age := 0.0
var _wreck_fade := -1.0
var _wreck_meshes: Array[MeshInstance3D] = []
var _wreck_collision_state: Array[Dictionary] = []
var _wreck_lights: Array[Dictionary] = []
## Carcaça que afunda em vez de ficar transparente (24/10, hipótese descartada). `transparency` > 0 em cada malha do carro põe cada
## material × formato no passe alfa: pipelines `draw` compiladas na hora do desenho, um quadro de 0,9–1,2 s
## 10 s depois de cada explosão no estresse (frio e quente; 5ª–7ª rodadas, doc §10–12), que o pré-aquecimento
## da carcaça sumindo (GETECO_WRECK_FADE_PREWARM) não cobria. Afundar não muda material nenhum.
## DESLIGADO por padrão (GETECO_WRECK_SINK=1 liga): no A/B da 8ª rodada o quadro de ~0,9 s continuou igual
## com a carcaça afundando (896/896 ms × 884/867 ms), então a causa não é o sumiço (doc §13).
static var WRECK_SINK_ENABLED := OS.get_environment("GETECO_WRECK_SINK") == "1"
const WRECK_SINK_DEPTH := LOD_WRECK.WRECK_SINK_DEPTH
var _wreck_sunk := 0.0

func _wreck_expires() -> bool:
	return not controlled

## true quando a carcaça foi removida neste passo.
func _tick_wreck(delta: float) -> bool: return _lod_wreck._tick_wreck(delta)

func _begin_wreck_fade() -> void: _lod_wreck._begin_wreck_fade()

func _physics_process(delta: float) -> void:
	var began := STALL_WORK.begin()
	_stall_physics_tick(delta)
	STALL_WORK.finish_slow("vehicle.physics", began, 10000, self)

func _stall_physics_tick(delta: float) -> void:
	# Spans (22/10): quadros com vehicle.physics de 8–11 ms num carro só e nenhum trecho interno nomeado.
	# Etapas separadas em 01/11 (Onda 3) só para caber na leitura; a ordem é a mesma de antes e só
	# entram 3 chamadas a mais por passo executado (1 nos pulados pelo LOD), todas no próprio veículo.
	if _physics_prelude(delta): return
	var rail_drive := false
	var rail_wake := false
	if TRAFFIC_RAILS.enabled and traffic_rails == null and traffic and get_meta("ambient_traffic",false):
		traffic_rails = TRAFFIC_RAILS.new()
	var stage := STALL_WORK.begin()
	# O trilho segue a mesma cadência do LOD: o passo executado cobre os pulados. Avaliar o trilho
	# todo passo (motorista, sensores e vizinhos em n²) custou ~4 ms com 37 carros no benchmark F
	# (2026-10-13), mais que o LOD antigo que ele substituía. Dano e contato acordam com wake().
	var lod := 1.0
	if traffic_rails != null and traffic_rails.force_physics_pending():
		_lod_pending = 0.0
		_lod_skipped = -1
	else:
		lod = _lod_gate(delta)
	STALL_WORK.finish_slow("vehicle.lod", stage, 5000, self)
	if lod == 0.0: return
	delta *= lod
	if traffic_rails != null:
		stage = STALL_WORK.begin()
		rail_drive = traffic_rails.prepare(self,delta)
		rail_wake = traffic_rails.force_physics
		STALL_WORK.finish_slow("vehicle.rails_prepare", stage, 2000, self)
	if health <= 0:
		controlled = false
		traffic = false
		speed = move_toward(speed,0,20*delta)
	stage = STALL_WORK.begin()
	if traffic:
		_motion_start_yaw = rotation.y
		_traffic_rail_drive = rail_drive
		_drive_traffic(delta)
		_traffic_rail_drive = false
	else:
		_drive_player(delta)
	STALL_WORK.finish_slow("vehicle.drive", stage, 5000, self)
	if rail_drive and _physics_rail_advance(delta): return
	# Trânsito parado em fila "dorme": sem move_and_slide nem consulta de giro. Em
	# engarrafamento, carros encostados custavam 60–98 ms por quadro somados (2026-09-23).
	if traffic and health > 0 and absf(speed) < 0.05 and horizontal_velocity.length_squared() < 0.0025 and is_on_floor():
		horizontal_velocity = Vector3.ZERO
		velocity = Vector3.ZERO
		return
	var previous := global_position
	var impact_speed := absf(speed)
	var impact_direction := signf(speed)
	var forward := -global_basis.z
	var incoming_velocity := _physics_move(delta, lod, forward)
	var motion := _physics_contacts(delta, previous, impact_speed, impact_direction, forward, incoming_velocity)
	stage = STALL_WORK.begin()
	STREET.vehicle_post_move(self,incoming_velocity,delta)
	STALL_WORK.finish_slow("vehicle.street_post", stage, 5000, self)
	if manual_wheelie != null: _tick_motorcycle_wheelie(delta)
	_tick_motion_presentation(delta,motion,incoming_velocity,forward)

## Antes de dirigir: aposentadoria, fuga, cruzamentos já deixados, vida da carcaça e repouso.
## true = o passo acaba aqui (carcaça removida ou veículo parado sem nada a simular).
func _physics_prelude(delta: float) -> bool:
	var stage := STALL_WORK.begin()
	if controlled and not external_input and (not _traffic_retirement_meshes.is_empty() or _retire_sunk > 0.0): fade_traffic_retirement(0)
	if traffic_escape!=null and (controlled or not traffic): traffic_escape.tick(self,delta)
	# Limpa também durante o recuo, controle do jogador e repouso; nenhum trabalho de geometria quando vazio.
	if not _clearing_junctions.is_empty(): _clear_departed_junctions()
	STALL_WORK.finish_slow("vehicle.pre_tick", stage, 2000, self)
	stage = STALL_WORK.begin()
	var removed := health <= 0.0 and _tick_wreck(delta)
	STALL_WORK.finish_slow("vehicle.wreck_lifetime", stage, 5000, self)
	if removed: return true
	stage = STALL_WORK.begin()
	var resting := _is_resting()
	STALL_WORK.finish_slow("vehicle.resting", stage, 5000, self)
	if resting:
		if traffic_rails != null and traffic_rails.active: traffic_rails.wake(self)
		return true
	return false

## Trilho do trânsito: true quando o trilho já moveu o carro neste passo (sem move_and_slide).
func _physics_rail_advance(delta: float) -> bool:
	var rail_previous := global_position
	var stage := STALL_WORK.begin()
	var advanced: bool = traffic_rails.advance(self,delta)
	STALL_WORK.finish_slow("vehicle.rails_advance", stage, 2000, self)
	if advanced:
		var rail_motion := global_position-rail_previous
		rail_motion.y = 0.0
		distance_travelled += rail_motion.length()
		_tick_motion_presentation(delta,rail_motion,horizontal_velocity,-global_basis.z)
		return true
	return false

## Velocidade do passo, física de rua antes de mover, apoio do deserto e move_and_slide.
## Devolve a velocidade horizontal de chegada (antes do LOD), que contatos e efeitos usam.
func _physics_move(delta: float, lod: float, forward: Vector3) -> Vector3:
	if not _handling_frame:
		var traction := .9 if controlled and brake_input and absf(speed)>5 else 9.0
		horizontal_velocity = horizontal_velocity.lerp(forward*speed,1.0-exp(-traction*delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	# floor_snap_length mantém o apoio, inclusive na descida. Empurrar contra o
	# piso já apoiado repetia colisões/deslizamentos do mesmo chão a cada passo.
	# Uma carga de mineração solta pode perder a caçamba que a apoiava. O monitor
	# temporário confirma chão estático; is_on_floor em cache não pode suprimir a gravidade.
	velocity.y = 0.0 if is_on_floor() and not has_meta("mining_released_load") else velocity.y-20.0*delta
	# Física de rua: atropelamento e mobília derrubável antes de mover (o carro
	# atravessa o que cedeu); batida carro x carro e deslize depois.
	var stage := STALL_WORK.begin()
	STREET.vehicle_pre_move(self,delta)
	STALL_WORK.finish_slow("vehicle.street_pre", stage, 5000, self)
	var incoming_velocity := Vector3(velocity.x,0,velocity.z)
	if lod != 1.0:
		velocity.x *= lod
		velocity.z *= lod
	var terrain_supported := false
	# Apoio exato de caixa em pé no cânion e na pedreira escritos. O helper verifica
	# o piso físico, incluindo quadros cujo apoio veio do snap.
	stage = STALL_WORK.begin()
	var support_y := DESERT_GROUND.vertical_velocity(self,velocity,get_physics_process_delta_time())
	STALL_WORK.finish_slow("vehicle.ground_support", stage, 2000, self)
	if is_finite(support_y):
		velocity.y=support_y
		terrain_supported=true
	var move_began := STALL_WORK.begin()
	move_and_slide()
	if terrain_supported and not is_on_floor() and not is_on_wall(): apply_floor_snap()
	STALL_WORK.finish_slow("vehicle.move_and_slide", move_began, 10000, self)
	if lod != 1.0:
		velocity.x /= lod
		velocity.z /= lod
	return incoming_velocity

## Depois de mover: distância, parede, atropelamento e dano de batida em parede. Devolve o movimento.
func _physics_contacts(delta: float, previous: Vector3, impact_speed: float, impact_direction: float, forward: Vector3, incoming_velocity: Vector3) -> Vector3:
	var stage := STALL_WORK.begin()
	var motion := global_position-previous
	motion.y = 0
	distance_travelled += motion.length()
	# O contato remove a velocidade para frente, em vez de acumular movimento contra a parede.
	if is_on_wall():
		speed = motion.dot(forward)/maxf(delta,0.001)
		horizontal_velocity = Vector3(velocity.x,0,velocity.z)
	var hit_vehicle := false
	for index in get_slide_collision_count():
		var target := get_slide_collision(index).get_collider()
		if target is Node and target.is_in_group("drivable"):
			hit_vehicle = true
			continue # StreetPhysics applies car-to-car damage once per actual impact.
		if impact_speed > 4 and target is Node and target.has_method("receive_damage") and target != self and not PROTECTION.is_protected(target):
			var living_person: bool = target is CharacterBody3D and target.get("dead") == false and target.get("health") != null
			target.receive_damage(impact_speed*4,self)
			if living_person and target.get("dead") == true:
				var stains := preload("res://gameplay/vehicle_effects/VehicleBlood.gd")
				restore_blood_stains(int(get_meta("blood_stains",0)) | stains.impact_side(self,forward * impact_direction))
	if is_on_wall() and not hit_vehicle and impact_speed > 6 and impact_speed-absf(speed) > 4:
		# O contato pode durar vários quadros; cobrar a batida apenas uma vez.
		# Tempo da simulação: uma pausa de compilação de shader não é outra batida.
		var now := Engine.get_physics_frames()
		if now-_last_wall_damage_frame >= ceili(WALL_DAMAGE_COOLDOWN_SECONDS * Engine.physics_ticks_per_second):
			_last_wall_damage_frame = now
			var local_pt := Vector3(0, 0, -half_length)
			var local_inward := Vector3.BACK
			var closing_speed := maxf(0.0,impact_speed-absf(speed))
			for i in get_slide_collision_count():
				var coll := get_slide_collision(i)
				if not (coll.get_collider() is CharacterBody3D) and absf(coll.get_normal().y)<.5:
					local_pt = to_local(coll.get_position())
					local_inward = global_basis.inverse()*coll.get_normal()
					closing_speed = maxf(0.0,-incoming_velocity.dot(coll.get_normal()))
					break
			receive_impact(minf((impact_speed-absf(speed))*WALL_DAMAGE_PER_SPEED, max_health*WALL_DAMAGE_MAX_RATIO), local_pt, null, closing_speed, local_inward, horizontal_velocity)
	STALL_WORK.finish_slow("vehicle.contacts", stage, 5000, self)
	return motion

func _tick_motion_presentation(delta: float, motion: Vector3, incoming_velocity: Vector3, forward: Vector3) -> void:
	var stage := STALL_WORK.begin()
	if traffic:
		# O erro de direção fica minúsculo quando o corpo segue a rota, mesmo numa
		# curva longa. Ajusta as rodas à curva realmente aplicada, incluindo
		# movimento em trilho e curvas recusadas por colisão, usando a relação de bicicleta.
		var travel := speed * delta
		steering = clampf(atan(WHEELBASE * angle_difference(_motion_start_yaw, rotation.y) / travel), -0.48, 0.48) if absf(travel) > 0.001 else 0.0
	wheel_spin += motion.dot(forward)/0.355
	_burnout_wheel_spin = fposmod(_burnout_wheel_spin + burnout_strength()*32.0*delta, TAU)
	for pivot in wheels:
		var front: bool = pivot.get_meta("front", false)
		pivot.rotation = Vector3(wheel_spin + (0.0 if front else _burnout_wheel_spin),steering if front else 0.0,0)
	for pivot in steer_pivots.values():
		pivot.rotation.y = steering if pivot.get_meta("front") else 0.0
	if tail_material and not is_instance_valid(equipment):
		tail_material.emission_energy_multiplier = 2.5 if brake_input or blocked else 0.65
	STALL_WORK.finish_slow("vehicle.wheels", stage, 5000, self)
	stage = STALL_WORK.begin()
	if is_instance_valid(effects): effects.physics_tick(delta,incoming_velocity)
	STALL_WORK.finish_slow("vehicle.effects", stage, 5000, self)

func stop_boarding_motion() -> void:
	reset_motorcycle_wheelie()
	# A animação do corpo usa âncoras fixas de porta/assento. Só a velocidade deixava a
	# velocidade horizontal suavizada arrastar o veículo para fora de baixo delas.
	speed = 0.0
	horizontal_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	# A StreetPhysics mantém o momento do impacto fora da velocidade. Mantê-lo deixava um
	# carro parado escorregar metros para longe das âncoras fixas de embarque a 0 km/h.
	for key in ["crash_slide", "crash_spin", "crash_stun"]:
		if has_meta(key): remove_meta(key)
	if handling != null: handling.reset()

func reset_motorcycle_wheelie() -> void:
	if manual_wheelie == null: return
	manual_wheelie.reset()
	if is_instance_valid(visual): visual.transform = _motorcycle_visual_rest

func _tick_motorcycle_wheelie(delta: float) -> void: _rider._tick_motorcycle_wheelie(delta)

func _bind_motorcycle_rider() -> void: _rider._bind_motorcycle_rider()

func motorcycle_handholds() -> Dictionary: return _rider.motorcycle_handholds()

## A held burnout is distinct from a moving skid or a normal launch.
func burnout_strength() -> float:
	if not controlled or external_input or input_locked or engine_disabled or health <= 0 or archetype == "army_tank": return 0.0
	if not brake_input or throttle_input <= .2 or not is_on_floor() or horizontal_velocity.length_squared() > .75*.75: return 0.0
	return clampf(throttle_input, 0.0, 1.0)

var _handbrake_held := false

func _drive_player(delta: float) -> void:
	_handling_frame = false
	if handling != null and controlled and not external_input and not input_locked and not engine_disabled and health > 0:
		var game_input := get_node("/root/GameInput")
		var axis: Vector2 = game_input.vehicle_input()
		if manual_wheelie != null: axis.x *= manual_wheelie.steering_scale()
		var handbrake := Input.is_action_pressed("handbrake")
		# Segurando a hidráulica, direção e pulo vão para a carroceria; o carro fica parado.
		if hydraulics != null and hydraulics.captures_input():
			axis = Vector2.ZERO
			handbrake = true
		# Só a puxada pelo botão faz barulho de alavanca; o burnout abaixo não é o freio de mão.
		if handbrake != _handbrake_held:
			_handbrake_held = handbrake
			if handbrake: FIREFLY.handbrake(self)
		var burnout: float = game_input.vehicle_burnout_throttle() if archetype != "army_tank" else 0.0
		if burnout > 0.0:
			axis.y = burnout
			handbrake = true
		throttle_input = axis.y
		steer_input = -axis.x
		brake_input = handbrake
		handling.step(self, delta, axis.y, axis.x, handbrake, _wetness())
		brake_input = handling.service_brake(self, axis.y, handbrake)
		steering = move_toward(steering, steer_input * 0.48, delta * 2.0)
		_handling_frame = true
		return
	if handling != null: handling.reset()
	if not external_input:
		throttle_input = 0
		steer_input = 0
		brake_input = input_locked
		if controlled and not input_locked:
			var axis: Vector2 = get_node("/root/GameInput").vehicle_input()
			if hydraulics != null and hydraulics.captures_input(): axis = Vector2.ZERO
			throttle_input = axis.y
			steer_input = -axis.x
			brake_input = Input.is_action_pressed("handbrake")
	if not controlled or engine_disabled: brake_input = true
	if brake_input:
		speed = move_toward(speed,0,14.0*delta)
	elif absf(throttle_input) > 0.01:
		var acceleration := 11.0 if speed*throttle_input < 0 else drive_acceleration
		speed = clampf(speed+throttle_input*acceleration*delta,-REVERSE_SPEED,max_forward_speed)
	else:
		speed = move_toward(speed,0,2.0*delta)
	steering = move_toward(steering,steer_input*0.48*(manual_wheelie.steering_scale() if manual_wheelie != null else 1.0),delta*2.0)
	var turn := speed/WHEELBASE*tan(steering)*delta
	if absf(turn) > 0.0001 and can_rotate(rotation.y+turn): rotation.y += turn

func _wetness() -> float:
	var world := get_parent()
	var session = world.get("session") if world != null else null
	var weather = session.get("weather") if session != null else null
	if weather == null: return 0.0
	# Aderência segue a rua: molha aos poucos e continua escorregadia enquanto
	# seca, em vez de voltar inteira no instante em que a chuva para.
	if weather.has_method("get_coastal_wetness"): return clampf(float(weather.get_coastal_wetness()), 0.0, 1.0)
	return 1.0 if int(weather.weather_state) in [1, 2] else 0.0

## A consulta é reaproveitada: alocar uma PhysicsShapeQueryParameters3D (e o array `exclude`) por
## carro por passo era custo à toa. O formato é reatribuído porque o esmagamento pesado o troca.
var _rotation_query: PhysicsShapeQueryParameters3D
func can_rotate(yaw: float) -> bool:
	if _rotation_query == null:
		_rotation_query = PhysicsShapeQueryParameters3D.new()
		_rotation_query.collision_mask = 7
		_rotation_query.exclude = [get_rid()]
	_rotation_query.shape = rotation_shape
	_rotation_query.transform = Transform3D(Basis(Vector3.UP,yaw),global_position+Vector3.UP*shape.position.y)
	return get_world_3d().direct_space_state.intersect_shape(_rotation_query,1).is_empty()

## Impasse de cruzamento: sem prioridade de via, dois carros de direções cruzadas
## entravam no sensor um do outro e paravam para sempre (engarrafamento de 2026-09-23).
## Depois de TRAFFIC_JAM_SECONDS parados um diante do outro, o de menor id segue
## devagar ignorando só aquele carro; o outro dá uma ré curta para abrir espaço.
const TRAFFIC_JAM_SECONDS := TRAFFIC_DRIVE.TRAFFIC_JAM_SECONDS

func _traffic_jam_partner() -> Object: return _traffic_drive._traffic_jam_partner()

## Obstáculo que o trânsito pode empurrar depois de esperar: nunca gente viva, o
## carro do jogador ou outro carro de trânsito (esse tem desempate próprio). Pessoa
## caída só depois de 8 s. Se for parede de verdade, a física segura o carro.
func _pushable_obstacle(target) -> bool: return _traffic_drive._pushable_obstacle(target)

## Distância ao longo da rota até `offset` (negativa depois de passar; rota fechada dá a volta).
func _route_ahead(offset: float, length: float, open: bool) -> float: return _traffic_drive._route_ahead(offset, length, open)

## Corpos físicos que podem manter ocupada uma reserva de cruzamento expirada.
func junction_collision_bodies() -> Array[CharacterBody3D]:
	return [self]

func _release_current_junction() -> void: _traffic_drive._release_current_junction()

# Resets explícitos e a saída da cena liberam todo token, incluindo o casco de trás.
func _release_junction() -> void: _traffic_drive._release_junction()

func _retain_current_junction() -> void: _traffic_drive._retain_current_junction()

func _clear_departed_junctions() -> void: _traffic_drive._clear_departed_junctions()

## Cruzamento à frente (TrafficJunctions): true = parar na faixa. `junction_gap` fica
## com a distância da frente do carro até a faixa, para frear de forma progressiva.
func _junction_gate(length: float, open: bool) -> bool: return _traffic_drive._junction_gate(length, open)

func _exit_tree() -> void:
	_release_junction()

func _invalidate_route_projection() -> void: _traffic_drive._invalidate_route_projection()

## Carros parados reaproveitam só a projeção geométrica. Decisões e sensores ainda
## rodam a cada tick; qualquer mudança exata de posição ou curva editada exige nova varredura.
func _traffic_route_offset(point: Vector3) -> float: return _traffic_drive._traffic_route_offset(point)

func _drive_traffic(delta: float) -> void: _traffic_drive._drive_traffic(delta)

## Desvio de obstáculo parado (viatura na faixa, carcaça, fila que não anda): antes o
## trânsito só esperava, e um carro parado virava engarrafamento sem fim (2026-09-25).
## Depois de BYPASS_AFTER_SECONDS travado, o carro procura a contramão (depois o
## acostamento) livre por uns 25 m, contorna devagar e volta quando a própria faixa
## está livre ao lado e à frente.
const BYPASS_AFTER_SECONDS := TRAFFIC_DRIVE.BYPASS_AFTER_SECONDS
const BYPASS_SPEED := TRAFFIC_DRIVE.BYPASS_SPEED
const BYPASS_MAX_DISTANCE := TRAFFIC_DRIVE.BYPASS_MAX_DISTANCE
const BYPASS_PROBES := TRAFFIC_DRIVE.BYPASS_PROBES
const MERGE_PROBES := TRAFFIC_DRIVE.MERGE_PROBES
## Waiting time is diagnostic; expiry never authorises entering a blocked exit.
var _exit_wait := 0.0

func traffic_rear_clear(distance := 3.0) -> bool: return _traffic_drive.traffic_rear_clear(distance)

func _is_vehicle(target) -> bool: return _traffic_drive._is_vehicle(target)

func _body_speed(target) -> float: return _traffic_drive._body_speed(target)

func _stall_estimate() -> float: return _traffic_drive._stall_estimate()

func _route_point(offset: float, length: float, open: bool) -> Vector3: return _traffic_drive._route_point(offset, length, open)

func _route_right(offset: float, length: float, open: bool) -> Vector3: return _traffic_drive._route_right(offset, length, open)

## Deslocamento lateral do desvio: faixa contrária inteira à esquerda; à direita só o
## que cabe até o meio-fio.
func _bypass_shift() -> float: return _traffic_drive._bypass_shift()

## Casco livre na rota deslocada `shift` metros para a direita, a `probes` metros à frente.
func _lane_clear(shift: float, probes: Array, mask := 7) -> bool: return _traffic_drive._lane_clear(shift, probes, mask)

func _try_bypass() -> bool: return _traffic_drive._try_bypass()

## Corpo parado na faixa original (o que estamos contornando): o sensor frontal o
## enxerga em diagonal durante o desvio e não deve frear o carro por isso.
func _in_home_lane(target) -> bool: return _traffic_drive._in_home_lane(target)

func _update_bypass() -> void: _traffic_drive._update_bypass()

func _end_bypass() -> void: _traffic_drive._end_bypass()

## Carro parado logo depois do cruzamento, na nossa saída.
func _exit_occupied(offset: float, length: float, open: bool) -> bool: return _traffic_drive._exit_occupied(offset, length, open)

func obstacle_ahead() -> bool: return _traffic_drive.obstacle_ahead()

## Retirada sem passe alfa (25/10, GETECO_RETIRE_SINK=1): só o visual afunda; a colisão fica até o fim,
## como na transparência. Junto com a carcaça (GETECO_WRECK_SINK) e o destroço (GETECO_DEBRIS_SHRINK) são as
## três fontes de `transparency` > 0 que a sonda de assinatura viu nos quadros de ~0,9 s (13ª rodada, doc §16).
static var RETIRE_SINK_ENABLED := OS.get_environment("GETECO_RETIRE_SINK") == "1"
const RETIRE_SINK_DEPTH := LOD_WRECK.RETIRE_SINK_DEPTH
var _retire_sunk := 0.0

func fade_traffic_retirement(alpha: float) -> void: _lod_wreck.fade_traffic_retirement(alpha)

func place(point: Vector3, yaw: float) -> void:
	reset_motorcycle_wheelie()
	global_position = point
	rotation.y = yaw
	speed = 0
	velocity = Vector3.ZERO
	horizontal_velocity = Vector3.ZERO
	reset_physics_interpolation()

## Porte para embarque/desembarque. Antes toda carroceria usava a porta e o banco do
## carro pequeno: o motorista de ônibus e de caminhão entrava abaixado pelo meio da
## lataria. `open`: moto, buggy e empilhadeira (sem porta); `car`: senta baixo;
## `tall`: caminhonete, SUV e van (um degrau); `truck`: cabine alta, sobe pelo estribo;
## `bus`: porta dianteira direita com escada.
func boarding_class() -> String: return _doors.boarding_class()

## Lados por onde se entra ao volante. Ônibus só pela porta de serviço da direita.
func boarding_sides() -> Array:
	return [1] if boarding_class() == "bus" else [-1, 1]

## Altura do piso da cabine sobre o chão, que o corpo precisa vencer para entrar.
func boarding_step_height() -> float: return _doors.boarding_step_height()

## Centro do vão da porta (eixo Z do veículo). Vem da tabela por modelo: antes vinha de uma
## fração do comprimento do casco, e em van, ambulância e caminhão ficava no meio da carga.
func _cab_z() -> float: return _doors._cab_z()

## Banco no meio do vão, um palmo à frente do centro. Tabela por modelo (VehicleDoorSpecs).
func _door_seat_z() -> float: return _doors._door_seat_z()

func driver_door_anchor(side: int) -> Vector3:
	return to_global(Vector3(float(side) * (half_width + .54), .04, _cab_z()))

## O piloto aparece sentado ao volante (carro, caminhão, ônibus, buggy, empilhadeira).
## Moto usa a pose de guidão; blindado tem escotilha e piloto próprios. Ver VehicleInterior.
func shows_seated_driver() -> bool:
	return preload("res://gameplay/VehicleInterior.gd").shows_driver(self)

## Quanto o corpo desce do porte de pé até o banco desta cabine (m).
func seated_drop() -> float:
	return preload("res://gameplay/VehicleInterior.gd").seated_drop(self)

func driver_seat_anchor() -> Vector3: return _doors.driver_seat_anchor()

## Geometria de embarque deste lado (ponto de espera fora do arco da folha, portão no
## vão, ponto de agarrar, ponta da folha aberta), em coordenadas do veículo. Vazio para
## veículo sem porta (moto, buggy, empilhadeira) e para o ônibus.
func door_layout(side: int) -> Dictionary: return _doors.door_layout(side)

## Porta do motorista num ângulo (rad) dado quadro a quadro pela mão e pelo corpo de quem entra
## (VehicleBoardingMocap). `sound`: 1 = destravou ao abrir, -1 = bateu ao fechar, 0 = sem som.
func pose_driver_door(side: int, radians: float, limit := 0.0, sound := 0) -> void: _doors.pose_driver_door(side, radians, limit, sound)

func animate_driver_door(side: int, opened: bool, duration := .28) -> void: _doors.animate_driver_door(side, opened, duration)

func _refresh_tuning_appearance() -> void:
	# Caminhos de restauração podem aplicar pintura/identidade de fábrica depois de instalar peças salvas.
	# Reaplica o acabamento local sem reconstruir malhas, cobrar nem mexer no estado.
	if has_meta("tuning_appearance"):
		invalidate_shadow_proxy()
		get_meta("tuning_appearance").apply(get_meta("desert_parts",{}),paint_color)
		if is_instance_valid(damage_look): damage_look.refresh_paint_finish()

func _ensure_door_presentation() -> void: _doors._ensure_door_presentation()

## Termina agora a porta que estiver sendo preparada. Deve rodar ANTES de qualquer módulo
## trocar as malhas do casco (interior, teto translúcido): o recorte parte das originais.
func finish_doors() -> void:
	_ensure_door_presentation()

## Prepara a porta aos poucos, antes de alguém precisar dela (o recorte custa dezenas de ms de
## uma vez). Chamado quadro a quadro enquanto o jogador está perto; true quando pronta.
func warm_doors(budget_usec := 2500) -> bool: return _doors.warm_doors(budget_usec)

func ensure_equipment(world: Node) -> Node:
	if is_instance_valid(equipment): return equipment
	equipment = preload("res://gameplay/VehicleEquipment.gd").new()
	equipment.configure(self,world)
	add_child(equipment)
	if not equipment_state.is_empty(): equipment.restore_state(equipment_state)
	return equipment

func receive_impact(amount: float, local_point: Vector3, source: Node = null, closing_speed := -1.0, local_normal := Vector3.ZERO, presentation_velocity := Vector3.INF) -> void:
	if not is_finite(amount) or amount <= 0 or not local_point.is_finite() or health <= 0 or PROTECTION.is_protected(self): return
	if not is_finite(closing_speed) or not local_normal.is_finite(): return
	invalidate_shadow_proxy()
	var inward := Vector3(local_normal.x,0,local_normal.z).normalized()
	var visual_amount := amount*damage_resistance
	if damage_prototype_enabled and closing_speed>=0:
		# O HP fica equilibrado para perseguições longas; a lataria responde à velocidade real de aproximação.
		visual_amount = maxf(visual_amount,maxf(0.0,closing_speed-3.0)*1.2*damage_resistance)
	# Spans por etapa (21/10): no estresse de release a batida custou 8–19 ms por carro sem dizer onde.
	var stage := STALL_WORK.begin()
	if is_instance_valid(body_dents): body_dents.impact(visual_amount,local_point,inward if damage_prototype_enabled and closing_speed>=0 else Vector3.ZERO)
	STALL_WORK.finish_slow("vehicle.impact.dents", stage, 2000, self)
	stage = STALL_WORK.begin()
	if damage_prototype_enabled and closing_speed>=0 and is_instance_valid(breakaway_parts):
		breakaway_parts.impact(local_point,closing_speed,inward,presentation_velocity)
	STALL_WORK.finish_slow("vehicle.impact.breakaway", stage, 2000, self)
	if is_instance_valid(equipment) and equipment.has_method('receive_impact'):
		equipment.receive_impact(local_point, amount)
	stage = STALL_WORK.begin()
	receive_damage(amount, source)
	STALL_WORK.finish_slow("vehicle.impact.damage", stage, 2000, self)

func snapshot_glass() -> Array:
	var owner := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").owner_for(self)
	return owner.snapshot() if owner != null else []

func restore_glass(records: Array) -> void:
	if not preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").valid_records(records): return
	var owner := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").owner_for(self,not records.is_empty())
	if owner != null: owner.restore_records(records)

func restore_blood_stains(mask: int) -> void:
	preload("res://gameplay/vehicle_effects/VehicleBlood.gd").apply(self, mask)

func restore_body_dents(records: Array, panel_state: Dictionary = {}, broken_glass: Array = []) -> void:
	if not preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd").valid_records(records) or not preload("res://gameplay/vehicle_effects/VehicleBreakawayParts.gd").valid_state(panel_state) or not preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").valid_records(broken_glass): return
	invalidate_shadow_proxy()
	# Restaura a geometria primeiro e depois esconde os painéis ausentes. Nenhum detrito ou evento de colisão é repetido.
	if is_instance_valid(breakaway_parts): breakaway_parts.repair()
	if is_instance_valid(body_dents): body_dents.restore_records(records)
	if is_instance_valid(breakaway_parts): breakaway_parts.restore_state(panel_state)
	restore_glass(broken_glass)

func receive_damage(amount: float, _source: Node = null) -> void:
	if not is_finite(amount) or amount <= 0 or health <= 0 or PROTECTION.is_protected(self): return
	invalidate_shadow_proxy()
	if TRAFFIC_RAILS.enabled and traffic_rails != null: traffic_rails.wake(self,2.0)
	var response: Callable = get_meta("gang_damage_handler",Callable())
	if response.is_valid(): response.call(_source)
	amount *= damage_resistance
	health = maxf(0,health-amount)
	damaged.emit(amount)
	# Aparência (desgaste, fogo no motor, carcaça) vive em VehicleDamage; a vida continua aqui.
	var look := damage_look if is_instance_valid(damage_look) else null
	if look: look.note_source(_source)
	if health <= 0:
		destroyed.emit()
		if look: look.wreck()
	elif look: look.refresh()

func crush(source: Node3D) -> bool:
	# O solver de rua já instalou o casco achatado que aguenta carga.
	if health <= 0 or not has_meta("heavy_crush_ratio") or PROTECTION.is_protected(self): return false
	if is_instance_valid(source): set_meta("heavy_crush_source",weakref(source))
	# Esmagar é terminal mesmo para carro com resistência a dano.
	receive_damage((health+1.0)/maxf(damage_resistance,.05),source)
	# Carros de produção/despacho explodem pelo ouvinte de destruição. Veículos
	# montados em outro lugar usam este recurso; o Gameplay deduplica os dois caminhos.
	var world := get_parent()
	var gameplay: Variant = world.get("gameplay") if is_instance_valid(world) else null
	if is_instance_valid(gameplay) and not get_meta("heavy_crush_exploded",false):
		gameplay.explode(global_position+Vector3.UP*.4,5.0,35.0,self,false)
	return true

func restore_health(saved_health: float) -> void:
	# Carregar dano não pode aplicar a blindagem de novo e curar o veículo em silêncio.
	if not is_finite(saved_health): return
	if saved_health < max_health: invalidate_shadow_proxy()
	health = clampf(saved_health, 0.0, max_health)
	if is_instance_valid(damage_look):
		if health <= 0.0: damage_look.wreck()
		else: damage_look.refresh()

func repair() -> void:
	invalidate_shadow_proxy()
	_wreck_age = 0.0
	if _wreck_fade >= 0.0:
		for entry in _wreck_collision_state:
			if is_instance_valid(entry.node):
				entry.node.collision_layer = entry.layer
				entry.node.collision_mask = entry.mask
		for entry in _wreck_lights:
			if is_instance_valid(entry.node): entry.node.visible = entry.visible
		for mesh in _wreck_meshes:
			if is_instance_valid(mesh): mesh.transparency = 0.0
		global_position.y += _wreck_sunk
	_wreck_sunk = 0.0
	_wreck_fade = -1.0
	_wreck_meshes.clear()
	_wreck_collision_state.clear()
	_wreck_lights.clear()
	STREET.vehicle_repaired(self)
	for marker in ["heavy_crush_source","heavy_crush_exploded"]:
		if has_meta(marker): remove_meta(marker)
	preload("res://gameplay/police_response/ground/TirePuncture.gd").repair_vehicle(self)
	health = max_health
	restore_glass([])
	if is_instance_valid(body_dents): body_dents.clear()
	if is_instance_valid(damage_look): damage_look.restore()
	if is_instance_valid(breakaway_parts): breakaway_parts.repair()
	if _shadow_proxy != null: _shadow_proxy.repair_completed()

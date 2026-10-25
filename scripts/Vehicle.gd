extends CharacterBody3D
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const DAMAGE_PANELS := preload("res://gameplay/vehicle_effects/VehiclePanelCatalog.gd")
## Process-local comparison; normal gameplay uses the prototype on authored models.
static var damage_prototype_enabled := not ("--vehicle-damage-baseline" in OS.get_cmdline_user_args())

const VISUAL := preload("res://scripts/VehicleVisual.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
const STREET := preload("res://gameplay/street_physics/StreetPhysics.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const DOOR_SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const WHEELIE := preload("res://gameplay/MotorcycleWheelie.gd")
const DESERT_GROUND := preload("res://gameplay/desert_cars/DesertVehicleGround.gd")
const TRAFFIC_RAILS := preload("res://gameplay/traffic/TrafficRails.gd")
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
var route: Curve3D
var _projection_route: Curve3D
var _projection_position := Vector3.ZERO
var _projection_offset := 0.0
var _projection_valid := false
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
# Previous crossings whose physical footprint is still occupied by this vehicle.
var _clearing_junctions: Array[Vector3i] = []
var _held_offset := 0.0
var sensor_clock := 0.0
## Tempo travado por obstáculo que não é sinal/PARE. A fila herda o do carro da frente,
## então fila de semáforo vermelho fica em zero e ninguém "ultrapassa no vermelho".
var stall_time := 0.0
## Tempo sem sair do lugar (fora de fila de sinal). A limpeza da população lê isso.
var stuck_time := 0.0
var _stuck_anchor := 0.0
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
	if damage_prototype_enabled and DAMAGE_PANELS.supports(archetype): visual = DAMAGE_PANELS.create(archetype)
	if visual == null:
		visual = preload("res://runtime/FleetCatalog.gd").create(archetype) if not specification.is_empty() else VISUAL.create(paint_color)
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

func _is_resting() -> bool:
	return not traffic and health > 0 and not controlled and absf(speed) < 0.05 and absf(throttle_input) < 0.01 		and horizontal_velocity.length_squared() < 0.0025 and velocity.length_squared() < 0.0025 and is_on_floor() 		and not has_meta("crash_stun") and not has_meta("awaiting_ground") and not has_meta("mining_released_load") and (manual_wheelie == null or manual_wheelie.pitch == 0)

## Trânsito ambiente longe da câmera roda menos passos: a 60-110 m um a cada 2, além disso um a cada 4,
## escalonados por carro. O passo executado usa o tempo acumulado e o move_and_slide anda a mesma
## distância (a velocidade horizontal é multiplicada só durante a chamada), então o movimento é o
## mesmo, só mais grosso, onde ninguém enxerga. Perto da câmera, controlado, batido, destruído ou
## suspenso pelo streaming: passo normal.
const LOD_NEAR := 60.0
const LOD_FAR := 110.0
const LOD_OFFSCREEN_NEAR := 45.0
const LOD_VIEW_MARGIN := 12.0
static var _lod_camera: Camera3D
static var _lod_camera_frame := -1
static var _lod_player: Node3D
static var _lod_frustum: Array[Plane] = []
static var _lod_frustum_frame := -1
var _lod_skipped := -1
var _lod_pending := 0.0

func _lod_stride() -> int:
	var frame := Engine.get_physics_frames()
	if _lod_camera_frame != frame:
		_lod_camera_frame = frame
		_lod_camera = get_viewport().get_camera_3d()
		_lod_player = get_parent().get("player") as Node3D
	if not is_instance_valid(_lod_camera): return 1
	var distance_squared := _lod_camera.global_position.distance_squared_to(global_position)
	if distance_squared > LOD_FAR*LOD_FAR: return 4
	# Only off-screen ambient cars enter the existing 4-step simulation earlier.
	# Keep a generous border for the car, lights and approaching camera; visible
	# traffic retains its original cadence. Physics sweeps/support remain active.
	if distance_squared > LOD_OFFSCREEN_NEAR*LOD_OFFSCREEN_NEAR and is_instance_valid(_lod_player) and _lod_player.global_position.distance_squared_to(global_position) > LOD_OFFSCREEN_NEAR*LOD_OFFSCREEN_NEAR:
		if _lod_frustum_frame != frame:
			_lod_frustum_frame = frame
			_lod_frustum = _lod_camera.get_frustum()
		var radius := half_length + LOD_VIEW_MARGIN
		for plane in _lod_frustum:
			if plane.distance_to(global_position) > radius: return 4
	return 2 if distance_squared > LOD_NEAR*LOD_NEAR else 1

## 0 = pular este passo; senão, quantos passos do motor o passo executado representa.
func _lod_gate(delta: float) -> float:
	if not traffic or controlled or health <= 0 or not is_on_floor() or has_meta("crash_stun") or has_meta("awaiting_ground"):
		_lod_skipped = -1
		_lod_pending = 0.0
		return 1.0
	var stride := _lod_stride()
	if stride == 1:
		# Catch up elapsed traffic time when returning to the near simulation.
		# Control, impacts and airborne state above deliberately discard it instead.
		var steps := (_lod_pending + delta)/maxf(delta,0.0001)
		_lod_skipped = -1
		_lod_pending = 0.0
		return steps
	if _lod_skipped < 0: _lod_skipped = get_instance_id() % stride
	_lod_pending += delta
	_lod_skipped += 1
	if _lod_skipped < stride: return 0.0
	var steps := _lod_pending/maxf(delta,0.0001)
	_lod_skipped = 0
	_lod_pending = 0.0
	return steps

## Carcaças desaparecem dez segundos após a destruição.
const WRECK_LIFETIME := 10.0
const WRECK_FADE := 2.0
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
const WRECK_SINK_DEPTH := 2.2
var _wreck_sunk := 0.0

func _wreck_expires() -> bool:
	return not controlled

## true quando a carcaça foi removida neste passo.
func _tick_wreck(delta: float) -> bool:
	if _wreck_fade < 0.0:
		if not _wreck_expires(): return false
		_wreck_age += delta
		if _wreck_age < WRECK_LIFETIME: return false
		var world := get_parent()
		var driving: Variant = world.get("driving") if is_instance_valid(world) else null
		if driving != null and driving.get("car") == self and driving.get("occupied") == true: return false
		_begin_wreck_fade()
		return false
	_wreck_fade += delta
	var amount := clampf(_wreck_fade / WRECK_FADE, 0.0, 1.0)
	if WRECK_SINK_ENABLED:
		# Desce sem colisão (desligada em _begin_wreck_fade); o fogo e a fumaça filhos descem junto.
		var sunk := WRECK_SINK_DEPTH * amount * amount
		global_position.y += _wreck_sunk - sunk
		_wreck_sunk = sunk
	else:
		for mesh in _wreck_meshes:
			if is_instance_valid(mesh): mesh.transparency = amount
	if amount >= 1.0:
		queue_free()
		return true
	return false

func _begin_wreck_fade() -> void:
	_wreck_fade = 0.0
	# Já não bloqueia ninguém enquanto some.
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is CollisionObject3D:
			_wreck_collision_state.append({"node": node, "layer": node.collision_layer, "mask": node.collision_mask})
			(node as CollisionObject3D).collision_layer = 0
			(node as CollisionObject3D).collision_mask = 0
		if node is MeshInstance3D: _wreck_meshes.append(node)
		if node is Light3D:
			_wreck_lights.append({"node": node, "visible": node.visible})
			(node as Light3D).visible = false
		for child in node.get_children(): pending.append(child)

func _physics_process(delta: float) -> void:
	var began := STALL_WORK.begin()
	_stall_physics_tick(delta)
	STALL_WORK.finish_slow("vehicle.physics", began, 10000, self)

func _stall_physics_tick(delta: float) -> void:
	# Spans (22/10): quadros com vehicle.physics de 8–11 ms num carro só e nenhum trecho interno nomeado.
	var stage := STALL_WORK.begin()
	if controlled and not external_input and not _traffic_retirement_meshes.is_empty(): fade_traffic_retirement(0)
	if traffic_escape!=null and (controlled or not traffic): traffic_escape.tick(self,delta)
	# Also clean during backoff, player control and resting; no geometry work when empty.
	if not _clearing_junctions.is_empty(): _clear_departed_junctions()
	STALL_WORK.finish_slow("vehicle.pre_tick", stage, 2000, self)
	stage = STALL_WORK.begin()
	var removed := health <= 0.0 and _tick_wreck(delta)
	STALL_WORK.finish_slow("vehicle.wreck_lifetime", stage, 5000, self)
	if removed: return
	stage = STALL_WORK.begin()
	var resting := _is_resting()
	STALL_WORK.finish_slow("vehicle.resting", stage, 5000, self)
	if resting:
		if traffic_rails != null and traffic_rails.active: traffic_rails.wake(self)
		return
	var rail_drive := false
	var rail_wake := false
	if TRAFFIC_RAILS.enabled and traffic_rails == null and traffic and get_meta("ambient_traffic",false):
		traffic_rails = TRAFFIC_RAILS.new()
	stage = STALL_WORK.begin()
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
	if rail_drive:
		var rail_previous := global_position
		stage = STALL_WORK.begin()
		var advanced: bool = traffic_rails.advance(self,delta)
		STALL_WORK.finish_slow("vehicle.rails_advance", stage, 2000, self)
		if advanced:
			var rail_motion := global_position-rail_previous
			rail_motion.y = 0.0
			distance_travelled += rail_motion.length()
			_tick_motion_presentation(delta,rail_motion,horizontal_velocity,-global_basis.z)
			return
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
	if not _handling_frame:
		var traction := .9 if controlled and brake_input and absf(speed)>5 else 9.0
		horizontal_velocity = horizontal_velocity.lerp(forward*speed,1.0-exp(-traction*delta))
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	# floor_snap_length mantém o apoio, inclusive na descida. Empurrar contra o
	# piso já apoiado repetia colisões/deslizamentos do mesmo chão a cada passo.
	# A released mining load can lose the bucket that supported it. Its temporary
	# monitor confirms static ground; cached is_on_floor cannot suppress gravity.
	velocity.y = 0.0 if is_on_floor() and not has_meta("mining_released_load") else velocity.y-20.0*delta
	# Física de rua: atropelamento e mobília derrubável antes de mover (o carro
	# atravessa o que cedeu); batida carro x carro e deslize depois.
	stage = STALL_WORK.begin()
	STREET.vehicle_pre_move(self,delta)
	STALL_WORK.finish_slow("vehicle.street_pre", stage, 5000, self)
	var incoming_velocity := Vector3(velocity.x,0,velocity.z)
	if lod != 1.0:
		velocity.x *= lod
		velocity.z *= lod
	var terrain_supported := false
	# Exact upright-box support on the authored canyon and quarry. The helper verifies
	# the physical floor, including frames whose support was established by snap.
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
	stage = STALL_WORK.begin()
	var motion := global_position-previous
	motion.y = 0
	distance_travelled += motion.length()
	# Contact removes forward speed, instead of accumulating motion into a wall.
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
	stage = STALL_WORK.begin()
	STREET.vehicle_post_move(self,incoming_velocity,delta)
	STALL_WORK.finish_slow("vehicle.street_post", stage, 5000, self)
	if manual_wheelie != null: _tick_motorcycle_wheelie(delta)
	_tick_motion_presentation(delta,motion,incoming_velocity,forward)

func _tick_motion_presentation(delta: float, motion: Vector3, incoming_velocity: Vector3, forward: Vector3) -> void:
	var stage := STALL_WORK.begin()
	if traffic:
		# Heading error becomes tiny once the body tracks its route, even in a
		# sustained bend. Match the wheels to the turn actually applied, including
		# rail movement and collision-rejected turns, using the bicycle relation.
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
	# The body animation uses fixed door/seat anchors. Speed alone left the
	# smoothed horizontal velocity dragging the vehicle out from under them.
	speed = 0.0
	horizontal_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	# StreetPhysics keeps impact momentum outside velocity. Retaining it let a
	# stopped car slide metres away from the fixed boarding anchors at 0 km/h.
	for key in ["crash_slide", "crash_spin", "crash_stun"]:
		if has_meta(key): remove_meta(key)
	if handling != null: handling.reset()

func reset_motorcycle_wheelie() -> void:
	if manual_wheelie == null: return
	manual_wheelie.reset()
	if is_instance_valid(visual): visual.transform = _motorcycle_visual_rest

func _tick_motorcycle_wheelie(delta: float) -> void:
	var eligible := controlled and not traffic and not external_input and not input_locked and not engine_disabled and health > 0 and not has_meta("crash_stun")
	var previous_pitch: float = manual_wheelie.pitch
	if not eligible and previous_pitch == 0: return
	var controls := get_node_or_null("/root/GameInput")
	eligible = eligible and (controls == null or not controls.remapping)
	manual_wheelie.step(delta,eligible and Input.is_action_pressed("motorcycle_wheelie"),eligible,is_on_floor(),speed,throttle_input,brake_input or is_on_wall())
	if manual_wheelie.pitch == previous_pitch: return
	visual.transform = Transform3D(Basis(Vector3.RIGHT,manual_wheelie.pitch),WHEELIE.rear_pivot_offset(manual_wheelie.pitch,_motorcycle_rear_contact))*_motorcycle_visual_rest

func _bind_motorcycle_rider() -> void:
	if not archetype.begins_with("bike_"): return
	_motorcycle_seat = visual.get_meta("motorcycle_seat", _motorcycle_seat)
	# Prepared V1 bikes bake the pilot into sibling meshes. Separate only the
	# authored pilot palette/accessories once, before paint and wheel reparenting.
	for child in visual.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		# A moto agrupada (RedesignedFleet) guarda o piloto numa malha própria marcada pelo bake:
		# as cores viram cor de vértice e a paleta original não aparece mais no material.
		if part.get_meta("motorcycle_rider", false):
			_motorcycle_rider_parts.append(part)
			part.visible = traffic
			continue
		# Idem para as manoplas: uma malha por lado, com o lado em metadado; o wheel_center
		# que elas trazem as leva ao pivô de direção logo abaixo, em _ready.
		if part.has_meta("motorcycle_grip"):
			_motorcycle_grips[str(part.get_meta("motorcycle_grip"))] = part
			continue
		var material: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
		if not material is StandardMaterial3D: continue
		var color: String = material.albedo_color.to_html(false)
		var center: Vector3 = (part.transform * part.mesh.get_aabb()).get_center()
		if color == "161b20" and part.get_meta("wheel_spins", true) == false and center.y > .85 and absf(center.x) > .25:
			_motorcycle_grips["Left" if center.x < 0 else "Right"] = part
		if part.has_meta("wheel_center"): continue
		var body := color in ["41454d", "253043", "181b20", "cf5058", "101d29"]
		var helmet_z := -.23 if archetype == "bike_sport" else .01
		var helmet_stud := color == "b5c4ce" and absf(center.x) < .14 and center.y > 1.3 and absf(center.z - helmet_z) < .03
		var stripe_z := .212 if archetype == "bike_sport" else .332
		var jacket_stripe := color in ["d4dce0", "b5c4ce", "f1ede5"] and absf(center.x) < .02 and center.y > .95 and absf(center.z - stripe_z) < .02
		if not body and not helmet_stud and not jacket_stripe: continue
		_motorcycle_rider_parts.append(part)
		part.visible = traffic
		if color == "253043" and absf(center.x) < .01:
			_motorcycle_seat = center - Vector3(0, .95, 0)
	# Keep the authored chassis/grips, replacing only the obsolete baked person.
	# Offline fleet baking still needs the original authored geometry.
	if not is_inside_tree(): return
	for part in _motorcycle_rider_parts:
		part.get_parent().remove_child(part)
		part.queue_free()
	_motorcycle_rider_parts.clear()
	# Appearance must not consume traffic/gameplay RNG (paint, routes, encounters).
	var identity := posmod(vehicle_id.hash() if not vehicle_id.is_empty() else str(get_instance_id()).hash(),100000)
	var rider := preload("res://assets/civilians/TrafficMotorcyclist.gd").create(self,identity)
	visual.add_child(rider)
	rider.visible = traffic
	_motorcycle_rider_parts.append(rider)

func motorcycle_handholds() -> Dictionary:
	var holds := {}
	for side in _motorcycle_grips:
		var part: MeshInstance3D = _motorcycle_grips[side]
		if not is_instance_valid(part): continue
		# The mesh is already a child of the steering pivot. Follow its actual
		# presentation, including steer and vehicle yaw, without another scene scan.
		var sign_side := -1.0 if side == "Left" else 1.0
		var palm_basis: Basis = part.get_parent().global_basis.orthonormalized() * Basis(Vector3.BACK, -sign_side * PI * .5)
		holds[side] = Transform3D(palm_basis, part.to_global(part.mesh.get_aabb().get_center()))
	if not holds.is_empty():
		if archetype == "bike_sport":
			holds["lean_multiplier"] = 1.8
			holds["lean_min"] = 0.5
		elif archetype == "bike_urban":
			holds["lean_multiplier"] = 0.5
			holds["lean_min"] = 0.1
		else: # cruiser or default
			holds["lean_multiplier"] = 0.5
			holds["lean_min"] = 0.2
	return holds

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
const TRAFFIC_JAM_SECONDS := 2.5

func _traffic_jam_partner() -> Object:
	if not is_instance_valid(blocker) or not blocker is CharacterBody3D: return null
	if blocker.get("traffic") != true or blocker.get("blocked") != true: return null
	# Fila na mesma direção não é impasse: quem está atrás só espera.
	var mine := -global_basis.z
	var theirs: Vector3 = -(blocker as Node3D).global_basis.z
	if mine.dot(theirs) > 0.85: return null
	return blocker

## Obstáculo que o trânsito pode empurrar depois de esperar: nunca gente viva, o
## carro do jogador ou outro carro de trânsito (esse tem desempate próprio). Pessoa
## caída só depois de 8 s. Se for parede de verdade, a física segura o carro.
func _pushable_obstacle(target) -> bool:
	if not is_instance_valid(target) or not target is Node: return false
	if target is CharacterBody3D:
		if target.get("traffic") == true: return false
		if target.has_method("driver_seat_anchor"):
			return target.get("controlled") != true and target.get("external_input") != true
		var down: bool = target.get("dead") == true or (target as Node).has_meta("street_down")
		return down and blocked_time > 8.0
	return true

## Distância ao longo da rota até `offset` (negativa depois de passar; rota fechada dá a volta).
func _route_ahead(offset: float, length: float, open: bool) -> float:
	if open: return offset-route_distance
	return fposmod(offset-route_distance+length*.5,length)-length*.5

## Physical bodies that can keep an expired junction lease occupied.
func junction_collision_bodies() -> Array[CharacterBody3D]:
	return [self]

func _release_current_junction() -> void:
	if _held_junction != null: JUNCTIONS.release(_held_junction,get_instance_id())
	_held_junction = null

# Explicit resets and scene exit release every token, including the trailing hull.
func _release_junction() -> void:
	_release_current_junction()
	for key in _clearing_junctions: JUNCTIONS.release(key, get_instance_id())
	_clearing_junctions.clear()

func _retain_current_junction() -> void:
	if _held_junction == null: return
	if JUNCTIONS.has_reservation(_held_junction, get_instance_id()) and JUNCTIONS.occupies(_held_junction, get_instance_id()):
		if not _clearing_junctions.has(_held_junction): _clearing_junctions.append(_held_junction)
	else:
		JUNCTIONS.release(_held_junction, get_instance_id())
	_held_junction = null

func _clear_departed_junctions() -> void:
	for index in range(_clearing_junctions.size() - 1, -1, -1):
		var key := _clearing_junctions[index]
		if JUNCTIONS.has_reservation(key, get_instance_id()) and JUNCTIONS.occupies(key, get_instance_id()): continue
		JUNCTIONS.release(key, get_instance_id())
		_clearing_junctions.remove_at(index)

## Cruzamento à frente (TrafficJunctions): true = parar na faixa. `junction_gap` fica
## com a distância da frente do carro até a faixa, para frear de forma progressiva.
func _junction_gate(length: float, open: bool) -> bool:
	junction_gap = INF
	if route != _junction_route:
		_retain_current_junction()
		_junction_route = route
		_junction_list = JUNCTIONS.along(route)
	if _held_junction != null:
		if not JUNCTIONS.has_reservation(_held_junction, get_instance_id()):
			_held_junction = null
		elif _route_ahead(_held_offset,length,open) < -JUNCTIONS.EXIT and not JUNCTIONS.occupies(_held_junction, get_instance_id()):
			_release_current_junction()
	for junction in _junction_list:
		var offset := float(junction.offset)
		var ahead := _route_ahead(offset,length,open)
		if ahead <= -(JUNCTIONS.EXIT + half_length) or ahead > float(junction.get("approach_distance",JUNCTIONS.APPROACH)): continue
		# A previous occupied crossing must not replace the newer approach token.
		if _clearing_junctions.has(junction.key): continue
		if _held_junction == junction.key:
			if ahead <= 0.0: continue
			return false
		var gap: float
		if junction.has("stop_offset"):
			gap = _route_ahead(float(junction.stop_offset),length,open)-half_length
		else:
			gap = ahead-half_length-JUNCTIONS.stop_line(junction.key)
		# Use the arrival arm resolved with its stop line. The curve tangent
		# near the centre can already face the cross street during a turn.
		var heading: Vector3 = junction.get("heading",Vector3.ZERO)
		if heading.length_squared()<.0001:
			var before := route.sample_baked(offset-12.0 if open else fposmod(offset-12.0,length),true)
			var at := route.sample_baked(offset-8.0 if open else fposmod(offset-8.0,length),true)
			heading = at-before
		# Não bloquear o cruzamento: com a saída ocupada por carro parado, quem entra
		# fica no miolo e trava o eixo cruzado; era o nó que começava os engarrafamentos.
		if gap > -1.5 and _sense_tick: _exit_blocked = _exit_occupied(offset,length,open)
		if gap > -1.5 and _exit_blocked:
			_exit_wait += 1.0/Engine.physics_ticks_per_second
			junction_gap = gap
			return true
		_exit_wait = 0.0
		if JUNCTIONS.request(junction.key,get_instance_id(),heading,gap,absf(speed)):
			_retain_current_junction()
			_held_junction = junction.key
			_held_offset = offset
			return false
		junction_gap = gap
		return true
	return false

func _exit_tree() -> void:
	_release_junction()

func _invalidate_route_projection() -> void:
	_projection_valid = false

## Stopped cars reuse only the geometric projection. Decisions and sensors still
## run each tick; any exact position change or edited curve requires a fresh scan.
func _traffic_route_offset(point: Vector3) -> float:
	if route != _projection_route:
		if _projection_route != null:
			_projection_route.changed.disconnect(_invalidate_route_projection)
		_projection_route = route
		_projection_route.changed.connect(_invalidate_route_projection)
		_projection_valid = false
	if not _projection_valid or point != _projection_position:
		_projection_offset = route.get_closest_offset(point)
		_projection_position = point
		_projection_valid = true
	return _projection_offset

func _drive_traffic(delta: float) -> void:
	if route == null: return
	if traffic_escape==null: traffic_escape=preload("res://gameplay/TrafficEscape.gd").new()
	traffic_escape.tick(self,delta)
	if is_queued_for_deletion() or traffic_escape.retiring: return
	if backoff_time > 0.0:
		backoff_time -= delta
		var rear_gap := .8 if traffic_escape!=null and not traffic_escape.active and traffic_escape.wait>0 else 3.0
		speed = move_toward(speed,-1.5 if traffic_rear_clear(rear_gap) else 0.0,8.0*delta)
		return
	sensor_clock -= delta
	_sense_tick = sensor_clock <= 0
	if _sense_tick:
		sensor_clock = 0.1
		blocked = obstacle_ahead()
		if unjam_time > 0.0 and blocked and blocker == get_meta("unjam_partner",null): blocked = false
		if bypass_side != 0.0 and blocked and _body_speed(blocker) < 0.6 and _in_home_lane(blocker): blocked = false
	unjam_time = maxf(0.0,unjam_time-delta)
	bypass_retry = maxf(0.0,bypass_retry-delta)
	blocked_time = blocked_time+delta if blocked else 0.0
	stall_time = _stall_estimate()
	# Sem progresso fora de fila de sinal: a limpeza tira o carro quando ninguém vê.
	# Zera só com avanço real na rota; empurrar carcaça centímetro a centímetro não conta.
	if absf(route_distance-_stuck_anchor) > 8.0:
		stuck_time = 0.0
		_stuck_anchor = route_distance
	elif stall_time > 0.0 or unjam_time > 0.0 or bypass_side != 0.0: stuck_time += delta
	if bypass_side != 0.0 and _sense_tick: _update_bypass()
	if blocked_time > TRAFFIC_JAM_SECONDS and not traffic_escape.active:
		var partner := _traffic_jam_partner()
		if partner != null:
			blocked_time = 0.0
			# Quem está desviando pela contramão é o intruso: recua e deixa passar.
			var i_yield: bool = bypass_side < 0.0 or (partner.get("bypass_side") == 0.0 and get_instance_id() > partner.get_instance_id())
			if not i_yield:
				unjam_time = 3.0
				set_meta("unjam_partner",partner)
			else:
				backoff_time = 1.2
		elif bypass_retry <= 0.0 and bypass_side == 0.0 and stall_time > BYPASS_AFTER_SECONDS and _try_bypass():
			blocked_time = 0.0
		elif _pushable_obstacle(blocker) and (not _is_vehicle(blocker) or stall_time > BYPASS_AFTER_SECONDS*3.0):
			# Adereço derrubado, lixeira, carcaça sem motorista: o trânsito empurrava
			# nada e esperava para sempre. Segue devagar; a física de rua derruba o objeto.
			blocked_time = 0.0
			unjam_time = 3.0
			set_meta("unjam_partner",blocker)
	# Progress uses actual position, so a collision cannot advance the car's route.
	var previous_distance := route_distance
	if not _traffic_rail_drive: route_distance = _traffic_route_offset(global_position)
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	if not open and previous_distance > length-5 and route_distance < 5: route_laps += 1
	junction_wait = _junction_gate(length,open)
	# Panic may disregard the signal; still update physical junction retention.
	if traffic_escape.active: junction_wait=false
	var near_point := route.sample_baked(minf(route_distance+2,length) if open else fposmod(route_distance+2,length),true)
	var far_point := route.sample_baked(minf(route_distance+5,length) if open else fposmod(route_distance+5,length),true)
	var bend := absf((near_point-global_position).normalized().signed_angle_to((far_point-near_point).normalized(),Vector3.UP))
	var desired_speed := lerpf(5.5,2.2,clampf(bend/1.0,0,1))
	if traffic_escape.active: desired_speed=lerpf(9.0,4.5,clampf(bend,0,1))
	if unjam_time > 0.0: desired_speed = minf(desired_speed,2.5)
	if bypass_side != 0.0: desired_speed = minf(desired_speed,BYPASS_SPEED)
	if open: desired_speed = minf(desired_speed,maxf(0,(length-route_distance-1)*1.5))
	# Sinal fechado: freia progressivamente até a faixa, em vez de travar a 12 m/s² a
	# qualquer distância (o carro parava longe do cruzamento ou em cima da faixa).
	if junction_wait: desired_speed = minf(desired_speed,sqrt(2.0*3.5*maxf(0.0,junction_gap-.4)))
	var target_speed := 0.0 if blocked else desired_speed * preload("res://data/catalogs/VehicleSpeedBalance.gd").FACTOR
	var rate := 12.0 if blocked else (7.0 if target_speed < speed else 2.5)
	speed = move_toward(speed,target_speed,rate*delta)
	var lookahead := lerpf(3.5,1.7,clampf(bend,0,1))
	var target := route.sample_baked(minf(route_distance+lookahead,length) if open else fposmod(route_distance+lookahead,length),true)
	# Desvio: persegue a mesma rota deslocada para o lado, entrando e saindo aos poucos.
	var blend_goal := 0.0 if _merging_back or bypass_side == 0.0 else 1.0
	bypass_blend = move_toward(bypass_blend,blend_goal,delta/1.2)
	if _merging_back and bypass_blend <= 0.0: _end_bypass()
	if bypass_blend > 0.0: target += _route_right(route_distance+lookahead,length,open)*_bypass_shift()*bypass_blend
	var direction := target-global_position
	direction.y = 0
	var desired := atan2(-direction.x,-direction.z)
	var next_yaw := rotate_toward(rotation.y,desired,delta*(2.7 if traffic_escape.active else 1.7))
	steering = clampf(angle_difference(rotation.y,desired),-0.48,0.48)
	# Carro parado não esterça no lugar (e poupa a consulta de colisão por passo).
	if not _traffic_rail_drive and absf(speed) > 0.2 and next_yaw != rotation.y and can_rotate(next_yaw): rotation.y = next_yaw

## Desvio de obstáculo parado (viatura na faixa, carcaça, fila que não anda): antes o
## trânsito só esperava, e um carro parado virava engarrafamento sem fim (2026-09-25).
## Depois de BYPASS_AFTER_SECONDS travado, o carro procura a contramão (depois o
## acostamento) livre por uns 25 m, contorna devagar e volta quando a própria faixa
## está livre ao lado e à frente.
const BYPASS_AFTER_SECONDS := 3.5
const BYPASS_SPEED := 4.0
const BYPASS_MAX_DISTANCE := 45.0
const BYPASS_PROBES := [0.0, 5.0, 10.0, 16.0, 22.0]
const MERGE_PROBES := [0.0, 4.0, 8.0]
## Waiting time is diagnostic; expiry never authorises entering a blocked exit.
var _exit_wait := 0.0

func traffic_rear_clear(distance := 3.0) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = 7
	query.exclude = [get_rid()]
	query.transform = Transform3D(global_basis,global_position+Vector3.UP*shape.position.y)
	query.motion = global_basis.z*distance
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return false
	return space.cast_motion(query)[0]>=1.0

func _is_vehicle(target) -> bool:
	return is_instance_valid(target) and target is Node and (target as Node).has_method("driver_seat_anchor")

func _body_speed(target) -> float:
	if not is_instance_valid(target): return 0.0
	if _is_vehicle(target): return absf(float(target.get("speed")))
	if target is CharacterBody3D: return (target as CharacterBody3D).velocity.length()
	if target is RigidBody3D: return (target as RigidBody3D).linear_velocity.length()
	return 0.0

func _stall_estimate() -> float:
	if junction_wait or not blocked or not is_instance_valid(blocker): return 0.0
	if blocker.has_method("is_servicing_stop") and blocker.is_servicing_stop(): return blocked_time
	if blocker is Node3D and blocker.get("traffic") == true:
		var same_way := (-global_basis.z).dot(-(blocker as Node3D).global_basis.z) > 0.85
		if same_way:
			# Fila: vale o travamento de quem está na frente. Na fila do sinal ele é zero.
			if blocker.get("junction_wait") == true or blocker.get("blocked") != true: return 0.0
			return float(blocker.get("stall_time"))
	if _body_speed(blocker) > 0.6: return 0.0
	return blocked_time

func _route_point(offset: float, length: float, open: bool) -> Vector3:
	return route.sample_baked(clampf(offset,0.0,length) if open else fposmod(offset,length),true)

func _route_right(offset: float, length: float, open: bool) -> Vector3:
	var tangent := _route_point(offset+1.0,length,open)-_route_point(offset-1.0,length,open)
	tangent.y = 0
	if tangent.length_squared() < .0001: return global_basis.x
	return tangent.normalized().cross(Vector3.UP)

## Deslocamento lateral do desvio: faixa contrária inteira à esquerda; à direita só o
## que cabe até o meio-fio.
func _bypass_shift() -> float:
	if not is_nan(bypass_lane_shift): return bypass_lane_shift
	return -3.4 if bypass_side < 0.0 else 2.6

## Casco livre na rota deslocada `shift` metros para a direita, a `probes` metros à frente.
func _lane_clear(shift: float, probes: Array, mask := 7) -> bool:
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = mask
	query.exclude = [get_rid()]
	for distance in probes:
		var at := route_distance+float(distance)
		var right := _route_right(at,length,open)
		var point := _route_point(at,length,open)+right*shift
		query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),point+Vector3.UP*shape.position.y)
		if not space.intersect_shape(query,1).is_empty(): return false
	return true

func _try_bypass() -> bool:
	bypass_retry = 1.0
	if route == null or str(get_meta("traffic_yield_state","")) != "": return false
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	# Nunca desvia para dentro de um cruzamento: lá a contramão é a via cruzada.
	for junction in _junction_list:
		var ahead := _route_ahead(float(junction.offset),length,open)
		if ahead > -JUNCTIONS.EXIT and ahead < 14.0: return false
	# On a four-lane avenue, use only the adjacent lane travelling in the same
	# direction. Look behind as well as ahead before merging around a stopped bus.
	var nearest := INF
	var profile := {}
	for section in route.get_meta("lane_sections",[]):
		var a: Vector3 = section.a
		var b: Vector3 = section.b
		if a.direction_to(b).dot(-global_basis.z)<.7: continue
		var separation := Geometry3D.get_closest_point_to_segment(global_position,a,b).distance_squared_to(global_position)
		if separation<nearest: nearest=separation; profile=section
	if int(profile.get("lanes",1))==2:
		bypass_side = 1.0 if int(route.get_meta("lane_index",0))==0 else -1.0
		bypass_lane_shift = bypass_side*float(profile.width)*.25
		if _lane_clear(bypass_lane_shift,[-8.0,-4.0,0.0,5.0,10.0,16.0,22.0]):
			bypass_start=route_distance; _merging_back=false
			return true
		bypass_side=0; bypass_lane_shift=NAN
		return false
	for side in [-1.0, 1.0]:
		bypass_side = side
		if _lane_clear(_bypass_shift(),BYPASS_PROBES):
			bypass_start = route_distance
			_merging_back = false
			return true
	bypass_side = 0.0
	return false

## Corpo parado na faixa original (o que estamos contornando): o sensor frontal o
## enxerga em diagonal durante o desvio e não deve frear o carro por isso.
func _in_home_lane(target) -> bool:
	if not target is Node3D: return false
	var point: Vector3 = (target as Node3D).global_position
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var offset := route.get_closest_offset(point)
	return absf((point-_route_point(offset,length,open)).dot(_route_right(offset,length,open))) < 1.7

func _update_bypass() -> void:
	if _merging_back: return
	var length := route.get_baked_length()
	var open: bool = route.get_meta("traffic_open",false)
	var travelled := route_distance-bypass_start if open else fposmod(route_distance-bypass_start,length)
	# Contramão fechada por quem vem de frente há muito tempo: desiste e volta.
	if travelled > 4.0 and _lane_clear(0.0,MERGE_PROBES): _merging_back = true
	elif travelled > BYPASS_MAX_DISTANCE or blocked_time > 6.0: _merging_back = true

func _end_bypass() -> void:
	bypass_lane_shift = NAN
	bypass_side = 0.0
	bypass_blend = 0.0
	_merging_back = false
	bypass_retry = 2.0

## Carro parado logo depois do cruzamento, na nossa saída.
func _exit_occupied(offset: float, length: float, open: bool) -> bool:
	var at := offset+JUNCTIONS.EXIT+half_length+1.0
	if open and at > length: return false
	var right := _route_right(at,length,open)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rotation_shape
	query.collision_mask = 4
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis(Vector3.UP,atan2(-right.z,right.x)),_route_point(at,length,open)+Vector3.UP*shape.position.y)
	for hit in get_world_3d().direct_space_state.intersect_shape(query,4):
		if _is_vehicle(hit.collider) and _body_speed(hit.collider) < 1.0: return true
	return false

func obstacle_ahead() -> bool:
	if traffic_escape!=null and traffic_escape.active: return traffic_escape.obstacle_ahead(self)
	var length := 2.2+speed*speed/20.0
	sensor_shape.size.z = length
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sensor_shape
	query.transform = Transform3D(global_basis,global_position-global_basis.z*(half_length+length/2)+Vector3.UP*0.8)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	# Estrutura de rampa marcada `vehicle_ramp_structure` (túnel do canal): numa
	# rampa de 12,5 % a caixa horizontal a 0,8 m entra no próprio piso e o carro
	# freava sem nada à frente. Carros, pessoas e o resto do mundo continuam valendo.
	blocker = null
	for hit in get_world_3d().direct_space_state.intersect_shape(query,4):
		if is_instance_valid(hit.collider) and hit.collider.has_meta("vehicle_ramp_structure"): continue
		if traffic_escape!=null and traffic_escape.active and hit.collider is CharacterBody3D and not _is_vehicle(hit.collider) and not PROTECTION.is_protected(hit.collider): continue
		blocker = hit.collider
		break
	return blocker != null

func fade_traffic_retirement(alpha: float) -> void:
	if alpha<=0:
		for record in _traffic_retirement_meshes:
			if is_instance_valid(record.node): record.node.transparency=record.original
		_traffic_retirement_meshes.clear()
		return
	if _traffic_retirement_meshes.is_empty() and is_instance_valid(visual):
		for mesh in visual.find_children("*","MeshInstance3D",true,false):
			_traffic_retirement_meshes.append({"node":mesh,"original":mesh.transparency})
	for record in _traffic_retirement_meshes:
		if is_instance_valid(record.node): record.node.transparency=maxf(record.original,alpha)

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
func boarding_class() -> String:
	if archetype.begins_with("bike_") or archetype in ["port_forklift", "beach_buggy", "dune_buggy"]: return "open"
	if archetype == "route_city": return "bus"
	# A tabela de portas manda quando tem opinião: vans e picapes têm casco alto sem serem
	# caminhões, e a classe decide o degrau, o banco e o ritmo da entrada.
	var listed: Dictionary = DOOR_SPECS.row(archetype)
	if listed.has("class"): return str(listed["class"])
	if body_height >= 2.35: return "truck"
	if body_height >= 1.75: return "tall"
	return "car"

## Lados por onde se entra ao volante. Ônibus só pela porta de serviço da direita.
func boarding_sides() -> Array:
	return [1] if boarding_class() == "bus" else [-1, 1]

## Altura do piso da cabine sobre o chão, que o corpo precisa vencer para entrar.
func boarding_step_height() -> float:
	match boarding_class():
		"truck": return clampf(body_height * .36, .85, 1.15)
		"bus": return .42
		"tall": return .32
	return 0.0

## Centro do vão da porta (eixo Z do veículo). Vem da tabela por modelo: antes vinha de uma
## fração do comprimento do casco, e em van, ambulância e caminhão ficava no meio da carga.
func _cab_z() -> float:
	var row := DOOR_SPECS.row(archetype)
	if not row.is_empty() and boarding_class() in ["car", "tall", "truck"] and is_instance_valid(visual):
		return (float(row.zf) + float(row.zr)) * .5 * visual.scale.z
	match boarding_class():
		"bus": return -(half_length - .8)
		"truck": return -(half_length - 1.3)
	return -clampf(half_length * .18, .30, .62)

## Banco no meio do vão, um palmo à frente do centro. Tabela por modelo (VehicleDoorSpecs).
func _door_seat_z() -> float:
	var row := DOOR_SPECS.row(archetype)
	if row.is_empty() or not is_instance_valid(visual): return _cab_z() + .15
	return ((float(row.zf) + float(row.zr)) * .5 - .06) * visual.scale.z

func driver_door_anchor(side: int) -> Vector3:
	return to_global(Vector3(float(side) * (half_width + .54), .04, _cab_z()))

## O piloto aparece sentado ao volante (carro, caminhão, ônibus, buggy, empilhadeira).
## Moto usa a pose de guidão; blindado tem escotilha e piloto próprios. Ver VehicleInterior.
func shows_seated_driver() -> bool:
	return preload("res://gameplay/VehicleInterior.gd").shows_driver(self)

## Quanto o corpo desce do porte de pé até o banco desta cabine (m).
func seated_drop() -> float:
	return preload("res://gameplay/VehicleInterior.gd").seated_drop(self)

func driver_seat_anchor() -> Vector3:
	if archetype.begins_with("bike_"): return visual.to_global(_motorcycle_seat)
	# Buggy e empilhadeira não têm porta nem linha no VehicleDoorSpecs: o banco vem do interior.
	var open_seat: Vector3 = preload("res://gameplay/VehicleInterior.gd").open_seat_local(self)
	if open_seat.is_finite(): return to_global(open_seat)
	if boarding_class() == "bus":
		return to_global(Vector3(-minf(.55, half_width * .4), .08 + boarding_step_height(), _cab_z() - .15))
	if boarding_class() in ["truck", "tall"]:
		return to_global(Vector3(-minf(.45, half_width * .3), .08 + boarding_step_height(), _door_seat_z()))
	var seat_z := _door_seat_z() if DOOR_SPECS.has_row(archetype) else -clampf(half_length * .16, .26, .55)
	return to_global(Vector3(-minf(.28, half_width * .24), .08, seat_z))

## Geometria de embarque deste lado (ponto de espera fora do arco da folha, portão no
## vão, ponto de agarrar, ponta da folha aberta), em coordenadas do veículo. Vazio para
## veículo sem porta (moto, buggy, empilhadeira) e para o ônibus.
func door_layout(side: int) -> Dictionary:
	_ensure_door_presentation()
	if not is_instance_valid(door_presentation) or not door_presentation.ready_for_boarding: return {}
	return door_presentation.layouts.get(side, {})

func animate_driver_door(side: int, opened: bool, duration := .28) -> void:
	_ensure_door_presentation()
	if is_instance_valid(door_presentation):
		door_presentation.set_open(side, opened, duration)
		# Som da porta no mesmo instante da folha (abrir ao chegar, bater ao fechar).
		FIREFLY.door(self, side, opened)

func _refresh_tuning_appearance() -> void:
	# Restore paths may assign factory paint/identity after installing saved parts.
	# Reapply the local finish without rebuilding meshes, charging or touching state.
	if has_meta("tuning_appearance"):
		get_meta("tuning_appearance").apply(get_meta("desert_parts",{}),paint_color)
		if is_instance_valid(damage_look): damage_look.refresh_paint_finish()

func _ensure_door_presentation() -> void:
	if boarding_class() in ["open", "bus"]: return
	var began := STALL_WORK.begin()
	if not is_instance_valid(door_presentation):
		door_presentation = preload("res://gameplay/VehicleDoorPresentation.gd").new()
		visual.add_child(door_presentation)
		door_presentation.configure(self)
	else:
		door_presentation.finish_now()
	STALL_WORK.finish_slow("vehicle.doors.prepare", began, 1000, self)

## Termina agora a porta que estiver sendo preparada. Deve rodar ANTES de qualquer módulo
## trocar as malhas do casco (interior, teto translúcido): o recorte parte das originais.
func finish_doors() -> void:
	_ensure_door_presentation()

## Prepara a porta aos poucos, antes de alguém precisar dela (o recorte custa dezenas de ms de
## uma vez). Chamado quadro a quadro enquanto o jogador está perto; true quando pronta.
func warm_doors(budget_usec := 2500) -> bool:
	if boarding_class() in ["open", "bus"]: return true
	if not is_instance_valid(door_presentation):
		door_presentation = preload("res://gameplay/VehicleDoorPresentation.gd").new()
		visual.add_child(door_presentation)
		door_presentation.configure(self, true)
	return door_presentation.advance(budget_usec)

func camera_lookahead() -> Vector3:
	return -global_basis.z*clampf(speed*0.4,-2.0,6.0)

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
	var inward := Vector3(local_normal.x,0,local_normal.z).normalized()
	var visual_amount := amount*damage_resistance
	if damage_prototype_enabled and closing_speed>=0:
		# HP remains balanced for long chases; the sheet metal responds to actual closing speed.
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
	# Restore geometry first, then hide absent panels. No debris or collision event is replayed.
	if is_instance_valid(breakaway_parts): breakaway_parts.repair()
	if is_instance_valid(body_dents): body_dents.restore_records(records)
	if is_instance_valid(breakaway_parts): breakaway_parts.restore_state(panel_state)
	restore_glass(broken_glass)

func receive_damage(amount: float, _source: Node = null) -> void:
	if not is_finite(amount) or amount <= 0 or health <= 0 or PROTECTION.is_protected(self): return
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
	# The street solver has already installed the flattened, load-bearing hull.
	if health <= 0 or not has_meta("heavy_crush_ratio") or PROTECTION.is_protected(self): return false
	if is_instance_valid(source): set_meta("heavy_crush_source",weakref(source))
	# Crushing is terminal even for a car with damage resistance.
	receive_damage((health+1.0)/maxf(damage_resistance,.05),source)
	# Production/dispatch cars explode from their destroyed listener. Vehicles
	# built elsewhere use this fallback; Gameplay deduplicates both paths.
	var world := get_parent()
	var gameplay: Variant = world.get("gameplay") if is_instance_valid(world) else null
	if is_instance_valid(gameplay) and not get_meta("heavy_crush_exploded",false):
		gameplay.explode(global_position+Vector3.UP*.4,5.0,35.0,self,false)
	return true

func restore_health(saved_health: float) -> void:
	# Loading damage must not apply armor again and silently heal the vehicle.
	if not is_finite(saved_health): return
	health = clampf(saved_health, 0.0, max_health)
	if is_instance_valid(damage_look):
		if health <= 0.0: damage_look.wreck()
		else: damage_look.refresh()

func repair() -> void:
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

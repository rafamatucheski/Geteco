extends Node
## Two bounded rear-wheel emitters and one bounded, surface-aligned mark mesh.

const SKID_BUDGET := preload("res://gameplay/vehicle_effects/SkidmarkBudget.gd")
const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
const SURFACE := preload("res://gameplay/vehicle_effects/VehicleSurfaceProbe.gd")
const ENGINE_PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const ROAD_AUDIO := preload("res://audio/VehicleRoadAudio.gd")
const STREET_PHYSICS := preload("res://gameplay/street_physics/StreetPhysics.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Imported resources are held while scripts load, before playable physics.
const SKID_SOURCES := {
	"street": preload("res://audio/acoustic/skid_street.wav"),
	"sport": preload("res://audio/acoustic/skid_sport.wav"),
	"heavy": preload("res://audio/acoustic/skid_heavy.wav"),
	"muscle": preload("res://audio/acoustic/skid_muscle.wav"),
	"monaliza": preload("res://audio/acoustic/skid_monaliza.wav"),
}
static var _skid_streams: Dictionary = {}

static func prewarm_skid_audio() -> void:
	for kind in SKID_SOURCES:
		if _skid_streams.has(kind): continue
		var stream := SKID_SOURCES[kind].duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8)
		_skid_streams[kind] = stream
# Voz de derrapagem, em dB relativos ao motor (camada do motor: -20 dB parado, ~-12 em cruzeiro, ~-5 a fundo):
#  - drift pleno: -8 dB, no nível do motor em cruzeiro (é o som principal da cena quando acontece);
#  - início do drift: -24 dB, 12 dB abaixo do motor, para a entrada não estalar;
#  - freio de serviço travando: -13 dB; freio de mão: -17 dB (era -10, "ainda muito alto"), curto e de fundo.
const SKID_DRIFT_MIN_SPEED := 6.0
const SKID_SLIP_ON := .08
const SKID_SLIP_FULL := .30
const SKID_DRIFT_DB := Vector2(-24.0, -8.0)
const SKID_SERVICE_BRAKE_DB := Vector2(-26.0, -13.0)
const SKID_HANDBRAKE_DB := Vector2(-26.0, -17.0)
const MAX_MARK_SEGMENTS := 320
const MARK_LIFETIME_MSEC := 22000
# Sulco em chÃ£o macio fica mais tempo que a borracha do asfalto: Ã© o rastro que o
# carro deixa na grama/terra mesmo andando reto, sem derrapar.
const RUT_LIFETIME_MSEC := 30000
const SOFT_KINDS := ["grass","dirt","snow","sand"]
const PROBE_INTERVAL := .05
const REDRAW_INTERVAL := .10

var vehicle: CharacterBody3D
var emitters: Array[GPUParticles3D] = []
var marks: Array[Dictionary] = []
var last_contacts: Array[Dictionary] = [{},{}]
var last_modes: Array[String] = ["",""]
var mark_mesh: MeshInstance3D
var geometry := ArrayMesh.new()
var skid_audio: AudioStreamPlayer3D
var _car_pitch := 1.0
var road_mixer: Node
var _probe_clock := 0.0
var _mark_timer: Timer
var _idle := false
var _burnout := 0.0
var _burnout_smoke: Array[bool] = [false, false]
static var _burnout_fade: GradientTexture1D
static var _burnout_growth: CurveTexture

func configure(car: CharacterBody3D) -> void:
	vehicle = car

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func _process(_delta: float) -> void:
	# Exiting/streaming can put a stationary car to sleep before its next tire
	# tick. This guard runs only during a held burnout, never for parked traffic.
	if not is_instance_valid(vehicle) or not vehicle.is_physics_processing() or not vehicle.is_visible_in_tree() or vehicle.burnout_strength() <= 0.0:
		_stop_emitters()

func _exit_tree() -> void:
	if SKID_BUDGET.enabled: SKID_BUDGET.release(self)
	_stop_emitters()
	if is_instance_valid(skid_audio): skid_audio.stop()
	geometry.clear_surfaces()

func physics_tick(delta: float, active: bool) -> void:
	if not active:
		# Parar emissores e zerar contatos uma vez ao ficar inativo, nÃ£o a cada passo.
		if not _idle:
			_stop_emitters()
			last_contacts = [{},{}]
			_idle = true
		return
	_idle = false
	# Contact probes are budgeted at 20 Hz, but the end of a drag wheel lock
	# must release its audio on the same physics step as restored rolling grip.
	if vehicle.has_meta("drag_service_brake_slip") and float(vehicle.get_meta("drag_service_brake_slip")) <= .15 and is_instance_valid(skid_audio) and skid_audio.playing:
		var wet := last_contacts.any(func(contact): return not contact.is_empty() and bool(contact.get("wet",false)))
		var lateral := absf(vehicle.horizontal_velocity.dot(vehicle.global_basis.x))
		if lateral <= (3.125 if wet else 5.625) and vehicle.burnout_strength() <= 0.0: skid_audio.stop()
	_probe_clock -= delta
	if _probe_clock > 0:
		return
	_probe_clock = PROBE_INTERVAL
	var contacts := _rear_contacts()
	var motion := Vector3(vehicle.horizontal_velocity.x,0,vehicle.horizontal_velocity.z)
	var road_speed := motion.length()
	var lateral_speed := absf(motion.dot(vehicle.global_basis.x))
	_burnout = vehicle.burnout_strength()
	set_process(_burnout > 0.0)
	var tire_speed := maxf(road_speed, _burnout*14.0)
	var any_wet := false
	for contact in contacts:
		if not contact.is_empty() and bool(contact.wet): any_wet = true
	var skid_threshold := 3.125 if any_wet else 5.625
	var service_brake: bool = vehicle.brake_input or (vehicle.throttle_input * vehicle.speed < -.1)
	var braking_slip: bool = vehicle.controlled and service_brake and road_speed > 3.75
	if vehicle.has_meta("drag_service_brake_slip"):
		braking_slip = float(vehicle.get_meta("drag_service_brake_slip"))>.15 and road_speed>8.0
	var sliding: bool = _burnout > 0.0 or lateral_speed > skid_threshold or braking_slip
	# Só a voz: o limiar absoluto de 5,6 m/s de velocidade lateral quase nunca é atingido em curva
	# (polícia a 19 m/s no limite chegava a 4 m/s, caminhão a 2), então o drift ficava mudo.
	# O que o ouvido percebe é o ângulo de deriva (lateral/velocidade), por isso a voz também abre por ele.
	var slip_ratio := lateral_speed / maxf(road_speed, 4.0)
	var drifting := road_speed > SKID_DRIFT_MIN_SPEED and slip_ratio > SKID_SLIP_ON
	var hard_contact := false
	for contact in contacts:
		if not contact.is_empty() and contact.kind == "hard": hard_contact = true
	# Freio de mão puxado em movimento trava as rodas de trás mesmo sem escorregar de lado ainda:
	# a voz entra como "trava" (teto próprio, mais baixo que o drift), não mais como falso slip lateral.
	var handbrake_lock: bool = vehicle.controlled and bool(vehicle.get("_handbrake_held")) and road_speed > 3.75
	var lock_kind := 2 if handbrake_lock else (1 if braking_slip else 0)
	_update_skid_audio((sliding or drifting) and hard_contact and tire_speed > 2.5, tire_speed, maxf(lateral_speed, _burnout*8.0), lock_kind)
	if vehicle.controlled and ENGINE_PROFILE.family(str(vehicle.archetype)) != "tank":
		if not is_instance_valid(road_mixer):
			road_mixer = ROAD_AUDIO.new()
			road_mixer.vehicle = vehicle
			add_child(road_mixer)
		road_mixer.update_contacts(contacts, tire_speed, sliding, PROBE_INTERVAL)
	elif is_instance_valid(road_mixer):
		road_mixer.stop()
	for side in 2:
		var contact: Dictionary = contacts[side]
		if contact.is_empty():
			_set_emitting(side,false)
			if side < droplets.size(): droplets[side].emitting = false
			last_modes[side] = ""
			last_contacts[side] = {}
			continue
		var kind: String = contact.kind
		var mode := ""
		# Lago de verdade (nÃ£o sÃ³ pista molhada): respingo grosso e gotas em arco.
		if kind == "water" and tire_speed > 1.5: mode = "lake"
		elif bool(contact.wet) and tire_speed > 3.0: mode = "water"
		elif kind in SOFT_KINDS and tire_speed > 2.5: mode = kind
		elif sliding and kind == "hard": mode = "smoke"
		var splash_in: bool = mode == "lake" and last_modes[side] != "lake" and road_speed > 4.0
		last_modes[side] = mode
		if mode.is_empty(): _set_emitting(side,false)
		else: _emit_surface(side,contact,mode,tire_speed,lateral_speed)
		_update_droplets(side,contact,mode == "lake",splash_in,tire_speed)
		if sliding and road_speed > 2.5: _append_mark(side,contact,kind,false)
		elif kind in SOFT_KINDS and road_speed > .8: _append_mark(side,contact,kind,true)
		else: last_contacts[side] = contact

func _rear_contacts() -> Array[Dictionary]:
	var began := STALL_WORK.begin()
	var result := _stall_rear_contacts()
	STALL_WORK.finish_slow("vehicle_tires.contacts",began,5000,vehicle)
	return result

func _stall_rear_contacts() -> Array[Dictionary]:
	var points: Array[Vector3] = []
	for pivot in vehicle.wheels:
		if not bool(pivot.get_meta("front",false)): points.append(pivot.global_position)
	if points.size() < 2:
		points.assign([
			vehicle.to_global(Vector3(-vehicle.half_width*.68,.42,vehicle.half_length*.64)),
			vehicle.to_global(Vector3(vehicle.half_width*.68,.42,vehicle.half_length*.64))])
	points.sort_custom(func(a: Vector3,b: Vector3): return vehicle.to_local(a).x < vehicle.to_local(b).x)
	return [SURFACE.sample(vehicle,points[0]),SURFACE.sample(vehicle,points[1])]

func _ensure_emitters() -> void:
	if not emitters.is_empty(): return
	for side in 2:
		var emitter := RESOURCES.emitter("RearWheelSurface%d"%side,18,.48,Vector2(.26,.26))
		emitter.process_material = RESOURCES.particle_process()
		vehicle.add_child(emitter)
		emitter.top_level = true
		emitters.append(emitter)

func _emit_surface(side: int, contact: Dictionary, mode: String, road_speed: float, lateral_speed: float) -> void:
	var began := STALL_WORK.begin()
	_stall_emit_surface(side,contact,mode,road_speed,lateral_speed)
	STALL_WORK.finish_slow("vehicle_tires.surface_emit",began,5000,vehicle)

func _stall_emit_surface(side: int, contact: Dictionary, mode: String, road_speed: float, lateral_speed: float) -> void:
	_ensure_emitters()
	var emitter := emitters[side]
	var process := emitter.process_material as ParticleProcessMaterial
	_set_burnout_smoke(side, mode == "smoke" and _burnout > 0.0)
	# 0 = moto/carro leve, 1 = caminhÃ£o/Ã´nibus: veÃ­culo pesado arranca mais chÃ£o.
	var heft := _heft()
	var normal: Vector3 = contact.normal
	var wake := -Vector3(vehicle.horizontal_velocity.x,0,vehicle.horizontal_velocity.z).normalized()
	process.direction = (normal*.75+wake*.45+vehicle.global_basis.x*(-.15 if side==0 else .15)).normalized()
	process.spread = 38
	process.gravity = Vector3(0,-2.5,0) if mode == "water" else (Vector3(0,-7.5,0) if mode == "grass" else Vector3(0,.28,0))
	process.initial_velocity_min = .9 if mode == "water" else .45
	process.initial_velocity_max = 2.7 if mode == "water" else 1.65
	if mode == "lake":
		# Lago: nÃ©voa de respingo maior e mais rÃ¡pida que a pista molhada; as gotas vÃ£o no emissor Ã  parte.
		process.gravity = Vector3(0,-4.0,0)
		process.initial_velocity_min = 1.4
		process.initial_velocity_max = 3.8
		process.scale_min = 1.2
		process.scale_max = 2.4
		process.color = Color(.80,.92,1.0,.85)
	elif mode == "water":
		process.scale_min = .45
		process.scale_max = .9
		process.color = Color(.75,.86,1,.62)
	elif mode == "snow":
		process.scale_min = .55
		process.scale_max = 1.15
		process.color = Color(.88,.91,.91,.45)
	elif mode == "dirt":
		process.scale_min = .48+heft*.3
		process.scale_max = 1.25+heft*.9
		process.color = Color(.38,.30,.22,.48+heft*.2)
	elif mode == "sand":
		# Poeira clara da areia do deserto, na cor do chão, não a fumaça cinza-azulada do asfalto.
		process.scale_min = .55+heft*.3
		process.scale_max = 1.35+heft*.9
		process.color = Color(.78,.66,.48,.40+heft*.2)
	elif mode == "grass":
		# Tufos arrancados sobem e caem (gravidade), nÃ£o pairam como poeira.
		process.initial_velocity_min = 1.0+heft
		process.initial_velocity_max = 2.6+heft*1.8
		process.scale_min = .22+heft*.15
		process.scale_max = .6+heft*.45
		process.color = Color(.27,.36,.15,.85).lerp(Color(.30,.24,.14,.85),heft*.6)
	else:
		var is_heavy: bool = lateral_speed > 6.0 or (vehicle.controlled and vehicle.brake_input and road_speed > 4.5)
		process.scale_min = .30 if is_heavy else .22
		process.scale_max = 1.30 if is_heavy else .70
		process.color = Color(.88,.88,.90,.36) if is_heavy else Color(.90,.91,.92,.22)
		process.angle_min = 0.0
		process.angle_max = 360.0
		process.angular_velocity_min = -2.2
		process.angular_velocity_max = 2.2
		if _burnout_smoke[side]:
			process.direction = (normal*.65 + vehicle.global_basis.z*.35 + vehicle.global_basis.x*(-.55 if side == 0 else .55)).normalized()
			process.spread = 42.0
			process.gravity = Vector3(0,.5,0)
			process.initial_velocity_min = .6
			process.initial_velocity_max = 1.5
			process.scale_min = .7
			process.scale_max = 1.4
			process.color = Color(.88,.90,.93,.68)
	emitter.global_position = _emission_point(contact,mode == "lake")+normal*.035
	var soft_boost := heft*.35 if mode in SOFT_KINDS else 0.0
	emitter.amount_ratio = clampf(.22+road_speed/18.0+lateral_speed/20.0+soft_boost,.22,1.0)
	emitter.emitting = true

func _set_burnout_smoke(side: int, enabled: bool) -> void:
	if _burnout_smoke[side] == enabled: return
	_burnout_smoke[side] = enabled
	var emitter := emitters[side]
	var process := emitter.process_material as ParticleProcessMaterial
	if enabled: burnout_ramps()
	emitter.amount = 36 if enabled else 18
	emitter.lifetime = 1.5 if enabled else .48
	emitter.draw_pass_1 = RESOURCES.quad(Vector2(.9,.9) if enabled else Vector2(.26,.26))
	process.color_ramp = _burnout_fade if enabled else null
	process.scale_curve = _burnout_growth if enabled else null

## Rampa de alfa e curva de crescimento da fumaça do burnout. Com elas o ParticleProcessMaterial
## vira outra variante de shader; VehicleMaterialVariantPrewarm a desenha sob a cortina.
static func burnout_ramps() -> Array:
	if _burnout_fade == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0,.12,.55,1.0])
		gradient.colors = PackedColorArray([Color(1,1,1,0),Color.WHITE,Color(1,1,1,.65),Color(1,1,1,0)])
		_burnout_fade = GradientTexture1D.new()
		_burnout_fade.gradient = gradient
		var curve := Curve.new()
		curve.add_point(Vector2(0,.25))
		curve.add_point(Vector2(.4,.65))
		curve.add_point(Vector2(1,1))
		_burnout_growth = CurveTexture.new()
		_burnout_growth.curve = curve
	return [_burnout_fade, _burnout_growth]

func _set_emitting(side: int, value: bool) -> void:
	if side < emitters.size(): emitters[side].emitting = value

func _stop_emitters() -> void:
	set_process(false)
	for emitter in emitters: emitter.emitting = false
	for emitter in droplets: emitter.emitting = false
	if is_instance_valid(skid_audio) and skid_audio.playing: skid_audio.stop()
	if is_instance_valid(road_mixer): road_mixer.stop()

func _update_skid_audio(audible: bool, road_speed: float, lateral_speed: float, lock_kind := 0) -> void:
	var began := STALL_WORK.begin()
	_stall_update_skid_audio(audible,road_speed,lateral_speed,lock_kind)
	STALL_WORK.finish_slow("vehicle_tires.skid_audio",began,5000,vehicle)

## lock_kind: 0 = só deriva lateral, 1 = freio de serviço travando, 2 = freio de mão.
func _stall_update_skid_audio(audible: bool, road_speed: float, lateral_speed: float, lock_kind := 0) -> void:
	# A burnout already has its own voice in the shared powertrain mixer. Avoid
	# summing the same tire recording twice, while preserving braking and drift.
	if audible and lock_kind == 0 and vehicle.get("brake_input") != true and lateral_speed <= maxf(0.0, road_speed) * .15:
		var powertrain_audio := vehicle.get_node_or_null("DesertCarAudio")
		if is_instance_valid(powertrain_audio) and powertrain_audio.has_method("has_wheelspin_voice") and powertrain_audio.has_wheelspin_voice():
			audible = false
	if not audible:
		if is_instance_valid(skid_audio) and skid_audio.playing: skid_audio.stop()
		return
	if not is_instance_valid(skid_audio):
		var began := STALL_WORK.begin()
		var family: String = ENGINE_PROFILE.family(str(vehicle.archetype))
		var kind := "monaliza" if str(vehicle.archetype) == "monaliza" else ("heavy" if family in ["truck", "bus", "fire_diesel", "diesel"] else ("muscle" if family == "muscle" else ("sport" if family in ["sport", "vq35", "m8_v8", "rosso_v12", "bike_sport"] else "street")))
		# Also covers isolated vehicles and --no-prewarm; sources are already held.
		prewarm_skid_audio()
		var stream: AudioStreamWAV = _skid_streams[kind]
		skid_audio = AudioStreamPlayer3D.new()
		skid_audio.name = "VehicleSkid"
		# Variação por carro além do take (cinco WAVs): leve guincha mais agudo, pesado mais grave
		# (±~12% pelo peso) e ±4% fixo pelo modelo, para dois carros do mesmo take não soarem iguais.
		_car_pitch = lerpf(1.12, .86, _heft()) * (1.0 + float(hash(str(vehicle.archetype)) % 9 - 4) * .01)
		skid_audio.stream = stream
		skid_audio.max_distance = 55.0
		skid_audio.unit_size = 4.0
		# Playtest 29/10 ("freio de mão sem barulho de pneu"): o teto de -22 dB deixava o chiado
		# ~23 dB abaixo do motor (max_db +1) e inaudível. O volume por velocidade abaixo já
		# dosa a intensidade; o teto só impede estouro de perto.
		skid_audio.max_db = -4.0
		skid_audio.bus = &"Vehicles" if AudioServer.get_bus_index("Vehicles") >= 0 else &"Master"
		vehicle.add_child(skid_audio)
		STALL_WORK.finish("vehicle_tires.skid_voice",began,{"kind":kind})
	# Deriva: o volume cresce com o ângulo de deriva (lateral/velocidade), não só com a velocidade, e
	# carro parado de lado quase não chia. Trava (freio): cresce com a velocidade, com teto mais baixo.
	var slip := smoothstep(SKID_SLIP_ON, SKID_SLIP_FULL, lateral_speed / maxf(road_speed, 4.0))
	var speed_gain := clampf(road_speed / 16.25, 0.0, 1.0)
	var drift_db := lerpf(SKID_DRIFT_DB.x, SKID_DRIFT_DB.y, slip * (.55 + .45 * speed_gain)) if slip > 0.0 else -80.0
	var lock_range := SKID_HANDBRAKE_DB if lock_kind == 2 else SKID_SERVICE_BRAKE_DB
	var lock_db := lerpf(lock_range.x, lock_range.y, speed_gain) if lock_kind > 0 else -80.0
	skid_audio.volume_db = maxf(drift_db, lock_db)
	# Tom: sobe com a deriva; o tom do carro (leve agudo, pesado grave) é fixo por veículo.
	var drive := maxf(slip, speed_gain * .5) if lock_kind > 0 else slip
	skid_audio.pitch_scale = lerpf(0.88, 1.12, drive) * _car_pitch
	if not skid_audio.playing: skid_audio.play()

func _heft() -> float:
	return clampf((STREET_PHYSICS._vehicle_mass(vehicle)-.6)/4.0,0.0,1.0)

func _append_mark(side: int, contact: Dictionary, kind: String, rut := false) -> void:
	var previous: Dictionary = last_contacts[side]
	last_contacts[side] = contact
	if previous.is_empty(): return
	var length: float = previous.point.distance_to(contact.point)
	if length < .035 or length > 2.2: return
	var heft := _heft()
	# Pneu de caminhÃ£o Ã© mais largo e afunda mais: sulco mais largo e mais escuro.
	var width := lerpf(.10,.22,heft) if rut else lerpf(.13,.22,heft)
	marks.append({"a":previous.point,"b":contact.point,"na":previous.normal,"nb":contact.normal,"kind":kind,
		"born":Time.get_ticks_msec(),"life":RUT_LIFETIME_MSEC if rut else MARK_LIFETIME_MSEC,"w":width,"depth":lerpf(.75,1.35,heft) if rut else 1.0})
	if SKID_BUDGET.enabled:
		SKID_BUDGET.append(self, marks.back(), mark_material())
		return
	while marks.size() > MAX_MARK_SEGMENTS: marks.pop_front()
	_start_mark_timer()

func _start_mark_timer() -> void:
	# Tire traces keep aging when the vehicle physics sleeps after parking.
	# Allocate only for cars that leave marks; stop ticking once they expire.
	if not is_instance_valid(_mark_timer):
		_mark_timer = Timer.new()
		_mark_timer.name = "TireMarkLifetime"
		_mark_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
		_mark_timer.wait_time = REDRAW_INTERVAL
		add_child(_mark_timer)
		_mark_timer.timeout.connect(_tick_mark_lifetime)
	if _mark_timer.is_stopped(): _mark_timer.start()

func _tick_mark_lifetime() -> void:
	_expire_marks()
	_redraw_marks()
	if marks.is_empty(): _mark_timer.stop()

## Material único das marcas, vivo a sessão inteira. Cada carro criava o seu na primeira marca e, quando
## nenhum tinha marcas, o shader morria junto: a próxima derrapagem recompilava a variante (163-290 ms
## num quadro no release de 2026-10-13, três vezes em 5 min).
static var _mark_material: StandardMaterial3D

static func mark_material() -> StandardMaterial3D:
	if _mark_material == null:
		_mark_material = StandardMaterial3D.new()
		_mark_material.albedo_color = Color.WHITE
		_mark_material.roughness = 1.0
		_mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mark_material.vertex_color_use_as_albedo = true
		_mark_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _mark_material

func _ensure_mark_mesh() -> void:
	if is_instance_valid(mark_mesh): return
	mark_mesh = MeshInstance3D.new()
	mark_mesh.name = "SurfaceAlignedTireMarks"
	mark_mesh.mesh = geometry
	mark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark_mesh.material_override = mark_material()
	vehicle.add_child(mark_mesh)
	mark_mesh.top_level = true
	mark_mesh.global_transform = Transform3D.IDENTITY

func _expire_marks() -> void:
	if SKID_BUDGET.enabled:
		SKID_BUDGET.expire()
		return
	if marks.is_empty(): return
	var now := Time.get_ticks_msec()
	marks = marks.filter(func(mark: Dictionary): return now-int(mark.born)<int(mark.life))

func _redraw_marks() -> void:
	if SKID_BUDGET.enabled:
		SKID_BUDGET.redraw()
		return
	var began := STALL_WORK.begin()
	_stall_redraw_marks()
	STALL_WORK.finish_slow("vehicle_tires.redraw_marks",began,5000,vehicle)

func _cache_mark_corners(mark: Dictionary) -> void:
	# A deposited segment never moves. Only its color fades on later redraws;
	# keep the sampled geometry instead of normalizing it again for up to 30 s.
	var a: Vector3 = mark.a
	var b: Vector3 = mark.b
	var na: Vector3 = mark.na
	var nb: Vector3 = mark.nb
	var tangent := (b-a).normalized()
	var half_width: float = mark.w
	var sa := tangent.cross(na).normalized()*half_width
	var sb := tangent.cross(nb).normalized()*half_width
	mark["corner_a_left"] = a-sa+na*.012
	mark["corner_b_left"] = b-sa+nb*.012
	mark["corner_b_right"] = b+sb+nb*.012
	mark["corner_a_right"] = a+sa+na*.012

func _stall_redraw_marks() -> void:
	if marks.is_empty():
		if is_instance_valid(mark_mesh): mark_mesh.visible = false
		return
	_ensure_mark_mesh()
	mark_mesh.visible = true
	geometry.clear_surfaces()
	# Submit packed surface data once instead of issuing three mesh calls per vertex.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var vertex_count := marks.size()*6
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var cursor := 0
	var now := Time.get_ticks_msec()
	for mark in marks:
		if not mark.has("corner_a_left"): _cache_mark_corners(mark)
		var na: Vector3 = mark.na
		var nb: Vector3 = mark.nb
		var age := float(now-int(mark.born))/float(mark.life)
		var depth: float = mark.depth
		var tint := Color(.035,.035,.03,(1.0-age)*(.48 if mark.kind=="hard" else .30))
		if mark.kind == "snow": tint = Color(.38,.43,.44,(1.0-age)*.38)
		elif mark.kind == "dirt": tint = Color(.15,.10,.07,minf(1.0,(1.0-age)*.36*depth))
		elif mark.kind == "sand": tint = Color(.42,.33,.22,minf(1.0,(1.0-age)*.30*depth))
		elif mark.kind == "grass": tint = Color(.13,.15,.06,minf(1.0,(1.0-age)*.42*depth))
		vertices[cursor] = mark.corner_a_left
		vertices[cursor+1] = mark.corner_b_left
		vertices[cursor+2] = mark.corner_b_right
		vertices[cursor+3] = vertices[cursor]
		vertices[cursor+4] = vertices[cursor+2]
		vertices[cursor+5] = mark.corner_a_right
		normals[cursor] = na
		normals[cursor+1] = nb
		normals[cursor+2] = nb
		normals[cursor+3] = na
		normals[cursor+4] = nb
		normals[cursor+5] = na
		for offset in 6: colors[cursor+offset] = tint
		cursor += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var upload_began := STALL_WORK.begin()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	STALL_WORK.finish_slow("vehicle_tires.surface_end",upload_began,5000,vehicle)

func clear_all() -> void:
	if SKID_BUDGET.enabled: SKID_BUDGET.release(self)
	_stop_emitters()
	marks.clear()
	if is_instance_valid(_mark_timer): _mark_timer.stop()
	last_contacts = [{},{}]
	last_modes = ["",""]
	geometry.clear_surfaces()
	if is_instance_valid(mark_mesh): mark_mesh.visible = false

## Gotas do lago: arco curto com gravidade cheia, por roda. Criadas sÃ³ na primeira vez que o
## veÃ­culo toca um lago, entÃ£o quem nunca molha a roda nÃ£o paga emissor nenhum. Ao entrar na
## Ã¡gua com velocidade, a roda solta uma rajada Ãºnica (splash_in).
var droplets: Array[GPUParticles3D] = []

func _update_droplets(side: int, contact: Dictionary, active: bool, splash_in: bool, road_speed: float) -> void:
	if not active:
		if side < droplets.size(): droplets[side].emitting = false
		return
	if droplets.is_empty():
		for index in 2:
			var branch_emitter := RESOURCES.emitter("RearWheelDroplets%d"%index,64,.9,Vector2(.3,.3))
			var branch_process := RESOURCES.particle_process(false)
			branch_process.spread = 58
			branch_process.gravity = Vector3(0,-9.8,0)
			branch_process.scale_min = .55
			branch_process.scale_max = 1.2
			branch_process.color = Color(.86,.94,1.0,.9)
			branch_emitter.process_material = branch_process
			vehicle.add_child(branch_emitter)
			branch_emitter.top_level = true
			droplets.append(branch_emitter)
	var emitter := droplets[side]
	var process := emitter.process_material as ParticleProcessMaterial
	var wake := -Vector3(vehicle.horizontal_velocity.x,0,vehicle.horizontal_velocity.z).normalized()
	var normal: Vector3 = contact.normal
	process.direction = (normal*.9+wake*.5+vehicle.global_basis.x*(-.2 if side == 0 else .2)).normalized()
	process.initial_velocity_min = 1.8+road_speed*.12
	process.initial_velocity_max = 3.6+road_speed*.3
	emitter.global_position = _emission_point(contact,true)+normal*.05
	emitter.amount_ratio = clampf(.25+road_speed/14.0,.25,1.0)
	emitter.emitting = true
	# Rajada de entrada: reinicia o emissor com a taxa cheia por um instante.
	if splash_in:
		emitter.amount_ratio = 1.0
		emitter.restart()

## Em lago o respingo sai do espelho d'Ã¡gua; o ponto de contato fica no fundo da bacia, sob a Ã¡gua.
func _emission_point(contact: Dictionary, lake: bool) -> Vector3:
	var point: Vector3 = contact.point
	if lake and contact.has("water_y") and not is_nan(float(contact.water_y)): point.y = maxf(point.y,float(contact.water_y)+.18)
	return point

extends Node3D
## Poças de chuva dinâmicas de Harbor, portadas de world/harbor/HarborRainPuddles.gd e
## geodata/Puddle.gd da V1 (ramo v1-legado).
##
## Como na V1: a cada chuva nasce um desenho novo de poças na beira do asfalto; elas
## enchem devagar enquanto chove (~45 s), secam quando para, e quem passa por cima
## (jogador a pé, pedestre, carro) levanta respingo e barulho de água.
##
## Diferença da V1: lá as 96 poças eram espalhadas no mapa inteiro de uma vez. Aqui o
## mapa é em streaming, então só existe um conjunto limitado em volta do foco. O desenho
## é determinístico por chuva (hash de geração + trecho de rua), portanto voltar a uma
## rua durante a mesma chuva mostra as mesmas poças.

const WATER_STEP := preload("res://runtime/world/OriginalWaterStep.gd")
const PUDDLE_SHADER := preload("res://world/rain/RainPuddle.gdshader")
const MAX_PUDDLES := 48
const LAYOUT_RADIUS := 85.0
const RELAYOUT_DISTANCE := 14.0
const SLOT_LENGTH := 22.0
const SLOT_CHANCE := 45 # em 100
const FILL_RATE := 1.0 / 45.0
const DRY_RATE := 1.0 / 120.0
const SPLASH_MIN_SPEED := 0.95 # 15 px/s da V1 a 16 px/m
const SPLASH_POOL_SIZE := 8
const AUDIO_POOL_SIZE := 4

var controller
var wetness := 0.0
var raining := false
var generation := 0
var _material: ShaderMaterial
var _mesh: PlaneMesh
var _active: Dictionary = {} # slot key -> Area3D
var _rejected: Dictionary = {}
var _free: Array[Area3D] = []
var _layout_focus := Vector3.INF
var _clock := 0.0
var _splashes: Array[GPUParticles3D] = []
var _splash_cursor := 0
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_cursor := 0
## Respingos disparados desde o início; o emissor one-shot desliga sozinho, então os
## testes contam por aqui.
var splash_count := 0

func _ready() -> void:
	name = "RainPuddles"
	_material = ShaderMaterial.new()
	_material.shader = PUDDLE_SHADER
	_material.set_shader_parameter("fill", 0.0)
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(2, 2)
	for i in SPLASH_POOL_SIZE:
		var emitter := _create_splash_emitter()
		add_child(emitter)
		_splashes.append(emitter)
	for i in AUDIO_POOL_SIZE:
		var voice := AudioStreamPlayer3D.new()
		voice.stream = WATER_STEP.sound(i)
		voice.max_distance = 30.0
		voice.unit_size = 4.0
		if AudioServer.get_bus_index("SFX") >= 0: voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)
	# Um save gravado no meio da chuva volta com a rua já molhada.
	if _weather_raining():
		wetness = 1.0
		raining = true
		generation = 1

func _weather():
	return controller.session.weather if controller != null and controller.session != null else null

func _weather_raining() -> bool:
	var weather = _weather()
	if weather == null or controller.world.player == null: return false
	if int(weather.weather_state) not in [1, 2]: return false
	# A neve de Mountain não enche poça; a costura segue o mesmo peso regional da chuva.
	var focus: Vector3 = weather.atmosphere.focus_position(controller)
	return float(weather.atmosphere.weights_at(focus).mountain) < 0.999

func _process(delta: float) -> void:
	var now_raining := _weather_raining()
	if now_raining and not raining and wetness <= 0.05:
		# Chuva nova depois de a rua secar: novo desenho, como _begin_rain() da V1.
		generation += 1
		_release_all()
		_rejected.clear()
	raining = now_raining
	wetness = clampf(wetness + (FILL_RATE if raining else -DRY_RATE) * delta, 0.0, 1.0)
	_material.set_shader_parameter("fill", wetness)
	_material.set_shader_parameter("rain", 1.0 if raining else 0.0)
	visible = wetness > 0.0
	if wetness <= 0.0:
		if not _active.is_empty(): _release_all()
		return
	_clock += delta
	if _clock < 0.25: return
	_clock = 0.0
	var focus: Vector3 = _weather().atmosphere.focus_position(controller)
	if _layout_focus.distance_to(focus) > RELAYOUT_DISTANCE:
		_layout_focus = focus
		_relayout(focus)
	# Poça rasa demais não respinga; a V1 também ligava o monitor só ao materializar.
	var splashing := wetness > 0.35
	for puddle: Area3D in _active.values():
		if puddle.monitoring != splashing: puddle.set_deferred("monitoring", splashing)

func _harbor_roads() -> Array:
	var harbor = controller.regions.get("harbor") if controller != null else null
	return harbor.roads if is_instance_valid(harbor) else []

func _relayout(focus: Vector3) -> void:
	var wanted: Array[Dictionary] = []
	var radius_sq := LAYOUT_RADIUS * LAYOUT_RADIUS
	for road: Dictionary in _harbor_roads():
		if String(road.get("surface", "asphalt")) != "asphalt": continue
		var points: PackedVector3Array = road.points
		for i in range(points.size() - 1):
			var a := points[i]
			var b := points[i + 1]
			if Geometry3D.get_closest_point_to_segment(focus, a, b).distance_squared_to(focus) > radius_sq: continue
			var length := a.distance_to(b)
			var slots := int(length / SLOT_LENGTH)
			for k in slots:
				var key := "%s:%d:%d" % [road.id, i, k]
				if _rejected.has(key): continue
				var h := hash([generation, key])
				if h % 100 >= SLOT_CHANCE: continue
				var t := (float(k) + 0.25 + float((h >> 8) % 50) / 100.0) * SLOT_LENGTH / length
				var center := a.lerp(b, t)
				var distance_sq := Vector2(center.x - focus.x, center.z - focus.z).length_squared()
				if distance_sq > radius_sq: continue
				wanted.append({"key": key, "hash": h, "center": center, "a": a, "b": b, "width": float(road.width), "distance": distance_sq})
	wanted.sort_custom(func(x: Dictionary, y: Dictionary): return x.distance < y.distance)
	if wanted.size() > MAX_PUDDLES: wanted.resize(MAX_PUDDLES)
	var keep := {}
	for spec in wanted: keep[spec.key] = true
	for key in _active.keys():
		if not keep.has(key): _release(key)
	for spec in wanted:
		if not _active.has(spec.key): _place(spec)

func _place(spec: Dictionary) -> void:
	var h: int = spec.hash
	var tangent: Vector3 = (spec.b - spec.a).normalized()
	var side := Vector3(tangent.z, 0, -tangent.x)
	# Raios da V1 (26-44 x 11-19 px) em metros.
	var radii := Vector2(1.6 + float((h >> 12) % 100) / 100.0 * 1.15, 0.7 + float((h >> 4) % 100) / 100.0 * 0.5)
	var lateral_room := maxf(0.0, spec.width * 0.5 - radii.y * 1.15 - 0.15)
	var offset := lateral_room * (float((h >> 16) % 161) / 100.0 - 0.8)
	var point: Vector3 = spec.center + side * offset
	var surface_y := _surface_height(point, spec.center.y)
	if is_nan(surface_y):
		_rejected[spec.key] = true
		return
	var puddle: Area3D = _free.pop_back() if not _free.is_empty() else _create_puddle()
	if puddle.get_parent() == null: add_child(puddle)
	puddle.global_position = Vector3(point.x, surface_y + 0.035, point.z)
	puddle.rotation = Vector3(0, atan2(-tangent.z, tangent.x), 0)
	var visual: MeshInstance3D = puddle.get_child(0)
	visual.scale = Vector3(radii.x, 1, radii.y)
	visual.set_instance_shader_parameter("seed", float(h % 1000) / 1000.0)
	var shape: CylinderShape3D = (puddle.get_child(1) as CollisionShape3D).shape
	shape.radius = radii.x * 0.85
	puddle.visible = true
	puddle.set_meta("cooldown", 0.0)
	_active[spec.key] = puddle

## Altura do chão no ponto; NAN quando há algo em cima (prédio, praça elevada, obstáculo).
func _surface_height(point: Vector3, road_y: float) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 6.0, point + Vector3.DOWN * 3.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty(): return road_y
	var y: float = hit.position.y
	if y > road_y + 0.3: return NAN
	return maxf(y, road_y)

func _create_puddle() -> Area3D:
	var puddle := Area3D.new()
	puddle.name = "RainPuddle"
	puddle.add_to_group("rain_puddle")
	puddle.collision_layer = 0
	puddle.collision_mask = 2 | 4 # pessoas e veículos
	puddle.monitorable = false
	var visual := MeshInstance3D.new()
	visual.mesh = _mesh
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puddle.add_child(visual)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = 1.2
	collider.shape = shape
	puddle.add_child(collider)
	puddle.body_entered.connect(_on_body_entered.bind(puddle))
	return puddle

func _release(key: String) -> void:
	var puddle: Area3D = _active[key]
	_active.erase(key)
	puddle.visible = false
	puddle.set_deferred("monitoring", false)
	_free.append(puddle)

func _release_all() -> void:
	for key in _active.keys(): _release(key)
	_layout_focus = Vector3.INF

func _on_body_entered(body: Node3D, puddle: Area3D) -> void:
	if not puddle.visible: return
	var speed := 0.0
	if "velocity" in body: speed = (body.velocity as Vector3).length()
	if speed < 0.01 and "speed" in body: speed = absf(float(body.speed))
	var now := Time.get_ticks_msec() / 1000.0
	if speed < SPLASH_MIN_SPEED or now < float(puddle.get_meta("cooldown", 0.0)): return
	puddle.set_meta("cooldown", now + 0.2)
	splash(Vector3(body.global_position.x, puddle.global_position.y, body.global_position.z), speed)

func splash(point: Vector3, speed: float) -> void:
	splash_count += 1
	var emitter := _splashes[_splash_cursor]
	_splash_cursor = (_splash_cursor + 1) % _splashes.size()
	var strength := clampf(speed / 12.0, 0.0, 1.0)
	var process := emitter.process_material as ParticleProcessMaterial
	process.initial_velocity_min = lerpf(1.2, 3.5, strength)
	process.initial_velocity_max = lerpf(2.6, 6.5, strength)
	process.emission_sphere_radius = lerpf(0.15, 0.7, strength)
	emitter.amount_ratio = lerpf(0.4, 1.0, strength)
	emitter.global_position = point
	emitter.restart()
	emitter.emitting = true
	var voice := _voices[_voice_cursor]
	_voice_cursor = (_voice_cursor + 1) % _voices.size()
	voice.global_position = point
	voice.pitch_scale = randf_range(1.5, 2.1)
	voice.volume_db = clampf(-16.0 + speed * 0.6, -16.0, -4.0)
	voice.play()

func _create_splash_emitter() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "PuddleSplash"
	particles.emitting = false
	particles.one_shot = true
	particles.amount = 28
	particles.lifetime = 0.5
	particles.explosiveness = 0.95
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.3
	process.direction = Vector3.UP
	process.spread = 60.0
	process.gravity = Vector3(0, -14.0, 0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.12)
	var drop := StandardMaterial3D.new()
	drop.albedo_color = Color(0.82, 0.9, 1.0, 0.75)
	drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = drop
	particles.draw_pass_1 = quad
	return particles

extends Node3D
## Rastro de sangue de pneu e sapato (porte de BloodTransferSystem da V1).
##
## V1: quem encosta numa mancha carrega resíduo que se gasta por DISTÂNCIA
## (pneu 210 px, sapato 85 px), não por tempo; cada marca vive 14 s com 4 s de
## desvanecimento. Mesmas regras aqui. As marcas ficam num único MultiMesh em
## anel (as mais antigas são reaproveitadas), com cor por instância: um draw
## call para todo o rastro da cidade.

const TIRE_DISTANCE := 210.0 / 16.0
const FOOT_DISTANCE := 85.0 / 16.0
const MARK_LIFETIME := 14.0
const MARK_FADE := 4.0
const MAX_MARKS := 700
const SAMPLE_INTERVAL := 1.0 / 30.0
const TIRE_STEP := 0.45
const FOOT_STEP := 0.72
const COLOR := Color("420c10")

var director: Node
var _tracks := {}
var _multimesh: MultiMesh
var _born: PackedFloat32Array
var _alpha: PackedFloat32Array
var _next := 0
var _clock := 0.0
var _sample := 0.0
var _fade_clock := 0.0


func _ready() -> void:
	name = "BloodTracks3D"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_MARKS
	_multimesh.visible_instance_count = 0
	_born.resize(MAX_MARKS)
	_alpha.resize(MAX_MARKS)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	# Cor por instância vem em sRGB; sem isto o vermelho escuro virava rosa.
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = _mark_texture()
	# Sangue arrastado é fosco; brilho de sol deixava o rastro rosado.
	material.roughness = 0.85
	material.metallic_specular = 0.2
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = -1
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Resíduo imediato (atropelamento: pneu banhado na hora).
func soak(body: Node3D, distance: float) -> void:
	var track := _track(body, "tire" if body.get("horizontal_velocity") != null else "foot")
	track.residue = maxf(float(track.residue), distance)


func _track(body: Node3D, kind: String) -> Dictionary:
	var id := body.get_instance_id()
	if not _tracks.has(id):
		_tracks[id] = {"body": weakref(body), "kind": kind, "residue": 0.0, "last": body.global_position, "travel": 0.0, "foot": 0}
	return _tracks[id]


func _physics_process(delta: float) -> void:
	_clock += delta
	_sample += delta
	_fade_clock += delta
	if _fade_clock >= 0.25:
		_fade_clock = 0.0
		_fade()
	if _sample < SAMPLE_INTERVAL: return
	_sample = 0.0
	var blood: Node3D = director.blood
	if blood.stains.is_empty() and _tracks.is_empty(): return
	# Contato: veículos e pessoas perto de alguma mancha pegam resíduo.
	if not blood.stains.is_empty():
		for vehicle in get_tree().get_nodes_in_group("drivable"):
			if not vehicle is Node3D or not vehicle.is_inside_tree(): continue
			var half: float = float(vehicle.get("half_length")) if vehicle.get("half_length") != null else 2.0
			if not blood.stains_near(vehicle.global_position, half).is_empty():
				_track(vehicle, "tire").residue = TIRE_DISTANCE
		for person in director.people():
			if person.has_meta("street_down") or person.get("dead") == true: continue
			if not blood.stains_near(person.global_position, 0.25).is_empty():
				_track(person, "foot").residue = FOOT_DISTANCE
	for id in _tracks.keys():
		var track: Dictionary = _tracks[id]
		var body = track.body.get_ref()
		if not is_instance_valid(body) or float(track.residue) <= 0.0:
			_tracks.erase(id)
			continue
		var moved: float = Vector2(body.global_position.x - track.last.x, body.global_position.z - track.last.z).length()
		if moved > 6.0:
			# Teleporte/streaming: não desenha rastro atravessando a cidade.
			track.last = body.global_position
			continue
		track.travel = float(track.travel) + moved
		track.residue = float(track.residue) - moved
		track.last = body.global_position
		var step := TIRE_STEP if track.kind == "tire" else FOOT_STEP
		if float(track.travel) < step: continue
		var covered := float(track.travel)
		track.travel = 0.0
		var strength := clampf(float(track.residue) / (TIRE_DISTANCE if track.kind == "tire" else FOOT_DISTANCE), 0.0, 1.0)
		if track.kind == "tire": _tire_marks(body, strength, covered)
		else:
			_foot_mark(body, int(track.foot), strength)
			track.foot = 1 - int(track.foot)


## Cada marca cobre o trecho andado desde a anterior (com sobreposição), então
## o rastro sai contínuo em qualquer velocidade em vez de tracejado.
func _tire_marks(vehicle: Node3D, strength: float, covered: float) -> void:
	var local_basis := vehicle.global_basis
	var right := Vector3(local_basis.x.x, 0, local_basis.x.z).normalized()
	var forward := -Vector3(local_basis.z.x, 0, local_basis.z.z).normalized()
	var half_width: float = float(vehicle.get("half_width")) if vehicle.get("half_width") != null else 1.0
	var half_length: float = float(vehicle.get("half_length")) if vehicle.get("half_length") != null else 2.3
	var yaw := atan2(forward.x, forward.z)
	for side in [-1.0, 1.0]:
		for axle in [0.72, -0.72]:
			var point: Vector3 = vehicle.global_position + right * side * half_width * 0.78 + forward * (axle * half_length - covered * 0.5)
			_emit(point, yaw, Vector2(0.22, covered + 0.35), 0.3 + strength * 0.6)


func _foot_mark(person: Node3D, foot: int, strength: float) -> void:
	var visual: Node3D = person.get("visual")
	var facing: float = visual.global_rotation.y if is_instance_valid(visual) else person.global_rotation.y
	var forward := Vector3(-sin(facing), 0, -cos(facing))
	var right := forward.cross(Vector3.UP)
	var point := person.global_position + right * (0.11 if foot == 0 else -0.11)
	_emit(point, atan2(forward.x, forward.z), Vector2(0.1, 0.24), strength * 0.9)


func _emit(point: Vector3, yaw: float, size: Vector2, alpha: float) -> void:
	var index := _next
	_next = (_next + 1) % MAX_MARKS
	_multimesh.visible_instance_count = mini(MAX_MARKS, maxi(_multimesh.visible_instance_count, index + 1))
	var local_basis := Basis(Vector3.UP, yaw).scaled(Vector3(size.x, 1, size.y))
	_multimesh.set_instance_transform(index, Transform3D(local_basis, Vector3(point.x, point.y + 0.048, point.z)))
	_born[index] = _clock
	_alpha[index] = clampf(alpha, 0.15, 0.95)
	var color := COLOR
	color.a = _alpha[index]
	_multimesh.set_instance_color(index, color)


func _fade() -> void:
	var count := _multimesh.visible_instance_count
	for index in count:
		var age := _clock - _born[index]
		if age < MARK_LIFETIME - MARK_FADE: continue
		var color := COLOR.lerp(Color("2e1012"), 0.6)
		color.a = _alpha[index] * clampf((MARK_LIFETIME - age) / MARK_FADE, 0.0, 1.0)
		_multimesh.set_instance_color(index, color)


## Marca com borda gasta (não retângulo chapado).
static func _mark_texture() -> ImageTexture:
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410
	for y in size:
		for x in size:
			var u := absf((x + 0.5) / size * 2.0 - 1.0)
			var v := absf((y + 0.5) / size * 2.0 - 1.0)
			# Borda lateral gasta, pontas quase retas: marcas vizinhas se emendam.
			var edge := (1.0 - smoothstep(0.55, 1.0, u)) * (1.0 - smoothstep(0.85, 1.0, v))
			var grain := rng.randf_range(0.55, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, edge * grain))
	return ImageTexture.create_from_image(image)

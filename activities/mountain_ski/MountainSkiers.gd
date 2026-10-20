extends Node3D
## Esquiadores de fundo do Cume Branco (20/10/2026). A pista estava vazia: só bandeiras, a estação e o
## cabo (captura de 20/10). Oito pessoas descem as três pistas em curvas e voltam pelo teleférico
## sentadas numa cadeira, num ciclo sem fim, enquanto o resort está aberto (08h–18h) e o jogador está
## perto da área. São de cenário: sem corpo físico, sem dano, sem testemunha de crime.
## Montagem: um esquiador por vez, a cada 0,25 s, só na primeira aproximação; longe, ficam escondidos
## e parados (estacionados), sem refazer nada. GETECO_MOUNTAIN_SKIERS=0 desliga (A/B no mesmo export).
const MODEL := preload("res://activities/mountain_ski/SkierModel.gd")
const BODIES := preload("res://assets/civilians/SkierBodyCatalog.gd")
const LIFT := preload("res://activities/MountainSkiLift.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const COUNT := 8
## Centro da área (V1: SOURCE_CENTER do teleférico) e raio em que os esquiadores existem.
const AREA_CENTER := Vector2(735, -557)
const ACTIVE_RADIUS := 230.0
const LIFT_SPEED := 4.5
## Cores dos conjuntos para o corpo do kit (sem malha Meshy de esquiador).
const SUITS := [[Color("c84b43"), Color("182b3b")], [Color("2a9d8f"), Color("2a9d8f")], [Color("f2b632"), Color("2b2f36")],
	[Color("15191d"), Color("1d2329")], [Color("3d6fb6"), Color("e8e6e1")], [Color("8e3fa3"), Color("26222c")], [Color("e8e6e1"), Color("3a3f47")]]
static var enabled := OS.get_environment("GETECO_MOUNTAIN_SKIERS") != "0"
var progression
var skiers: Array[Dictionary] = []
var courses: Array = []
var lift_path := Curve3D.new()
var _build_clock := 0.0
var _parked := true
var _ray_clock := 0.0

func configure(owner_progression) -> void:
	progression = owner_progression
	name = "MountainSkiers"
	for id in progression.COURSES:
		var spec: Dictionary = progression.COURSES[id]
		var points := PackedVector3Array([progression.Definitions.at(spec.start, "mountain")])
		for point in spec.points: points.append(progression.Definitions.at(point, "mountain"))
		courses.append(points)
	for point in LIFT.POINTS: lift_path.add_point(progression.Definitions.at(point, "mountain") + Vector3(0, 4.0, 0))

func _active() -> bool:
	if not enabled or progression == null or not progression._outside() or not progression._open(): return false
	var player: Vector3 = progression.session.world.player.global_position
	return Vector2(player.x, player.z).distance_to(AREA_CENTER) < ACTIVE_RADIUS

func _process(delta: float) -> void:
	var active := _active()
	if not active:
		if not _parked:
			_parked = true
			for skier in skiers: skier.root.visible = false
		return
	if _parked:
		_parked = false
		for skier in skiers: skier.root.visible = true
	if skiers.size() < COUNT:
		_build_clock += delta
		if _build_clock >= .25:
			_build_clock = 0.0
			var trace := STALL_WORK.begin()
			_add_skier(skiers.size())
			STALL_WORK.finish_slow("mountain.skiers.build", trace, 2000)
	_ray_clock += delta
	var probe := _ray_clock >= .12
	if probe: _ray_clock = 0.0
	for skier in skiers: _move(skier, delta, probe)

func _add_skier(index: int) -> void:
	var root := Node3D.new()
	root.name = "Skier%d" % index
	add_child(root)
	var identity := 88100 + index * 37
	var model := MODEL.new()
	model.name = "SkierModel"
	model.appearance_locked = true
	model.appearance_variant = 130 + index
	var suit: Array = SUITS[index % SUITS.size()]
	model.coat_color = suit[0]
	model.pants_color = suit[1]
	model.wardrobe_overrides = {"female": index % 2 == 1, "build": 1, "height": 1.0,
		"top": 2, "bottom": 0, "shoe": 1, "hat": 0, "backpack": false,
		"bag": 0, "glasses": false, "inner": (suit[0] as Color).lightened(.35),
		"accent": (suit[0] as Color).lightened(.3), "shoe_color": Color("1a1d21")}
	BODIES.apply(model, identity)
	model.lod_enabled = true
	root.add_child(model)
	# Esquis e bastões: caixas finas presas ao esquiador (os bastões seguem as mãos a cada quadro).
	var skis := Node3D.new()
	skis.name = "Skis"
	root.add_child(skis)
	for side in [-1.0, 1.0]: _box(skis, Vector3(side * .12, .03, -.1), Vector3(.09, .03, 1.65), suit[0])
	var poles: Array[MeshInstance3D] = []
	for i in 2: poles.append(_box(root, Vector3.ZERO, Vector3(.025, 1.15, .025), Color("cfd4d8")))
	var chair := Node3D.new()
	chair.name = "Chair"
	root.add_child(chair)
	_box(chair, Vector3(0, .38, .02), Vector3(1.3, .08, .6), Color("2d4b68"))
	_box(chair, Vector3(0, .78, .3), Vector3(1.3, .7, .07), Color("2d4b68"))
	_box(chair, Vector3(0, 2.0, .3), Vector3(.05, 2.4, .05), Color("4a5660"))
	chair.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = identity
	var skier := {"root": root, "model": model, "poles": poles, "skis": skis, "chair": chair, "rng": rng,
		"speed": rng.randf_range(7.5, 11.5), "amplitude": rng.randf_range(3.0, 6.0), "wave": rng.randf_range(.08, .14),
		"y": 0.0, "target_y": 0.0, "plant": 0.0}
	skiers.append(skier)
	# Espalha os primeiros: metade já na pista, metade no teleférico, em pontos diferentes.
	if index % 3 == 2: _start_lift(skier, float(index) / float(COUNT))
	else: _start_course(skier, float(index) / float(COUNT))

func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .6
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	return mesh

func _start_course(skier: Dictionary, progress := 0.0) -> void:
	var rng: RandomNumberGenerator = skier.rng
	skier.state = "ski"
	skier.course = courses[rng.randi() % courses.size()]
	var course: PackedVector3Array = skier.course
	skier.length = _length(course)
	skier.distance = progress * float(skier.length)
	skier.phase = rng.randf() * TAU
	(skier.model as Node3D).set("mode", "ski")
	skier.chair.visible = false
	skier.skis.visible = true
	for pole in skier.poles: pole.visible = true
	_place_ground(skier, true)

func _start_lift(skier: Dictionary, progress := 0.0) -> void:
	skier.state = "lift"
	skier.distance = progress * lift_path.get_baked_length()
	(skier.model as Node3D).set("mode", "lift")
	skier.chair.visible = true
	skier.skis.visible = false
	for pole in skier.poles: pole.visible = false

func _length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in points.size() - 1: total += points[i].distance_to(points[i + 1])
	return total

## Ponto e rumo na linha da pista a `distance` metros da largada.
func _along(points: PackedVector3Array, distance: float) -> Array:
	var left := distance
	for i in points.size() - 1:
		var span := points[i].distance_to(points[i + 1])
		if left <= span or i == points.size() - 2:
			var t := clampf(left / maxf(span, .001), 0.0, 1.0)
			return [points[i].lerp(points[i + 1], t), points[i].direction_to(points[i + 1])]
		left -= span
	return [points[points.size() - 1], Vector3.FORWARD]

func _move(skier: Dictionary, delta: float, probe: bool) -> void:
	var root: Node3D = skier.root
	var model: Node3D = skier.model
	if skier.state == "lift":
		skier.distance = float(skier.distance) + LIFT_SPEED * delta
		var length := lift_path.get_baked_length()
		if float(skier.distance) >= length:
			_start_course(skier)
			return
		var at := lift_path.sample_baked(float(skier.distance))
		var ahead := lift_path.sample_baked(minf(float(skier.distance) + 1.0, length))
		root.global_position = at
		var heading := Vector3(ahead.x - at.x, 0, ahead.z - at.z)
		if heading.length() > .01: root.rotation.y = atan2(-heading.x, -heading.z)
		return
	var course: PackedVector3Array = skier.course
	skier.distance = float(skier.distance) + float(skier.speed) * delta
	if float(skier.distance) >= float(skier.length):
		_start_lift(skier)
		return
	var line: Array = _along(course, float(skier.distance))
	var center: Vector3 = line[0]
	var forward: Vector3 = line[1]
	var right := Vector3(-forward.z, 0, forward.x).normalized()
	# Curvas de slalom: deslocamento lateral em seno ao longo da descida; a derivada dá a inclinação.
	var wave := float(skier.distance) * float(skier.wave) + float(skier.phase)
	var offset := sin(wave) * float(skier.amplitude)
	var slope := cos(wave) * float(skier.amplitude) * float(skier.wave)
	var at := center + right * offset
	var direction := (forward + right * slope).normalized()
	if probe: _place_ground(skier, false, at)
	skier.y = lerpf(float(skier.y), float(skier.target_y), 1.0 - exp(-10.0 * delta))
	root.global_position = Vector3(at.x, float(skier.y), at.z)
	root.rotation.y = atan2(-direction.x, -direction.z)
	model.set("carve", -cos(wave) * .9)
	# Finca o bastão na virada (quando o seno troca de lado).
	var plant: float = maxf(0.0, float(skier.plant) - delta * 3.0)
	if absf(sin(wave)) < .12: plant = 1.0
	skier.plant = plant
	model.set("pole_plant", plant)
	for i in 2:
		var pole: MeshInstance3D = skier.poles[i]
		var hand: Vector3 = model.hand_point(i)
		var tip := root.global_transform * Vector3((-1.0 if i == 0 else 1.0) * .45, .02, .1 - .45 * plant)
		pole.global_position = (hand + tip) * .5
		var axis := hand - tip
		if axis.length() > .05: pole.global_basis = Basis(Quaternion(Vector3.UP, axis.normalized()))

func _place_ground(skier: Dictionary, snap: bool, at := Vector3.INF) -> void:
	var root: Node3D = skier.root
	if at == Vector3.INF:
		var line: Array = _along(skier.course, float(skier.distance))
		at = line[0]
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 30, at - Vector3.UP * 30, 1)
	var hit: Dictionary = space.intersect_ray(ray)
	skier.target_y = float(hit.position.y) if not hit.is_empty() else at.y
	if snap:
		skier.y = skier.target_y
		root.global_position = Vector3(at.x, float(skier.y), at.z)

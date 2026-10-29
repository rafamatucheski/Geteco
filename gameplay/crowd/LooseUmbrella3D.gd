extends RigidBody3D
## Guarda-chuva largado por um pedestre atropelado ou morto. Sai com parte da velocidade do
## carro, rodopiando; no chão, aberto, o vento empurra a copa e as rajadas o fazem rolar.
## Não tem camada própria: o carro passa sem frear, mas a máscara inclui os veículos (4),
## então quem passa por cima arrasta o guarda-chuva junto.

const UMBRELLA := preload("res://gameplay/crowd/PedestrianUmbrella.gd")
const LIFETIME := 50.0
const FADE_SECONDS := 1.2
## Poucos soltos ao mesmo tempo: num caos o mais antigo some primeiro.
const MAX_LOOSE := 8
static var _live: Array = []

var open := 1.0
var _age := 0.0
var _mesh_scales: Dictionary = {}

static func spawn(parent: Node, at: Transform3D, tint: Color, amount: float, impact: Vector3) -> void:
	_live = _live.filter(func(body): return is_instance_valid(body))
	while _live.size() >= MAX_LOOSE:
		_live.pop_front().queue_free()
	var body = load("res://gameplay/crowd/LooseUmbrella3D.gd").new()
	body.open = amount
	var top := UMBRELLA.build_parts(body, tint)
	UMBRELLA.shape_canopy(top, amount)
	body._add_shapes(amount)
	parent.add_child(body)
	body.global_transform = at.orthonormalized()
	var flat := Vector3(impact.x, 0.0, impact.z)
	var speed := minf(flat.length(), 30.0)
	# Atropelado sobe e vai na direção do carro; morto a tiro (impacto ~0) só tomba da mão.
	var launch := flat.normalized() * speed * 0.75 + Vector3.UP * (1.2 + speed * 0.3) if speed > 0.5 else Vector3(randf_range(-0.6, 0.6), 0.6, randf_range(-0.6, 0.6))
	body.linear_velocity = launch.limit_length(22.0)
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * lerpf(2.0, 11.0, clampf(speed / 15.0, 0.0, 1.0))
	_live.append(body)

func _add_shapes(amount: float) -> void:
	collision_layer = 0
	collision_mask = 1 | 4
	mass = 0.6
	continuous_cd = true
	# Precisa continuar acordado para o vento achar ele parado no chão.
	can_sleep = false
	angular_damp = 1.2
	var material := PhysicsMaterial.new()
	material.friction = 0.55
	material.bounce = 0.15
	physics_material_override = material
	var shaft := CollisionShape3D.new()
	var stick := CylinderShape3D.new()
	stick.radius = 0.03
	stick.height = UMBRELLA.SHAFT_TOP - UMBRELLA.SHAFT_BOTTOM
	shaft.shape = stick
	shaft.position.y = (UMBRELLA.SHAFT_TOP + UMBRELLA.SHAFT_BOTTOM) * 0.5
	add_child(shaft)
	var cover := CollisionShape3D.new()
	var dome := CylinderShape3D.new()
	var t := smoothstep(0.0, 1.0, amount)
	dome.radius = lerpf(0.07, UMBRELLA.CANOPY_RADIUS * 0.9, t)
	dome.height = UMBRELLA.CANOPY_HEIGHT * lerpf(2.2, 1.0, t)
	cover.shape = dome
	cover.position.y = UMBRELLA.SHAFT_TOP - dome.height * 0.5
	add_child(cover)

func _ready() -> void:
	for child in get_children():
		if child is MeshInstance3D: _mesh_scales[child] = child.scale

func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		var left := 1.0 - (_age - LIFETIME) / FADE_SECONDS
		if left <= 0.0:
			queue_free()
			return
		# Encolhe em vez de esmaecer: transparência criaria outra variante de shader.
		for child in _mesh_scales: child.scale = _mesh_scales[child] * maxf(left, 0.02)
	var field = preload("res://runtime/atmosphere/WindField.gd").current
	if field == null: return
	# Arrasto linear pela diferença entre vento e guarda-chuva; a copa aberta pega muito mais.
	var relative: Vector3 = field.velocity - Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var grab := lerpf(0.04, 0.32, open)
	apply_central_force(relative * grab)
	# Copa virada para o vento levanta um pouco na rajada e faz o guarda-chuva cambalhotar.
	var cup := absf(global_basis.y.dot(relative.normalized())) if relative.length_squared() > 0.01 else 0.0
	apply_central_force(Vector3.UP * relative.length() * grab * 0.35 * cup * float(field.gust))
	apply_torque(global_basis.y.cross(relative) * grab * 0.04)

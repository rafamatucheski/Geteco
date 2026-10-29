extends Node3D
## Guarda-chuva de pedestre na chuva. Parte da multidão (pela identidade) carrega um; cada um
## abre num limiar próprio de chuva, para a rua não abrir todos no mesmo segundo. Atropelado
## ou morto, o pedestre larga o guarda-chuva (`LooseUmbrella3D`), que voa com o impacto e
## depois anda com o vento e com o carro que passa por cima.
## GETECO_UMBRELLAS=0 desliga (A/B).

static var enabled := OS.get_environment("GETECO_UMBRELLAS") != "0"
## Fração da multidão que tem guarda-chuva.
const SHARE := 55
const OPEN_SECONDS := 0.7
## Medidas a partir da palma (origem), em metros.
const SHAFT_TOP := 0.95
const SHAFT_BOTTOM := -0.1
const CANOPY_RADIUS := 0.56
const CANOPY_HEIGHT := 0.26
## Eixo inclinado para o centro do corpo: a palma fica à direita e à frente, a copa sobre a cabeça.
const TILT := Vector3(-0.15, 0.95, -0.18)
const COLORS := [Color("1d1f24"), Color("2b3f63"), Color("8c2a2a"), Color("2f5a3c"), Color("c9a227"), Color("5a3a66"), Color("d8d4c8"), Color("3d6f8a")]

static var _canopy_mesh: CylinderMesh
static var _shaft_mesh: CylinderMesh
static var _handle_mesh: CapsuleMesh
static var _materials: Dictionary = {}
static var _weather: WeakRef

var model
var color := Color.BLACK
var open := 0.0
var raining := false
var canopy: MeshInstance3D

## Chamado pelo `Actor` cerca de uma vez por segundo.
static func update(actor: Node3D, model_node, identity: int) -> void:
	if not enabled or model_node == null or not ("umbrella" in model_node): return
	if actor.get("dead") == true or actor.has_meta("street_down") or actor.has_meta("umbrella_lost"): return
	if posmod(identity * 37 + 11, 100) >= SHARE: return
	if model_node.get("activity") == "carry" or float(model_node.get("sit_amount")) > 0.0: return
	var rain := rain_at(actor)
	# Cada um com o próprio limiar e uma folga para não abrir e fechar na garoa oscilando.
	var threshold := 0.06 + 0.16 * float(posmod(identity * 131, 97)) / 97.0
	var held = model_node.umbrella
	var wants := rain > (threshold * 0.5 if held != null and held.raining else threshold)
	if held == null:
		if not wants: return
		held = load("res://gameplay/crowd/PedestrianUmbrella.gd").new()
		held.model = model_node
		held.color = COLORS[posmod(identity * 7 + 3, COLORS.size())]
		model_node.add_child(held)
		model_node.umbrella = held
	held.set_raining(wants)

## Larga o guarda-chuva que estiver na mão, com o impulso do impacto (velocidade do carro, m/s).
static func drop(actor: Node3D, impact: Vector3) -> void:
	var visual = actor.get("visual")
	if not is_instance_valid(visual) or visual.get_child_count() == 0: return
	var model_node = visual.get_child(0)
	if not ("umbrella" in model_node): return
	var held = model_node.umbrella
	model_node.umbrella = null
	model_node.umbrella_raised = false
	if not is_instance_valid(held): return
	actor.set_meta("umbrella_lost", true)
	if held.visible and held.is_inside_tree():
		var world := actor.get_parent()
		if world != null:
			load("res://gameplay/crowd/LooseUmbrella3D.gd").spawn(world, held.global_transform, held.color, held.open, impact)
	held.queue_free()

## Chuva no ponto, pelo Weather da sessão (o mesmo que molha a rua e faz espirrar a roda).
static func rain_at(actor: Node3D) -> float:
	var weather = _weather.get_ref() if _weather != null else null
	if weather == null:
		var node := actor.get_parent()
		for depth in 4:
			if node == null: break
			var session = node.get("session")
			if session != null and session.get("weather") != null:
				weather = session.weather
				_weather = weakref(weather)
				break
			node = node.get_parent()
	if weather == null or not weather.has_method("rain_strength_at"): return 0.0
	return float(weather.rain_strength_at(actor.global_position))

static func canopy_mesh() -> CylinderMesh:
	if _canopy_mesh == null:
		_canopy_mesh = CylinderMesh.new()
		_canopy_mesh.top_radius = 0.025
		_canopy_mesh.bottom_radius = CANOPY_RADIUS
		_canopy_mesh.height = CANOPY_HEIGHT
		_canopy_mesh.radial_segments = 8
		_canopy_mesh.rings = 1
	return _canopy_mesh

static func material(tint: Color) -> StandardMaterial3D:
	# Mesmo tipo de material do `CivilianBase` (só cor e aspereza): não cria variante nova de shader.
	if not _materials.has(tint):
		var made := StandardMaterial3D.new()
		made.albedo_color = tint
		made.roughness = 0.9
		_materials[tint] = made
	return _materials[tint]

## Monta as peças em `parent` com origem na palma; devolve a copa (escala = abertura).
static func build_parts(parent: Node3D, tint: Color) -> MeshInstance3D:
	if _shaft_mesh == null:
		_shaft_mesh = CylinderMesh.new()
		_shaft_mesh.top_radius = 0.011
		_shaft_mesh.bottom_radius = 0.011
		_shaft_mesh.height = SHAFT_TOP - SHAFT_BOTTOM
		_shaft_mesh.radial_segments = 6
		_shaft_mesh.rings = 1
		_handle_mesh = CapsuleMesh.new()
		_handle_mesh.radius = 0.022
		_handle_mesh.height = 0.16
		_handle_mesh.radial_segments = 6
		_handle_mesh.rings = 2
	var shaft := MeshInstance3D.new()
	shaft.mesh = _shaft_mesh
	shaft.material_override = material(Color("2a2522"))
	shaft.position.y = (SHAFT_TOP + SHAFT_BOTTOM) * 0.5
	parent.add_child(shaft)
	var handle := MeshInstance3D.new()
	handle.mesh = _handle_mesh
	handle.material_override = material(Color("4a3020"))
	handle.position.y = -0.02
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(handle)
	var top := MeshInstance3D.new()
	top.mesh = canopy_mesh()
	top.material_override = material(tint)
	parent.add_child(top)
	return top

## Fechado é um cone fino e comprido; aberto, a copa inteira. A ponta fica sempre no topo do eixo.
static func shape_canopy(top: MeshInstance3D, amount: float) -> void:
	var t := smoothstep(0.0, 1.0, amount)
	var radial := lerpf(0.11, 1.0, t)
	var tall := lerpf(2.2, 1.0, t)
	top.scale = Vector3(radial, tall, radial)
	top.position.y = SHAFT_TOP - CANOPY_HEIGHT * tall * 0.5

func _ready() -> void:
	basis = Basis(Quaternion(Vector3.UP, TILT.normalized()))
	visible = false
	canopy = build_parts(self, color)
	shape_canopy(canopy, open)

func set_raining(value: bool) -> void:
	raining = value
	set_process(true)

func _process(delta: float) -> void:
	if not is_instance_valid(model): set_process(false); return
	# Primeiro o braço sobe com ele fechado; abre lá em cima. Ao parar: fecha, depois o braço desce.
	var arm: float = model.umbrella_arm_weight()
	var target := 1.0 if raining and arm > 0.85 else 0.0
	open = move_toward(open, target, delta / OPEN_SECONDS)
	model.umbrella_raised = raining or open > 0.0
	shape_canopy(canopy, open)
	if open == target and (raining and open == 1.0 or not raining and arm == 0.0): set_process(false)

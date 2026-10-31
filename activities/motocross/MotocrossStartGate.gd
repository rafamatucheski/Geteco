extends Node3D
## Largada real de motocross: uma fileira de barras com dobradiça atravessando a reta final. As
## barras são só visuais (as motos ficam presas pelo controlador da corrida até a queda),
## então ficam deitadas no barro sempre que nenhuma corrida está largando, e os pilotos
## de treino passam livremente por cima. Um MultiMesh, animado só enquanto se move.
const GRID_DISTANCE := -18.0
## As barras giram meio metro à frente dos pneus dianteiros no grid.
const GATE_DISTANCE := GRID_DISTANCE+1.45
## Ordem do grid: o jogador primeiro, depois os rivais para fora. O espaçamento de 1.7 m deixa o
## piloto montando (0.95 m à esquerda do assento) longe do guidão do vizinho;
## a faixa externa direita fica no começo suave da berma da primeira curva.
const LANES := [-.85,.85,-2.55,2.55,-4.25,4.25]
const BAR_SIZE := Vector3(1.5,.52,.05)
var course: Node3D
var raised := false
var _angle := 1.0
var _target := 1.0
var _pivots: Array[Transform3D] = []
var _bars: MultiMeshInstance3D

func _ready() -> void:
	name = "MotocrossStartGate"
	var road: Transform3D = course.pose(GATE_DISTANCE)
	road.origin = course.sample(GATE_DISTANCE)
	for lane in LANES:
		var lateral := float(lane)
		var left: float = course.ribbon_height(GATE_DISTANCE,lateral-BAR_SIZE.x*.5)
		var right: float = course.ribbon_height(GATE_DISTANCE,lateral+BAR_SIZE.x*.5)
		# Cada dobradiça segue a inclinação transversal do barro, incluindo a berma direita.
		var across := (road.basis.x*BAR_SIZE.x+Vector3.UP*(right-left)).normalized()
		var forward := -road.basis.z
		var up := across.cross(forward).normalized()
		var pivot := Transform3D(Basis(across,up,-forward),road.origin+road.basis.x*lateral)
		pivot.origin.y = (left+right)*.5+.012
		_pivots.append(pivot)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = BAR_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c9c3ae")
	material.metallic = .55
	material.roughness = .5
	mesh.material = material
	multimesh.mesh = mesh
	multimesh.instance_count = LANES.size()
	_bars = MultiMeshInstance3D.new()
	_bars.name = "DropBars"
	_bars.multimesh = multimesh
	add_child(_bars)
	_build_frame()
	_apply()
	set_process(false)

func grid_pose(index: int) -> Transform3D:
	return course.pose(GRID_DISTANCE,float(LANES[clampi(index,0,LANES.size()-1)]))

func raise_gate() -> void:
	raised = true
	_target = 0.0
	set_process(true)

func drop_gate() -> void:
	raised = false
	_target = 1.0
	set_process(true)

func _process(delta: float) -> void:
	# Molas derrubam as barras rápido; o largador as ergue devagar.
	_angle = move_toward(_angle,_target,delta*(7.5 if _target > _angle else 1.6))
	_apply()
	if is_equal_approx(_angle,_target): set_process(false)

func _apply() -> void:
	# O topo da barra cai para trás, em direção aos pilotos esperando, como num portão real.
	var hinge := Basis(Vector3.RIGHT,_angle*PI*.5)
	for index in _pivots.size():
		var local := Transform3D(hinge,Vector3.ZERO)*Transform3D(Basis.IDENTITY,Vector3(0,BAR_SIZE.y*.5,0))
		_bars.multimesh.set_instance_transform(index,global_transform.affine_inverse()*_pivots[index]*local)

func _build_frame() -> void:
	# A cabine do largador e os pilares das pontas ficam fora da largura pilotável dos dois lados.
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("4a5351")
	steel.metallic = .5
	steel.roughness = .55
	var road: Transform3D = course.pose(GATE_DISTANCE)
	for side in [-1.0,1.0]:
		# Fora da linha da fita da pista em HALF_WIDTH+0.45.
		var lateral: float = side*(course.HALF_WIDTH+1.0)
		# Canto mais baixo da pegada no acostamento inclinado, afundado 6 cm.
		var ground := minf(course.ground_height(GATE_DISTANCE,lateral-.16),course.ground_height(GATE_DISTANCE,lateral+.16))
		var pylon := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.32,.8,.32)
		pylon.mesh = box
		pylon.material_override = steel
		pylon.position = to_local(road.origin+road.basis.x*lateral)
		pylon.position.y = ground+.34
		pylon.name = "GatePylon"
		add_child(pylon)

extends "res://world/places/arcade/ArcadeGeometry.gd"
## Ferro Velho por dentro: o mesmo galpão de 11 × 8 m da fachada (frente em +Z, porta no meio) e só
## os materiais dos bares, já aquecidos. Fileira do fundo: saco, speedbag, halteres, colchonete da
## flexão e esteira; da frente: corda, agachamento e colchonete do abdominal, com o corredor da porta
## livre. Cada aparelho fica atrás do ponto onde o Dante treina (`GymPlace.STATIONS`), virado para −Z.
const SIZE := Vector2(11, 8)
## Peças que se mexem enquanto o Dante treina (GymPlace chama `animate`). Só transformação por quadro,
## sem física: o sólido do saco foi medido na pose de repouso, quando o lugar montou as colisões.
var bag_pivot: Node3D
var speed_ball: Node3D
var belt_stripes: Array[Node3D] = []
const BELT_LENGTH := 1.8

func _ready() -> void:
	var half := SIZE * .5
	box("RubberFloor",Vector3(0,-.03,0),Vector3(SIZE.x,.06,SIZE.y),"2f3331","","cloth")
	box("RearBrick",Vector3(0,1.5,-half.y+.12),Vector3(SIZE.x,3.0,.24),"7a4f40","RearWall","stone")
	for side in [-1,1]:
		box("SideBrick",Vector3(side*(half.x-.12),1.5,0),Vector3(.24,3.0,SIZE.y),"74675a","SideWall%d"%side,"stone")
		box("FrontBrick",Vector3(side*(1.2+(half.x-1.2)*.5),1.5,half.y-.12),Vector3(half.x-1.2,3.0,.24),"6a5446","FrontWall%d"%side,"stone")
	box("Mirror",Vector3(-.7,1.45,-half.y+.26),Vector3(2.6,1.7,.03),"9fb2b8","","screen")
	_punching_bag(Vector3(-4.0,0,-3.0))
	_speedbag(Vector3(-2.0,0,-3.6))
	_dumbbells(Vector3(.3,0,-3.55))
	_mat(Vector3(2.3,0,-2.3),Vector2(.9,1.9))
	_treadmill(Vector3(4.3,0,-2.4))
	_mat(Vector3(3.6,0,1.3),Vector2(.9,1.9))
	box("Bench",Vector3(-4.9,.42,2.6),Vector3(.4,.12,1.2),"3a3f45","Bench","cloth")
	box("BenchBase",Vector3(-4.9,.2,2.6),Vector3(.28,.4,.9),"55595c","Bench","metal")
	box("Lockers",Vector3(5.1,1.0,2.9),Vector3(.5,2.0,1.6),"566a73","Lockers","metal")
	var label := Label3D.new()
	label.text = "FERRO VELHO"
	label.font_size = 60
	label.pixel_size = .008
	label.position = Vector3(2.6,2.45,-half.y+.26)
	label.outline_size = 0
	label.modulate = Color("d9b46a")
	add_child(label)
	flush()
	set_process(false)
	set_physics_process(false)

func _punching_bag(at: Vector3) -> void:
	box("BagBeam",at+Vector3(0,2.85,-.3),Vector3(.12,.12,1.4),"3a3632","","metal")
	# Corrente e saco penduram num pivô no gancho da viga, para balançar com os socos.
	bag_pivot = Node3D.new()
	bag_pivot.name = "BagPivot"
	bag_pivot.position = at+Vector3(0,2.8,0)
	add_child(bag_pivot)
	for part in [box("BagChain",at+Vector3(0,2.5,0),Vector3(.02,.6,.02),"8c8f8a","","metal"), box("PunchingBag",at+Vector3(0,1.4,0),Vector3(.42,1.1,.42),"7b2f2a","PunchingBag","cloth")]:
		remove_child(part)
		bag_pivot.add_child(part)
		part.position -= bag_pivot.position

func _speedbag(at: Vector3) -> void:
	box("SpeedbagBoard",at+Vector3(0,2.0,.12),Vector3(.8,.06,.6),"6f4e37","","wood")
	box("SpeedbagBrace",at+Vector3(0,1.55,-.15),Vector3(.12,.9,.12),"3a3632","","metal")
	speed_ball = box("SpeedBall",at+Vector3(0,1.76,.26),Vector3(.18,.26,.18),"a33b30","","cloth")

func _dumbbells(at: Vector3) -> void:
	box("DumbbellRack",at+Vector3(0,.42,0),Vector3(1.4,.84,.45),"3a3f45","DumbbellRack","metal")
	for i in 5: detail(at+Vector3(-.56+i*.28,.9,0),Vector3(.11,.11,.3),"202325","metal",Vector3(PI*.5,0,0),true)

func _mat(at: Vector3, size: Vector2) -> void:
	box("Mat",at+Vector3(0,.012,0),Vector3(size.x,.025,size.y),"2f4a5c","","cloth")

func _treadmill(at: Vector3) -> void:
	# Esteira rente ao chão: o clipe corre no lugar, sem subir; só o console é sólido.
	box("TreadBelt",at+Vector3(0,.02,0),Vector3(.75,.04,BELT_LENGTH),"1e2022","","cloth")
	# Faixas claras na lona: correm para trás (+Z) enquanto o Dante corre na esteira.
	for i in 4:
		var stripe := box("BeltStripe",at+Vector3(0,.043,-BELT_LENGTH*.5+(i+.5)*BELT_LENGTH/4.0),Vector3(.7,.006,.05),"4a4e52","","cloth")
		stripe.set_meta("belt_origin",at)
		belt_stripes.append(stripe)
	for side in [-1,1]:
		box("TreadRail",at+Vector3(side*.43,.06,0),Vector3(.1,.12,1.8),"55595c","","metal")
		detail(at+Vector3(side*.43,.62,-.85),Vector3(.05,1.1,.05),"55595c","metal")
	box("TreadConsole",at+Vector3(0,1.18,-.97),Vector3(.9,.22,.18),"2b2e30","TreadConsole","metal")

## Uma série em andamento: `age` em segundos desde o começo. Fora da série, `rest()` volta tudo.
func animate(station: String, age: float) -> void:
	match station:
		"punching_bag":
			if is_instance_valid(bag_pivot): bag_pivot.rotation.x = -.16 * absf(sin(age * 4.1)) + .03 * sin(age * 9.0)
		"speedbag":
			if is_instance_valid(speed_ball): speed_ball.rotation.x = .55 * sin(age * 21.0)
		"treadmill":
			for stripe in belt_stripes:
				var origin: Vector3 = stripe.get_meta("belt_origin")
				var base: float = stripe.get_meta("belt_base", stripe.position.z - origin.z)
				stripe.set_meta("belt_base", base)
				stripe.position.z = origin.z + fposmod(base + BELT_LENGTH * .5 + age * 2.6, BELT_LENGTH) - BELT_LENGTH * .5

func rest() -> void:
	if is_instance_valid(bag_pivot): bag_pivot.rotation = Vector3.ZERO
	if is_instance_valid(speed_ball): speed_ball.rotation = Vector3.ZERO

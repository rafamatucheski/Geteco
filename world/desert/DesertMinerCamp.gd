extends Node3D
## Acampamento do velho Tião, minerador aposentado da cava do deserto: barraca, carrinho
## com o minério negro que ele guarda há vinte anos, caixotes e uma fogueira apagada.
## Fica a ~32 m da estrada de acesso da Mineração, entre a rodovia do sal e o portão,
## fora de `MiningLayout.BOUNDS`. Último elo da pista da Forja da Serra.
const GEO := preload("res://world/mountain_detail/forge/ForgeGeometry.gd")
const RESIDENT := preload("res://world/mountain_detail/forge/ForgeResident.gd")
const GROUND := preload("res://world/desert/DesertTerrainMesh.gd")
const CENTER := Vector3(-212,0,-932)
const MINER_STAND := Vector3(1.6,.12,1.2)
var miner: Node3D
var session

static func ground(point: Vector2) -> float:
	return GROUND.surface_height(point)

func _ready() -> void:
	name = "DesertMinerCamp"
	add_to_group("blade_forge_site")
	position.y = ground(Vector2(CENTER.x, CENTER.z))
	var g := GEO.new()
	# Barraca de lona em A, aberta para a estrada.
	var tent := Vector3(-2.4,0,-1.4)
	for side in [-1.0,1.0]:
		_part(g, "box", tent+Vector3(side*.85,1.0,0), Vector3(.08,2.1,3.0), "a58e64", Vector3(0,0,side*.62))
	_part(g, "pole", tent+Vector3(0,1.85,0), Vector3(.08,3.2,.08), "59452e", Vector3(PI*.5,0,0))
	_solid("Tent", tent+Vector3(0,.9,0), Vector3(2.2,1.8,3.0))
	# Carrinho de mina com o minério negro.
	var cart := Vector3(2.6,0,-.6)
	_part(g, "box", cart+Vector3(0,.72,0), Vector3(1.0,.6,1.5), "5d5249")
	for x in [-.52,.52]:
		for z in [-.5,.5]: _part(g, "pole", cart+Vector3(x,.22,z), Vector3(.36,.08,.36), "2d3033", Vector3(0,0,PI*.5))
	for i in 5: _part(g, "round", cart+Vector3(-.25+float(i%3)*.25,1.08,-.4+float(i)*.2), Vector3(.34,.26,.3), "1f1c22")
	_solid("OreCart", cart+Vector3(0,.6,0), Vector3(1.1,1.2,1.6))
	# Caixotes, picareta encostada e lampião.
	for i in 3:
		var at := Vector3(-.2+float(i)*.62,0,-3.0+float(i%2)*.2)
		_part(g, "box", at+Vector3(0,.3,0), Vector3(.58,.6,.58), "8a6a45")
		_solid("Crate", at+Vector3(0,.3,0), Vector3(.58,.6,.58))
	_part(g, "box", Vector3(1.1,.75,-3.0), Vector3(.05,1.4,.05), "806044", Vector3(0,0,.25))
	_part(g, "box", Vector3(1.28,1.42,-3.0), Vector3(.6,.06,.06), "2d3033", Vector3(0,0,.25))
	# Fogueira apagada: pedras e tições, sem chama nem luz.
	var fire := Vector3(.2,0,1.8)
	for i in 8:
		var angle := float(i)/8.0*TAU
		_part(g, "round", fire+Vector3(cos(angle)*.55,.1,sin(angle)*.55), Vector3(.3,.2,.26), "6e655b")
	for i in 3: _part(g, "pole", fire+Vector3(0,.12,0), Vector3(.1,.8,.1), "2b2826", Vector3(PI*.5,float(i)*1.05,0))
	_part(g, "pole", fire+Vector3(-1.6,.22,.2), Vector3(.42,1.3,.42), "7a5a3a", Vector3(0,.3,PI*.5))
	_solid("LogSeat", fire+Vector3(-1.6,.22,.2), Vector3(1.3,.44,.45))
	g.flush(self)
	miner = RESIDENT.new()
	miner.name = "Miner"
	miner.site_id = "miner"
	miner.speaker = "Tião"
	miner.identity = 753
	miner.stand = MINER_STAND+Vector3.UP*_lift(MINER_STAND)
	# De frente para a estrada (+X, onde o jogador chega de carro).
	miner.facing = -PI*.5
	add_child(miner)

func nearest_action() -> Dictionary:
	return miner.nearest_action() if is_instance_valid(miner) else {}

## Peça assentada no chão do deserto do ponto dela (o acampamento não aplana o terreno).
func _part(g: RefCounted, kind: String, at: Vector3, size: Vector3, color: String, rotation := Vector3.ZERO) -> void:
	g.part(kind, at+Vector3.UP*_lift(at), size, color, rotation)

func _solid(id: String, at: Vector3, size: Vector3) -> void:
	GEO.solid(self, id, at+Vector3.UP*_lift(at), size)

func _lift(at: Vector3) -> float:
	return ground(Vector2(CENTER.x+at.x, CENTER.z+at.z)) - position.y

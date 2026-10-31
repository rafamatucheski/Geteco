extends "res://world/places/NativePlace.gd"
## Telhado caminhável no mundo compartilhado da cidade: sem viewport, skybox nem cidade duplicada.
const MATERIALS = preload("res://world/places/ShopInteriorMaterials.gd")
class RoofModel extends Node3D:
	func create_reward_art(reward: Dictionary) -> Node3D:
		return preload("res://world/places/harbor_buildings/HarborBuildingRewardArt.gd").build(reward)
const CIRCULATION = preload("res://world/places/harbor_buildings/HarborRoofCirculation.gd")
const HOUSE_OFFSET := CIRCULATION.HOUSE_OFFSET
const HOUSE_SIZE := CIRCULATION.HOUSE_SIZE
var jump_point := Vector3.ZERO
var jump_outward := Vector3.BACK
var _jump_gate: StaticBody3D
var _jump_gate_art: Node3D

func stair_point() -> Vector3:
	return CIRCULATION.stair(definition)

## Chegada de quem sobe: ao lado do patamar, para dentro do telhado.
func landing_point() -> Vector3:
	var stair := stair_point()
	return stair+(Vector3.RIGHT if stair.x<0.0 else Vector3.LEFT)*1.35

func _ready() -> void:
	name = "Rooftop"
	model = RoofModel.new()
	model.name = "RoofFurniture"
	add_child(model)
	var width: float = definition.size.x
	var depth: float = definition.size.y
	var half_w := width*.5
	var half_d := depth*.5
	# A face de cima da laje é a referência real do telhado usada pelo ator.
	_piece("RoofSlab",Vector3(0,-.11,0),Vector3(width,.22,depth),"stone","70736b",false)
	_box_solid("RoofSupport",AABB(Vector3(-half_w,-.24,-half_d),Vector3(width,.24,depth)),false)
	# Emendas da cobertura e um ralo fazem a superfície parecer construída, não uma base vazia.
	for seam in range(1,maxi(2,floori(width/1.25))):
		var x := -half_w+float(seam)*width/float(maxi(2,floori(width/1.25)))
		_piece("RoofSeam",Vector3(x,.008,0),Vector3(.018,.014,depth-.35),"metal","4f5651",false)
	_piece("DrainGrate",Vector3(half_w-.65,.017,-half_d+.65),Vector3(.38,.024,.42),"metal","323c3b",false)
	jump_point = Vector3(float(definition.get("jump_x",maxf(.7,half_w-2.0))),0,half_d-.88)
	var gap_left := jump_point.x-.95
	var gap_right := jump_point.x+.95
	_guard("NorthGuard",Vector3(0,.52,-half_d+.12),Vector3(width,1.04,.24))
	_guard("WestGuard",Vector3(-half_w+.12,.52,0),Vector3(.24,1.04,depth-.24))
	_guard("EastGuard",Vector3(half_w-.12,.52,0),Vector3(.24,1.04,depth-.24))
	_guard("SouthGuardWest",Vector3((-half_w+gap_left)*.5,.52,half_d-.12),Vector3(gap_left+half_w,1.04,.24))
	_guard("SouthGuardEast",Vector3((gap_right+half_w)*.5,.52,half_d-.12),Vector3(half_w-gap_right,1.04,.24))
	# O guarda-corpo continua sólido: o jogador pula por cima fisicamente andando para fora.
	_jump_gate_art = Node3D.new()
	_jump_gate_art.name = "RoofJumpGate"
	_jump_gate_art.position = Vector3(gap_left,0,half_d-.12)
	model.add_child(_jump_gate_art)
	for height in [.52,1.02]:
		var rail := _piece("GateRail",Vector3(.95,height,0),Vector3(1.90,.055,.055),"metal","555f59",false,_jump_gate_art)
		if height>.9: rail.set_meta("functional_jump_gate",true)
	_box_solid("RoofJumpGate",AABB(Vector3(gap_left,0,half_d-.24),Vector3(1.90,1.06,.24)))
	_jump_gate = solid_bodies[-1]
	# A saída da escada divide o patamar com todo andar autorado. Playtest de
	# 29/10: o telhado visto da rua tinha casinhas sorteadas pelo enfeite (até três)
	# e esta saída de pedra aparecia em outro lugar. Agora a saída é UMA casinha
	# fechada, no mesmo lugar e com as cores da casinha que o CityChunkDressing põe
	# no telhado (HarborRoofCirculation.stair_house), um pouco maior para cobri-la
	# sem brigar de profundidade; o patamar fica em frente à porta.
	var stair := stair_point()
	var house: Vector3 = stair+HOUSE_OFFSET
	if CIRCULATION.uses_hatch(definition):
		_build_open_hatch(house)
	else:
		_piece("StairHouse",house+Vector3(0,HOUSE_SIZE.y*.5,0),HOUSE_SIZE,"stone","a39b8c",true)
		_piece("StairHouseCap",house+Vector3(0,HOUSE_SIZE.y+.08,.05),Vector3(HOUSE_SIZE.x+.2,.16,HOUSE_SIZE.z+.2),"metal","6e7577",false)
		_piece("StairHouseDoor",house+Vector3(.4,.87,HOUSE_SIZE.z*.5+.012),Vector3(.82,1.74,.02),"wood","5a4a3c",false)
		_piece("StairHouseWindow",house+Vector3(-.55,1.4,HOUSE_SIZE.z*.5+.012),Vector3(.52,.42,.02),"metal","2e3a40",false)
	# Alguns objetos úteis de telhado, de propósito fora do patamar e da coleta.
	if width>=8.0 and depth>=8.0:
		_piece("Planter",Vector3(half_w-1.0,.29,-half_d+1.25),Vector3(1.15,.58,1.4),"stone","817961",true)
		_piece("PlanterSoil",Vector3(half_w-1.0,.59,-half_d+1.25),Vector3(1.04,.06,1.29),"stone","3e4031",false)
		for index in 5:
			_piece("RoofHerbs",Vector3(half_w-1.31+(index%2)*.52,.78,-half_d+.91+floori(float(index)/2.0)*.28),Vector3(.25,.35,.23),"cloth","66754e",false)
		_piece("ServiceBench",Vector3(half_w-1.15,.44,-half_d+3.0),Vector3(1.35,.12,.58),"wood","847154",true)
		for side in [-1,1]: _piece("BenchLeg",Vector3(half_w-1.15+side*.5,.20,-half_d+3.0),Vector3(.09,.40,.48),"metal","515851",true)
	_install_reward()
	set_process(false)
	set_physics_process(false)

## Alçapão de prédio térreo, aberto (quem sobe acabou de passar por ele): moldura sólida
## que cobre o alçapão fechado do enfeite, boca escura, tampa erguida para trás e os
## montantes da escada passando da boca, como escada de telhado de verdade.
func _build_open_hatch(at: Vector3) -> void:
	var size := CIRCULATION.HATCH_SIZE
	_piece("RoofHatchCurb",at+Vector3(0,size.y*.5,0),size,"metal","7d8284",true)
	_piece("RoofHatchOpening",at+Vector3(0,size.y+.006,0),Vector3(size.x-.2,.012,size.z-.2),"metal","15181a",false)
	var hinge := Node3D.new()
	hinge.name = "RoofHatchHinge"
	hinge.position = at+Vector3(0,size.y,-size.z*.5+.04)
	# Passa um pouco da vertical para trás: fica de pé sozinha, como tampa escorada.
	hinge.rotation.x = deg_to_rad(-105.0)
	model.add_child(hinge)
	_piece("RoofHatchLid",Vector3(0,.03,size.z*.5-.06),Vector3(size.x-.08,.06,size.z-.12),"metal","4b5052",false,hinge)
	_piece("RoofHatchHandle",Vector3(0,.08,size.z-.22),Vector3(.3,.03,.04),"metal","2b2f31",false,hinge)
	for x in [-.3,.3]:
		_piece("RoofHatchLadderRail",at+Vector3(x,size.y+.45,.12),Vector3(.05,.9,.05),"metal","8a8f90",false)
	_piece("RoofHatchLadderTop",at+Vector3(0,size.y+.88,.12),Vector3(.65,.05,.05),"metal","8a8f90",false)

func jump_access() -> Dictionary:
	return {"point":jump_point,"outward":jump_outward}

func _guard(id: String, at: Vector3, size: Vector3) -> void:
	if size.x <= .01 or size.z <= .01: return
	_piece(id,at,Vector3(size.x,.45,size.z),"stone","929383",false)
	_piece(id+"Rail",Vector3(at.x,1.04,at.z),Vector3(size.x+.02,.065,size.z+.02),"metal","4c5952",false)
	_box_solid(id,AABB(Vector3(at.x-size.x*.5,0,at.z-size.z*.5),size))

func _piece(id: String, at: Vector3, size: Vector3, material_kind: String, color: String, solid: bool, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = MATERIALS.material(material_kind,Color(color))
	(parent if parent != null else model).add_child(node)
	if solid:
		node.set_meta("interior_solid_id",id)
		# A área inteira bloqueia andar sob bancos/armários, como no cômodo.
		_box_solid(id,AABB(Vector3(at.x-size.x*.5,0,at.z-size.z*.5),Vector3(size.x,at.y+size.y*.5,size.z)))
	return node

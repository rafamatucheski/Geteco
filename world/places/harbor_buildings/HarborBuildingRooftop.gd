extends "res://world/places/NativePlace.gd"
## Walkable roof in the shared city world: no viewport, skybox or duplicate city.
const MATERIALS = preload("res://world/places/ShopInteriorMaterials.gd")
class RoofModel extends Node3D:
	func create_reward_art(reward: Dictionary) -> Node3D:
		return preload("res://world/places/harbor_buildings/HarborBuildingRewardArt.gd").build(reward)
var jump_point := Vector3.ZERO
var jump_outward := Vector3.BACK
var _jump_gate: StaticBody3D
var _jump_gate_art: Node3D

func stair_point() -> Vector3:
	return Vector3(-definition.size.x*.5+1.45,0,1.45)

func _ready() -> void:
	name = "Rooftop"
	model = RoofModel.new()
	model.name = "RoofFurniture"
	add_child(model)
	var width: float = definition.size.x
	var depth: float = definition.size.y
	var half_w := width*.5
	var half_d := depth*.5
	# The slab's upper face is the actual roof datum used by the actor.
	_piece("RoofSlab",Vector3(0,-.11,0),Vector3(width,.22,depth),"stone","70736b",false)
	_box_solid("RoofSupport",AABB(Vector3(-half_w,-.24,-half_d),Vector3(width,.24,depth)),false)
	# Roofing seams and a drain make the surface read as built, not an empty pad.
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
	# The rail remains solid: the player physically vaults it by moving outward.
	_jump_gate_art = Node3D.new()
	_jump_gate_art.name = "RoofJumpGate"
	_jump_gate_art.position = Vector3(gap_left,0,half_d-.12)
	model.add_child(_jump_gate_art)
	for height in [.52,1.02]:
		var rail := _piece("GateRail",Vector3(.95,height,0),Vector3(1.90,.055,.055),"metal","555f59",false,_jump_gate_art)
		if height>.9: rail.set_meta("functional_jump_gate",true)
	_box_solid("RoofJumpGate",AABB(Vector3(gap_left,0,half_d-.24),Vector3(1.90,1.06,.24)))
	_jump_gate = solid_bodies[-1]
	# The stair exit shares its landing with every authored floor. Side walls
	# and canopy are physical, with a clear 1.5m opening facing that landing.
	var stair := stair_point()
	_piece("StairRear",stair+Vector3(0,1.1,-2.35),Vector3(1.90,2.2,.18),"stone","858574",true)
	for side in [-1,1]:
		_piece("StairJamb",stair+Vector3(side*.91,1.1,-1.62),Vector3(.16,2.2,1.64),"stone","858574",true)
	_piece("StairCap",stair+Vector3(0,2.24,-1.62),Vector3(2.05,.16,1.86),"metal","525b55",false)
	_box_solid("StairOverhead",AABB(stair+Vector3(-1.025,2.16,-2.55),Vector3(2.05,.16,1.86)),false)
	_piece("StairDoorOpen",stair+Vector3(-.77,1.03,-.65),Vector3(.075,2.05,.9),"metal","394741",true)
	# A few useful roof objects, deliberately outside the landing and pickup.
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
		# Full footprint blocks walking under benches/cabinets, as in the room.
		_box_solid(id,AABB(Vector3(at.x-size.x*.5,0,at.z-size.z*.5),Vector3(size.x,at.y+size.y*.5,size.z)))
	return node

extends RefCounted
## Persistent distance geometry: basin and asymmetric, eroded sandstone ranges.
## Close ground, rocks and all physical boundaries remain owned by streamed cells.
const L := preload("res://world/desert/DesertLayout.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const MINING := preload("res://world/mining/MiningExterior.gd")
const MINING_LAYOUT := preload("res://world/mining/MiningLayout.gd")
const LIFETIME := preload("res://world/desert/DesertPreparationLifetime.gd")
static func build() -> Node3D:
	var root := Node3D.new()
	root.name="DesertHorizon"
	# Never paint over Harbor's sea or the independent eastern mountain territory.
	var rect := L.BOUNDS
	# The visual horizon must have the same excavation cut as streamed ground.
	# A single datum-height quad would occlude the entire physically valid mine.
	for remainder in MINING.ground_remainders(rect):
		for untouched in preload("res://world/desert/canyon/DesertSmugglerLayout.gd").ground_remainders(remainder):
			_basin(root,"DistantBasin",untouched,-.045)
	if MINING_LAYOUT.enabled():
		# Keep a distant backdrop below the lowest floor while nearby authored
		# benches and road geometry remain owned by their existing stream chunks.
		_basin(root,"DistantQuarryFloor",rect.intersection(MINING.OWNED_GROUND),-MINING_LAYOUT.PIT_DEPTH-.045)
	root.add_child(preload("res://world/desert/DesertHorizonRelief.gd").build())
	root.add_child(preload("res://world/desert/DesertTerrainMesh.gd").build_visuals())
	root.add_child(preload("res://world/desert/canyon/DesertSmugglerScenery.gd").build_visuals())
	return root

## Versão que cede o quadro entre as partes e dentro do terreno (ver
## DesertTerrainMesh.build_visuals_sliced). Mesmo resultado de build().
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

static func build_sliced(tree: SceneTree, token: Dictionary = {}) -> Node3D:
	if LIFETIME.cancelled(token): return null
	var root := Node3D.new()
	LIFETIME.track(token,root)
	root.name="DesertHorizon"
	var rect := L.BOUNDS
	for remainder in MINING.ground_remainders(rect):
		for untouched in preload("res://world/desert/canyon/DesertSmugglerLayout.gd").ground_remainders(remainder):
			_basin(root,"DistantBasin",untouched,-.045)
	if MINING_LAYOUT.enabled():
		_basin(root,"DistantQuarryFloor",rect.intersection(MINING.OWNED_GROUND),-MINING_LAYOUT.PIT_DEPTH-.045)
	await tree.process_frame
	if LIFETIME.cancelled(token): return null
	var t := STALL_WORK.begin()
	root.add_child(preload("res://world/desert/DesertHorizonRelief.gd").build())
	STALL_WORK.finish("lookout.horizon.relief", t)
	await tree.process_frame
	if LIFETIME.cancelled(token): return null
	var terrain: Node3D=await preload("res://world/desert/DesertTerrainMesh.gd").build_visuals_sliced(tree,12000,token)
	if LIFETIME.cancelled(token): return null
	root.add_child(terrain)
	await tree.process_frame
	if LIFETIME.cancelled(token): return null
	var canyon: Node3D=await preload("res://world/desert/canyon/DesertSmugglerScenery.gd").build_visuals_sliced(tree,token)
	if LIFETIME.cancelled(token): return null
	root.add_child(canyon)
	LIFETIME.release(token,root)
	return root

static func _basin(root: Node3D,label: String,rect: Rect2,height: float) -> void:
	if not rect.has_area(): return
	G.quad(root,label,PackedVector3Array([Vector3(rect.position.x,height,rect.position.y),Vector3(rect.end.x,height,rect.position.y),Vector3(rect.end.x,height,rect.end.y),Vector3(rect.position.x,height,rect.end.y)]),G.material(Color("b9a079"),true))

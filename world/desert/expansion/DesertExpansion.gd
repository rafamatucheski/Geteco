extends RefCounted
## Region-owned additions share its chunk lifetime and bounded dressing queue.
const LANDFORMS := preload("res://world/desert/expansion/DesertLandforms.gd")
const RELICS := preload("res://world/desert/expansion/DesertRelics.gd")
const FLORA := preload("res://world/desert/expansion/DesertEcologyFlora.gd")
const LIFE := preload("res://world/desert/expansion/DesertEcologyLife.gd")
const STAGES := 2

static func enabled() -> bool:
	# Read only by the isolated before/after benchmark, never a saved game option.
	return not (OS.is_debug_build() and Engine.get_meta("desert_expansion_benchmark_disabled",false))

static func prewarm(height: Callable) -> Dictionary:
	if not enabled(): return {}
	return LANDFORMS.prewarm(height,6102026)

static func build_stage(parent: Node3D,rect: Rect2,stage: int,height: Callable,clearance: Callable) -> void:
	if not enabled(): return
	match stage:
		0: RELICS.build_chunk(parent,rect,6102026,height)
		1: FLORA.build_chunk(parent,rect,6102026,height,clearance)

static func build_surfaces(parent: Node3D,rect: Rect2,height: Callable) -> void:
	# Raised surfaces must exist before the region admits a restored actor/car.
	if enabled(): LANDFORMS.build_chunk(parent,rect,6102026,height)

static func reservation_clear(point: Vector2,radius: float=0.0) -> bool:
	return not enabled() or (LANDFORMS.reservation_clear(point,radius) and RELICS.reservation_clear(point,radius))

static func create_life(parent: Node3D,height: Callable,clearance: Callable) -> Node3D:
	if not enabled(): return null
	var node:=LIFE.new()
	parent.add_child(node)
	node.configure(height,clearance)
	return node

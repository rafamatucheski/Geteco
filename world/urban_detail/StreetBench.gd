@tool
extends RefCounted
## Shared slatted bench sized to the established street furniture colliders.
static func create(width: float, depth: float) -> MeshInstance3D:
	return preload("res://world/urban_detail/BenchFinish.gd").create(width, depth, .6025, 1.12, Color("96734d"), Color("303e40"))

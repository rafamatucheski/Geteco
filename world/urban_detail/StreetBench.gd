@tool
extends RefCounted
## Banco de ripas compartilhado, dimensionado pelos colisores estabelecidos de mobiliário de rua.
static func create(width: float, depth: float) -> MeshInstance3D:
	return preload("res://world/urban_detail/BenchFinish.gd").create(width, depth, .6025, 1.12, Color("96734d"), Color("303e40"))

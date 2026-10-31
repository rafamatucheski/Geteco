extends RefCounted
## Preserva o caminho de entrada/eixo definido do CanalTunnel3D. Só o segmento de superfície
## é buscado de forma incremental; não há aqui uma segunda cópia da geometria do túnel.
const GRID := preload("res://gameplay/navigation/LocalGridPathSearch.gd")
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var done := false
var path := PackedVector3Array()
var _grid: RefCounted
var _tunnel_path := PackedVector3Array()
var _surface_first := false

func configure(gameplay: Node3D, start: Vector3, finish: Vector3) -> void:
	var surface: Array = []
	_tunnel_path = TUNNEL.walking_path(start, finish, func(surface_start: Vector3, surface_end: Vector3) -> PackedVector3Array:
		surface.append([surface_start, surface_end])
		return PackedVector3Array())
	if not _tunnel_path.is_empty() and surface.is_empty():
		path = _tunnel_path
		done = true
		return
	var from := start
	var to := finish
	if not surface.is_empty():
		from = surface[0][0]
		to = surface[0][1]
		_surface_first = TUNNEL.below_grade(finish)
	_grid = GRID.new()
	_grid.configure(from, to, gameplay.get("_occupancy"), Callable(gameplay, "_walkable_at"), Callable(gameplay, "_clear_at"))
	if _grid.done: _complete()

func advance(max_expansions: int, deadline_usec: int) -> int:
	if done: return 0
	var count: int = _grid.advance(max_expansions, deadline_usec)
	if _grid.done: _complete()
	return count

func _complete() -> void:
	if _tunnel_path.is_empty(): path = _grid.path
	elif _surface_first:
		path = _grid.path.duplicate()
		path.append_array(_tunnel_path)
	else:
		path = _tunnel_path.duplicate()
		path.append_array(_grid.path)
	done = true

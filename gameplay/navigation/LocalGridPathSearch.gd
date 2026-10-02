extends RefCounted
## The existing bounded local search, with an optional boundary between node
## expansions. Synchronous callers and queued police requests use the same work.
const MAX_EXPANSIONS := 256
var done := false
var path := PackedVector3Array()
var _start := Vector3.ZERO
var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _best := Vector2i.ZERO
var _frontier: Array[Vector2i] = []
var _previous: Dictionary = {}
var _costs: Dictionary = {}
var _dynamic_clear: Dictionary = {}
var _occupancy: Dictionary = {}
var _walkable: Callable
var _clear: Callable
var _expanded := 0

func configure(start: Vector3, finish: Vector3, occupancy: Dictionary, walkable: Callable, clear: Callable) -> void:
	_start = start
	_occupancy = occupancy
	_walkable = walkable
	_clear = clear
	_from = Vector2i(roundi(start.x / 2), roundi(start.z / 2))
	_to = Vector2i(roundi(finish.x / 2), roundi(finish.z / 2))
	_best = _from
	if _from == _to:
		path = PackedVector3Array([finish])
		done = true
		return
	_frontier.append(_from)
	_costs[_from] = 0.0

## A single expansion has at most four cell probes. The deadline is checked
## between expansions; individual physics queries cannot be preempted.
func advance(max_expansions := MAX_EXPANSIONS, deadline_usec := 0) -> int:
	var performed := 0
	while not done and performed < max_expansions:
		if deadline_usec > 0 and Time.get_ticks_usec() >= deadline_usec: break
		if _frontier.is_empty():
			_complete()
			break
		var chosen := 0
		var score := INF
		for index in _frontier.size():
			var value: float = _costs[_frontier[index]] + Vector2(_frontier[index] - _to).length()
			if value < score:
				score = value
				chosen = index
		var current: Vector2i = _frontier.pop_at(chosen)
		performed += 1
		_expanded += 1
		if Vector2(current - _to).length_squared() < Vector2(_best - _to).length_squared(): _best = current
		if current == _to:
			_best = current
			_complete()
			break
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if Vector2(next - _from).length() > 20: continue
			var key := Vector3i(next.x, roundi(_start.y), next.y)
			var point := Vector3(next.x * 2, _start.y, next.y * 2)
			if not _occupancy.has(key): _occupancy[key] = _walkable.call(point)
			if not _occupancy[key]: continue
			if not _dynamic_clear.has(next): _dynamic_clear[next] = _clear.call(point, 4)
			if not _dynamic_clear[next]: continue
			var cost: float = _costs[current] + 1
			if _costs.has(next) and _costs[next] <= cost: continue
			_costs[next] = cost
			_previous[next] = current
			if not _frontier.has(next): _frontier.append(next)
		if _expanded >= MAX_EXPANSIONS: _complete()
	return performed

func _complete() -> void:
	var reverse: Array[Vector3] = []
	while _best != _from and _previous.has(_best):
		reverse.append(Vector3(_best.x * 2, _start.y, _best.y * 2))
		_best = _previous[_best]
	reverse.reverse()
	path = PackedVector3Array(reverse)
	done = true

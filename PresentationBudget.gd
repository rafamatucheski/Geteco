extends Node
## O orçamento limita trabalho entre entidades; um rig individual é indivisível.
var pending: Array[Node2D] = []
var max_builds_per_frame := 1
var budget_usec := 2000

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func request(actor: Node2D) -> void:
	if not pending.has(actor):
		pending.append(actor)

func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	for iteration in max_builds_per_frame:
		var best: Node2D
		var best_distance := INF
		for index in range(pending.size() - 1, -1, -1):
			var actor := pending[index]
			if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
				pending.remove_at(index)
				continue
			if not actor.is_visible_in_tree():
				continue
			var screen := actor.get_global_transform_with_canvas().origin
			var rect := actor.get_viewport_rect()
			if not rect.grow(220).has_point(screen):
				continue
			var distance := screen.distance_squared_to(rect.get_center())
			if distance < best_distance:
				best = actor
				best_distance = distance
		if best == null:
			return
		pending.erase(best)
		best.ensure_presentation()
		if Time.get_ticks_usec() - started >= budget_usec:
			return

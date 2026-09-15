extends Node
## Scene-owned closure of the tour lanes. Only unowned ambient stock outside
## the camera is retired; visible traffic keeps physical movement and exits.
var lanes: Array[Path2D] = []
var player: Node2D
var elapsed := 0.0

func configure(paths: Array[Path2D], actor: Node2D) -> void:
	player = actor
	for path in paths:
		if is_instance_valid(path) and not lanes.has(path):
			lanes.append(path)
			path.set_meta("tour_lane_reservation", weakref(self))
	clear_unseen_stock()

static func reserved(path: Path2D) -> bool:
	if not is_instance_valid(path) or not path.has_meta("tour_lane_reservation"): return false
	var owner_ref = path.get_meta("tour_lane_reservation")
	return owner_ref is WeakRef and is_instance_valid(owner_ref.get_ref())

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < .5: return
	elapsed = 0.0
	clear_unseen_stock()

func clear_unseen_stock() -> void:
	if not is_instance_valid(player): return
	var viewport := player.get_viewport()
	var visible_rect := viewport.get_visible_rect().grow(180.0)
	for path in lanes:
		if not is_instance_valid(path): continue
		for follow in path.get_children():
			if not follow is PathFollow2D: continue
			for actor in follow.get_children():
				if not actor is Node2D or not actor.is_in_group("modern_traffic"): continue
				if actor.get("is_driven_by_player") == true or actor.get("_detached_from_lane") == true or actor.get_meta("service_crew_owned", false): continue
				if actor.global_position.distance_to(player.global_position) < 1100: continue
				if visible_rect.has_point(viewport.get_canvas_transform() * actor.global_position): continue
				actor.queue_free()

func _exit_tree() -> void:
	for path in lanes:
		if is_instance_valid(path) and path.has_meta("tour_lane_reservation"):
			var reference = path.get_meta("tour_lane_reservation")
			if reference is WeakRef and reference.get_ref() == self:
				path.remove_meta("tour_lane_reservation")

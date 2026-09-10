extends Node
## O sensor abre as folhas; atravessar a soleira é que troca de ambiente.
var room: Node2D
var previous_position := Vector2.ZERO
var has_previous := false
var pending_door: BuildingEntrance
var pending_outward := false

func _physics_process(_delta: float) -> void:
	var actor: Node2D = room.actor
	if not is_instance_valid(actor):
		has_previous = false
		return
	var now := actor.global_position
	var can_walk: bool = actor.visible and not actor.is_dead and not actor.is_arrested and not actor.is_in_dialogue and not actor.is_control_disabled
	if not can_walk or (has_previous and previous_position.distance_to(now) >= 100.0):
		pending_door = null
	if has_previous and previous_position.distance_to(now) < 100.0 and can_walk:
		var inside: bool = room.actor_inside()
		var door: BuildingEntrance = room.exit_door if inside else room.entrance
		var before := door.to_local(previous_position)
		var after := door.to_local(now)
		var direction := 1.0 if inside else -1.0
		if before.y * direction < 0.0 and after.y * direction >= 0.0:
			var crossing_x := lerpf(before.x, after.x, -before.y / (after.y - before.y))
			var half_width: float = room.project_floor(Vector2(1.0, 0)).x if inside else 22.0
			if absf(crossing_x) < half_width:
				pending_door = door
				pending_outward = inside
	# Uma volta rápida pode alcançar a soleira durante o cooldown. Conserva
	# a passagem até liberar a porta; recuar cancela, sem teleporte atrasado.
	if is_instance_valid(pending_door):
		var offset := pending_door.to_local(now)
		var depth := offset.y * (1.0 if pending_outward else -1.0)
		var width: float = room.project_floor(Vector2(1.0, 0)).x if pending_outward else 22.0
		if depth < 0.0 or depth > 32.0 or absf(offset.x) >= width:
			pending_door = null
		elif pending_door.enabled and not pending_door._busy:
			var confirmed := pending_door
			pending_door = null
			confirmed._begin_transition(actor)
	previous_position = now
	has_previous = true
